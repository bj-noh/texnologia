import PDFKit
import SwiftUI

struct PDFPaneView: View {
    var documentURL: URL?

    var body: some View {
        PDFKitRepresentable(documentURL: documentURL)
            .overlay {
                if documentURL == nil {
                    ContentUnavailableView("No PDF", systemImage: "doc.richtext")
                }
            }
    }
}

struct PDFKitRepresentable: NSViewRepresentable {
    var documentURL: URL?

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .windowBackgroundColor
        return view
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        guard context.coordinator.lastURL != documentURL else { return }
        context.coordinator.lastURL = documentURL

        guard let documentURL, let data = try? Data(contentsOf: documentURL) else {
            pdfView.document = nil
            return
        }

        let currentPageIndex = pdfView.currentPage.flatMap { pdfView.document?.index(for: $0) } ?? 0
        pdfView.document = PDFDocument(data: data)

        if let document = pdfView.document,
           let page = document.page(at: min(currentPageIndex, max(0, document.pageCount - 1))) {
            pdfView.go(to: page)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var lastURL: URL?
    }
}

