import AppKit
import SwiftUI

private enum EditorLayout {
    static let lineNumberGutterWidth: CGFloat = 74
    static let textInset = NSSize(width: 26, height: 12)
}

struct LaTeXEditorView: NSViewRepresentable {
    @Binding var text: String
    var settings: AppSettings
    var syntaxMode: EditorSyntaxMode = .latex
    var jump: EditorJump?

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, settings: settings, syntaxMode: syntaxMode)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = EditorScrollView()
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
        textView.textContainerInset = EditorLayout.textInset
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.lineBreakMode = .byWordWrapping
        textView.layoutManager?.allowsNonContiguousLayout = true
        textView.string = text
        textView.delegate = context.coordinator

        scrollView.documentView = textView
        let lineNumberView = LineNumberRulerView(textView: textView)
        scrollView.verticalRulerView = lineNumberView
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        scrollView.tile()
        textView.updateWrappingContainerWidth()
        context.coordinator.textView = textView
        context.coordinator.lineNumberView = lineNumberView
        context.coordinator.settings = settings
        context.coordinator.syntaxMode = syntaxMode
        context.coordinator.applySettings(to: textView, force: true)
        context.coordinator.highlight(textView, force: true)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        scrollView.verticalRulerView?.ruleThickness = EditorLayout.lineNumberGutterWidth
        scrollView.tile()

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
        fileprivate weak var lineNumberView: LineNumberRulerView?
        var settings: AppSettings
        var syntaxMode: EditorSyntaxMode
        private let highlighter = LatexSyntaxHighlighter()
        private var isProgrammaticChange = false
        private var handledJumpID: UUID?
        private var pendingHighlight: DispatchWorkItem?
        private var spellCheckExcludedRanges: [NSRange] = []

        init(text: Binding<String>, settings: AppSettings, syntaxMode: EditorSyntaxMode) {
            self._text = text
            self.settings = settings
            self.syntaxMode = syntaxMode
        }

        func textDidChange(_ notification: Notification) {
            guard !isProgrammaticChange else { return }
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
            scheduleHighlight(textView)
            lineNumberView?.needsDisplay = true
        }

        func replaceText(_ newText: String, in textView: NSTextView) {
            let selectedRange = textView.selectedRange()
            isProgrammaticChange = true
            textView.string = newText
            textView.setSelectedRange(selectedRange.clamped(to: textView.string.utf16.count))
            isProgrammaticChange = false
            lineNumberView?.needsDisplay = true
        }

        func highlight(_ textView: NSTextView, force: Bool) {
            pendingHighlight?.cancel()
            highlighter.apply(to: textView.textStorage, text: textView.string, settings: settings, syntaxMode: syntaxMode)
            clearLatexSpellingMarkers(in: textView)
            lineNumberView?.needsDisplay = true
        }

        func textView(_ textView: NSTextView, shouldSetSpellingState value: Int, range affectedCharRange: NSRange) -> Int {
            spellCheckExcludedRanges.contains { excludedRange in
                NSIntersectionRange(affectedCharRange, excludedRange).length > 0
            } ? 0 : value
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

        private func scheduleHighlight(_ textView: NSTextView) {
            pendingHighlight?.cancel()
            let workItem = DispatchWorkItem { [weak self, weak textView] in
                guard let self, let textView else { return }
                self.highlight(textView, force: false)
            }
            pendingHighlight = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(90), execute: workItem)
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
            lineNumberView?.needsDisplay = true
        }

        private func clearLatexSpellingMarkers(in textView: NSTextView) {
            guard settings.editorSpellChecking else {
                spellCheckExcludedRanges = []
                return
            }
            let excludedRanges = highlighter.spellCheckExcludedRanges(in: textView.string, syntaxMode: syntaxMode)
            spellCheckExcludedRanges = excludedRanges
            for range in excludedRanges where range.length > 0 {
                textView.setSpellingState(0, range: range)
            }
        }
    }
}

private final class EditorScrollView: NSScrollView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func tile() {
        verticalRulerView?.ruleThickness = EditorLayout.lineNumberGutterWidth
        super.tile()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        tile()
    }

    override func layout() {
        super.layout()
        verticalRulerView?.ruleThickness = EditorLayout.lineNumberGutterWidth
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

fileprivate final class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?
    private let gutterWidth = EditorLayout.lineNumberGutterWidth

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        self.clientView = textView
        self.ruleThickness = gutterWidth
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var requiredThickness: CGFloat {
        gutterWidth
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard
            let textView,
            let layoutManager = textView.layoutManager,
            let textContainer = textView.textContainer,
            let scrollView = textView.enclosingScrollView
        else {
            return
        }

        let backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.72)
        backgroundColor.setFill()
        bounds.fill()

        NSColor.separatorColor.setStroke()
        let separator = NSBezierPath()
        separator.move(to: NSPoint(x: bounds.maxX - 0.5, y: bounds.minY))
        separator.line(to: NSPoint(x: bounds.maxX - 0.5, y: bounds.maxY))
        separator.lineWidth = 1
        separator.stroke()

        let visibleRect = scrollView.contentView.bounds
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        guard glyphRange.location < layoutManager.numberOfGlyphs else { return }

        let numberAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        let nsString = textView.string as NSString
        var glyphIndex = glyphRange.location
        while glyphIndex < NSMaxRange(glyphRange) {
            var lineGlyphRange = NSRange()
            let lineRect = layoutManager.lineFragmentRect(
                forGlyphAt: glyphIndex,
                effectiveRange: &lineGlyphRange,
                withoutAdditionalLayout: true
            )
            let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
            let sourceLineRange = nsString.lineRange(for: NSRange(location: min(characterIndex, max(nsString.length - 1, 0)), length: 0))

            if characterIndex == sourceLineRange.location || glyphIndex == glyphRange.location {
                let lineNumber = nsString.lineNumber(at: characterIndex)
                let label = "\(lineNumber)" as NSString
                let labelSize = label.size(withAttributes: numberAttributes)
                let y = textView.textContainerOrigin.y + lineRect.minY - visibleRect.minY + 1
                let x = gutterWidth - labelSize.width - 14
                label.draw(at: NSPoint(x: x, y: y), withAttributes: numberAttributes)
            }

            let nextGlyphIndex = NSMaxRange(lineGlyphRange)
            glyphIndex = nextGlyphIndex > glyphIndex ? nextGlyphIndex : glyphIndex + 1
        }
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

private extension NSString {
    func lineNumber(at characterIndex: Int) -> Int {
        guard length > 0 else { return 1 }
        let clampedIndex = min(max(characterIndex, 0), length)
        var line = 1
        var index = 0

        while index < clampedIndex {
            let range = lineRange(for: NSRange(location: index, length: 0))
            let nextIndex = range.location + range.length
            guard nextIndex > index else { break }
            if nextIndex <= clampedIndex {
                line += 1
            }
            index = nextIndex
        }

        return line
    }
}
