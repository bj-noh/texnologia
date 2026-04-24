import AppKit
import SwiftUI

struct SplitViewDividerHitExpander: NSViewRepresentable {
    var extraHitAreaOnEachSide: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(extraHitAreaOnEachSide: extraHitAreaOnEachSide)
    }

    func makeNSView(context: Context) -> NSView {
        let view = AccessorView(onAttach: context.coordinator.attach)
        view.setAccessibilityElement(false)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.extraHitAreaOnEachSide = extraHitAreaOnEachSide
        context.coordinator.reattachIfNeeded(from: nsView)
    }

    final class Coordinator: NSObject, NSSplitViewDelegate {
        var extraHitAreaOnEachSide: CGFloat
        private weak var split: NSSplitView?
        private weak var previousDelegate: NSSplitViewDelegate?

        init(extraHitAreaOnEachSide: CGFloat) {
            self.extraHitAreaOnEachSide = extraHitAreaOnEachSide
        }

        func attach(from view: NSView) {
            guard let split = Self.findSplitView(ancestorOf: view) else { return }
            guard split !== self.split else { return }
            previousDelegate = split.delegate === self ? nil : split.delegate
            split.delegate = self
            self.split = split
        }

        func reattachIfNeeded(from view: NSView) {
            if let split, split.delegate === self { return }
            attach(from: view)
        }

        func splitView(_ splitView: NSSplitView,
                       effectiveRect proposedEffectiveRect: NSRect,
                       forDrawnRect drawnRect: NSRect,
                       ofDividerAt dividerIndex: Int) -> NSRect {
            var rect = proposedEffectiveRect
            if splitView.isVertical {
                rect.origin.x -= extraHitAreaOnEachSide
                rect.size.width += extraHitAreaOnEachSide * 2
            } else {
                rect.origin.y -= extraHitAreaOnEachSide
                rect.size.height += extraHitAreaOnEachSide * 2
            }
            if let previousDelegate,
               previousDelegate.responds(to: #selector(NSSplitViewDelegate.splitView(_:effectiveRect:forDrawnRect:ofDividerAt:))) {
                let forwarded = previousDelegate.splitView?(splitView,
                                                             effectiveRect: rect,
                                                             forDrawnRect: drawnRect,
                                                             ofDividerAt: dividerIndex)
                return forwarded ?? rect
            }
            return rect
        }

        private static func findSplitView(ancestorOf view: NSView) -> NSSplitView? {
            var current: NSView? = view.superview
            while let node = current {
                if let split = node as? NSSplitView {
                    return split
                }
                current = node.superview
            }
            return nil
        }
    }

    private final class AccessorView: NSView {
        private let onAttach: (NSView) -> Void
        private var didAttach = false

        init(onAttach: @escaping (NSView) -> Void) {
            self.onAttach = onAttach
            super.init(frame: .zero)
            translatesAutoresizingMaskIntoConstraints = false
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if !didAttach {
                    didAttach = true
                    onAttach(self)
                } else {
                    onAttach(self)
                }
            }
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            guard superview != nil else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                onAttach(self)
            }
        }
    }
}
