import AppKit
import PDFKit

final class SyncTeXBridge {
    static let shared = SyncTeXBridge()

    weak var editorTextView: NSTextView?
    var editorFileURL: URL?

    private final class Preview {
        weak var view: PDFView?
        weak var clickedDocument: PDFDocument?
        var clickedLocation: PDFLocationReport?

        init(view: PDFView) { self.view = view }
    }

    private var previews: [PreviewPaneID: Preview] = [:]

    func registerPDFView(_ view: PDFView, for paneID: PreviewPaneID) {
        if previews[paneID]?.view !== view { previews[paneID] = Preview(view: view) }
    }

    func recordPDFClick(at point: NSPoint, in view: PDFView, paneID: PreviewPaneID) {
        registerPDFView(view, for: paneID)
        guard let document = view.document, let url = document.documentURL,
              let page = view.page(for: point, nearest: false) else { return }
        let location = view.convert(point, to: page)
        let bounds = page.bounds(for: .mediaBox)
        previews[paneID]?.clickedDocument = document
        previews[paneID]?.clickedLocation = PDFLocationReport(
            pdfURL: url, page: document.index(for: page) + 1,
            x: Double(location.x - bounds.minX), y: Double(bounds.maxY - location.y)
        )
    }

    private init() {}

    func currentEditorLocation() -> (fileURL: URL, line: Int, column: Int)? {
        guard let textView = editorTextView, let fileURL = editorFileURL else { return nil }
        let selection = textView.selectedRange()
        let (line, column) = Self.lineAndColumn(in: textView.string, at: selection.location)
        return (fileURL, line, column)
    }

    func currentPDFLocation(in paneID: PreviewPaneID) -> (pdfURL: URL, page: Int, x: Double, y: Double)? {
        guard let preview = previews[paneID], let view = preview.view,
              let document = view.document, let url = document.documentURL else { return nil }
        if preview.clickedDocument === document, let location = preview.clickedLocation {
            return (location.pdfURL, location.page, location.x, location.y)
        }
        // Before the first click, use selected text or the visible page's center.
        let center = NSPoint(x: view.visibleRect.midX, y: view.visibleRect.midY)
        guard let page = view.currentSelection?.pages.first ?? view.page(for: center, nearest: true) else { return nil }
        let point: NSPoint
        if let selection = view.currentSelection, selection.pages.contains(page) {
            let selectionBounds = selection.bounds(for: page)
            point = NSPoint(x: selectionBounds.midX, y: selectionBounds.midY)
        } else {
            point = view.convert(center, to: page)
        }
        let bounds = page.bounds(for: .mediaBox)
        return (url, document.index(for: page) + 1,
                Double(max(0, min(bounds.width, point.x - bounds.minX))),
                Double(max(0, min(bounds.height, bounds.maxY - point.y))))
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
