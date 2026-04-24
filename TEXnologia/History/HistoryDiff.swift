import Foundation

enum DiffLineKind: Equatable {
    case context
    case added
    case removed
}

struct DiffLine: Identifiable, Equatable {
    let id = UUID()
    let kind: DiffLineKind
    let text: String
    let oldLineNumber: Int?
    let newLineNumber: Int?
}

struct DiffStats: Equatable {
    var added: Int = 0
    var removed: Int = 0
    var isIdentical: Bool { added == 0 && removed == 0 }
}

enum HistoryDiffComputer {
    static func computeLines(from oldText: String, to newText: String) -> [DiffLine] {
        let oldLines = splitLines(oldText)
        let newLines = splitLines(newText)
        let diff = newLines.difference(from: oldLines)

        var removedAtOldOffset: [Int: String] = [:]
        var addedAtNewOffset: [Int: String] = [:]
        for change in diff {
            switch change {
            case .remove(let offset, let element, _):
                removedAtOldOffset[offset] = element
            case .insert(let offset, let element, _):
                addedAtNewOffset[offset] = element
            }
        }

        var result: [DiffLine] = []
        var oldIdx = 0
        var newIdx = 0

        while oldIdx < oldLines.count || newIdx < newLines.count {
            let isRemoved = oldIdx < oldLines.count && removedAtOldOffset[oldIdx] != nil
            let isAdded = newIdx < newLines.count && addedAtNewOffset[newIdx] != nil

            if isRemoved && isAdded {
                result.append(DiffLine(
                    kind: .removed,
                    text: oldLines[oldIdx],
                    oldLineNumber: oldIdx + 1,
                    newLineNumber: nil
                ))
                result.append(DiffLine(
                    kind: .added,
                    text: newLines[newIdx],
                    oldLineNumber: nil,
                    newLineNumber: newIdx + 1
                ))
                oldIdx += 1
                newIdx += 1
            } else if isRemoved {
                result.append(DiffLine(
                    kind: .removed,
                    text: oldLines[oldIdx],
                    oldLineNumber: oldIdx + 1,
                    newLineNumber: nil
                ))
                oldIdx += 1
            } else if isAdded {
                result.append(DiffLine(
                    kind: .added,
                    text: newLines[newIdx],
                    oldLineNumber: nil,
                    newLineNumber: newIdx + 1
                ))
                newIdx += 1
            } else if oldIdx < oldLines.count && newIdx < newLines.count {
                result.append(DiffLine(
                    kind: .context,
                    text: oldLines[oldIdx],
                    oldLineNumber: oldIdx + 1,
                    newLineNumber: newIdx + 1
                ))
                oldIdx += 1
                newIdx += 1
            } else if oldIdx < oldLines.count {
                result.append(DiffLine(
                    kind: .removed,
                    text: oldLines[oldIdx],
                    oldLineNumber: oldIdx + 1,
                    newLineNumber: nil
                ))
                oldIdx += 1
            } else if newIdx < newLines.count {
                result.append(DiffLine(
                    kind: .added,
                    text: newLines[newIdx],
                    oldLineNumber: nil,
                    newLineNumber: newIdx + 1
                ))
                newIdx += 1
            }
        }

        return result
    }

    static func collapseToHunks(_ lines: [DiffLine], context: Int = 3) -> [DiffHunk] {
        guard !lines.isEmpty else { return [] }
        let changedIndexes = lines.enumerated().compactMap { $0.element.kind == .context ? nil : $0.offset }
        if changedIndexes.isEmpty {
            return []
        }

        var ranges: [ClosedRange<Int>] = []
        for index in changedIndexes {
            let start = max(0, index - context)
            let end = min(lines.count - 1, index + context)
            if let last = ranges.last, start <= last.upperBound + 1 {
                ranges[ranges.count - 1] = last.lowerBound...max(last.upperBound, end)
            } else {
                ranges.append(start...end)
            }
        }

        return ranges.map { range in
            DiffHunk(lines: Array(lines[range]))
        }
    }

    static func stats(for lines: [DiffLine]) -> DiffStats {
        var stats = DiffStats()
        for line in lines {
            switch line.kind {
            case .added: stats.added += 1
            case .removed: stats.removed += 1
            case .context: break
            }
        }
        return stats
    }

    private static func splitLines(_ text: String) -> [String] {
        if text.isEmpty { return [] }
        var lines = text.components(separatedBy: "\n")
        if text.hasSuffix("\n"), lines.last == "" {
            lines.removeLast()
        }
        return lines
    }
}

struct DiffHunk: Identifiable, Equatable {
    let id = UUID()
    let lines: [DiffLine]

    var header: String {
        let oldStart = lines.compactMap(\.oldLineNumber).first ?? 0
        let oldCount = lines.filter { $0.kind != .added }.count
        let newStart = lines.compactMap(\.newLineNumber).first ?? 0
        let newCount = lines.filter { $0.kind != .removed }.count
        return "@@ -\(oldStart),\(oldCount) +\(newStart),\(newCount) @@"
    }
}

enum LatexDiffExporter {
    static func export(from oldText: String, to newText: String) -> String {
        let oldTokens = tokenize(oldText)
        let newTokens = tokenize(newText)
        let diff = newTokens.difference(from: oldTokens)

        var removedAtOldOffset: [Int: Bool] = [:]
        var addedAtNewOffset: [Int: Bool] = [:]
        for change in diff {
            switch change {
            case .remove(let offset, _, _):
                removedAtOldOffset[offset] = true
            case .insert(let offset, _, _):
                addedAtNewOffset[offset] = true
            }
        }

        var output = ""
        var delBuffer: [String] = []
        var addBuffer: [String] = []

        func flush() {
            let delText = trimToBoundaryWords(delBuffer)
            let addText = trimToBoundaryWords(addBuffer)
            if !delText.core.isEmpty {
                output += delText.leading
                output += "\\DIFdelbegin \\DIFdel{\(delText.core)} \\DIFdelend"
                output += delText.trailing
            } else {
                output += delText.leading + delText.trailing
            }
            if !addText.core.isEmpty {
                if !delText.core.isEmpty { output += " " }
                output += addText.leading
                output += "\\DIFaddbegin \\DIFadd{\(addText.core)} \\DIFaddend"
                output += addText.trailing
            } else {
                output += addText.leading + addText.trailing
            }
            delBuffer.removeAll()
            addBuffer.removeAll()
        }

        var oldIdx = 0
        var newIdx = 0
        while oldIdx < oldTokens.count || newIdx < newTokens.count {
            let isRemoved = oldIdx < oldTokens.count && removedAtOldOffset[oldIdx] == true
            let isAdded = newIdx < newTokens.count && addedAtNewOffset[newIdx] == true

            if isRemoved {
                delBuffer.append(oldTokens[oldIdx])
                oldIdx += 1
            } else if isAdded {
                addBuffer.append(newTokens[newIdx])
                newIdx += 1
            } else if oldIdx < oldTokens.count && newIdx < newTokens.count {
                flush()
                output += oldTokens[oldIdx]
                oldIdx += 1
                newIdx += 1
            } else if oldIdx < oldTokens.count {
                delBuffer.append(oldTokens[oldIdx])
                oldIdx += 1
            } else {
                addBuffer.append(newTokens[newIdx])
                newIdx += 1
            }
        }
        flush()

        return collapseWhitespace(output)
    }

    private struct TrimmedRun {
        let leading: String
        let core: String
        let trailing: String
    }

    private static func trimToBoundaryWords(_ tokens: [String]) -> TrimmedRun {
        guard !tokens.isEmpty else {
            return TrimmedRun(leading: "", core: "", trailing: "")
        }
        var start = 0
        var end = tokens.count
        while start < end, tokens[start].isAllWhitespace {
            start += 1
        }
        while end > start, tokens[end - 1].isAllWhitespace {
            end -= 1
        }
        let leading = tokens[0..<start].joined()
        let trailing = tokens[end..<tokens.count].joined()
        let core = tokens[start..<end].joined()
        return TrimmedRun(leading: leading, core: core, trailing: trailing)
    }

    private static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inWhitespace: Bool? = nil
        for ch in text {
            let isSpace = ch.isWhitespace
            if let mode = inWhitespace {
                if mode == isSpace {
                    current.append(ch)
                } else {
                    tokens.append(current)
                    current = String(ch)
                    inWhitespace = isSpace
                }
            } else {
                current.append(ch)
                inWhitespace = isSpace
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    private static func collapseWhitespace(_ text: String) -> String {
        var result = ""
        var pendingSpace = false
        var pendingNewlines = 0
        for ch in text {
            if ch == "\n" {
                pendingNewlines += 1
                pendingSpace = false
            } else if ch.isWhitespace {
                if pendingNewlines == 0 {
                    pendingSpace = true
                }
            } else {
                if pendingNewlines > 0 {
                    result.append(String(repeating: "\n", count: min(pendingNewlines, 2)))
                    pendingNewlines = 0
                    pendingSpace = false
                } else if pendingSpace {
                    result.append(" ")
                    pendingSpace = false
                }
                result.append(ch)
            }
        }
        if pendingNewlines > 0 {
            result.append(String(repeating: "\n", count: min(pendingNewlines, 2)))
        } else if pendingSpace {
            result.append(" ")
        }
        return result
    }
}

private extension String {
    var isAllWhitespace: Bool {
        !isEmpty && allSatisfy { $0.isWhitespace }
    }
}
