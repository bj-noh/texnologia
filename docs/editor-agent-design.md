# Subagent 3: Editor Agent - macOS Native LaTeX Editor 설계

## 1. 목표와 방향

Texifier의 편집기는 SwiftUI의 `TextEditor`만으로 구현하지 않는다. `TextEditor`는 macOS에서 다음 기능을 안정적으로 제어하기 어렵다.

- 긴 문서에서 부분 syntax highlighting
- line number gutter
- bracket matching overlay
- command autocomplete 팝오버
- selection/range 기반 search/replace
- IME, spell checking, undo manager, scroll sync 세부 제어
- 대용량 문서에서 incremental highlighting

따라서 MVP는 `NSViewRepresentable`로 `NSTextView`를 감싸는 방식으로 구현한다. 내부 텍스트 엔진은 우선 TextKit 1 기반 `NSTextStorage`/`NSLayoutManager`/`NSTextContainer` 조합을 사용하고, macOS 13+ 이상에서 TextKit 2 전환 가능성을 열어 둔다.

핵심 전략은 다음과 같다.

- 편집 컴포넌트는 AppKit을 사용하되, 외부 API는 SwiftUI 친화적으로 노출한다.
- MVP parsing은 regex/tokenizer 기반 lightweight parser로 제한한다.
- syntax highlighting은 변경 범위 주변 paragraph/block 단위로 incremental 적용한다.
- autocomplete, snippets, bracket matching, search/replace는 각각 독립 provider/service로 분리한다.
- 향후 tree-sitter 또는 custom LaTeX parser를 붙일 수 있도록 token stream 인터페이스를 안정화한다.

## 2. Editor Component 설계

### 2.1 주요 컴포넌트

```text
SwiftUI View
  LaTeXEditorView
    NSTextViewRepresentable
      EditorContainerView: NSView
        NSScrollView
          EditorTextView: NSTextView
        LineNumberRulerView: NSRulerView

Editor Core
  EditorCoordinator
  LaTeXTokenizer
  SyntaxHighlighter
  BracketMatcher
  AutocompleteController
  SnippetController
  SearchReplaceController
```

### 2.2 책임 분리

`LaTeXEditorView`

- SwiftUI에서 사용하는 진입점
- `@Binding var text: String`
- 현재 selection, search query, editor options를 binding 또는 callback으로 전달

`NSTextViewRepresentable`

- AppKit 뷰 생성 및 SwiftUI 업데이트 브리지
- `Coordinator`를 통해 delegate 이벤트 수신
- SwiftUI state와 `NSTextView.string` 간 동기화

`EditorTextView`

- `NSTextView` subclass
- keyDown override로 autocomplete/snippet/bracket shortcut 처리
- selection 변경, marked text, IME 흐름은 AppKit 기본 동작을 최대한 유지

`LineNumberRulerView`

- visible glyph range 기반 line number 렌더링
- soft wrap이 켜져도 logical line number 기준 표시

`SyntaxHighlighter`

- tokenizer 결과를 attribute로 변환
- theme와 font 정보를 주입받음
- 전체 문서 highlight와 dirty range highlight를 모두 지원

`LaTeXTokenizer`

- LaTeX command, environment, math delimiter, comment, brace, optional argument 등을 token화
- parser가 아니라 lexical scanner에 가깝게 유지

`AutocompleteProvider`

- 현재 cursor context를 입력받아 command/environment/snippet 후보 반환
- 기본 provider는 built-in LaTeX command 목록과 document-local command 목록을 합친다.

## 3. NSTextViewRepresentable 구현 방향

### 3.1 TextKit 1 우선 선택

MVP에서는 TextKit 1을 우선한다.

- `NSTextView`와의 통합 사례가 많고 안정적이다.
- `NSLayoutManager` 기반 line number 계산이 단순하다.
- `NSTextStorage` attribute 편집으로 syntax highlighting 적용이 쉽다.
- macOS compatibility 범위가 넓다.

구성:

```text
NSTextStorage
  NSLayoutManager
    NSTextContainer
      NSTextView
```

추후 TextKit 2 전환 시에는 `NSTextLayoutManager`, `NSTextContentStorage`, `NSTextViewportLayoutController`를 사용하는 별도 backend로 분리한다.

### 3.2 SwiftUI API 예시

```swift
struct LaTeXEditorView: View {
    @Binding var text: String
    var configuration: EditorConfiguration = .default
    var onSelectionChange: ((NSRange) -> Void)?

    var body: some View {
        LaTeXTextViewRepresentable(
            text: $text,
            configuration: configuration,
            onSelectionChange: onSelectionChange
        )
    }
}
```

### 3.3 동기화 원칙

- 사용자가 타이핑한 변경은 `textDidChange`에서 SwiftUI binding으로 전달한다.
- SwiftUI 외부에서 text가 바뀐 경우에만 `NSTextView.string`을 갱신한다.
- 갱신 시 selection을 가능한 보존한다.
- highlighting 중에는 delegate callback 재진입을 막는 flag를 둔다.
- undo stack은 `NSTextView.undoManager`를 기본 사용한다.

## 4. LaTeX Tokenizer 설계

### 4.1 MVP 토큰 타입

```swift
enum LaTeXTokenKind: Equatable {
    case command              // \section, \textbf
    case commandDeclaration   // \newcommand, \renewcommand
    case environmentName      // begin/end 내부 이름
    case beginEnvironment     // \begin
    case endEnvironment       // \end
    case comment              // % ...
    case mathDelimiter        // $, $$, \(, \), \[, \]
    case braceOpen            // {
    case braceClose           // }
    case bracketOpen          // [
    case bracketClose         // ]
    case argument
    case escapedCharacter     // \%, \&, \_
    case text
    case error
}

struct LaTeXToken: Equatable {
    let kind: LaTeXTokenKind
    let range: NSRange
    let lexeme: String
}
```

### 4.2 Scanner 규칙

Tokenizer는 한 번의 선형 scan으로 동작한다.

1. `%`를 만나면 line end까지 comment token
2. `\`를 만나면 다음 패턴을 확인
   - `\begin{...}`이면 begin/environmentName 토큰
   - `\end{...}`이면 end/environmentName 토큰
   - `\(`, `\)`, `\[`, `\]`이면 mathDelimiter
   - `\%`, `\&`, `\_`, `\{`, `\}` 등은 escapedCharacter
   - `\` 뒤 alphabet run은 command
   - `\` 뒤 non-alphabet 1글자는 command 또는 escapedCharacter
3. `$`는 `$` 또는 `$$` mathDelimiter
4. `{}`, `[]`는 bracket/brace token
5. 나머지는 text token으로 병합

### 4.3 Incremental Tokenizing

MVP에서는 변경된 range가 포함된 paragraph 범위를 다시 tokenizing한다.

- 입력: full string, edited range
- 확장: `NSString.paragraphRange(for:)`
- 추가 확장: LaTeX command/environment가 줄을 넘을 수 있으므로 앞뒤 N줄, 기본 3줄
- 적용: 해당 범위 token만 다시 highlight

수학 모드처럼 상태가 이전 줄에 의존하는 기능은 MVP에서 완전성을 포기하고, 근방 재스캔으로 실용성을 확보한다. 장문 문서 정확도는 추후 parser 도입 시 개선한다.

## 5. Syntax Highlighting Algorithm

### 5.1 색상 범주

- command: accent color
- environment: secondary accent
- comment: muted green/gray
- math delimiter: warm accent
- braces/brackets: foreground + subtle weight
- error: red underline
- text: normal foreground

### 5.2 적용 절차

1. dirty range 계산
2. 해당 range의 base attributes reset
3. tokenizer 실행
4. token kind별 attributes 생성
5. `textStorage.beginEditing()`
6. token range에 `addAttributes`
7. bracket match/error underline 등 transient style 적용
8. `textStorage.endEditing()`

중요한 점:

- 전체 문자열에 매 타이핑마다 attribute를 다시 입히지 않는다.
- `NSTextStorage` mutation 중 selection이 흔들리지 않도록 selection range를 저장/복원한다.
- attribute 적용은 main thread에서만 수행한다.
- tokenizer 자체는 background queue에서 실행 가능하지만, MVP에서는 단순성을 위해 main thread + dirty range로 시작한다.

### 5.3 Bracket Matching

커서가 `{`, `}`, `[`, `]`, `(`, `)` 또는 math delimiter 근처에 있을 때 실행한다.

- 현재 selection.location 기준 좌우 1글자 검사
- stack 기반으로 matching pair 탐색
- comment range 내부는 무시
- 찾으면 temporary attribute 또는 overlay로 highlight
- 못 찾으면 현재 bracket에 warning underline

MVP에서는 `NSLayoutManager` temporary attributes 사용을 우선한다.

## 6. Command Autocomplete 설계

### 6.1 Trigger

- `\` 입력 직후
- `\sec`처럼 command prefix 입력 중
- `\begin{` 내부 environment 이름 입력 중
- snippet prefix 입력 후 Tab

### 6.2 Context

```swift
struct AutocompleteContext {
    let fullText: String
    let cursorLocation: Int
    let currentLine: String
    let prefix: String
    let mode: AutocompleteMode
}

enum AutocompleteMode {
    case command
    case environment
    case citation
    case reference
    case snippet
}
```

### 6.3 Provider Interface

```swift
protocol AutocompleteProvider {
    func suggestions(for context: AutocompleteContext) async -> [AutocompleteSuggestion]
}

struct AutocompleteSuggestion: Identifiable, Equatable {
    let id: String
    let title: String
    let insertionText: String
    let detail: String?
    let kind: AutocompleteSuggestionKind
    let replacementRange: NSRange
}

enum AutocompleteSuggestionKind {
    case command
    case environment
    case citation
    case reference
    case snippet
}
```

Provider 구성:

- `BuiltInLaTeXCommandProvider`: 기본 LaTeX 명령
- `DocumentSymbolProvider`: 문서 내 `\label`, `\ref`, `\newcommand`, `\bibitem` 추출
- `SnippetProvider`: 사용자 snippet
- `CompositeAutocompleteProvider`: 여러 provider 결과 병합/정렬

정렬 기준:

1. prefix exact match
2. prefix startsWith
3. 최근 사용 빈도
4. command category priority
5. alphabetic order

## 7. Snippets 설계

Snippet은 placeholder를 가진 template로 정의한다.

```swift
struct EditorSnippet: Identifiable, Codable, Equatable {
    let id: String
    let trigger: String
    let title: String
    let template: String
}
```

예:

```text
trigger: fig
template:
\begin{figure}[ht]
    \centering
    \includegraphics[width=\linewidth]{${1:path}}
    \caption{${2:caption}}
    \label{fig:${3:label}}
\end{figure}
```

MVP에서는 snippet 삽입 후 첫 placeholder만 선택한다. 다중 placeholder 이동은 추후 `SnippetSession`으로 관리한다.

## 8. Spell Checking

`NSTextView`의 기본 spell checking을 활용한다.

- `isContinuousSpellCheckingEnabled = true`
- `isGrammarCheckingEnabled`는 옵션으로 제공
- LaTeX command/comment/math 구간은 spell checking 제외가 이상적이나, MVP에서는 command token에 `.spellCheckingState` 또는 temporary attribute 제어를 검토한다.
- 현실적인 MVP: AppKit 기본 spell checking을 켜고, LaTeX command 오탐은 추후 개선한다.

추후 개선:

- tokenizer token range를 기반으로 natural language range만 spell checker에 전달
- custom `NSSpellChecker` integration

## 9. Line Numbers

`NSRulerView` subclass로 구현한다.

동작:

- `NSScrollView.verticalRulerView = LineNumberRulerView(textView:)`
- `hasVerticalRuler = true`
- visible rect 기준 glyph range 계산
- glyph index -> character index -> line number 계산
- line number 폭은 전체 line count 자릿수에 따라 동적 조정

주의:

- soft wrap 시 visual line마다 번호를 찍지 않고 logical line 시작 위치에만 표시한다.
- font 변경 시 ruler width와 baseline offset 재계산
- scroll/resize/text change 시 `needsDisplay = true`

## 10. Search/Replace 설계

### 10.1 Search Options

```swift
struct SearchOptions: Equatable {
    var caseSensitive: Bool = false
    var wholeWord: Bool = false
    var useRegularExpression: Bool = false
    var wraps: Bool = true
}
```

### 10.2 Search Controller

기능:

- 현재 query match ranges 계산
- next/previous 이동
- current match selection 적용
- all matches temporary highlight
- replace current
- replace all

MVP에서는 `NSString.range(of:options:range:)`와 `NSRegularExpression`을 사용한다. 대용량 문서에서는 debounce 후 background queue에서 match range를 계산한다.

## 11. Example Swift Code Skeleton

아래 코드는 구조 예시이며, 실제 프로젝트 생성 후 파일을 나누어 배치한다.

```swift
import SwiftUI
import AppKit

struct EditorConfiguration: Equatable {
    var font: NSFont = .monospacedSystemFont(ofSize: 14, weight: .regular)
    var showsLineNumbers: Bool = true
    var isSpellCheckingEnabled: Bool = true

    static let `default` = EditorConfiguration()
}

struct LaTeXEditorView: View {
    @Binding var text: String
    var configuration: EditorConfiguration = .default
    var onSelectionChange: ((NSRange) -> Void)?

    var body: some View {
        LaTeXTextViewRepresentable(
            text: $text,
            configuration: configuration,
            onSelectionChange: onSelectionChange
        )
    }
}

struct LaTeXTextViewRepresentable: NSViewRepresentable {
    @Binding var text: String
    let configuration: EditorConfiguration
    let onSelectionChange: ((NSRange) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> EditorContainerView {
        let container = EditorContainerView(configuration: configuration)
        container.textView.delegate = context.coordinator
        container.textView.string = text
        context.coordinator.attach(textView: container.textView)
        return container
    }

    func updateNSView(_ nsView: EditorContainerView, context: Context) {
        context.coordinator.parent = self
        nsView.apply(configuration: configuration)

        if nsView.textView.string != text && !context.coordinator.isApplyingTextChange {
            let selectedRange = nsView.textView.selectedRange()
            nsView.textView.string = text
            nsView.textView.setSelectedRange(selectedRange.clamped(toLength: (text as NSString).length))
            context.coordinator.highlightFullDocument()
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: LaTeXTextViewRepresentable
        weak var textView: EditorTextView?
        var isApplyingTextChange = false

        private let tokenizer = LaTeXTokenizer()
        private let highlighter = SyntaxHighlighter()

        init(_ parent: LaTeXTextViewRepresentable) {
            self.parent = parent
        }

        func attach(textView: EditorTextView) {
            self.textView = textView
            textView.autocompleteProvider = CompositeAutocompleteProvider(providers: [
                BuiltInLaTeXCommandProvider(),
                SnippetAutocompleteProvider()
            ])
            highlightFullDocument()
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }

            isApplyingTextChange = true
            parent.text = textView.string
            isApplyingTextChange = false

            let editedRange = textView.lastEditedRange
            highlighter.highlight(
                textStorage: textView.textStorage,
                string: textView.string,
                dirtyRange: editedRange,
                tokenizer: tokenizer
            )

            textView.lineNumberRulerView?.needsDisplay = true
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView else { return }
            parent.onSelectionChange?(textView.selectedRange())
            textView.bracketMatcher.updateMatch(in: textView)
        }

        func highlightFullDocument() {
            guard let textView else { return }
            let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
            highlighter.highlight(
                textStorage: textView.textStorage,
                string: textView.string,
                dirtyRange: fullRange,
                tokenizer: tokenizer
            )
        }
    }
}

final class EditorContainerView: NSView {
    let scrollView = NSScrollView()
    let textView: EditorTextView

    init(configuration: EditorConfiguration) {
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(containerSize: .zero)

        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)

        textContainer.widthTracksTextView = true
        textContainer.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        textView = EditorTextView(frame: .zero, textContainer: textContainer)
        super.init(frame: .zero)

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = true

        addSubview(scrollView)
        apply(configuration: configuration)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
    }

    func apply(configuration: EditorConfiguration) {
        textView.font = configuration.font
        textView.isContinuousSpellCheckingEnabled = configuration.isSpellCheckingEnabled

        if configuration.showsLineNumbers {
            let ruler = textView.lineNumberRulerView ?? LineNumberRulerView(textView: textView)
            textView.lineNumberRulerView = ruler
            scrollView.verticalRulerView = ruler
            scrollView.hasVerticalRuler = true
            scrollView.rulersVisible = true
        } else {
            scrollView.hasVerticalRuler = false
            scrollView.rulersVisible = false
        }
    }
}

final class EditorTextView: NSTextView {
    var autocompleteProvider: AutocompleteProvider?
    let bracketMatcher = BracketMatcher()
    weak var lineNumberRulerView: LineNumberRulerView?

    var lastEditedRange: NSRange {
        // MVP placeholder. 실제 구현에서는 shouldChangeTextIn 또는 textStorage delegate에서 추적한다.
        selectedRange()
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if handleAutocompleteKey(event) {
            return
        }
        super.keyDown(with: event)
    }

    private func handleAutocompleteKey(_ event: NSEvent) -> Bool {
        // Tab, Escape, Return, Arrow key를 autocomplete popover와 연결한다.
        false
    }
}

extension NSRange {
    func clamped(toLength length: Int) -> NSRange {
        let location = min(max(0, self.location), length)
        let maxLength = max(0, length - location)
        return NSRange(location: location, length: min(self.length, maxLength))
    }
}
```

### 11.1 Tokenizer Skeleton

```swift
import Foundation

enum LaTeXTokenKind: Equatable {
    case command
    case commandDeclaration
    case environmentName
    case beginEnvironment
    case endEnvironment
    case comment
    case mathDelimiter
    case braceOpen
    case braceClose
    case bracketOpen
    case bracketClose
    case escapedCharacter
    case text
    case error
}

struct LaTeXToken: Equatable {
    let kind: LaTeXTokenKind
    let range: NSRange
    let lexeme: String
}

final class LaTeXTokenizer {
    func tokenize(_ string: String, in range: NSRange? = nil) -> [LaTeXToken] {
        let nsString = string as NSString
        let scanRange = range ?? NSRange(location: 0, length: nsString.length)
        let end = scanRange.location + scanRange.length
        var index = scanRange.location
        var tokens: [LaTeXToken] = []

        while index < end {
            let char = nsString.character(at: index)

            if char == ascii("%") {
                let lineRange = nsString.lineRange(for: NSRange(location: index, length: 0))
                let commentEnd = min(lineRange.location + lineRange.length, end)
                tokens.append(token(.comment, nsString, index, commentEnd))
                index = commentEnd
                continue
            }

            if char == ascii("\\") {
                let parsed = parseCommand(in: nsString, start: index, limit: end)
                tokens.append(contentsOf: parsed.tokens)
                index = parsed.nextIndex
                continue
            }

            if char == ascii("$") {
                let next = index + 1
                if next < end && nsString.character(at: next) == ascii("$") {
                    tokens.append(token(.mathDelimiter, nsString, index, index + 2))
                    index += 2
                } else {
                    tokens.append(token(.mathDelimiter, nsString, index, index + 1))
                    index += 1
                }
                continue
            }

            switch char {
            case ascii("{"):
                tokens.append(token(.braceOpen, nsString, index, index + 1))
                index += 1
            case ascii("}"):
                tokens.append(token(.braceClose, nsString, index, index + 1))
                index += 1
            case ascii("["):
                tokens.append(token(.bracketOpen, nsString, index, index + 1))
                index += 1
            case ascii("]"):
                tokens.append(token(.bracketClose, nsString, index, index + 1))
                index += 1
            default:
                let start = index
                index += 1
                while index < end && !isSpecial(nsString.character(at: index)) {
                    index += 1
                }
                tokens.append(token(.text, nsString, start, index))
            }
        }

        return tokens
    }

    private func parseCommand(in nsString: NSString, start: Int, limit: Int) -> (tokens: [LaTeXToken], nextIndex: Int) {
        let next = start + 1
        guard next < limit else {
            return ([token(.error, nsString, start, start + 1)], start + 1)
        }

        let nextChar = nsString.character(at: next)

        if nextChar == ascii("(") || nextChar == ascii(")") ||
            nextChar == ascii("[") || nextChar == ascii("]") {
            return ([token(.mathDelimiter, nsString, start, next + 1)], next + 1)
        }

        if !isLetter(nextChar) {
            return ([token(.escapedCharacter, nsString, start, next + 1)], next + 1)
        }

        var index = next
        while index < limit && isLetter(nsString.character(at: index)) {
            index += 1
        }

        let lexeme = nsString.substring(with: NSRange(location: start, length: index - start))
        let kind: LaTeXTokenKind

        switch lexeme {
        case "\\begin":
            kind = .beginEnvironment
        case "\\end":
            kind = .endEnvironment
        case "\\newcommand", "\\renewcommand", "\\DeclareMathOperator":
            kind = .commandDeclaration
        default:
            kind = .command
        }

        var tokens = [token(kind, nsString, start, index)]

        if (kind == .beginEnvironment || kind == .endEnvironment),
           index < limit,
           nsString.character(at: index) == ascii("{") {
            tokens.append(token(.braceOpen, nsString, index, index + 1))
            let nameStart = index + 1
            var nameEnd = nameStart
            while nameEnd < limit && nsString.character(at: nameEnd) != ascii("}") {
                nameEnd += 1
            }
            if nameEnd > nameStart {
                tokens.append(token(.environmentName, nsString, nameStart, nameEnd))
            }
            if nameEnd < limit {
                tokens.append(token(.braceClose, nsString, nameEnd, nameEnd + 1))
                return (tokens, nameEnd + 1)
            }
        }

        return (tokens, index)
    }

    private func token(_ kind: LaTeXTokenKind, _ nsString: NSString, _ start: Int, _ end: Int) -> LaTeXToken {
        let range = NSRange(location: start, length: end - start)
        return LaTeXToken(kind: kind, range: range, lexeme: nsString.substring(with: range))
    }

    private func isSpecial(_ char: unichar) -> Bool {
        char == ascii("%") || char == ascii("\\") || char == ascii("$") ||
        char == ascii("{") || char == ascii("}") ||
        char == ascii("[") || char == ascii("]")
    }

    private func isLetter(_ char: unichar) -> Bool {
        (char >= ascii("a") && char <= ascii("z")) ||
        (char >= ascii("A") && char <= ascii("Z"))
    }
}

private func ascii(_ value: Character) -> unichar {
    unichar(String(value).utf16.first!)
}
```

### 11.2 Highlighter Skeleton

```swift
import AppKit

final class SyntaxHighlighter {
    private let baseAttributes: [NSAttributedString.Key: Any] = [
        .foregroundColor: NSColor.labelColor,
        .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    ]

    func highlight(
        textStorage: NSTextStorage?,
        string: String,
        dirtyRange: NSRange,
        tokenizer: LaTeXTokenizer
    ) {
        guard let textStorage else { return }

        let nsString = string as NSString
        let expandedRange = expandedHighlightRange(in: nsString, dirtyRange: dirtyRange)
        let tokens = tokenizer.tokenize(string, in: expandedRange)

        textStorage.beginEditing()
        textStorage.setAttributes(baseAttributes, range: expandedRange)

        for token in tokens {
            textStorage.addAttributes(attributes(for: token.kind), range: token.range)
        }

        textStorage.endEditing()
    }

    private func expandedHighlightRange(in nsString: NSString, dirtyRange: NSRange) -> NSRange {
        let paragraph = nsString.paragraphRange(for: dirtyRange)
        return paragraph
    }

    private func attributes(for kind: LaTeXTokenKind) -> [NSAttributedString.Key: Any] {
        switch kind {
        case .command, .commandDeclaration:
            return [.foregroundColor: NSColor.systemBlue]
        case .beginEnvironment, .endEnvironment, .environmentName:
            return [.foregroundColor: NSColor.systemPurple]
        case .comment:
            return [.foregroundColor: NSColor.systemGreen]
        case .mathDelimiter:
            return [.foregroundColor: NSColor.systemOrange]
        case .braceOpen, .braceClose, .bracketOpen, .bracketClose:
            return [.foregroundColor: NSColor.secondaryLabelColor]
        case .error:
            return [
                .foregroundColor: NSColor.systemRed,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ]
        case .escapedCharacter, .text:
            return [:]
        }
    }
}
```

### 11.3 Autocomplete Skeleton

```swift
import Foundation

struct AutocompleteContext {
    let fullText: String
    let cursorLocation: Int
    let currentLine: String
    let prefix: String
    let mode: AutocompleteMode
}

enum AutocompleteMode {
    case command
    case environment
    case citation
    case reference
    case snippet
}

struct AutocompleteSuggestion: Identifiable, Equatable {
    let id: String
    let title: String
    let insertionText: String
    let detail: String?
    let kind: AutocompleteSuggestionKind
    let replacementRange: NSRange
}

enum AutocompleteSuggestionKind {
    case command
    case environment
    case citation
    case reference
    case snippet
}

protocol AutocompleteProvider {
    func suggestions(for context: AutocompleteContext) async -> [AutocompleteSuggestion]
}

struct BuiltInLaTeXCommandProvider: AutocompleteProvider {
    private let commands = [
        "\\section",
        "\\subsection",
        "\\textbf",
        "\\emph",
        "\\frac",
        "\\sqrt",
        "\\label",
        "\\ref",
        "\\cite"
    ]

    func suggestions(for context: AutocompleteContext) async -> [AutocompleteSuggestion] {
        guard context.mode == .command else { return [] }

        return commands
            .filter { $0.hasPrefix(context.prefix) }
            .map {
                AutocompleteSuggestion(
                    id: $0,
                    title: $0,
                    insertionText: $0,
                    detail: nil,
                    kind: .command,
                    replacementRange: NSRange(
                        location: context.cursorLocation - (context.prefix as NSString).length,
                        length: (context.prefix as NSString).length
                    )
                )
            }
    }
}

struct SnippetAutocompleteProvider: AutocompleteProvider {
    func suggestions(for context: AutocompleteContext) async -> [AutocompleteSuggestion] {
        []
    }
}

struct CompositeAutocompleteProvider: AutocompleteProvider {
    let providers: [AutocompleteProvider]

    func suggestions(for context: AutocompleteContext) async -> [AutocompleteSuggestion] {
        var merged: [AutocompleteSuggestion] = []
        for provider in providers {
            merged.append(contentsOf: await provider.suggestions(for: context))
        }
        return Array(merged.prefix(20))
    }
}
```

## 12. MVP 구현 순서

1. `LaTeXEditorView` + `NSTextViewRepresentable` 기본 편집
2. line number gutter
3. tokenizer + full document highlighting
4. dirty range incremental highlighting
5. bracket matching
6. command autocomplete popover
7. snippets insertion
8. search/replace panel
9. spell checking options
10. document symbol extraction

## 13. 향후 확장

### 13.1 Tree-sitter

LaTeX grammar가 프로젝트 요구에 충분히 맞는지 검증한 뒤 도입한다. 장점은 incremental parsing과 구조적 query이고, 단점은 Swift/macOS 배포 빌드 복잡도다.

적합한 기능:

- 정확한 environment folding
- outline/sidebar
- command argument semantic highlighting
- syntax error diagnostics
- symbol index

### 13.2 Custom Parser

LaTeX는 macro expansion 때문에 완전 parsing이 어렵다. 대신 Texifier 목적에 맞춘 pragmatic parser를 고려한다.

- tokenizer는 유지
- command/environment/math/comment block parser 추가
- symbol table 생성
- diagnostics와 autocomplete에 활용

### 13.3 TextKit 2

TextKit 2는 viewport 기반 layout과 modern text rendering에 장점이 있다. 단, `NSTextView` 생태계에서 TextKit 1 대비 구현 사례와 호환성 이슈를 확인해야 한다.

전환 조건:

- 대형 문서 성능 병목이 TextKit 1 layout에서 발생
- viewport 기반 highlighting/decoration이 필요
- target macOS 버전을 충분히 높일 수 있음

## 14. 결론

MVP는 `NSTextView` + TextKit 1 + lightweight tokenizer로 시작하는 것이 가장 현실적이다. 이 선택은 macOS-native editing 기능을 즉시 확보하면서도, tokenizer/provider/controller 경계를 잘 나누면 tree-sitter, custom parser, TextKit 2로의 확장도 막지 않는다.

초기 구현의 핵심은 완벽한 LaTeX parsing이 아니라, 빠른 입력 반응성, 안정적인 selection/undo 동작, 편집자가 기대하는 syntax highlighting/autocomplete/search 경험을 균형 있게 제공하는 것이다.
