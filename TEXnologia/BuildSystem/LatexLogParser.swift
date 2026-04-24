import Foundation

struct LatexLogParser {
    func parse(_ log: String, rootFile: URL) -> [BuildIssue] {
        var issues: [BuildIssue] = []
        issues.append(contentsOf: parseFileLineErrors(log, rootFile: rootFile))
        issues.append(contentsOf: parseBangErrors(log, rootFile: rootFile))
        issues.append(contentsOf: parseWarnings(log, rootFile: rootFile))
        return deduplicated(issues)
    }

    private func parseFileLineErrors(_ log: String, rootFile: URL) -> [BuildIssue] {
        let pattern = #"(?m)^(.+?\.tex):(\d+):\s*(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let range = NSRange(log.startIndex..<log.endIndex, in: log)
        return regex.matches(in: log, range: range).compactMap { match in
            guard
                let fileRange = Range(match.range(at: 1), in: log),
                let lineRange = Range(match.range(at: 2), in: log),
                let messageRange = Range(match.range(at: 3), in: log),
                let line = Int(log[lineRange])
            else {
                return nil
            }

            let fileURL = resolveFile(String(log[fileRange]), rootFile: rootFile)
            let message = String(log[messageRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            return BuildIssue(
                severity: message.localizedCaseInsensitiveContains("warning") ? .warning : .error,
                message: message,
                location: TextLocation(fileURL: fileURL, line: line, column: 1),
                rawLogExcerpt: context(around: match.range, in: log)
            )
        }
    }

    private func parseBangErrors(_ log: String, rootFile: URL) -> [BuildIssue] {
        let lines = log.components(separatedBy: .newlines)
        var issues: [BuildIssue] = []
        var currentFile = rootFile

        for (index, line) in lines.enumerated() {
            if let file = fileMention(in: line, rootFile: rootFile) {
                currentFile = file
            }

            guard line.hasPrefix("!") else { continue }

            let message = line.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
            let location = nearbyLineNumber(in: lines, from: index).map {
                TextLocation(fileURL: currentFile, line: $0, column: 1)
            }

            issues.append(BuildIssue(
                severity: .error,
                message: message,
                location: location,
                rawLogExcerpt: nearbyExcerpt(lines: lines, index: index)
            ))
        }

        return issues
    }

    private func parseWarnings(_ log: String, rootFile: URL) -> [BuildIssue] {
        let warningPatterns = [
            #"(?m)^LaTeX Warning: (.+)$"#,
            #"(?m)^Package .+ Warning: (.+)$"#,
            #"(?m)^(Overfull \\hbox .+)$"#,
            #"(?m)^(Underfull \\hbox .+)$"#
        ]

        var issues: [BuildIssue] = []
        for pattern in warningPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(log.startIndex..<log.endIndex, in: log)
            issues.append(contentsOf: regex.matches(in: log, range: range).compactMap { match in
                guard let messageRange = Range(match.range(at: 1), in: log) else { return nil }
                return BuildIssue(
                    severity: .warning,
                    message: String(log[messageRange]).trimmingCharacters(in: .whitespacesAndNewlines),
                    location: nil,
                    rawLogExcerpt: context(around: match.range, in: log)
                )
            })
        }

        return issues
    }

    private func resolveFile(_ path: String, rootFile: URL) -> URL {
        let expanded = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded).standardizedFileURL
        }
        return rootFile.deletingLastPathComponent().appendingPathComponent(expanded).standardizedFileURL
    }

    private func fileMention(in line: String, rootFile: URL) -> URL? {
        guard let range = line.range(of: #"[^()\s]+\.tex"#, options: .regularExpression) else {
            return nil
        }
        return resolveFile(String(line[range]), rootFile: rootFile)
    }

    private func nearbyLineNumber(in lines: [String], from index: Int) -> Int? {
        let end = min(lines.count - 1, index + 8)
        guard index <= end else { return nil }

        for line in lines[index...end] {
            if let range = line.range(of: #"l\.(\d+)"#, options: .regularExpression) {
                let raw = line[range].dropFirst(2)
                return Int(raw)
            }
        }

        return nil
    }

    private func nearbyExcerpt(lines: [String], index: Int) -> String {
        let start = max(0, index - 2)
        let end = min(lines.count - 1, index + 6)
        guard start <= end else { return "" }
        return lines[start...end].joined(separator: "\n")
    }

    private func context(around range: NSRange, in text: String) -> String {
        let nsText = text as NSString
        let start = max(0, range.location - 400)
        let end = min(nsText.length, range.location + range.length + 400)
        return nsText.substring(with: NSRange(location: start, length: end - start))
    }

    private func deduplicated(_ issues: [BuildIssue]) -> [BuildIssue] {
        var seen: Set<String> = []
        return issues.filter { issue in
            let key = [
                issue.severity.rawValue,
                issue.location?.fileURL.path ?? "",
                String(issue.location?.line ?? 0),
                issue.message
            ].joined(separator: "|")

            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }
}
