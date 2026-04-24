import AppKit
import SwiftUI

private enum EditorLayout {
    static let minGutterWidth: CGFloat = 54
    static let maxGutterWidth: CGFloat = 96
    static let gutterDigitWidth: CGFloat = 8
    static let gutterLeftPadding: CGFloat = 12
    static let gutterRightPadding: CGFloat = 16
    static let textLeftInset: CGFloat = 32
    static let textRightInset: CGFloat = 16
    static let textVerticalInset: CGFloat = 12
    static let lineFragmentPadding: CGFloat = 4

    static func gutterWidth(for maxLine: Int) -> CGFloat {
        let digits = max(3, String(max(maxLine, 1)).count)
        let raw = gutterLeftPadding + gutterDigitWidth * CGFloat(digits) + gutterRightPadding
        return min(maxGutterWidth, max(minGutterWidth, raw))
    }
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
        scrollView.borderType = .noBorder
        scrollView.findBarPosition = .aboveContent

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
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.allowsUndo = true
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(
            width: EditorLayout.textLeftInset,
            height: EditorLayout.textVerticalInset
        )
        textView.textContainer?.lineFragmentPadding = EditorLayout.lineFragmentPadding
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
        context.coordinator.updateGutterWidth(for: textView)
        context.coordinator.highlight(textView, force: true)
        SyncTeXBridge.shared.editorTextView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if !scrollView.rulersVisible {
            scrollView.hasVerticalRuler = true
            scrollView.rulersVisible = true
        }
        SyncTeXBridge.shared.editorTextView = textView

        let settingsChanged = context.coordinator.settings != settings
        let syntaxModeChanged = context.coordinator.syntaxMode != syntaxMode
        context.coordinator.settings = settings
        context.coordinator.syntaxMode = syntaxMode
        context.coordinator.applySettings(to: textView, force: settingsChanged)
        context.coordinator.updateGutterWidth(for: textView)

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
        private let highlightQueue = DispatchQueue(label: "com.texifier.LatexHighlight", qos: .userInitiated)
        private var isProgrammaticChange = false
        private var handledJumpID: UUID?
        private var pendingHighlight: DispatchWorkItem?
        private var highlightVersion: UInt64 = 0
        private var spellCheckExcludedRanges: [NSRange] = []
        private var cachedLineBucket: Int = -1

        init(text: Binding<String>, settings: AppSettings, syntaxMode: EditorSyntaxMode) {
            self._text = text
            self.settings = settings
            self.syntaxMode = syntaxMode
            super.init()
            registerEditorNotifications()
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        private func registerEditorNotifications() {
            let nc = NotificationCenter.default
            nc.addObserver(self, selector: #selector(handleToggleComment), name: .editorToggleComment, object: nil)
            nc.addObserver(self, selector: #selector(handleDuplicateLine), name: .editorDuplicateLine, object: nil)
            nc.addObserver(self, selector: #selector(handleDeleteLine), name: .editorDeleteLine, object: nil)
            nc.addObserver(self, selector: #selector(handleSelectLine), name: .editorSelectCurrentLine, object: nil)
            nc.addObserver(self, selector: #selector(handleMoveLineUp), name: .editorMoveLineUp, object: nil)
            nc.addObserver(self, selector: #selector(handleMoveLineDown), name: .editorMoveLineDown, object: nil)
            nc.addObserver(self, selector: #selector(handlePerformFind), name: .editorPerformFind, object: nil)
        }

        @objc private func handleToggleComment() {
            guard let textView, textView.window?.firstResponder === textView else { return }
            EditorTextOps.toggleComment(in: textView)
        }

        @objc private func handleDuplicateLine() {
            guard let textView, textView.window?.firstResponder === textView else { return }
            EditorTextOps.duplicateLine(in: textView)
        }

        @objc private func handleDeleteLine() {
            guard let textView, textView.window?.firstResponder === textView else { return }
            EditorTextOps.deleteLine(in: textView)
        }

        @objc private func handleSelectLine() {
            guard let textView, textView.window?.firstResponder === textView else { return }
            EditorTextOps.selectCurrentLine(in: textView)
        }

        @objc private func handleMoveLineUp() {
            guard let textView, textView.window?.firstResponder === textView else { return }
            EditorTextOps.moveLine(up: true, in: textView)
        }

        @objc private func handleMoveLineDown() {
            guard let textView, textView.window?.firstResponder === textView else { return }
            EditorTextOps.moveLine(up: false, in: textView)
        }

        @objc private func handlePerformFind() {
            guard let textView, textView.window?.firstResponder === textView else { return }
            let item = NSMenuItem()
            item.tag = NSTextFinder.Action.showFindInterface.rawValue
            textView.performTextFinderAction(item)
        }

        func textDidChange(_ notification: Notification) {
            guard !isProgrammaticChange else { return }
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
            scheduleHighlight(textView)
            updateGutterWidth(for: textView)
            lineNumberView?.needsDisplay = true
        }

        func replaceText(_ newText: String, in textView: NSTextView) {
            let selectedRange = textView.selectedRange()
            isProgrammaticChange = true
            textView.string = newText
            textView.setSelectedRange(selectedRange.clamped(to: textView.string.utf16.count))
            isProgrammaticChange = false
            cachedLineBucket = -1
            updateGutterWidth(for: textView)
            lineNumberView?.needsDisplay = true
        }

        func updateGutterWidth(for textView: NSTextView) {
            guard let rulerView = lineNumberView, let scrollView = textView.enclosingScrollView else { return }
            let nsText = textView.string as NSString
            let approximateLines = nsText.length / 40 + 1
            let bucket = digitBucket(for: approximateLines)
            if bucket == cachedLineBucket {
                return
            }
            let lineCount = nsText.approximateLineCount
            let actualBucket = digitBucket(for: lineCount)
            cachedLineBucket = actualBucket
            let width = EditorLayout.gutterWidth(for: lineCount)
            if rulerView.setGutterWidth(width) {
                scrollView.tile()
                (textView as? WrappingTextView)?.updateWrappingContainerWidth()
            }
        }

        private func digitBucket(for lineCount: Int) -> Int {
            max(3, String(max(lineCount, 1)).count)
        }

        func highlight(_ textView: NSTextView, force: Bool) {
            pendingHighlight?.cancel()
            if force {
                highlightVersion &+= 1
                let plan = highlighter.computePlan(
                    text: textView.string,
                    settings: settings,
                    syntaxMode: syntaxMode
                )
                applyHighlightPlan(plan, to: textView)
            } else {
                scheduleAsyncHighlight(for: textView)
            }
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
            textView.textContainerInset = NSSize(
                width: EditorLayout.textLeftInset,
                height: EditorLayout.textVerticalInset
            )
            textView.textContainer?.lineFragmentPadding = EditorLayout.lineFragmentPadding
            updateWrappingWidth(for: textView)
            textView.isHorizontallyResizable = false
            textView.autoresizingMask = [.width]
        }

        private func scheduleHighlight(_ textView: NSTextView) {
            pendingHighlight?.cancel()
            let workItem = DispatchWorkItem { [weak self, weak textView] in
                guard let self, let textView else { return }
                self.scheduleAsyncHighlight(for: textView)
            }
            pendingHighlight = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(70), execute: workItem)
        }

        private func scheduleAsyncHighlight(for textView: NSTextView) {
            highlightVersion &+= 1
            let version = highlightVersion
            let snapshot = textView.string
            let settingsSnapshot = settings
            let syntaxModeSnapshot = syntaxMode
            let highlighter = self.highlighter
            highlightQueue.async { [weak self, weak textView] in
                let plan = highlighter.computePlan(
                    text: snapshot,
                    settings: settingsSnapshot,
                    syntaxMode: syntaxModeSnapshot
                )
                DispatchQueue.main.async { [weak self, weak textView] in
                    guard let self, let textView, self.highlightVersion == version else { return }
                    self.applyHighlightPlan(plan, to: textView)
                }
            }
        }

        private func applyHighlightPlan(_ plan: HighlightPlan, to textView: NSTextView) {
            guard let textStorage = textView.textStorage, textStorage.length == plan.textLength else { return }
            highlighter.apply(plan: plan, to: textStorage)
            if settings.editorSpellChecking {
                spellCheckExcludedRanges = plan.spellExcludedRanges
                for range in plan.spellExcludedRanges where range.length > 0 {
                    textView.setSpellingState(0, range: range)
                }
            } else {
                spellCheckExcludedRanges = []
            }
            lineNumberView?.needsDisplay = true
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

    }
}

private final class EditorScrollView: NSScrollView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        tile()
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
    private var gutterWidth: CGFloat = EditorLayout.minGutterWidth

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

    @discardableResult
    func setGutterWidth(_ width: CGFloat) -> Bool {
        guard abs(width - gutterWidth) > 0.5 else { return false }
        gutterWidth = width
        ruleThickness = width
        needsDisplay = true
        return true
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

        let backgroundColor = textView.backgroundColor
        backgroundColor.setFill()
        bounds.fill()

        NSColor.separatorColor.withAlphaComponent(0.25).setStroke()
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
            .foregroundColor: NSColor.tertiaryLabelColor
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
                let x = gutterWidth - labelSize.width - EditorLayout.gutterRightPadding
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
    var approximateLineCount: Int {
        guard length > 0 else { return 1 }
        var count = 1
        var index = 0
        while index < length {
            let r = range(of: "\n", options: .literal, range: NSRange(location: index, length: length - index))
            guard r.location != NSNotFound else { break }
            count += 1
            index = r.location + 1
        }
        return count
    }

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
