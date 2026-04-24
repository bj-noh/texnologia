import Foundation

actor LatexBuildService {
    func build(configuration: BuildConfiguration) async -> BuildResult {
        do {
            try prepareBuildDirectory(configuration.outputDirectory)

            let toolchain = ToolchainResolver().resolve(year: configuration.toolchainYear)
            let result: ProcessExecutionResult

            if let latexmk = toolchain.latexmk {
                result = try await runLatexmk(configuration, executable: latexmk, toolchain: toolchain)
            } else if let engine = toolchain.path(for: configuration.engine) {
                result = try await runDirectEngine(configuration, executable: engine, toolchain: toolchain)
            } else {
                return missingToolchainResult(configuration: configuration, toolchain: toolchain)
            }

            let combinedLog = result.output + "\n" + readTranscript(configuration)
            var issues = LatexLogParser().parse(combinedLog, rootFile: configuration.rootFile)
            issues.append(contentsOf: processIssues(from: result))

            let pdfURL = expectedPDFURL(configuration)
            let succeeded = result.exitCode == 0
                && FileManager.default.fileExists(atPath: pdfURL.path)
                && issues.allSatisfy { $0.severity != .error }

            if !succeeded && issues.isEmpty {
                issues.append(BuildIssue(
                    severity: .error,
                    message: "LaTeX build failed without a file-line error. Open the raw log for details.",
                    location: nil,
                    rawLogExcerpt: String(combinedLog.suffix(2_000))
                ))
            }

            return BuildResult(
                succeeded: succeeded,
                pdfURL: FileManager.default.fileExists(atPath: pdfURL.path) ? pdfURL : nil,
                issues: issues,
                rawLog: combinedLog
            )
        } catch {
            return BuildResult(
                succeeded: false,
                pdfURL: nil,
                issues: [
                    BuildIssue(
                        severity: .error,
                        message: error.localizedDescription,
                        location: nil,
                        rawLogExcerpt: ""
                    )
                ],
                rawLog: ""
            )
        }
    }

    private func runLatexmk(
        _ configuration: BuildConfiguration,
        executable: URL,
        toolchain: Toolchain
    ) async throws -> ProcessExecutionResult {
        var arguments = [
            configuration.engine.latexmkFlag,
            "-interaction=nonstopmode",
            "-file-line-error",
            "-outdir=\(configuration.outputDirectory.path)",
            "-auxdir=\(configuration.outputDirectory.path)"
        ]

        arguments.append(configuration.synctexEnabled ? "-synctex=1" : "-synctex=0")
        arguments.append(configuration.shellEscape ? "-shell-escape" : "-no-shell-escape")
        arguments.append(configuration.rootFile.lastPathComponent)

        return try await ProcessRunner().run(
            executable: executable,
            arguments: arguments,
            workingDirectory: configuration.projectDirectory,
            environment: toolchain.environment
        )
    }

    private func runDirectEngine(
        _ configuration: BuildConfiguration,
        executable: URL,
        toolchain: Toolchain
    ) async throws -> ProcessExecutionResult {
        var accumulatedOutput = ""
        var lastResult = ProcessExecutionResult(exitCode: 1, output: "")
        var didRunBibTeX = false

        for pass in 1...max(1, configuration.maxDirectPasses) {
            let result = try await ProcessRunner().run(
                executable: executable,
                arguments: directArguments(configuration),
                workingDirectory: configuration.projectDirectory,
                environment: toolchain.environment
            )

            accumulatedOutput += "\n--- \(configuration.engine.displayName) pass \(pass) ---\n"
            accumulatedOutput += result.output
            lastResult = ProcessExecutionResult(exitCode: result.exitCode, output: accumulatedOutput)

            if result.exitCode != 0 {
                break
            }

            let transcript = result.output + "\n" + readTranscript(configuration)
            if !didRunBibTeX, shouldRunBibTeX(configuration, transcript: transcript) {
                didRunBibTeX = true
                if let bibTeX = toolchain.bibTeX {
                    let bibResult = try await ProcessRunner().run(
                        executable: bibTeX,
                        arguments: [configuration.rootFile.deletingPathExtension().lastPathComponent],
                        workingDirectory: configuration.outputDirectory,
                        environment: bibTeXEnvironment(configuration, toolchain: toolchain)
                    )
                    accumulatedOutput += "\n--- BibTeX ---\n"
                    accumulatedOutput += bibResult.output
                    lastResult = ProcessExecutionResult(
                        exitCode: bibResult.exitCode,
                        output: accumulatedOutput
                    )

                    if bibResult.exitCode != 0 {
                        break
                    }

                    continue
                } else {
                    accumulatedOutput += "\n--- BibTeX ---\nBibTeX was required but no bibtex executable was found.\n"
                    lastResult = ProcessExecutionResult(exitCode: 1, output: accumulatedOutput)
                    break
                }
            }

            if !needsRerun(transcript) {
                break
            }
        }

        return lastResult
    }

    private func directArguments(_ configuration: BuildConfiguration) -> [String] {
        var arguments = [
            "-interaction=nonstopmode",
            "-file-line-error",
            "-output-directory=\(configuration.outputDirectory.path)"
        ]

        arguments.append(configuration.synctexEnabled ? "-synctex=1" : "-synctex=0")
        arguments.append(configuration.shellEscape ? "-shell-escape" : "-no-shell-escape")
        arguments.append(configuration.rootFile.lastPathComponent)
        return arguments
    }

    private func shouldRunBibTeX(_ configuration: BuildConfiguration, transcript: String) -> Bool {
        let baseName = configuration.rootFile.deletingPathExtension().lastPathComponent
        let auxURL = configuration.outputDirectory.appendingPathComponent(baseName).appendingPathExtension("aux")
        guard FileManager.default.fileExists(atPath: auxURL.path) else { return false }

        let aux = (try? String(contentsOf: auxURL, encoding: .utf8)) ?? ""
        let bblURL = configuration.outputDirectory.appendingPathComponent(baseName).appendingPathExtension("bbl")
        let hasBibliographyData = aux.contains("\\bibdata") || transcript.localizedCaseInsensitiveContains("No file \(baseName).bbl")
        let unresolvedCitations = transcript.localizedCaseInsensitiveContains("Citation") && transcript.localizedCaseInsensitiveContains("undefined")

        return hasBibliographyData && (!FileManager.default.fileExists(atPath: bblURL.path) || unresolvedCitations)
    }

    private func bibTeXEnvironment(_ configuration: BuildConfiguration, toolchain: Toolchain) -> [String: String] {
        var environment = toolchain.environment
        let projectTree = configuration.projectDirectory.path + "//:"
        environment["BIBINPUTS"] = projectTree + (environment["BIBINPUTS"] ?? "")
        environment["BSTINPUTS"] = projectTree + (environment["BSTINPUTS"] ?? "")
        return environment
    }

    private func prepareBuildDirectory(_ outputDirectory: URL) throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let marker = outputDirectory.appendingPathComponent(".texnologia-owned")
        if !FileManager.default.fileExists(atPath: marker.path) {
            try "TEXnologia build directory\n".write(to: marker, atomically: true, encoding: .utf8)
        }
    }

    private func expectedPDFURL(_ configuration: BuildConfiguration) -> URL {
        configuration.outputDirectory
            .appendingPathComponent(configuration.rootFile.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("pdf")
    }

    private func readTranscript(_ configuration: BuildConfiguration) -> String {
        let logURL = configuration.outputDirectory
            .appendingPathComponent(configuration.rootFile.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("log")

        return (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
    }

    private func needsRerun(_ log: String) -> Bool {
        let signals = [
            "Rerun to get cross-references right",
            "Label(s) may have changed",
            "There were undefined references",
            "Citation",
            "undefined"
        ]
        return signals.contains { log.localizedCaseInsensitiveContains($0) }
    }

    private func processIssues(from result: ProcessExecutionResult) -> [BuildIssue] {
        guard result.exitCode == 0 else { return [] }
        return []
    }

    private func missingToolchainResult(configuration: BuildConfiguration, toolchain: Toolchain) -> BuildResult {
        let searched = toolchain.searchedDirectories.map(\.path).joined(separator: "\n")
        return BuildResult(
            succeeded: false,
            pdfURL: nil,
            issues: [
                BuildIssue(
                    severity: .error,
                    message: "No TeX engine was found for \(configuration.engine.displayName) \(configuration.toolchainYear.displayName). Install MacTeX/BasicTeX or choose another TeX Live year.",
                    location: nil,
                    rawLogExcerpt: searched
                )
            ],
            rawLog: searched
        )
    }
}

struct ProcessExecutionResult: Sendable {
    var exitCode: Int32
    var output: String
}

struct ProcessRunner: Sendable {
    func run(
        executable: URL,
        arguments: [String],
        workingDirectory: URL,
        environment: [String: String]
    ) async throws -> ProcessExecutionResult {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.currentDirectoryURL = workingDirectory
            process.environment = environment

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            let output = LockedBuffer()
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                output.append(String(data: data, encoding: .utf8) ?? "")
            }

            try process.run()
            process.waitUntilExit()
            pipe.fileHandleForReading.readabilityHandler = nil

            let remaining = pipe.fileHandleForReading.readDataToEndOfFile()
            if !remaining.isEmpty {
                output.append(String(data: remaining, encoding: .utf8) ?? "")
            }

            return ProcessExecutionResult(exitCode: process.terminationStatus, output: output.value)
        }.value
    }
}

private final class LockedBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = ""

    var value: String {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ string: String) {
        lock.lock()
        storage += string
        lock.unlock()
    }
}

struct Toolchain: Sendable {
    var latexmk: URL?
    var pdfLaTeX: URL?
    var xeLaTeX: URL?
    var luaLaTeX: URL?
    var bibTeX: URL?
    var searchedDirectories: [URL]

    var environment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let path = searchedDirectories.map(\.path).joined(separator: ":")
        environment["PATH"] = path + ":" + (environment["PATH"] ?? "")
        return environment
    }

    func path(for engine: LatexEngine) -> URL? {
        switch engine {
        case .pdfLaTeX: return pdfLaTeX
        case .xeLaTeX: return xeLaTeX
        case .luaLaTeX: return luaLaTeX
        }
    }
}

struct ToolchainResolver: Sendable {
    func resolve(year: TexToolchainYear) -> Toolchain {
        let directories = candidateDirectories(year: year)
        return Toolchain(
            latexmk: find("latexmk", in: directories),
            pdfLaTeX: find("pdflatex", in: directories),
            xeLaTeX: find("xelatex", in: directories),
            luaLaTeX: find("lualatex", in: directories),
            bibTeX: find("bibtex", in: directories),
            searchedDirectories: directories
        )
    }

    private func candidateDirectories(year: TexToolchainYear) -> [URL] {
        var paths = [
            "/usr/local/texlive/\(year.rawValue)basic/bin/universal-darwin",
            "/usr/local/texlive/\(year.rawValue)basic/bin/x86_64-darwin",
            "/usr/local/texlive/\(year.rawValue)basic/bin/aarch64-darwin",
            "/usr/local/texlive/\(year.rawValue)/bin/universal-darwin",
            "/usr/local/texlive/\(year.rawValue)/bin/x86_64-darwin",
            "/usr/local/texlive/\(year.rawValue)/bin/aarch64-darwin",
            "/Library/TeX/texbin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin"
        ]

        if let path = ProcessInfo.processInfo.environment["PATH"] {
            paths.append(contentsOf: path.split(separator: ":").map(String.init))
        }

        var seen: Set<String> = []
        return paths.compactMap { path in
            let url = URL(fileURLWithPath: path)
            guard !seen.contains(url.path) else { return nil }
            seen.insert(url.path)
            return url
        }
    }

    private func find(_ executable: String, in directories: [URL]) -> URL? {
        directories
            .map { $0.appendingPathComponent(executable) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
