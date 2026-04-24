import PDFKit
import SwiftUI

struct PDFPaneView: View {
    var documentURL: URL?

    var body: some View {
        PDFKitRepresentable(documentURL: documentURL)
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            .fixedSize(horizontal: false, vertical: false)
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
        let view = NonResizingPDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .windowBackgroundColor
        return view
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        context.coordinator.load(documentURL, into: pdfView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private var lastURL: URL?
        private var loadID = UUID()

        func load(_ documentURL: URL?, into pdfView: PDFView) {
            guard lastURL != documentURL else { return }
            lastURL = documentURL
            loadID = UUID()
            let currentLoadID = loadID

            guard let documentURL else {
                pdfView.document = nil
                return
            }

            let currentPageIndex = pdfView.currentPage.flatMap { pdfView.document?.index(for: $0) } ?? 0
            pdfView.document = nil

            DispatchQueue.global(qos: .userInitiated).async {
                let document = PDFDocument(url: documentURL)

                DispatchQueue.main.async { [weak pdfView, weak self] in
                    guard let self, let pdfView, self.loadID == currentLoadID else { return }
                    pdfView.document = document

                    if let document,
                       let page = document.page(at: min(currentPageIndex, max(0, document.pageCount - 1))) {
                        pdfView.go(to: page)
                    }
                }
            }
        }
    }
}

private final class NonResizingPDFView: PDFView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}
