import PDFKit
import SwiftUI

struct PDFPaneView: View {
    var documentURL: URL?
    var refreshID: Int = 0
    var paneID: PreviewPaneID? = nil
    var navigationTarget: PDFNavigationTarget? = nil
    var onActivate: (() -> Void)? = nil

    var body: some View {
        PDFKitRepresentable(documentURL: documentURL, refreshID: refreshID,
                            paneID: paneID, navigationTarget: navigationTarget, onActivate: onActivate)
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
    var paneID: PreviewPaneID? = nil
    var navigationTarget: PDFNavigationTarget? = nil
    var onActivate: (() -> Void)? = nil

    func makeNSView(context: Context) -> PDFView {
        let view = NonResizingPDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = FolioTheme.nsCanvas
        configureInteraction(for: view)
        return view
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        pdfView.backgroundColor = FolioTheme.nsCanvas
        context.coordinator.load(documentURL, refreshID: refreshID, into: pdfView)
        configureInteraction(for: pdfView)
        context.coordinator.navigate(to: navigationTarget?.paneID == paneID ? navigationTarget : nil, in: pdfView)
    }

    private func configureInteraction(for view: PDFView) {
        guard let paneID, let view = view as? NonResizingPDFView else { return }
        SyncTeXBridge.shared.registerPDFView(view, for: paneID)
        view.onClick = { [weak view] point in
            guard let view else { return }
            onActivate?()
            SyncTeXBridge.shared.recordPDFClick(at: point, in: view, paneID: paneID)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject {
        private var lastURL: URL?
        private var lastRefreshID: Int?
        private var loadID = UUID()
        private var pendingNavigation: PDFNavigationTarget?
        private var handledNavigationID: UUID?

        func navigate(to target: PDFNavigationTarget?, in pdfView: PDFView) {
            pendingNavigation = target
            applyPendingNavigation(in: pdfView)
        }

        private func applyPendingNavigation(in pdfView: PDFView) {
            guard let target = pendingNavigation, handledNavigationID != target.id,
                  let document = pdfView.document,
                  document.documentURL?.standardizedFileURL == target.pdfURL.standardizedFileURL,
                  let page = document.page(at: target.page - 1) else { return }
            handledNavigationID = target.id
            let bounds = page.bounds(for: .mediaBox)
            let point = NSPoint(x: bounds.minX + CGFloat(target.x), y: bounds.maxY - CGFloat(target.y))
            // Bring the matching line into view and highlight its text.
            let rect = NSRect(x: point.x - 12, y: point.y - 8, width: 160, height: 20)
            pdfView.go(to: rect, on: page)
            SyncTeXBridge.shared.recordPDFClick(
                at: pdfView.convert(point, from: page), in: pdfView, paneID: target.paneID
            )
            if let selection = page.selection(for: rect) {
                pdfView.setCurrentSelection(selection, animate: true)
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
                    self.applyPendingNavigation(in: pdfView)
                }
            }
        }
    }
}

private final class NonResizingPDFView: PDFView {
    var onClick: ((NSPoint) -> Void)?

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onClick?(point)
        super.mouseDown(with: event)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}
