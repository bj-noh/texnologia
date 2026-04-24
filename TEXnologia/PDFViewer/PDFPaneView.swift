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
        SyncTeXBridge.shared.pdfView = view
        context.coordinator.registerNavigationObserver(for: view)
        return view
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        context.coordinator.load(documentURL, into: pdfView)
        SyncTeXBridge.shared.pdfView = pdfView
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject {
        private var lastURL: URL?
        private var loadID = UUID()
        private var navigationObserver: NSObjectProtocol?

        deinit {
            if let navigationObserver {
                NotificationCenter.default.removeObserver(navigationObserver)
            }
        }

        func registerNavigationObserver(for pdfView: PDFView) {
            guard navigationObserver == nil else { return }
            navigationObserver = NotificationCenter.default.addObserver(
                forName: .pdfNavigateTo,
                object: nil,
                queue: .main
            ) { [weak pdfView] notification in
                guard let pdfView,
                      let target = notification.object as? PDFNavigationTarget,
                      let document = pdfView.document,
                      let page = document.page(at: max(0, target.page - 1)) else { return }
                let bounds = page.bounds(for: .mediaBox)
                let pointY = bounds.height - CGFloat(target.y)
                let destination = PDFDestination(page: page, at: NSPoint(x: CGFloat(target.x), y: pointY))
                pdfView.go(to: destination)
            }
        }

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
