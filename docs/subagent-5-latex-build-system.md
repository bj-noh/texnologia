# Subagent 5: LaTeX Build System Agent

## 목표

PaperForge의 LaTeX 빌드 파이프라인은 MVP에서 `latexmk`를 기본 빌더로 사용하고, `latexmk`가 없거나 실패 정책상 직접 실행이 필요한 경우 `pdflatex`, `xelatex`, `lualatex`를 fallback으로 실행한다. macOS Swift 앱 내부에서 `Process` API로 외부 명령을 안전하게 실행하며, 취소, 증분 재빌드, 출력 캡처, 로그 파싱, 오류 위치 매핑, 탐색 가능한 이슈 목록까지 하나의 일관된 도메인 모델로 묶는다.

기본 보안 정책은 `shell-escape` 비활성이다. 사용자가 명시적으로 허용한 프로젝트에서만 제한적으로 켜며, UI에서는 위험한 옵션으로 분리한다.

## 빌드 파이프라인 개요

1. `BuildConfiguration`을 만든다.
2. `BuildCommandGenerator`가 실행 계획을 생성한다.
3. `BuildCoordinator`가 증분 재빌드 여부를 판단한다.
4. `LatexProcessRunner`가 Swift `Process`로 명령을 실행한다.
5. stdout/stderr와 `.log` 파일을 `BuildLogParser`가 해석한다.
6. `BuildIssue` 목록을 생성하고, 에디터 위치와 PDF 산출물 위치에 연결한다.
7. 빌드 성공 시 PDF 경로, SyncTeX 경로, aux 디렉터리 정보를 갱신한다.

MVP는 단일 루트 `.tex` 파일 빌드에 집중한다. 멀티 파일 프로젝트는 `\input`, `\include`, `.fls`, `.aux`를 통해 증분 판단을 보강한다.

## Build Configuration Model

```swift
import Foundation

enum LatexEngine: String, Codable, CaseIterable, Sendable {
    case pdfLaTeX = "pdflatex"
    case xeLaTeX = "xelatex"
    case luaLaTeX = "lualatex"
}

enum LatexBuildTool: Codable, Sendable, Equatable {
    case latexmk
    case direct(engine: LatexEngine)
}

enum ShellEscapePolicy: Codable, Sendable, Equatable {
    case disabled
    case enabled
}

struct BuildConfiguration: Codable, Sendable, Equatable {
    var rootFile: URL
    var projectDirectory: URL
    var outputDirectory: URL
    var auxDirectory: URL
    var tool: LatexBuildTool
    var preferredEngine: LatexEngine
    var interactionMode: InteractionMode
    var shellEscape: ShellEscapePolicy
    var synctexEnabled: Bool
    var haltOnError: Bool
    var maxDirectPasses: Int
    var environment: [String: String]

    enum InteractionMode: String, Codable, Sendable {
        case nonstopmode
        case scrollmode
        case batchmode
        case errorstopmode
    }
}
```

권장 기본값:

```swift
extension BuildConfiguration {
    static func `default`(rootFile: URL) -> BuildConfiguration {
        let projectDirectory = rootFile.deletingLastPathComponent()
        let buildDirectory = projectDirectory.appendingPathComponent(".paperforge-build", isDirectory: true)

        return BuildConfiguration(
            rootFile: rootFile,
            projectDirectory: projectDirectory,
            outputDirectory: buildDirectory,
            auxDirectory: buildDirectory,
            tool: .latexmk,
            preferredEngine: .pdfLaTeX,
            interactionMode: .nonstopmode,
            shellEscape: .disabled,
            synctexEnabled: true,
            haltOnError: false,
            maxDirectPasses: 3,
            environment: [:]
        )
    }
}
```

## Command Generation

`latexmk` 기본 명령:

```text
latexmk -pdf -interaction=nonstopmode -halt-on-error? -synctex=1 -file-line-error
        -outdir=<outputDirectory> -auxdir=<auxDirectory> <rootFile>
```

엔진별 `latexmk` 옵션:

```swift
extension LatexEngine {
    var latexmkFlag: String {
        switch self {
        case .pdfLaTeX: return "-pdf"
        case .xeLaTeX: return "-xelatex"
        case .luaLaTeX: return "-lualatex"
        }
    }
}
```

직접 실행 fallback 명령:

```text
pdflatex -interaction=nonstopmode -file-line-error -synctex=1
         -output-directory=<outputDirectory> <rootFile>
```

직접 실행은 cross-reference, bibliography, index 때문에 여러 pass가 필요하다. MVP에서는 최대 3회 반복하고, 로그에서 `Rerun to get cross-references right` 또는 `Label(s) may have changed`가 보이면 한 번 더 실행한다. BibTeX/Biber 자동 실행은 MVP 후속으로 두되, 로그에서 bibliography 필요 신호를 감지해 UI 경고를 띄운다.

```swift
struct BuildCommand: Sendable, Equatable {
    var executable: URL
    var arguments: [String]
    var workingDirectory: URL
    var environment: [String: String]
}

struct BuildCommandGenerator {
    var latexmkPath: URL?
    var enginePaths: [LatexEngine: URL]

    enum CommandGenerationError: LocalizedError {
        case missingExecutable(String)

        var errorDescription: String? {
            switch self {
            case .missingExecutable(let name):
                return "\(name) 실행 파일을 찾을 수 없습니다."
            }
        }
    }

    func makeCommands(for configuration: BuildConfiguration) throws -> [BuildCommand] {
        switch configuration.tool {
        case .latexmk where latexmkPath != nil:
            return [try makeLatexmkCommand(configuration)]
        case .latexmk:
            return [try makeDirectCommand(configuration, engine: configuration.preferredEngine)]
        case .direct(let engine):
            return [try makeDirectCommand(configuration, engine: engine)]
        }
    }

    private func makeLatexmkCommand(_ configuration: BuildConfiguration) throws -> BuildCommand {
        guard let latexmkPath else {
            throw CommandGenerationError.missingExecutable("latexmk")
        }

        var arguments: [String] = [
            configuration.preferredEngine.latexmkFlag,
            "-interaction=\(configuration.interactionMode.rawValue)",
            "-file-line-error",
            "-outdir=\(configuration.outputDirectory.path)",
            "-auxdir=\(configuration.auxDirectory.path)"
        ]

        if configuration.synctexEnabled {
            arguments.append("-synctex=1")
        }
        if configuration.haltOnError {
            arguments.append("-halt-on-error")
        }
        if configuration.shellEscape == .enabled {
            arguments.append("-shell-escape")
        } else {
            arguments.append("-no-shell-escape")
        }

        arguments.append(configuration.rootFile.path)

        return BuildCommand(
            executable: latexmkPath,
            arguments: arguments,
            workingDirectory: configuration.projectDirectory,
            environment: configuration.environment
        )
    }

    private func makeDirectCommand(_ configuration: BuildConfiguration, engine: LatexEngine) throws -> BuildCommand {
        guard let enginePath = enginePaths[engine] else {
            throw CommandGenerationError.missingExecutable(engine.rawValue)
        }

        var arguments: [String] = [
            "-interaction=\(configuration.interactionMode.rawValue)",
            "-file-line-error",
            "-output-directory=\(configuration.outputDirectory.path)"
        ]

        if configuration.synctexEnabled {
            arguments.append("-synctex=1")
        }
        if configuration.haltOnError {
            arguments.append("-halt-on-error")
        }
        arguments.append(configuration.shellEscape == .enabled ? "-shell-escape" : "-no-shell-escape")
        arguments.append(configuration.rootFile.path)

        return BuildCommand(
            executable: enginePath,
            arguments: arguments,
            workingDirectory: configuration.projectDirectory,
            environment: configuration.environment
        )
    }
}
```

## Process Wrapper

`Process` 래퍼는 다음 책임만 가진다.

- 실행 시작
- stdout/stderr 비동기 캡처
- 취소 시 프로세스 트리 종료
- 종료 코드와 캡처된 출력 반환
- 실행 중 이벤트 스트림 제공

```swift
enum BuildProcessEvent: Sendable {
    case started(command: BuildCommand)
    case stdout(String)
    case stderr(String)
    case terminated(exitCode: Int32)
}

struct BuildProcessResult: Sendable {
    var command: BuildCommand
    var exitCode: Int32
    var stdout: String
    var stderr: String
    var wasCancelled: Bool
}

final class LatexProcessRunner {
    private var process: Process?
    private let lock = NSLock()

    func run(
        command: BuildCommand,
        onEvent: @escaping @Sendable (BuildProcessEvent) -> Void
    ) async throws -> BuildProcessResult {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = command.executable
        process.arguments = command.arguments
        process.currentDirectoryURL = command.workingDirectory
        process.environment = ProcessInfo.processInfo.environment.merging(command.environment) { _, new in new }
        process.standardOutput = stdout
        process.standardError = stderr

        lock.lock()
        self.process = process
        lock.unlock()

        var stdoutText = ""
        var stderrText = ""

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            stdoutText += text
            onEvent(.stdout(text))
        }

        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            stderrText += text
            onEvent(.stderr(text))
        }

        onEvent(.started(command: command))
        try process.run()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                process.terminationHandler = { process in
                    stdout.fileHandleForReading.readabilityHandler = nil
                    stderr.fileHandleForReading.readabilityHandler = nil
                    onEvent(.terminated(exitCode: process.terminationStatus))
                    continuation.resume(returning: BuildProcessResult(
                        command: command,
                        exitCode: process.terminationStatus,
                        stdout: stdoutText,
                        stderr: stderrText,
                        wasCancelled: false
                    ))
                }
            }
        } onCancel: {
            self.cancel()
        }
    }

    func cancel() {
        lock.lock()
        let process = self.process
        lock.unlock()

        guard let process, process.isRunning else { return }
        process.terminate()

        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
    }
}
```

주의: 위 골격은 방향을 보여주는 코드다. 실제 앱 코드에서는 `stdoutText`/`stderrText` 동시 접근을 actor나 serial queue로 보호해야 한다. `latexmk`가 하위 프로세스를 만들 수 있으므로, 취소 안정성을 높이려면 process group을 만들고 group 전체에 signal을 보내는 별도 launch helper를 고려한다.

## Build Cancellation

취소 정책:

1. 사용자가 빌드 버튼을 다시 누르면 현재 빌드를 취소하고 새 빌드를 큐에 넣는다.
2. `Task.cancel()`이 들어오면 `Process.terminate()`로 SIGTERM을 보낸다.
3. 1초 후에도 살아 있으면 SIGKILL로 종료한다.
4. 취소된 빌드 결과는 error issue로 표시하지 않고 `BuildStatus.cancelled`로 끝낸다.
5. 취소 중 생성된 불완전 PDF는 기존 성공 산출물을 덮어쓰지 않도록 임시 output directory 전략을 쓴다.

권장 상태 모델:

```swift
enum BuildStatus: Sendable, Equatable {
    case idle
    case running(startedAt: Date)
    case succeeded(BuildArtifact)
    case failed([BuildIssue])
    case cancelled
}

struct BuildArtifact: Sendable, Equatable {
    var pdfURL: URL
    var logURL: URL?
    var synctexURL: URL?
    var builtAt: Date
}
```

## Incremental Rebuild

MVP 기준:

- 루트 `.tex` 파일의 수정 시간이 마지막 성공 빌드보다 최신이면 rebuild.
- 산출 PDF가 없으면 rebuild.
- build configuration이 바뀌면 rebuild.
- `latexmk` 사용 시 증분 판단은 대부분 `latexmk`에 위임한다.

1차 개선:

- `.fls` 파일에서 `INPUT` 목록을 읽고 의존 파일 수정 시간을 비교한다.
- `.bib`, `.sty`, 이미지 파일, `\input`/`\include` 대상 파일을 포함한다.
- 마지막 빌드의 configuration hash를 저장한다.

```swift
struct BuildFingerprint: Codable, Sendable, Equatable {
    var configurationHash: String
    var dependencyModificationDates: [URL: Date]
    var lastSuccessfulBuildAt: Date
}

struct IncrementalBuildPlanner {
    func needsRebuild(configuration: BuildConfiguration, fingerprint: BuildFingerprint?, pdfURL: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: pdfURL.path) else { return true }
        guard let fingerprint else { return true }

        let currentHash = stableHash(configuration)
        if currentHash != fingerprint.configurationHash {
            return true
        }

        for (url, previousDate) in fingerprint.dependencyModificationDates {
            guard let currentDate = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else {
                return true
            }
            if currentDate > previousDate {
                return true
            }
        }

        return false
    }

    private func stableHash(_ configuration: BuildConfiguration) -> String {
        // 실제 구현에서는 JSONEncoder + CryptoKit.SHA256 사용.
        // skeleton에서는 세부 구현을 생략한다.
        ""
    }
}
```

실제 구현에서는 `Codable` 직렬화 후 CryptoKit `SHA256`으로 안정적인 hash를 만든다. Swift의 `hashValue`는 실행마다 달라질 수 있으므로 fingerprint 저장용으로 쓰지 않는다.

## Output Capture

캡처 채널은 세 가지로 나눈다.

- raw stdout/stderr: 빌드 콘솔 UI에 그대로 표시
- normalized log stream: 줄 단위로 parser에 전달
- final `.log` file: 빌드 종료 후 가장 신뢰할 수 있는 파싱 대상

LaTeX 오류는 stdout과 `.log`에 모두 나타나지만, 줄 접힘과 인코딩 문제가 있으므로 최종 이슈 목록은 `.log` 파일을 우선한다. `.log`가 없으면 stdout/stderr parser로 fallback한다.

## Build Log Parser

파서 목표는 완벽한 TeX parser가 아니라, 편집기 UX에 필요한 높은 신뢰도의 issue 추출이다.

감지 대상:

- 오류: `! Undefined control sequence.`
- file-line-error: `./main.tex:12: Undefined control sequence.`
- 경고: `LaTeX Warning: Reference 'x' on page 1 undefined on input line 23.`
- overfull/underfull box: `Overfull \hbox ... at lines 40--42`
- missing file: `LaTeX Error: File 'foo.sty' not found.`
- rerun 필요: `Rerun to get cross-references right.`

```swift
enum BuildIssueSeverity: String, Codable, Sendable {
    case error
    case warning
    case info
}

struct SourceLocation: Codable, Sendable, Equatable, Hashable {
    var fileURL: URL
    var line: Int
    var column: Int?
}

struct BuildIssue: Identifiable, Codable, Sendable, Equatable {
    var id: UUID
    var severity: BuildIssueSeverity
    var message: String
    var location: SourceLocation?
    var rawLogExcerpt: String
    var category: BuildIssueCategory
}

enum BuildIssueCategory: String, Codable, Sendable {
    case latexError
    case latexWarning
    case missingFile
    case overfullBox
    case underfullBox
    case rerunRequired
    case processFailure
}
```

```swift
struct BuildLogParser {
    func parse(logText: String, rootFile: URL, projectDirectory: URL) -> [BuildIssue] {
        var issues: [BuildIssue] = []
        let lines = logText.components(separatedBy: .newlines)

        for (index, line) in lines.enumerated() {
            if let issue = parseFileLineError(line, projectDirectory: projectDirectory) {
                issues.append(issue)
                continue
            }

            if line.hasPrefix("LaTeX Warning:") {
                issues.append(parseLatexWarning(line, context: lines, index: index, rootFile: rootFile))
                continue
            }

            if line.hasPrefix("Overfull \\hbox") || line.hasPrefix("Underfull \\hbox") {
                issues.append(parseBoxWarning(line, projectDirectory: projectDirectory))
                continue
            }

            if line.hasPrefix("! ") {
                issues.append(BuildIssue(
                    id: UUID(),
                    severity: .error,
                    message: String(line.dropFirst(2)),
                    location: nil,
                    rawLogExcerpt: excerpt(lines, around: index),
                    category: .latexError
                ))
            }
        }

        return coalesceDuplicates(issues)
    }

    private func parseFileLineError(_ line: String, projectDirectory: URL) -> BuildIssue? {
        let pattern = #"^(.+\.tex):(\d+):\s*(.+)$"#
        guard let match = line.firstMatch(pattern: pattern) else { return nil }

        let path = match[1]
        let lineNumber = Int(match[2]) ?? 1
        let message = match[3]
        let fileURL = URL(fileURLWithPath: path, relativeTo: projectDirectory).standardizedFileURL

        return BuildIssue(
            id: UUID(),
            severity: .error,
            message: message,
            location: SourceLocation(fileURL: fileURL, line: lineNumber, column: nil),
            rawLogExcerpt: line,
            category: .latexError
        )
    }

    private func parseLatexWarning(
        _ line: String,
        context: [String],
        index: Int,
        rootFile: URL
    ) -> BuildIssue {
        let inputLinePattern = #"input line (\d+)"#
        let lineNumber = line.firstMatch(pattern: inputLinePattern).flatMap { Int($0[1]) }

        return BuildIssue(
            id: UUID(),
            severity: .warning,
            message: line.replacingOccurrences(of: "LaTeX Warning: ", with: ""),
            location: lineNumber.map {
                SourceLocation(fileURL: rootFile, line: $0, column: nil)
            },
            rawLogExcerpt: excerpt(context, around: index),
            category: .latexWarning
        )
    }

    private func parseBoxWarning(_ line: String, projectDirectory: URL) -> BuildIssue {
        let isOverfull = line.hasPrefix("Overfull")
        return BuildIssue(
            id: UUID(),
            severity: .warning,
            message: line,
            location: nil,
            rawLogExcerpt: line,
            category: isOverfull ? .overfullBox : .underfullBox
        )
    }

    private func excerpt(_ lines: [String], around index: Int) -> String {
        let start = max(0, index - 2)
        let end = min(lines.count, index + 3)
        return lines[start..<end].joined(separator: "\n")
    }

    private func coalesceDuplicates(_ issues: [BuildIssue]) -> [BuildIssue] {
        var seen = Set<String>()
        return issues.filter { issue in
            let key = "\(issue.severity.rawValue)|\(issue.category.rawValue)|\(issue.location?.fileURL.path ?? "")|\(issue.location?.line ?? 0)|\(issue.message)"
            return seen.insert(key).inserted
        }
    }
}
```

정규식 helper:

```swift
extension String {
    func firstMatch(pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(startIndex..<endIndex, in: self)
        guard let match = regex.firstMatch(in: self, range: range) else { return nil }

        return (0..<match.numberOfRanges).compactMap { index in
            guard let range = Range(match.range(at: index), in: self) else { return nil }
            return String(self[range])
        }
    }
}
```

## Error Location Mapping

가장 안정적인 경로는 `-file-line-error` 옵션이다. 이 옵션이 켜져 있으면 오류가 `path.tex:line: message` 형식으로 나오므로 직접 `SourceLocation`을 만든다.

보조 전략:

- `.log`의 파일 스택을 추적해 현재 열린 파일을 유지한다.
- `l.<line>` 패턴을 만나면 현재 파일 + line으로 매핑한다.
- warning의 `input line <n>`은 root file 또는 현재 파일 스택으로 매핑한다.
- `synctex`는 PDF 위치에서 소스 위치로 이동할 때 사용하고, build issue 위치 매핑의 1차 수단으로 쓰지 않는다.

파일 스택 파싱은 TeX 로그의 괄호 구조 때문에 까다롭다. MVP에서는 `-file-line-error`를 항상 켜고, 파일 스택은 "위치 없음" 이슈를 줄이기 위한 개선 항목으로 둔다.

## Navigable Issue List 설계

UI 모델:

```swift
struct BuildIssueRowViewModel: Identifiable, Equatable {
    var id: UUID
    var iconName: String
    var title: String
    var subtitle: String
    var locationText: String?
    var issue: BuildIssue
}
```

동작:

- error, warning, info 순서로 그룹화한다.
- 같은 파일 안에서는 line 오름차순으로 정렬한다.
- 위치가 있는 항목 클릭 시 에디터가 해당 파일/라인으로 이동한다.
- 위치가 없는 항목 클릭 시 build console의 raw excerpt를 강조한다.
- 빌드가 새로 시작되면 이전 이슈는 흐리게 유지하거나 비우고, 진행 중 상태를 별도로 표시한다.
- `rerunRequired`는 자동 재빌드 가능 상태이면 info로 숨기고, 직접 실행 fallback에서 pass 한도 초과 시 warning으로 보여준다.

탐색 API:

```swift
protocol BuildIssueNavigating: AnyObject {
    func revealIssue(_ issue: BuildIssue)
}

final class BuildIssueNavigator: BuildIssueNavigating {
    func revealIssue(_ issue: BuildIssue) {
        guard let location = issue.location else {
            // Build console에서 rawLogExcerpt를 선택한다.
            return
        }

        // EditorCoordinator.open(file: location.fileURL, line: location.line, column: location.column)
    }
}
```

## Build Coordinator Skeleton

```swift
actor BuildCoordinator {
    private let commandGenerator: BuildCommandGenerator
    private let processRunner: LatexProcessRunner
    private let logParser: BuildLogParser
    private var currentTask: Task<BuildStatus, Never>?

    init(
        commandGenerator: BuildCommandGenerator,
        processRunner: LatexProcessRunner,
        logParser: BuildLogParser
    ) {
        self.commandGenerator = commandGenerator
        self.processRunner = processRunner
        self.logParser = logParser
    }

    func build(configuration: BuildConfiguration) -> Task<BuildStatus, Never> {
        currentTask?.cancel()

        let task = Task { [commandGenerator, processRunner, logParser] in
            do {
                let commands = try commandGenerator.makeCommands(for: configuration)
                var lastResult: BuildProcessResult?

                for command in commands {
                    let result = try await processRunner.run(command: command) { event in
                        // Build console stream으로 전달한다.
                    }
                    lastResult = result

                    if Task.isCancelled {
                        return .cancelled
                    }
                    if result.exitCode != 0 {
                        break
                    }
                }

                let logText = readBestAvailableLog(configuration: configuration, fallback: lastResult)
                let issues = logParser.parse(
                    logText: logText,
                    rootFile: configuration.rootFile,
                    projectDirectory: configuration.projectDirectory
                )

                if let result = lastResult, result.exitCode == 0, !issues.contains(where: { $0.severity == .error }) {
                    return .succeeded(BuildArtifact(
                        pdfURL: pdfURL(for: configuration),
                        logURL: logURL(for: configuration),
                        synctexURL: synctexURL(for: configuration),
                        builtAt: Date()
                    ))
                }

                return .failed(issues)
            } catch is CancellationError {
                return .cancelled
            } catch {
                return .failed([
                    BuildIssue(
                        id: UUID(),
                        severity: .error,
                        message: error.localizedDescription,
                        location: nil,
                        rawLogExcerpt: "",
                        category: .processFailure
                    )
                ])
            }
        }

        currentTask = task
        return task
    }

    func cancel() {
        currentTask?.cancel()
        processRunner.cancel()
    }
}
```

위 skeleton의 `readBestAvailableLog`, `pdfURL`, `logURL`, `synctexURL`은 경로 helper로 분리한다. 직접 실행 fallback에서 여러 pass를 돌릴 경우에는 `commands`를 pass 수만큼 만들거나 coordinator가 rerun 신호를 보고 같은 command를 반복한다.

## Fallback Strategy

권장 순서:

1. `latexmk` 존재 확인: `/Library/TeX/texbin/latexmk`, `/usr/local/bin/latexmk`, `/opt/homebrew/bin/latexmk`, PATH 탐색.
2. 사용자가 선택한 엔진 존재 확인.
3. `latexmk`가 없으면 direct engine 실행.
4. direct engine도 없으면 "MacTeX 또는 BasicTeX 설치 필요" 이슈를 생성한다.

`latexmk` 실행 실패 fallback은 조심해야 한다. TeX 문서 오류로 실패한 경우 direct 실행으로 바꿔도 해결되지 않는다. fallback은 "실행 파일 없음" 또는 "latexmk 자체 실행 실패"일 때만 적용한다.

## Security Defaults

- `shellEscape` 기본값은 `.disabled`.
- 명령 생성 시 항상 `-no-shell-escape` 또는 `-shell-escape`를 명시한다.
- 프로젝트 설정에 shell escape를 저장할 때 사용자 확인을 요구한다.
- 빌드 프로세스는 프로젝트 디렉터리에서 실행하되, output/aux는 `.paperforge-build` 아래로 격리한다.
- PATH는 앱 기본 환경에 TeX 경로를 추가하되, 임의 shell을 거치지 않는다.

## MVP 구현 순서

1. `BuildConfiguration`, `BuildCommand`, `BuildIssue` 모델 추가.
2. TeX 실행 파일 탐색기 추가.
3. `BuildCommandGenerator` 구현.
4. `LatexProcessRunner` 구현.
5. `BuildCoordinator`에서 build/cancel 상태 연결.
6. `.log` 우선 `BuildLogParser` 구현.
7. SwiftUI issue list와 editor navigation 연결.
8. `.fls` 기반 dependency fingerprint 추가.

## 테스트 전략

- command generation unit test: engine, shell escape, output dir, synctex 옵션 검증.
- parser unit test: 대표 LaTeX error/warning log fixture 검증.
- cancellation integration test: 긴 빌드를 시작한 뒤 취소 시 status가 `.cancelled`인지 검증.
- missing executable test: `latexmk`가 없을 때 direct fallback 또는 processFailure issue 확인.
- incremental test: dependency mtime 변경 전후 rebuild 판단 검증.
