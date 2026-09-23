import PDFKit
import SwiftUI

struct PDFPaneView: View {
    var documentURL: URL?
    var refreshID: Int = 0

    var body: some View {
        PDFKitRepresentable(documentURL: documentURL, refreshID: refreshID)
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            .fixedSize(horizontal: false, vertical: false)
            .overlay {
                if documentURL == nil {
                    PDFPreviewEmptyState()
                }
            }
            .background(FolioTheme.canvas)
    }
}

private struct PDFPreviewEmptyState: View {
    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.height <= 300 || geometry.size.width <= 320
            ScrollView(.vertical) {
                content(compact: compact)
                    .padding(compact ? 16 : 24)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geometry.size.height)
            }
            .scrollIndicators(.hidden)
        }
        .background(FolioTheme.canvas)
    }

    private func content(compact: Bool) -> some View {
        VStack(spacing: 0) {
            if compact {
                Image(systemName: "doc.text")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(FolioTheme.accent)
                    .frame(width: 36, height: 36)
                    .background(FolioTheme.accentSoft, in: RoundedRectangle(cornerRadius: 9))
                    .accessibilityHidden(true)
                    .padding(.bottom, 12)
            } else {
                documentIllustration
                    .padding(.bottom, 28)
            }

            Text("A little space for your ideas.")
                .font(.system(size: compact ? 15 : 18, weight: .medium, design: .serif))
                .foregroundStyle(FolioTheme.text)
                .multilineTextAlignment(.center)

            Text(compact ? "Build your document to preview the finished pages." : "Build your LaTeX document to see\nyour finished pages here.")
                .font(.system(size: compact ? 11 : 12))
                .foregroundStyle(FolioTheme.muted)
                .multilineTextAlignment(.center)
                .lineSpacing(compact ? 2 : 5)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: compact ? 260 : .infinity)
                .padding(.top, compact ? 8 : 10)

            HStack(spacing: 7) {
                Image(systemName: "play")
                    .font(.system(size: 9, weight: .medium))
                Text("Build document")
                Text("⌘B")
                    .font(.system(size: 10, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(FolioTheme.surface, in: RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(FolioTheme.border, lineWidth: 1))
            }
            .font(.system(size: 10))
            .foregroundStyle(FolioTheme.muted)
            .padding(.top, compact ? 12 : 22)
        }
    }

    private var documentIllustration: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(FolioTheme.accentSoft)
                .frame(width: 100, height: 118)
                .rotationEffect(.degrees(-9))

            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.system(size: 27, weight: .light))
                    .foregroundStyle(FolioTheme.accent)
                    .padding(.bottom, 6)
                RoundedRectangle(cornerRadius: 2)
                    .fill(FolioTheme.accent.opacity(0.22))
                    .frame(width: 45, height: 4)
                RoundedRectangle(cornerRadius: 2)
                    .fill(FolioTheme.border)
                    .frame(width: 58, height: 4)
                RoundedRectangle(cornerRadius: 2)
                    .fill(FolioTheme.border)
                    .frame(width: 37, height: 4)
            }
            .padding(22)
            .frame(width: 100, height: 118)
            .background(FolioTheme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(FolioTheme.border, lineWidth: 1))
            .shadow(color: FolioTheme.accent.opacity(0.07), radius: 12, y: 7)
        }
        .accessibilityHidden(true)
    }
}

struct PDFKitRepresentable: NSViewRepresentable {
    var documentURL: URL?
    var refreshID: Int = 0

    func makeNSView(context: Context) -> PDFView {
        let view = NonResizingPDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = FolioTheme.nsCanvas
        SyncTeXBridge.shared.pdfView = view
        context.coordinator.registerNavigationObserver(for: view)
        return view
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        pdfView.backgroundColor = FolioTheme.nsCanvas
        context.coordinator.load(documentURL, refreshID: refreshID, into: pdfView)
        SyncTeXBridge.shared.pdfView = pdfView
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject {
        private var lastURL: URL?
        private var lastRefreshID: Int?
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

        func load(_ documentURL: URL?, refreshID: Int = 0, into pdfView: PDFView) {
            guard lastURL != documentURL || lastRefreshID != refreshID else { return }
            lastURL = documentURL
            lastRefreshID = refreshID
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
