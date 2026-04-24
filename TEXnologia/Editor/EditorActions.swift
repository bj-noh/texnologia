import AppKit
import Foundation

extension Notification.Name {
    static let editorToggleComment = Notification.Name("TXEditorToggleComment")
    static let editorDuplicateLine = Notification.Name("TXEditorDuplicateLine")
    static let editorDeleteLine = Notification.Name("TXEditorDeleteLine")
    static let editorSelectCurrentLine = Notification.Name("TXEditorSelectCurrentLine")
    static let editorMoveLineUp = Notification.Name("TXEditorMoveLineUp")
    static let editorMoveLineDown = Notification.Name("TXEditorMoveLineDown")
    static let editorPerformFind = Notification.Name("TXEditorPerformFind")
    static let editorRequestCursor = Notification.Name("TXEditorRequestCursor")
    static let editorDidReportCursor = Notification.Name("TXEditorDidReportCursor")
    static let pdfRequestLocation = Notification.Name("TXPDFRequestLocation")
    static let pdfDidReportLocation = Notification.Name("TXPDFDidReportLocation")
    static let pdfNavigateTo = Notification.Name("TXPDFNavigateTo")
}

struct EditorCursorReport {
    var fileURL: URL
    var line: Int
    var column: Int
}

struct PDFLocationReport {
    var pdfURL: URL
    var page: Int
    var x: Double
    var y: Double
}

struct PDFNavigationTarget {
    var page: Int
    var x: Double
    var y: Double
}

enum EditorTextOps {
    static func toggleComment(in textView: NSTextView) {
        let ns = textView.string as NSString
        let selection = textView.selectedRange()
        let lineRange = ns.lineRange(for: selection)
        let existing = ns.substring(with: lineRange)
        let lines = existing.split(separator: "\n", omittingEmptySubsequences: false)

        let nonEmptyLines = lines.filter { !$0.allSatisfy(\.isWhitespace) }
        let shouldComment = nonEmptyLines.contains { !$0.trimmingWhitespacePrefix.hasPrefix("%") }

        let transformed = lines.enumerated().map { _, line -> String in
            if line.allSatisfy(\.isWhitespace) { return String(line) }
            if shouldComment {
                return "% " + line
            } else {
                var l = String(line)
                if l.hasPrefix("% ") { l.removeFirst(2) }
                else if l.hasPrefix("%") { l.removeFirst(1) }
                return l
            }
        }
        let newText = transformed.joined(separator: "\n")
        guard textView.shouldChangeText(in: lineRange, replacementString: newText) else { return }
        textView.replaceCharacters(in: lineRange, with: newText)
        textView.didChangeText()
    }

    static func duplicateLine(in textView: NSTextView) {
        let ns = textView.string as NSString
        let selection = textView.selectedRange()
        let lineRange = ns.lineRange(for: selection)
        var block = ns.substring(with: lineRange)
        if !block.hasSuffix("\n") { block += "\n" }
        let insertRange = NSRange(location: lineRange.location + lineRange.length, length: 0)
        guard textView.shouldChangeText(in: insertRange, replacementString: block) else { return }
        textView.replaceCharacters(in: insertRange, with: block)
        textView.didChangeText()
        let newLocation = selection.location + block.utf16.count
        textView.setSelectedRange(NSRange(location: newLocation, length: 0))
    }

    static func deleteLine(in textView: NSTextView) {
        let ns = textView.string as NSString
        let selection = textView.selectedRange()
        let lineRange = ns.lineRange(for: selection)
        guard lineRange.length > 0 else { return }
        guard textView.shouldChangeText(in: lineRange, replacementString: "") else { return }
        textView.replaceCharacters(in: lineRange, with: "")
        textView.didChangeText()
        let caret = min(lineRange.location, textView.string.utf16.count)
        textView.setSelectedRange(NSRange(location: caret, length: 0))
    }

    static func selectCurrentLine(in textView: NSTextView) {
        let ns = textView.string as NSString
        let lineRange = ns.lineRange(for: textView.selectedRange())
        textView.setSelectedRange(lineRange)
    }

    static func moveLine(up: Bool, in textView: NSTextView) {
        let ns = textView.string as NSString
        let selection = textView.selectedRange()
        let lineRange = ns.lineRange(for: selection)
        guard lineRange.length > 0 else { return }

        if up {
            guard lineRange.location > 0 else { return }
            let prevEnd = lineRange.location
            let prevRange = ns.lineRange(for: NSRange(location: prevEnd - 1, length: 0))
            let block = ns.substring(with: NSRange(location: prevRange.location, length: prevRange.length + lineRange.length))
            let newBlock = ns.substring(with: lineRange) + ns.substring(with: prevRange)
            let replaceRange = NSRange(location: prevRange.location, length: prevRange.length + lineRange.length)
            guard textView.shouldChangeText(in: replaceRange, replacementString: newBlock) else { return }
            textView.replaceCharacters(in: replaceRange, with: newBlock)
            textView.didChangeText()
            let newLocation = prevRange.location + (selection.location - lineRange.location)
            textView.setSelectedRange(NSRange(location: newLocation, length: selection.length))
            _ = block
        } else {
            let nextStart = lineRange.location + lineRange.length
            guard nextStart < ns.length else { return }
            let nextRange = ns.lineRange(for: NSRange(location: nextStart, length: 0))
            let replaceRange = NSRange(location: lineRange.location, length: lineRange.length + nextRange.length)
            let newBlock = ns.substring(with: nextRange) + ns.substring(with: lineRange)
            guard textView.shouldChangeText(in: replaceRange, replacementString: newBlock) else { return }
            textView.replaceCharacters(in: replaceRange, with: newBlock)
            textView.didChangeText()
            let newLineStart = lineRange.location + nextRange.length
            let newLocation = newLineStart + (selection.location - lineRange.location)
            textView.setSelectedRange(NSRange(location: newLocation, length: selection.length))
        }
    }
}

private extension Substring {
    var trimmingWhitespacePrefix: String {
        var s = String(self)
        while let first = s.first, first.isWhitespace { s.removeFirst() }
        return s
    }
}
