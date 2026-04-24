import Foundation

final class ProjectIndexer {
    func detectRootFile(in rootURL: URL) -> URL? {
        let texFiles = findFiles(in: rootURL, extensions: ["tex"])
        return texFiles
            .map { ($0, rootScore(for: $0)) }
            .sorted { $0.1 > $1.1 }
            .first?
            .0
    }

    func indexProject(rootURL: URL, mainFileURL: URL?) -> ProjectIndex {
        let texFiles = findFiles(in: rootURL, extensions: ["tex"])
        let bibFiles = findFiles(in: rootURL, extensions: ["bib"])
        let parsedTex = texFiles.map(parseTexFile)
        let parsedBib = bibFiles.flatMap(parseBibFile)

        return ProjectIndex(
            rootURL: rootURL,
            rootFiles: mainFileURL.map { [$0] } ?? [],
            texFiles: texFiles,
            bibFiles: bibFiles,
            outline: parsedTex.flatMap(\.outline),
            labels: Dictionary(parsedTex.flatMap(\.labels), uniquingKeysWith: { first, _ in first }),
            citationKeys: parsedBib.sorted()
        )
    }

    private func findFiles(in rootURL: URL, extensions allowedExtensions: Set<String>) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator
            .compactMap { $0 as? URL }
            .filter { allowedExtensions.contains($0.pathExtension.lowercased()) }
    }

    private func rootScore(for fileURL: URL) -> Int {
        let text = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        var score = 0
        if text.contains("\\documentclass") { score += 60 }
        if text.contains("\\begin{document}") { score += 40 }
        if fileURL.lastPathComponent.lowercased() == "main.tex" { score += 20 }
        return score
    }

    private func parseTexFile(_ fileURL: URL) -> (outline: [OutlineItem], labels: [(String, TextLocation)]) {
        let text = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        let lines = text.components(separatedBy: .newlines)
        var outline: [OutlineItem] = []
        var labels: [(String, TextLocation)] = []

        for (index, line) in lines.enumerated() {
            if let section = capture(#"\\(section|subsection|paragraph)\*?(?:\[[^\]]*\])?\{([^}]*)\}"#, in: line) {
                outline.append(OutlineItem(
                    title: section.value,
                    command: section.command,
                    level: outlineLevel(for: section.command),
                    location: TextLocation(fileURL: fileURL, line: index + 1, column: 1)
                ))
            }

            if let label = capture(#"\\label\{([^}]*)\}"#, in: line)?.value {
                labels.append((label, TextLocation(fileURL: fileURL, line: index + 1, column: 1)))
            }
        }

        return (outline, labels)
    }

    private func outlineLevel(for command: String) -> Int {
        switch command {
        case "section": return 1
        case "subsection": return 2
        case "paragraph": return 3
        default: return 1
        }
    }

    private func parseBibFile(_ fileURL: URL) -> [String] {
        let text = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        let regex = try? NSRegularExpression(pattern: #"@\w+\s*\{\s*([^,\s]+)"#)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex?.matches(in: text, range: range).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        } ?? []
    }

    private func capture(_ pattern: String, in line: String) -> (command: String, value: String)? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range) else { return nil }

        if match.numberOfRanges == 3,
           let commandRange = Range(match.range(at: 1), in: line),
           let valueRange = Range(match.range(at: 2), in: line) {
            return (String(line[commandRange]), String(line[valueRange]))
        }

        if match.numberOfRanges == 2,
           let valueRange = Range(match.range(at: 1), in: line) {
            return ("", String(line[valueRange]))
        }

        return nil
    }
}
