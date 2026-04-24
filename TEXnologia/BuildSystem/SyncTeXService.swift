import Foundation

struct SyncTeXForwardResult: Equatable {
    var page: Int
    var x: Double
    var y: Double
}

struct SyncTeXReverseResult: Equatable {
    var inputFile: String
    var line: Int
    var column: Int
}

enum SyncTeXService {
    static func forward(
        sourceFile: URL,
        line: Int,
        column: Int,
        outputPDF: URL,
        synctex: URL?
    ) async -> SyncTeXForwardResult? {
        guard let synctex else { return nil }
        let arg = "\(line):\(max(column, 0)):\(sourceFile.path)"
        let result = await runProcess(
            executable: synctex,
            arguments: ["view", "-i", arg, "-o", outputPDF.path]
        )
        return parseForward(result.output)
    }

    static func reverse(
        page: Int,
        x: Double,
        y: Double,
        outputPDF: URL,
        synctex: URL?
    ) async -> SyncTeXReverseResult? {
        guard let synctex else { return nil }
        let arg = "\(page):\(x):\(y):\(outputPDF.path)"
        let result = await runProcess(
            executable: synctex,
            arguments: ["edit", "-o", arg]
        )
        return parseReverse(result.output)
    }

    static func parseForward(_ output: String) -> SyncTeXForwardResult? {
        var page: Int?
        var xValue: Double?
        var yValue: Double?
        for rawLine in output.components(separatedBy: CharacterSet.newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("Page:") { page = Int(line.dropFirst("Page:".count).trimmingCharacters(in: .whitespaces)) }
            else if line.hasPrefix("x:") { xValue = Double(line.dropFirst("x:".count).trimmingCharacters(in: .whitespaces)) }
            else if line.hasPrefix("y:") { yValue = Double(line.dropFirst("y:".count).trimmingCharacters(in: .whitespaces)) }
        }
        guard let p = page, let x = xValue, let y = yValue else { return nil }
        return SyncTeXForwardResult(page: p, x: x, y: y)
    }

    static func parseReverse(_ output: String) -> SyncTeXReverseResult? {
        var input: String?
        var lineNum: Int?
        var columnNum: Int?
        for rawLine in output.components(separatedBy: CharacterSet.newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("Input:") { input = String(line.dropFirst("Input:".count).trimmingCharacters(in: .whitespaces)) }
            else if line.hasPrefix("Line:") { lineNum = Int(line.dropFirst("Line:".count).trimmingCharacters(in: .whitespaces)) }
            else if line.hasPrefix("Column:") { columnNum = Int(line.dropFirst("Column:".count).trimmingCharacters(in: .whitespaces)) }
        }
        guard let input, let lineNum else { return nil }
        return SyncTeXReverseResult(inputFile: input, line: lineNum, column: columnNum ?? 0)
    }

    static func resolveBinary(near executables: [URL?]) -> URL? {
        for candidate in executables {
            guard let candidate else { continue }
            let synctex = candidate.deletingLastPathComponent().appendingPathComponent("synctex")
            if FileManager.default.isExecutableFile(atPath: synctex.path) {
                return synctex
            }
        }
        let fallbacks = [
            "/Library/TeX/texbin/synctex",
            "/usr/local/bin/synctex",
            "/opt/homebrew/bin/synctex"
        ]
        for path in fallbacks {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    private static func runProcess(executable: URL, arguments: [String]) async -> (output: String, exitCode: Int32) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = executable
                process.arguments = arguments
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    continuation.resume(returning: (output, process.terminationStatus))
                } catch {
                    continuation.resume(returning: ("", -1))
                }
            }
        }
    }
}
