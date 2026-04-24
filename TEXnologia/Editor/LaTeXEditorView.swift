import AppKit
import SwiftUI

struct LaTeXEditorView: NSViewRepresentable {
    @Binding var text: String
    var settings: AppSettings
    var syntaxMode: EditorSyntaxMode = .latex
    var jump: EditorJump?

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, settings: settings, syntaxMode: syntaxMode)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true

        let initialFrame = scrollView.contentView.bounds.width > 0
            ? scrollView.contentView.bounds
            : NSRect(x: 0, y: 0, width: 420, height: 700)
        let textView = WrappingTextView(frame: initialFrame)
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isGrammarCheckingEnabled = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 14, height: 12)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.lineBreakMode = .byWordWrapping
        textView.string = text
        textView.delegate = context.coordinator

        scrollView.documentView = textView
        textView.updateWrappingContainerWidth()
        context.coordinator.textView = textView
        context.coordinator.settings = settings
        context.coordinator.syntaxMode = syntaxMode
        context.coordinator.applySettings(to: textView, force: true)
        context.coordinator.highlight(textView, force: true)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let settingsChanged = context.coordinator.settings != settings
        let syntaxModeChanged = context.coordinator.syntaxMode != syntaxMode
        context.coordinator.settings = settings
        context.coordinator.syntaxMode = syntaxMode
        context.coordinator.applySettings(to: textView, force: settingsChanged)
        context.coordinator.updateWrappingWidth(for: textView)

        if textView.string != text {
            context.coordinator.replaceText(text, in: textView)
            context.coordinator.highlight(textView, force: true)
            return
        }

        if settingsChanged || syntaxModeChanged {
            context.coordinator.highlight(textView, force: true)
        }

        context.coordinator.performJumpIfNeeded(jump, in: textView)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String
        weak var textView: NSTextView?
        var settings: AppSettings
        var syntaxMode: EditorSyntaxMode
        private let highlighter = LatexSyntaxHighlighter()
        private var isProgrammaticChange = false
        private var handledJumpID: UUID?

        init(text: Binding<String>, settings: AppSettings, syntaxMode: EditorSyntaxMode) {
            self._text = text
            self.settings = settings
            self.syntaxMode = syntaxMode
        }

        func textDidChange(_ notification: Notification) {
            guard !isProgrammaticChange else { return }
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
            highlight(textView, force: false)
        }

        func replaceText(_ newText: String, in textView: NSTextView) {
            let selectedRange = textView.selectedRange()
            isProgrammaticChange = true
            textView.string = newText
            textView.setSelectedRange(selectedRange.clamped(to: textView.string.utf16.count))
            isProgrammaticChange = false
        }

        func highlight(_ textView: NSTextView, force: Bool) {
            highlighter.apply(to: textView.textStorage, text: textView.string, settings: settings, syntaxMode: syntaxMode)
            clearLatexSpellingMarkers(in: textView)
        }

        func textView(_ textView: NSTextView, shouldSetSpellingState value: Int, range affectedCharRange: NSRange) -> Int {
            highlighter.isSpellCheckExcluded(affectedCharRange, in: textView.string, syntaxMode: syntaxMode) ? 0 : value
        }

        func applySettings(to textView: NSTextView, force: Bool) {
            guard force else { return }

            let font = NSFont(name: settings.editorFontName, size: settings.editorFontSize)
                ?? .monospacedSystemFont(ofSize: settings.editorFontSize, weight: .regular)

            textView.font = font
            textView.isAutomaticSpellingCorrectionEnabled = settings.editorSpellChecking
            textView.isContinuousSpellCheckingEnabled = settings.editorSpellChecking
            textView.isGrammarCheckingEnabled = settings.editorSpellChecking
            textView.enabledTextCheckingTypes = settings.editorSpellChecking
                ? NSTextCheckingResult.CheckingType.spelling.rawValue | NSTextCheckingResult.CheckingType.grammar.rawValue
                : 0
            textView.insertionPointColor = settings.editorTheme.palette.insertionPoint
            textView.backgroundColor = settings.editorTheme.palette.background
            textView.textColor = settings.editorTheme.palette.foreground
            textView.drawsBackground = true
            textView.enclosingScrollView?.backgroundColor = settings.editorTheme.palette.background

            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = settings.editorLineSpacing
            paragraphStyle.lineBreakMode = .byWordWrapping
            textView.defaultParagraphStyle = paragraphStyle

            textView.enclosingScrollView?.hasHorizontalScroller = false
            textView.textContainer?.widthTracksTextView = true
            updateWrappingWidth(for: textView)
            textView.isHorizontallyResizable = false
            textView.autoresizingMask = [.width]
        }

        func updateWrappingWidth(for textView: NSTextView) {
            textView.enclosingScrollView?.hasHorizontalScroller = false
            textView.textContainer?.widthTracksTextView = true
            let insetWidth = textView.textContainerInset.width * 2
            let visibleWidth = max((textView.enclosingScrollView?.contentSize.width ?? textView.bounds.width) - insetWidth, 120)
            textView.textContainer?.containerSize = NSSize(width: visibleWidth, height: CGFloat.greatestFiniteMagnitude)
            textView.textContainer?.lineBreakMode = .byWordWrapping
            textView.isHorizontallyResizable = false
            (textView as? WrappingTextView)?.updateWrappingContainerWidth()
        }

        func performJumpIfNeeded(_ jump: EditorJump?, in textView: NSTextView) {
            guard let jump, handledJumpID != jump.id else { return }
            handledJumpID = jump.id

            let range = textView.characterRange(forLine: jump.location.line, column: jump.location.column)
            textView.setSelectedRange(range)
            textView.scrollRangeToVisible(range)
            textView.showFindIndicator(for: range)
        }

        private func clearLatexSpellingMarkers(in textView: NSTextView) {
            guard settings.editorSpellChecking else { return }
            for range in highlighter.spellCheckExcludedRanges(in: textView.string, syntaxMode: syntaxMode) where range.length > 0 {
                textView.setSpellingState(0, range: range)
            }
        }
    }
}

private final class WrappingTextView: NSTextView {
    private var isUpdatingWrapWidth = false

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        updateWrappingContainerWidth()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateWrappingContainerWidth()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateWrappingContainerWidth()
    }

    override func layout() {
        super.layout()
        updateWrappingContainerWidth()
    }

    func updateWrappingContainerWidth() {
        guard !isUpdatingWrapWidth else { return }
        isUpdatingWrapWidth = true
        defer { isUpdatingWrapWidth = false }

        enclosingScrollView?.hasHorizontalScroller = false
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        textContainer?.widthTracksTextView = true
        textContainer?.lineBreakMode = .byWordWrapping

        let scrollWidth = max(enclosingScrollView?.contentSize.width ?? bounds.width, 120)
        let targetFrameWidth = scrollWidth
        if abs(frame.size.width - targetFrameWidth) > 0.5 {
            super.setFrameSize(NSSize(width: targetFrameWidth, height: max(frame.height, enclosingScrollView?.contentSize.height ?? frame.height)))
        }

        let insetWidth = textContainerInset.width * 2
        let containerWidth = max(scrollWidth - insetWidth, 120)
        textContainer?.containerSize = NSSize(width: containerWidth, height: CGFloat.greatestFiniteMagnitude)
    }
}

private extension NSRange {
    func clamped(to upperBound: Int) -> NSRange {
        NSRange(location: min(location, upperBound), length: min(length, max(0, upperBound - location)))
    }
}

private extension NSTextView {
    func characterRange(forLine line: Int, column: Int) -> NSRange {
        let nsString = string as NSString
        guard nsString.length > 0 else {
            return NSRange(location: 0, length: 0)
        }

        var currentLine = 1
        var lineStart = 0

        while currentLine < max(1, line), lineStart < nsString.length {
            let lineRange = nsString.lineRange(for: NSRange(location: lineStart, length: 0))
            lineStart = lineRange.location + lineRange.length
            currentLine += 1
        }

        let targetLineRange = nsString.lineRange(for: NSRange(location: min(lineStart, nsString.length - 1), length: 0))
        let columnOffset = max(0, column - 1)
        let location = min(targetLineRange.location + columnOffset, targetLineRange.location + targetLineRange.length)
        return NSRange(location: min(location, nsString.length), length: 0)
    }
}
