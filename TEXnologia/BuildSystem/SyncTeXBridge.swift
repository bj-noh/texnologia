import AppKit
import PDFKit

final class SyncTeXBridge {
    static let shared = SyncTeXBridge()

    weak var editorTextView: NSTextView?
    var editorFileURL: URL?

    weak var pdfView: PDFView?

    private init() {}

    func currentEditorLocation() -> (fileURL: URL, line: Int, column: Int)? {
        guard let textView = editorTextView, let fileURL = editorFileURL else { return nil }
        let selection = textView.selectedRange()
        let (line, column) = Self.lineAndColumn(in: textView.string, at: selection.location)
        return (fileURL, line, column)
    }

    func currentPDFTopLocation() -> (pdfURL: URL, page: Int, x: Double, y: Double)? {
        guard let pdfView, let document = pdfView.document, let page = pdfView.currentPage else { return nil }
        guard let url = document.documentURL else { return nil }
        let pageIndex = document.index(for: page) + 1
        let bounds = page.bounds(for: .mediaBox)
        let visible = pdfView.convert(pdfView.visibleRect, to: page)
        let x = max(0, Double(bounds.midX))
        let topY = Double(bounds.height - visible.maxY)
        return (url, pageIndex, x, max(0, topY))
    }

    static func lineAndColumn(in text: String, at utf16Offset: Int) -> (Int, Int) {
        let ns = text as NSString
        let clamped = max(0, min(utf16Offset, ns.length))
        var line = 1
        var columnStart = 0
        var i = 0
        while i < clamped {
            let ch = ns.character(at: i)
            if ch == 0x0A {
                line += 1
                columnStart = i + 1
            }
            i += 1
        }
        let column = clamped - columnStart
        return (line, column)
    }
}
