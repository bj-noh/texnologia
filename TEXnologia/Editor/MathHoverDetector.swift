import Foundation

struct MathHoverRange: Equatable {
    var startIndex: Int
    var endIndex: Int
    var source: String
    var display: Bool
}

enum MathHoverDetector {
    // Walks the text around `index` to find the enclosing math expression.
    // Returns nil if the index is not inside any math.
    static func mathRange(in text: String, at utf16Index: Int) -> MathHoverRange? {
        let ns = text as NSString
        let length = ns.length
        guard utf16Index >= 0, utf16Index <= length else { return nil }

        if let result = findDelimited(text: ns,
                                      length: length,
                                      index: utf16Index,
                                      open: "$$",
                                      close: "$$",
                                      display: true) { return result }
        if let result = findDelimited(text: ns,
                                      length: length,
                                      index: utf16Index,
                                      open: "\\[",
                                      close: "\\]",
                                      display: true) { return result }
        if let result = findDelimited(text: ns,
                                      length: length,
                                      index: utf16Index,
                                      open: "\\(",
                                      close: "\\)",
                                      display: false) { return result }
        return findSingleDollar(text: ns, length: length, index: utf16Index)
    }

    private static func findDelimited(
        text ns: NSString,
        length: Int,
        index: Int,
        open: String,
        close: String,
        display: Bool
    ) -> MathHoverRange? {
        var searchStart = 0
        while searchStart < length {
            let openRange = ns.range(of: open, options: [], range: NSRange(location: searchStart, length: length - searchStart))
            guard openRange.location != NSNotFound else { break }
            let afterOpen = openRange.location + openRange.length
            let closeRange = ns.range(of: close, options: [], range: NSRange(location: afterOpen, length: length - afterOpen))
            guard closeRange.location != NSNotFound else { break }
            if index >= openRange.location && index <= closeRange.location + closeRange.length {
                let sourceRange = NSRange(location: afterOpen, length: closeRange.location - afterOpen)
                let source = ns.substring(with: sourceRange).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !source.isEmpty else { return nil }
                return MathHoverRange(
                    startIndex: openRange.location,
                    endIndex: closeRange.location + closeRange.length,
                    source: source,
                    display: display
                )
            }
            searchStart = closeRange.location + closeRange.length
        }
        return nil
    }

    private static func findSingleDollar(text ns: NSString, length: Int, index: Int) -> MathHoverRange? {
        if let asOpen = attemptSingleDollar(text: ns, length: length, index: index, startLeftAt: min(index, length - 1)) {
            return asOpen
        }
        // Cursor might be on a closing `$`. Try again starting one position earlier.
        if index > 0 && index <= length {
            if let asClose = attemptSingleDollar(text: ns, length: length, index: index - 1, startLeftAt: index - 1) {
                return asClose
            }
        }
        return nil
    }

    private static func attemptSingleDollar(text ns: NSString, length: Int, index: Int, startLeftAt: Int) -> MathHoverRange? {
        var start: Int? = nil
        var i = startLeftAt
        while i >= 0 && i < length {
            let c = ns.character(at: i)
            if c == 0x24 && isSingleDollarBoundary(text: ns, length: length, at: i) {
                start = i
                break
            }
            if c == 0x0A { return nil }
            i -= 1
        }
        guard let openIndex = start else { return nil }

        var j = openIndex + 1
        var end: Int? = nil
        while j < length {
            let c = ns.character(at: j)
            if c == 0x24 && isSingleDollarBoundary(text: ns, length: length, at: j) {
                end = j
                break
            }
            if c == 0x0A { return nil }
            j += 1
        }
        guard let closeIndex = end, closeIndex > openIndex else { return nil }
        guard index >= openIndex && index <= closeIndex + 1 else { return nil }

        let sourceRange = NSRange(location: openIndex + 1, length: closeIndex - (openIndex + 1))
        let source = ns.substring(with: sourceRange).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return nil }
        return MathHoverRange(
            startIndex: openIndex,
            endIndex: closeIndex + 1,
            source: source,
            display: false
        )
    }

    private static func isSingleDollarBoundary(text ns: NSString, length: Int, at i: Int) -> Bool {
        guard i >= 0 && i < length else { return false }
        let prevIsEscape = (i >= 1 && ns.character(at: i - 1) == 0x5C)
        let nextIsDollar = (i + 1 < length && ns.character(at: i + 1) == 0x24)
        let prevIsDollar = (i >= 1 && ns.character(at: i - 1) == 0x24)
        return !prevIsEscape && !nextIsDollar && !prevIsDollar
    }
}
