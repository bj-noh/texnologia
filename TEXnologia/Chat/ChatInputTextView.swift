import AppKit
import SwiftUI

struct ChatInputTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var measuredHeight: CGFloat
    var placeholder: String
    var font: NSFont = .systemFont(ofSize: 13)
    var minHeight: CGFloat
    var maxHeight: CGFloat
    var isEnabled: Bool
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.verticalScrollElasticity = .automatic

        let textContainer = NSTextContainer(containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        textContainer.lineFragmentPadding = 0

        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(textContainer)

        let textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)

        let tv = ChatInputNSTextView(frame: .zero, textContainer: textContainer)
        tv.delegate = context.coordinator
        tv.isEditable = true
        tv.isSelectable = true
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.font = font
        tv.textColor = NSColor.labelColor
        tv.insertionPointColor = NSColor.labelColor
        tv.backgroundColor = NSColor.clear
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 0, height: 4)
        tv.isHorizontallyResizable = false
        tv.isVerticallyResizable = true
        tv.autoresizingMask = [NSView.AutoresizingMask.width]
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .font: font,
                .foregroundColor: NSColor.placeholderTextColor
            ]
        )
        tv.submitHandler = { [weak coordinator = context.coordinator] in
            coordinator?.submit()
        }
        tv.string = text
        tv.textContainer?.widthTracksTextView = true

        scroll.documentView = tv
        context.coordinator.textView = tv
        context.coordinator.scrollView = scroll

        DispatchQueue.main.async {
            context.coordinator.updateMeasuredHeight()
        }

        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tv = nsView.documentView as? ChatInputNSTextView else { return }
        context.coordinator.parent = self
        tv.isEditable = isEnabled
        tv.isSelectable = true
        if tv.string != text {
            tv.string = text
            context.coordinator.updateMeasuredHeight()
        }
        tv.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .font: font,
                .foregroundColor: NSColor.placeholderTextColor
            ]
        )
        tv.needsDisplay = true
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ChatInputTextView
        weak var textView: ChatInputNSTextView?
        weak var scrollView: NSScrollView?

        init(_ parent: ChatInputTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            updateMeasuredHeight()
        }

        func submit() {
            parent.onSubmit()
        }

        func updateMeasuredHeight() {
            guard let tv = textView, let layoutManager = tv.layoutManager, let container = tv.textContainer else { return }
            layoutManager.ensureLayout(for: container)
            let used = layoutManager.usedRect(for: container)
            let inset = tv.textContainerInset
            let total = used.height + inset.height * 2
            let clamped = min(parent.maxHeight, max(parent.minHeight, total))
            if abs(parent.measuredHeight - clamped) > 0.5 {
                DispatchQueue.main.async {
                    self.parent.measuredHeight = clamped
                }
            }
        }
    }
}

final class ChatInputNSTextView: NSTextView {
    var placeholderAttributedString: NSAttributedString?
    var submitHandler: (() -> Void)?

    override var acceptsFirstResponder: Bool { isEditable }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        needsDisplay = true
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        needsDisplay = true
        return result
    }

    override func mouseDown(with event: NSEvent) {
        if let window, !window.isKeyWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        // Plain Return → submit. Shift+Return / Opt+Return → insert newline.
        if event.keyCode == 36 || event.keyCode == 76 {
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if modifiers.isEmpty {
                submitHandler?()
                return
            }
            if modifiers.contains(.shift) || modifiers.contains(.option) {
                insertNewline(nil)
                return
            }
        }
        super.keyDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty,
              let placeholder = placeholderAttributedString,
              !placeholder.string.isEmpty else { return }
        let inset = textContainerInset
        let origin = NSPoint(x: inset.width, y: inset.height)
        placeholder.draw(at: origin)
    }
}
