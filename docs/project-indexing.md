# PaperForge LaTeX Project Indexing 설계

## 목표

PaperForge의 프로젝트 인덱서는 LaTeX 프로젝트를 파일 그래프와 심볼 인덱스로 해석해 사이드바, 자동완성, 빠른 이동, 경고 표시의 공통 기반을 제공한다.

핵심 산출물은 다음과 같다.

- 루트 `.tex` 탐지
- `\input`, `\include`, `\subfile`, `\includeonly` 기반 파일 그래프
- `\bibliography`, `\addbibresource` 기반 BibTeX/BibLaTeX 리소스 그래프
- `\label`, `\ref`, `\pageref`, `\autoref`, `\cref`, `\cite...` 추출
- `.bib` 파일의 citation key 추출
- section outline, labels, citation keys, TODO index model
- 파일 변경에 반응하는 증분 인덱싱

## ProjectIndex 데이터 모델

인덱스는 "프로젝트 스냅샷"으로 취급한다. UI는 항상 불변 스냅샷을 읽고, 백그라운드 인덱서가 새 스냅샷을 만들어 교체한다.

```swift
struct ProjectIndex: Equatable, Sendable {
    var projectRoot: URL
    var rootDocuments: [TexRootDocument]
    var files: [URL: IndexedFile]
    var graph: FileGraph
    var outline: [OutlineNode]
    var labels: [String: [LabelDefinition]]
    var references: [ReferenceUse]
    var citationKeys: [String: [CitationKeyDefinition]]
    var citationUses: [CitationUse]
    var todos: [TodoItem]
    var diagnostics: [IndexDiagnostic]
    var builtAt: Date
    var version: Int
}

struct TexRootDocument: Equatable, Sendable {
    var url: URL
    var confidence: RootConfidence
    var reason: String
}

enum RootConfidence: Int, Sendable {
    case explicit = 100
    case high = 80
    case medium = 50
    case low = 20
}

struct IndexedFile: Equatable, Sendable {
    var url: URL
    var kind: IndexedFileKind
    var contentHash: String
    var modifiedAt: Date
    var parseResult: FileParseResult
}

enum IndexedFileKind: Sendable {
    case tex
    case bib
    case cls
    case sty
    case unknown
}

struct FileGraph: Equatable, Sendable {
    var roots: [URL]
    var edges: [FileEdge]
    var reverseEdges: [URL: Set<URL>]
    var missingFiles: [MissingFileReference]
}

struct FileEdge: Hashable, Sendable {
    var from: URL
    var to: URL
    var kind: FileEdgeKind
    var sourceRange: SourceRange
}

enum FileEdgeKind: Hashable, Sendable {
    case input
    case include
    case subfile
    case bibliography
    case bibResource
    case package
    case documentClass
}

struct FileParseResult: Equatable, Sendable {
    var dependencies: [DependencyUse]
    var outline: [OutlineNode]
    var labels: [LabelDefinition]
    var references: [ReferenceUse]
    var citationUses: [CitationUse]
    var citationDefinitions: [CitationKeyDefinition]
    var todos: [TodoItem]
    var diagnostics: [IndexDiagnostic]
}
```

사이드바에 바로 쓰는 모델은 `ProjectIndex`에서 파생한다. UI가 매번 전체 인덱스를 뒤지지 않도록 뷰 모델 캐시를 둘 수 있다.

```swift
struct SidebarIndexModel: Equatable, Sendable {
    var fileTree: [ProjectFileNode]
    var outline: [OutlineNode]
    var labels: [LabelSidebarItem]
    var citationKeys: [CitationSidebarItem]
    var todos: [TodoItem]
}

struct ProjectFileNode: Identifiable, Equatable, Sendable {
    var id: URL { url }
    var url: URL
    var displayName: String
    var kind: IndexedFileKind
    var children: [ProjectFileNode]
    var isMissing: Bool
}

struct OutlineNode: Identifiable, Equatable, Sendable {
    var id: SymbolID
    var title: String
    var level: OutlineLevel
    var fileURL: URL
    var range: SourceRange
    var numberHint: String?
    var children: [OutlineNode]
}

enum OutlineLevel: Int, Comparable, Sendable {
    case part = 0
    case chapter = 1
    case section = 2
    case subsection = 3
    case subsubsection = 4
    case paragraph = 5
    case subparagraph = 6

    static func < (lhs: OutlineLevel, rhs: OutlineLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct LabelDefinition: Identifiable, Equatable, Sendable {
    var id: SymbolID
    var key: String
    var fileURL: URL
    var range: SourceRange
    var nearestOutlineID: SymbolID?
}

struct ReferenceUse: Identifiable, Equatable, Sendable {
    var id: SymbolID
    var command: String
    var key: String
    var fileURL: URL
    var range: SourceRange
    var resolvedDefinition: SymbolID?
}

struct CitationKeyDefinition: Identifiable, Equatable, Sendable {
    var id: SymbolID
    var key: String
    var entryType: String
    var fileURL: URL
    var range: SourceRange
    var title: String?
    var author: String?
    var year: String?
}

struct CitationUse: Identifiable, Equatable, Sendable {
    var id: SymbolID
    var command: String
    var keys: [String]
    var fileURL: URL
    var range: SourceRange
    var resolvedDefinitions: [String: SymbolID]
}

struct TodoItem: Identifiable, Equatable, Sendable {
    var id: SymbolID
    var text: String
    var kind: TodoKind
    var fileURL: URL
    var range: SourceRange
}

enum TodoKind: Sendable {
    case todo
    case fixme
    case note
    case custom(String)
}

struct SourceRange: Hashable, Sendable {
    var start: SourceLocation
    var end: SourceLocation
}

struct SourceLocation: Hashable, Sendable {
    var line: Int
    var column: Int
    var utf8Offset: Int
}

struct SymbolID: Hashable, Codable, Sendable {
    var rawValue: String
}
```

## 파일 그래프 탐색 알고리즘

### 1. 루트 `.tex` 탐지

루트 후보는 프로젝트 루트 이하의 `.tex` 파일에서 찾는다. 사용자가 명시한 main file이 있으면 최우선으로 사용하고, 없으면 점수 기반으로 추정한다.

점수 규칙:

- `\documentclass` 포함: +50
- `\begin{document}` 포함: +40
- `\end{document}` 포함: +20
- 파일명이 `main.tex`, `paper.tex`, `thesis.tex`, `dissertation.tex`, `article.tex`, `manuscript.tex`: +15
- 다른 `.tex` 파일에서 `\input`/`\include`로 참조되지 않음: +20
- `.latexmkrc`, `.texpadtmp`, `.fls`, `.synctex` 등 빌드 산출물에서 main으로 확인됨: +30
- `\documentclass` 없이 section만 있는 fragment: -40
- `standalone` class는 낮은 우선순위 또는 별도 root 후보: -10

탐지 결과:

- 명시 root가 있으면 `confidence = .explicit`
- 점수 80 이상이면 high
- 50 이상이면 medium
- 여러 high 후보가 있으면 multi-root 프로젝트로 취급
- 후보가 없으면 최상위 `.tex` 중 가장 많이 참조되는 파일 또는 최근 열린 파일을 low confidence root로 둔다

### 2. dependency 명령 파싱

`.tex` 파일에서 다음 명령을 dependency로 추출한다.

- `\input{path}`
- `\include{path}`
- `\subfile{path}`
- `\includeonly{a,b,c}`
- `\bibliography{refs,moreRefs}`
- `\addbibresource[options]{refs.bib}`
- `\usepackage{pkg}`와 `\documentclass{cls}`는 로컬 `.sty`, `.cls`가 있을 때만 그래프에 연결

경로 해석 규칙:

1. LaTeX 주석 제거 후 명령 인자를 읽는다.
2. `\input`/`\include`/`\subfile`의 확장자가 없으면 `.tex`를 우선 붙인다.
3. `\bibliography` 항목의 확장자가 없으면 `.bib`를 붙인다.
4. `\addbibresource`는 명시 확장자를 존중하되 없으면 `.bib` 후보도 확인한다.
5. 상대 경로는 현재 파일의 디렉터리 기준으로 해석한다.
6. 없으면 프로젝트 루트 기준 후보도 확인한다.
7. `TEXINPUTS` 같은 외부 검색 경로는 설정으로 주입 가능하게 둔다.
8. 발견 실패 시 `MissingFileReference`로 보존해 UI와 diagnostic에 표시한다.

### 3. 그래프 구축

1. 루트 후보를 queue에 넣는다.
2. queue에서 `.tex`를 하나 꺼내 파싱한다.
3. dependency edge를 만든다.
4. 참조된 `.tex`/`.bib`/로컬 `.sty`/`.cls`가 있으면 queue에 추가한다.
5. 방문 집합으로 순환 include를 방지한다.
6. `\includeonly`가 있으면 "빌드 활성 여부" metadata로만 표시하고, 인덱싱은 기본적으로 모든 include 파일을 계속 읽는다. 그래야 검색/자동완성이 누락되지 않는다.
7. 루트에서 도달 불가능한 `.tex`는 orphan file로 별도 보관한다. 열린 파일이면 임시 root처럼 파싱한다.

그래프는 방향성을 유지한다.

- `from main.tex -> to sections/intro.tex`
- reverse edge는 변경 파일의 영향 범위를 찾는 데 사용한다.

## label/ref/cite/BibTeX/BibLaTeX 추출 알고리즘

### 1. LaTeX 토큰화 기본 방침

정규식 하나로 끝내지 말고, 경량 scanner를 둔다.

필요한 최소 토큰:

- command: `\label`, `\ref`, `\citep` 등
- mandatory group: `{...}`
- optional group: `[...]`
- comment: `%...`
- escaped percent: `\%`
- whitespace/newline

주석 처리 규칙:

- `%`는 escape되지 않았을 때 줄 끝까지 comment
- comment 내부에서도 TODO/FIXME는 추출
- command 추출은 comment 바깥에서만 수행

### 2. label 정의

대상 명령:

- `\label{key}`

처리:

- key는 trim하되 내부 공백은 보존하거나 diagnostic으로 경고
- 같은 key가 여러 번 정의되면 duplicate diagnostic 생성
- nearest outline node를 연결해 사이드바에서 "sec:intro · Introduction"처럼 표시 가능하게 한다

### 3. reference 사용

대상 명령:

- `\ref{key}`
- `\pageref{key}`
- `\autoref{key}`
- `\nameref{key}`
- `\eqref{key}`
- `\cref{a,b}`
- `\Cref{a,b}`
- `\vref{key}`

처리:

- 인자가 comma-separated key list일 수 있으므로 brace depth 0의 comma 기준으로 분리
- 각 key를 `labels` map과 resolve
- 없는 key는 unresolved reference diagnostic

### 4. citation 사용

대상 명령:

- BibTeX 기본: `\cite`, `\nocite`
- natbib: `\citet`, `\citep`, `\citealt`, `\citealp`, `\citeauthor`, `\citeyear`, star variant 포함
- biblatex: `\parencite`, `\textcite`, `\autocite`, `\footcite`, `\fullcite`, `\supercite`, `\smartcite`, `\citeyear`, `\citeauthor`
- cleveref가 citation은 아니므로 ref 계열과 분리

명령 파싱:

- star variant: `\citep*{key}`는 command를 `citep*`로 보관
- optional group이 여러 개 올 수 있음: `\citep[see][12]{key}`
- 마지막 mandatory group을 citation key list로 해석
- `\nocite{*}`는 전체 bibliography 표시 의도로 보관하되 unresolved 경고에서 제외

key 분리:

- `\cite{knuth1984,lamport1994}` -> `["knuth1984", "lamport1994"]`
- trim whitespace
- 빈 key는 diagnostic

### 5. BibTeX/BibLaTeX key 정의

`.bib` 파서는 entry 시작부만 안정적으로 읽으면 1차 인덱싱에 충분하다.

대상 패턴:

- `@article{key, ...}`
- `@book{key, ...}`
- `@online{key, ...}`
- `@string`, `@preamble`, `@comment`는 citation key 정의에서 제외

처리:

1. comment와 string literal을 고려하는 scanner로 `@`를 찾는다.
2. entry type을 읽는다.
3. 다음 `{` 또는 `(` 이후 첫 comma 전까지를 key로 읽는다.
4. brace depth를 추적해 entry range를 계산한다.
5. title/author/year/date 정도만 얕게 추출해 sidebar subtitle에 사용한다.
6. 중복 key는 duplicate citation diagnostic.

BibLaTeX는 `date = {2024-03}`처럼 `year`가 없을 수 있으므로 `year`가 없으면 `date`의 앞 4자리를 표시용 year로 쓴다.

## outline 추출 알고리즘

대상 명령:

- `\part`
- `\chapter`
- `\section`
- `\subsection`
- `\subsubsection`
- `\paragraph`
- `\subparagraph`

지원 형태:

- `\section{Title}`
- `\section*{Title}`
- `\section[Short Title]{Long Title}`
- `\section[Short]{Long \texorpdfstring{A}{B}}`

처리 순서:

1. comment 바깥의 section command를 찾는다.
2. star variant를 읽는다.
3. optional short title이 있으면 sidebar title은 short title을 우선 사용한다.
4. mandatory title을 읽고 LaTeX command를 display text로 정리한다.
5. level stack으로 계층을 구성한다.
6. 여러 파일의 outline은 root traversal 순서에 따라 merge한다.

계층 구성:

- 새 node의 level보다 같거나 깊은 stack top을 pop한다.
- 남은 stack top의 children에 새 node를 추가한다.
- stack이 비면 top-level outline에 추가한다.
- chapter가 없는 article class에서도 section을 top-level로 둔다.

제목 display 정리:

- `\emph{A}` -> `A`
- `~` -> space
- escaped chars `\%`, `\_`, `\&` -> `%`, `_`, `&`
- 알 수 없는 command는 command명 제거 후 group text를 보존
- 수식은 원문을 짧게 보존하거나 `…`로 축약

## TODO 추출

대상:

- LaTeX comment: `% TODO: rewrite intro`
- command: `\todo{...}`, `\TODO{...}`, `\fixme{...}`, `\note{...}`
- 패키지별 확장: `\missingfigure{...}`는 warning성 TODO로 취급 가능

규칙:

- comment TODO는 comment 내부에서만 찾는다.
- command TODO는 comment 바깥에서 찾는다.
- 종류는 `TODO`, `FIXME`, `NOTE`, custom으로 분류한다.
- 사이드바 정렬은 file graph traversal order, line number 순.

## 증분 인덱싱 전략

### 캐시 단위

파일 단위로 parse result를 캐시한다.

```swift
struct FileIndexCacheEntry: Sendable {
    var url: URL
    var contentHash: String
    var modifiedAt: Date
    var parseResult: FileParseResult
}
```

`modifiedAt`만으로는 iCloud/외부 sync에서 놓칠 수 있으므로 content hash를 같이 둔다. 큰 파일은 빠른 non-cryptographic hash를 사용해도 된다.

### 변경 처리

파일 이벤트 종류:

- created
- modified
- deleted
- renamed
- project settings changed

처리 절차:

1. file watcher가 이벤트를 debounce한다.
2. 변경 파일의 hash를 확인한다.
3. hash가 같으면 무시한다.
4. 변경 파일을 재파싱한다.
5. dependency 목록이 바뀌면 그래프를 재계산한다.
6. reverse graph로 해당 파일을 참조하는 ancestors를 찾는다.
7. labels/citations resolve 단계는 전역 map이 필요하므로 affected closure에 대해 다시 수행한다.
8. 최종 `ProjectIndex` snapshot을 main actor에 publish한다.

### 영향 범위

- `.tex` 내용 변경: 해당 파일 parse + 전역 resolve
- `.tex` dependency 변경: 해당 파일 parse + 그래프 discovery 재실행
- `.bib` 변경: 해당 bib parse + citation resolve 재실행
- root 후보 변경: root discovery + graph discovery 전체 재실행
- 파일 삭제: graph edge 제거 + missing reference diagnostic 생성

### 동시성

- `ProjectIndexer`는 `actor`로 둔다.
- UI publish는 `@MainActor` view model에서 받는다.
- 현재 indexing task가 도는 중 새 이벤트가 오면 이전 task를 cancel하고 최신 이벤트 batch로 다시 시작한다.
- 파싱은 파일 단위 병렬 가능하지만, 최종 graph merge는 deterministic order를 유지한다.

### 성능 목표

- 100개 `.tex`, 20개 `.bib`, 총 5MB 프로젝트: 초기 인덱싱 500ms-2s 목표
- 타이핑 중 열린 파일 재파싱: 50-150ms 목표
- sidebar publish debounce: 150-300ms

## Swift 코드 스켈레톤

아래 코드는 실제 구현의 뼈대다. 핵심은 scanner, parser, graph discovery, index actor를 분리하는 것이다.

```swift
import Foundation

actor ProjectIndexer {
    private let fileSystem: ProjectFileSystem
    private let rootDetector: TexRootDetector
    private let texParser: TexFileParser
    private let bibParser: BibFileParser
    private var cache: [URL: FileIndexCacheEntry] = [:]
    private var version = 0

    init(
        fileSystem: ProjectFileSystem,
        rootDetector: TexRootDetector = TexRootDetector(),
        texParser: TexFileParser = TexFileParser(),
        bibParser: BibFileParser = BibFileParser()
    ) {
        self.fileSystem = fileSystem
        self.rootDetector = rootDetector
        self.texParser = texParser
        self.bibParser = bibParser
    }

    func buildInitialIndex(projectRoot: URL, explicitRoot: URL? = nil) async throws -> ProjectIndex {
        let texFiles = try fileSystem.findFiles(root: projectRoot, extensions: ["tex"])
        let roots = try await rootDetector.detectRoots(
            projectRoot: projectRoot,
            texFiles: texFiles,
            explicitRoot: explicitRoot,
            fileSystem: fileSystem
        )

        let discovery = try await FileGraphDiscoverer(
            fileSystem: fileSystem,
            texParser: texParser,
            bibParser: bibParser,
            cache: cache
        ).discover(projectRoot: projectRoot, roots: roots.map(\.url))

        cache.merge(discovery.cacheUpdates) { _, new in new }
        version += 1

        return ProjectIndexBuilder().build(
            projectRoot: projectRoot,
            roots: roots,
            parsedFiles: discovery.parsedFiles,
            graph: discovery.graph,
            version: version
        )
    }

    func updateIndex(
        current index: ProjectIndex,
        events: [ProjectFileEvent]
    ) async throws -> ProjectIndex {
        let changedURLs = Set(events.map(\.url))
        let needsRootRediscovery = events.contains { event in
            event.url.pathExtension == "tex" && (event.kind == .created || event.kind == .deleted || event.kind == .renamed)
        }

        if needsRootRediscovery {
            return try await buildInitialIndex(projectRoot: index.projectRoot, explicitRoot: index.rootDocuments.first?.url)
        }

        var parsedFiles = index.files
        var graph = index.graph

        for url in changedURLs {
            guard try fileSystem.exists(url) else {
                parsedFiles.removeValue(forKey: url)
                cache.removeValue(forKey: url)
                continue
            }

            let entry = try await parseWithCache(url: url)
            parsedFiles[url] = IndexedFile(
                url: url,
                kind: IndexedFileKind.fromPathExtension(url.pathExtension),
                contentHash: entry.contentHash,
                modifiedAt: entry.modifiedAt,
                parseResult: entry.parseResult
            )
        }

        if changedURLs.contains(where: { parsedFiles[$0]?.kind == .tex }) {
            graph = FileGraphRebuilder().rebuild(from: parsedFiles, roots: index.graph.roots)
        }

        version += 1

        return ProjectIndexBuilder().build(
            projectRoot: index.projectRoot,
            roots: index.rootDocuments,
            parsedFiles: parsedFiles,
            graph: graph,
            version: version
        )
    }

    private func parseWithCache(url: URL) async throws -> FileIndexCacheEntry {
        let metadata = try fileSystem.metadata(url)
        let hash = try fileSystem.contentHash(url)

        if let cached = cache[url], cached.contentHash == hash {
            return cached
        }

        let text = try fileSystem.readText(url)
        let kind = IndexedFileKind.fromPathExtension(url.pathExtension)
        let parseResult: FileParseResult

        switch kind {
        case .tex, .sty, .cls:
            parseResult = texParser.parse(text: text, fileURL: url)
        case .bib:
            parseResult = bibParser.parse(text: text, fileURL: url)
        case .unknown:
            parseResult = FileParseResult.empty
        }

        let entry = FileIndexCacheEntry(
            url: url,
            contentHash: hash,
            modifiedAt: metadata.modifiedAt,
            parseResult: parseResult
        )
        cache[url] = entry
        return entry
    }
}
```

```swift
struct TexRootDetector {
    func detectRoots(
        projectRoot: URL,
        texFiles: [URL],
        explicitRoot: URL?,
        fileSystem: ProjectFileSystem
    ) async throws -> [TexRootDocument] {
        if let explicitRoot {
            return [TexRootDocument(url: explicitRoot, confidence: .explicit, reason: "User selected main document")]
        }

        var referenced = Set<URL>()
        var candidates: [(url: URL, score: Int, reasons: [String])] = []

        for url in texFiles {
            let text = try fileSystem.readTextPrefix(url, maxBytes: 128 * 1024)
            let commands = TexDependencyScanner().scan(text: text, fileURL: url)
            referenced.formUnion(commands.compactMap { $0.resolvedURL })

            var score = 0
            var reasons: [String] = []

            if text.contains("\\documentclass") {
                score += 50
                reasons.append("contains \\documentclass")
            }
            if text.contains("\\begin{document}") {
                score += 40
                reasons.append("contains document environment")
            }
            if text.contains("\\end{document}") {
                score += 20
            }
            if Self.preferredRootNames.contains(url.lastPathComponent.lowercased()) {
                score += 15
                reasons.append("preferred root filename")
            }

            candidates.append((url, score, reasons))
        }

        candidates = candidates.map { candidate in
            var copy = candidate
            if !referenced.contains(candidate.url) {
                copy.score += 20
                copy.reasons.append("not referenced by another tex file")
            }
            return copy
        }

        let selected = candidates
            .filter { $0.score >= 50 }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.url.path < rhs.url.path
                }
                return lhs.score > rhs.score
            }

        return selected.prefix(3).map { candidate in
            TexRootDocument(
                url: candidate.url,
                confidence: confidence(for: candidate.score),
                reason: candidate.reasons.joined(separator: ", ")
            )
        }
    }

    private static let preferredRootNames: Set<String> = [
        "main.tex",
        "paper.tex",
        "article.tex",
        "thesis.tex",
        "dissertation.tex",
        "manuscript.tex"
    ]

    private func confidence(for score: Int) -> RootConfidence {
        if score >= 80 { return .high }
        if score >= 50 { return .medium }
        return .low
    }
}
```

```swift
struct TexFileParser {
    func parse(text: String, fileURL: URL) -> FileParseResult {
        let scanner = LatexScanner(text: text)
        let commands = scanner.commandsIgnoringComments()
        let comments = scanner.comments()

        let dependencies = TexDependencyParser().parse(commands: commands, fileURL: fileURL)
        let outline = OutlineExtractor().extract(commands: commands, fileURL: fileURL)
        let labels = LabelExtractor().extract(commands: commands, outline: outline, fileURL: fileURL)
        let references = ReferenceExtractor().extract(commands: commands, fileURL: fileURL)
        let citations = CitationUseExtractor().extract(commands: commands, fileURL: fileURL)
        let todos = TodoExtractor().extract(commands: commands, comments: comments, fileURL: fileURL)

        return FileParseResult(
            dependencies: dependencies,
            outline: outline,
            labels: labels,
            references: references,
            citationUses: citations,
            citationDefinitions: [],
            todos: todos,
            diagnostics: []
        )
    }
}

struct LabelExtractor {
    func extract(commands: [LatexCommand], outline: [OutlineNode], fileURL: URL) -> [LabelDefinition] {
        commands.compactMap { command in
            guard command.name == "label", let key = command.firstMandatoryArgument else {
                return nil
            }

            return LabelDefinition(
                id: SymbolID(rawValue: "\(fileURL.path)#label:\(command.range.start.utf8Offset)"),
                key: key.trimmingCharacters(in: .whitespacesAndNewlines),
                fileURL: fileURL,
                range: command.range,
                nearestOutlineID: nearestOutline(before: command.range.start, in: outline)?.id
            )
        }
    }

    private func nearestOutline(before location: SourceLocation, in nodes: [OutlineNode]) -> OutlineNode? {
        nodes.flattenedDepthFirst()
            .filter { $0.range.start.utf8Offset <= location.utf8Offset }
            .max { $0.range.start.utf8Offset < $1.range.start.utf8Offset }
    }
}

struct ReferenceExtractor {
    private let referenceCommands: Set<String> = [
        "ref", "pageref", "autoref", "nameref", "eqref", "cref", "Cref", "vref"
    ]

    func extract(commands: [LatexCommand], fileURL: URL) -> [ReferenceUse] {
        commands.flatMap { command -> [ReferenceUse] in
            guard referenceCommands.contains(command.name),
                  let rawKeys = command.firstMandatoryArgument else {
                return []
            }

            return splitKeyList(rawKeys).map { key in
                ReferenceUse(
                    id: SymbolID(rawValue: "\(fileURL.path)#ref:\(command.range.start.utf8Offset):\(key)"),
                    command: command.name,
                    key: key,
                    fileURL: fileURL,
                    range: command.range,
                    resolvedDefinition: nil
                )
            }
        }
    }
}

struct CitationUseExtractor {
    func extract(commands: [LatexCommand], fileURL: URL) -> [CitationUse] {
        commands.compactMap { command in
            guard command.name.isCitationCommand,
                  let rawKeys = command.lastMandatoryArgument else {
                return nil
            }

            let keys = splitKeyList(rawKeys)
            return CitationUse(
                id: SymbolID(rawValue: "\(fileURL.path)#cite:\(command.range.start.utf8Offset)"),
                command: command.name,
                keys: keys,
                fileURL: fileURL,
                range: command.range,
                resolvedDefinitions: [:]
            )
        }
    }
}
```

```swift
struct BibFileParser {
    func parse(text: String, fileURL: URL) -> FileParseResult {
        let entries = BibScanner(text: text).entries()

        let definitions = entries.compactMap { entry -> CitationKeyDefinition? in
            guard !["string", "preamble", "comment"].contains(entry.type.lowercased()) else {
                return nil
            }

            return CitationKeyDefinition(
                id: SymbolID(rawValue: "\(fileURL.path)#bib:\(entry.key)"),
                key: entry.key,
                entryType: entry.type,
                fileURL: fileURL,
                range: entry.range,
                title: entry.fields["title"],
                author: entry.fields["author"],
                year: entry.fields["year"] ?? entry.fields["date"]?.prefix(4).map(String.init)
            )
        }

        return FileParseResult(
            dependencies: [],
            outline: [],
            labels: [],
            references: [],
            citationUses: [],
            citationDefinitions: definitions,
            todos: [],
            diagnostics: []
        )
    }
}
```

```swift
struct ProjectIndexBuilder {
    func build(
        projectRoot: URL,
        roots: [TexRootDocument],
        parsedFiles: [URL: IndexedFile],
        graph: FileGraph,
        version: Int
    ) -> ProjectIndex {
        let allParseResults = parsedFiles.values.map(\.parseResult)

        let labelsByKey = Dictionary(grouping: allParseResults.flatMap(\.labels), by: \.key)
        let citationDefinitionsByKey = Dictionary(grouping: allParseResults.flatMap(\.citationDefinitions), by: \.key)

        let resolvedReferences = allParseResults.flatMap(\.references).map { use in
            var copy = use
            copy.resolvedDefinition = labelsByKey[use.key]?.first?.id
            return copy
        }

        let resolvedCitations = allParseResults.flatMap(\.citationUses).map { use in
            var copy = use
            copy.resolvedDefinitions = Dictionary(uniqueKeysWithValues: use.keys.compactMap { key in
                guard let definition = citationDefinitionsByKey[key]?.first else {
                    return nil
                }
                return (key, definition.id)
            })
            return copy
        }

        let diagnostics = DiagnosticBuilder().build(
            labelsByKey: labelsByKey,
            references: resolvedReferences,
            citationDefinitionsByKey: citationDefinitionsByKey,
            citationUses: resolvedCitations,
            graph: graph
        )

        return ProjectIndex(
            projectRoot: projectRoot,
            rootDocuments: roots,
            files: parsedFiles,
            graph: graph,
            outline: mergeOutline(parsedFiles: parsedFiles, graph: graph),
            labels: labelsByKey,
            references: resolvedReferences,
            citationKeys: citationDefinitionsByKey,
            citationUses: resolvedCitations,
            todos: allParseResults.flatMap(\.todos).sortedBySourceOrder(),
            diagnostics: diagnostics,
            builtAt: Date(),
            version: version
        )
    }
}
```

## 구현 우선순위

1. `LatexScanner`와 `BibScanner`를 먼저 만든다. 이후 기능은 scanner 정확도에 의존한다.
2. root detection과 file graph discovery를 붙인다.
3. outline/label/ref/cite/bib key 추출을 파일 단위 parse result로 만든다.
4. `ProjectIndexBuilder`에서 resolve와 diagnostic을 처리한다.
5. 사이드바용 `SidebarIndexModel` adapter를 만든다.
6. file watcher와 debounce 기반 증분 인덱싱을 붙인다.

## 테스트 케이스

필수 fixtures:

- 단일 `main.tex`
- `main.tex` + nested `\input`
- `\includeonly`가 있는 프로젝트
- extension 없는 `\bibliography{refs}`
- `\addbibresource[location=local]{refs.bib}`
- duplicate label
- unresolved ref
- duplicate bib key
- `\citep[see][p. 12]{a,b}`
- `% \label{ignored}` 주석 무시
- `% TODO: revise` 주석 TODO 추출
- `\section[Short]{Long Title}` outline title 선택
- 순환 input: `a.tex -> b.tex -> a.tex`

