import AppKit

enum EditorSyntaxMode: Equatable {
    case latex
    case bibtex
    case plain
}

struct LatexToken {
    enum Kind {
        case command
        case comment
        case brace
        case mathDelimiter
    }

    var kind: Kind
    var range: NSRange
}

final class LatexTokenizer {
    func tokenize(_ text: String) -> [LatexToken] {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        var tokens: [LatexToken] = []

        let patterns: [(LatexToken.Kind, String)] = [
            (.comment, #"(?m)%.*$"#),
            (.command, #"\\[A-Za-z@]+|\\."#),
            (.mathDelimiter, #"\$\$?|\Q\(\E|\Q\)\E|\Q\[\E|\Q\]\E"#),
            (.brace, #"[{}\[\]]"#)
        ]

        for (kind, pattern) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            regex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
                if let range = match?.range {
                    tokens.append(LatexToken(kind: kind, range: range))
                }
            }
        }

        return tokens.sorted { $0.range.location < $1.range.location }
    }
}

struct BibToken {
    enum Kind {
        case entryType
        case citationKey
        case fieldName
        case string
        case number
        case comment
        case punctuation
    }

    var kind: Kind
    var range: NSRange
}

final class BibTokenizer {
    func tokenize(_ text: String) -> [BibToken] {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        var tokens: [BibToken] = []

        appendMatches(kind: .comment, pattern: #"(?m)^\s*%.*$"#, in: text, range: fullRange, to: &tokens)
        appendMatches(kind: .entryType, pattern: #"@[A-Za-z]+\b"#, in: text, range: fullRange, to: &tokens)
        appendMatches(kind: .fieldName, pattern: #"(?m)^\s*([A-Za-z][A-Za-z0-9_-]*)\s*="#, captureGroup: 1, in: text, range: fullRange, to: &tokens)
        appendMatches(kind: .citationKey, pattern: #"@[A-Za-z]+\s*\{\s*([^,\s]+)"#, captureGroup: 1, in: text, range: fullRange, to: &tokens)
        appendMatches(kind: .string, pattern: #""(?:\\.|[^"\\])*""#, in: text, range: fullRange, to: &tokens)
        appendMatches(kind: .number, pattern: #"\b\d{2,4}\b"#, in: text, range: fullRange, to: &tokens)
        appendMatches(kind: .punctuation, pattern: #"[{}(),=#]"#, in: text, range: fullRange, to: &tokens)

        return tokens.sorted { $0.range.location < $1.range.location }
    }

    private func appendMatches(
        kind: BibToken.Kind,
        pattern: String,
        captureGroup: Int = 0,
        in text: String,
        range fullRange: NSRange,
        to tokens: inout [BibToken]
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        regex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            guard let match else { return }
            let range = match.range(at: captureGroup)
            guard range.location != NSNotFound, range.length > 0 else { return }
            tokens.append(BibToken(kind: kind, range: range))
        }
    }
}

final class LatexSyntaxHighlighter {
    private let tokenizer = LatexTokenizer()
    private let bibTokenizer = BibTokenizer()
    private let maxHighlightedCharacters = 180_000

    func apply(to textStorage: NSTextStorage?, text: String, settings: AppSettings, syntaxMode: EditorSyntaxMode = .latex) {
        guard let textStorage else { return }

        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        let font = NSFont(name: settings.editorFontName, size: settings.editorFontSize)
            ?? .monospacedSystemFont(ofSize: settings.editorFontSize, weight: .regular)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = settings.editorLineSpacing
        paragraphStyle.lineBreakMode = .byWordWrapping
        let palette = settings.editorTheme.palette

        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: palette.foreground,
            .paragraphStyle: paragraphStyle
        ]

        textStorage.beginEditing()
        textStorage.setAttributes(baseAttributes, range: fullRange)

        if text.count <= maxHighlightedCharacters {
            switch syntaxMode {
            case .latex:
                for token in tokenizer.tokenize(text) {
                    textStorage.addAttributes(attributes(for: token.kind, palette: palette), range: token.range)
                }
            case .bibtex:
                for token in bibTokenizer.tokenize(text) {
                    textStorage.addAttributes(attributes(for: token.kind, palette: palette), range: token.range)
                }
            case .plain:
                break
            }

            if settings.editorShowInvisibles {
                applyInvisibleMarks(to: textStorage, text: text, font: font, palette: palette)
            }
        }


        textStorage.endEditing()
    }

    private func attributes(for kind: LatexToken.Kind, palette: EditorPalette) -> [NSAttributedString.Key: Any] {
        switch kind {
        case .command:
            return [.foregroundColor: palette.command]
        case .comment:
            return [.foregroundColor: palette.comment]
        case .brace:
            return [.foregroundColor: palette.brace]
        case .mathDelimiter:
            return [.foregroundColor: palette.math]
        }
    }

    private func attributes(for kind: BibToken.Kind, palette: EditorPalette) -> [NSAttributedString.Key: Any] {
        switch kind {
        case .entryType:
            return [.foregroundColor: palette.bibEntryType]
        case .citationKey:
            return [.foregroundColor: palette.bibCitationKey]
        case .fieldName:
            return [.foregroundColor: palette.bibFieldName]
        case .string:
            return [.foregroundColor: palette.bibString]
        case .number:
            return [.foregroundColor: palette.math]
        case .comment:
            return [.foregroundColor: palette.comment]
        case .punctuation:
            return [.foregroundColor: palette.brace]
        }
    }

    func isSpellCheckExcluded(_ range: NSRange, in text: String, syntaxMode: EditorSyntaxMode = .latex) -> Bool {
        spellCheckExcludedRanges(in: text, syntaxMode: syntaxMode).contains { excludedRange in
            NSIntersectionRange(range, excludedRange).length > 0
        }
    }

    func spellCheckExcludedRanges(in text: String, syntaxMode: EditorSyntaxMode = .latex) -> [NSRange] {
        switch syntaxMode {
        case .latex:
            return latexSpellCheckExcludedRanges(in: text)
        case .bibtex:
            return bibSpellCheckExcludedRanges(in: text)
        case .plain:
            return []
        }
    }

    private func latexSpellCheckExcludedRanges(in text: String) -> [NSRange] {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        var ranges = tokenizer.tokenize(text)
            .filter { token in
                switch token.kind {
                case .command, .comment, .mathDelimiter:
                    return true
                case .brace:
                    return false
                }
            }
            .map(\.range)

        let textCommandNames = [
            "emph",
            "section",
            "subsection",
            "subsubsection",
            "paragraph",
            "subparagraph",
            "textbf",
            "textit",
            "textrm",
            "textsf",
            "texttt",
            "caption"
        ]
        let latexOnlyCommandNames = [
            "addbibresource",
            "autocite",
            "autoref",
            "bibliography",
            "cite",
            "citealp",
            "citeauthor",
            "citep",
            "citet",
            "citeyear",
            "Cref",
            "cref",
            "eqref",
            "include",
            "includegraphics",
            "input",
            "label",
            "nocite",
            "parencite",
            "ref",
            "textcite",
            "url"
        ]

        let commandArgumentPattern = #"\\(?!(?:"# + textCommandNames.joined(separator: "|") + #")\b)[A-Za-z@]+\*?(?:\s*\[[^\]]*\]){0,3}\s*\{[^{}\n]*\}"#
        let latexOnlyArgumentPattern = #"\\"# + "(?:" + latexOnlyCommandNames.joined(separator: "|") + #")\*?(?:\s*\[[^\]]*\]){0,3}\s*\{[^{}]*\}"#

        let regexes: [(String, NSRegularExpression.Options)] = [
            (#"(?m)%.*$"#, []),
            (commandArgumentPattern, []),
            (latexOnlyArgumentPattern, [.dotMatchesLineSeparators]),
            (#"\\(?:begin|end)\s*\{[^{}]*\}"#, []),
            (#"\$\$.*?\$\$"#, [.dotMatchesLineSeparators]),
            (#"\$[^\n$]*\$"#, []),
            (#"\\\[.*?\\\]"#, [.dotMatchesLineSeparators]),
            (#"\\\(.*?\\\)"#, [.dotMatchesLineSeparators])
        ]

        for (pattern, options) in regexes {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { continue }
            regex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
                guard let range = match?.range else { return }
                ranges.append(range)
            }
        }

        return ranges
    }

    private func bibSpellCheckExcludedRanges(in text: String) -> [NSRange] {
        bibTokenizer.tokenize(text)
            .filter { token in
                switch token.kind {
                case .entryType, .citationKey, .fieldName, .comment, .punctuation:
                    return true
                case .string, .number:
                    return false
                }
            }
            .map(\.range)
    }

    private func applyInvisibleMarks(
        to textStorage: NSTextStorage,
        text: String,
        font: NSFont,
        palette: EditorPalette
    ) {
        let nsText = text as NSString
        for index in 0..<nsText.length {
            let character = nsText.character(at: index)
            guard character == 32 || character == 9 else { continue }
            let mark = character == 9 ? "→" : "·"
            textStorage.addAttribute(
                .toolTip,
                value: mark,
                range: NSRange(location: index, length: 1)
            )
            textStorage.addAttributes(
                [
                    .foregroundColor: palette.invisible,
                    .font: font
                ],
                range: NSRange(location: index, length: 1)
            )
        }
    }
}

struct EditorPalette {
    var background: NSColor
    var foreground: NSColor
    var command: NSColor
    var comment: NSColor
    var brace: NSColor
    var math: NSColor
    var bibEntryType: NSColor
    var bibCitationKey: NSColor
    var bibFieldName: NSColor
    var bibString: NSColor
    var invisible: NSColor
    var insertionPoint: NSColor
}

extension EditorTheme {
    var palette: EditorPalette {
        switch self {
        case .system:
            return EditorPalette(
                background: .textBackgroundColor,
                foreground: .labelColor,
                command: .systemBlue,
                comment: .systemGreen,
                brace: .secondaryLabelColor,
                math: .systemOrange,
                bibEntryType: .systemPurple,
                bibCitationKey: .systemTeal,
                bibFieldName: .systemBlue,
                bibString: .systemBrown,
                invisible: .tertiaryLabelColor,
                insertionPoint: .labelColor
            )
        case .paper:
            return EditorPalette(
                background: NSColor(red: 0.98, green: 0.97, blue: 0.94, alpha: 1),
                foreground: NSColor(red: 0.13, green: 0.12, blue: 0.10, alpha: 1),
                command: NSColor(red: 0.10, green: 0.32, blue: 0.66, alpha: 1),
                comment: NSColor(red: 0.34, green: 0.45, blue: 0.24, alpha: 1),
                brace: NSColor(red: 0.42, green: 0.38, blue: 0.31, alpha: 1),
                math: NSColor(red: 0.66, green: 0.29, blue: 0.12, alpha: 1),
                bibEntryType: NSColor(red: 0.43, green: 0.18, blue: 0.58, alpha: 1),
                bibCitationKey: NSColor(red: 0.05, green: 0.44, blue: 0.44, alpha: 1),
                bibFieldName: NSColor(red: 0.10, green: 0.32, blue: 0.66, alpha: 1),
                bibString: NSColor(red: 0.58, green: 0.33, blue: 0.12, alpha: 1),
                invisible: NSColor(red: 0.70, green: 0.66, blue: 0.58, alpha: 1),
                insertionPoint: NSColor(red: 0.13, green: 0.12, blue: 0.10, alpha: 1)
            )
        case .dusk:
            return EditorPalette(
                background: NSColor(red: 0.13, green: 0.15, blue: 0.18, alpha: 1),
                foreground: NSColor(red: 0.86, green: 0.87, blue: 0.84, alpha: 1),
                command: NSColor(red: 0.51, green: 0.70, blue: 0.96, alpha: 1),
                comment: NSColor(red: 0.55, green: 0.70, blue: 0.45, alpha: 1),
                brace: NSColor(red: 0.68, green: 0.70, blue: 0.72, alpha: 1),
                math: NSColor(red: 0.95, green: 0.66, blue: 0.35, alpha: 1),
                bibEntryType: NSColor(red: 0.78, green: 0.62, blue: 0.95, alpha: 1),
                bibCitationKey: NSColor(red: 0.42, green: 0.82, blue: 0.78, alpha: 1),
                bibFieldName: NSColor(red: 0.51, green: 0.70, blue: 0.96, alpha: 1),
                bibString: NSColor(red: 0.95, green: 0.74, blue: 0.42, alpha: 1),
                invisible: NSColor(red: 0.38, green: 0.42, blue: 0.46, alpha: 1),
                insertionPoint: NSColor(red: 0.86, green: 0.87, blue: 0.84, alpha: 1)
            )
        case .midnight:
            return EditorPalette(
                background: NSColor(red: 0.05, green: 0.06, blue: 0.08, alpha: 1),
                foreground: NSColor(red: 0.88, green: 0.90, blue: 0.92, alpha: 1),
                command: NSColor(red: 0.42, green: 0.68, blue: 1.00, alpha: 1),
                comment: NSColor(red: 0.40, green: 0.72, blue: 0.52, alpha: 1),
                brace: NSColor(red: 0.70, green: 0.74, blue: 0.78, alpha: 1),
                math: NSColor(red: 1.00, green: 0.72, blue: 0.36, alpha: 1),
                bibEntryType: NSColor(red: 0.82, green: 0.60, blue: 1.00, alpha: 1),
                bibCitationKey: NSColor(red: 0.34, green: 0.86, blue: 0.82, alpha: 1),
                bibFieldName: NSColor(red: 0.42, green: 0.68, blue: 1.00, alpha: 1),
                bibString: NSColor(red: 1.00, green: 0.78, blue: 0.44, alpha: 1),
                invisible: NSColor(red: 0.28, green: 0.31, blue: 0.36, alpha: 1),
                insertionPoint: NSColor.white
            )
        }
    }
}
