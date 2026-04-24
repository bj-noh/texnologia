# Subagent 10: PaperForge 통합 구현 계획

## 1. 계획 목적

이 문서는 PaperForge PRD와 각 하위 설계 산출물을 하나의 실행 가능한 구현 계획으로 통합한다. 목표는 8주 안에 “프로젝트 폴더 열기 -> `.tex` 편집 -> `latexmk` 빌드 -> 오류 위치 이동 -> PDF 확인”의 MVP 핵심 루프를 안정적으로 완성하는 것이다.

기준 문서:

- `docs/paperforge-prd.md`
- `docs/subagent-2-macos-architecture.md`
- `docs/editor-agent-design.md`
- `docs/project-indexing.md`
- `docs/subagent-5-latex-build-system.md`
- `docs/subagent-6-pdf-viewer-synctex.md`
- `docs/subagent-7-ux-workflow.md`
- `docs/subagent-8-security-sandboxing.md`
- `docs/subagent-9-qa-test.md`

## 2. 통합 구현 원칙

1. MVP는 완전한 LaTeX IDE가 아니라 핵심 작성 루프의 신뢰성을 우선한다.
2. SwiftUI shell + AppKit adapter 구조를 유지한다. 편집기는 `NSTextView`, PDF는 `PDFKit`을 감싼다.
3. 도메인 로직은 UI에서 분리한다. `ProjectIndexer`, `BuildSystem`, `LogParser`, `FileAccess`, `Persistence`는 테스트 가능한 서비스로 구현한다.
4. 외부 명령은 `Process`의 executable URL + argument array로만 실행한다. `/bin/sh -c`는 금지한다.
5. 기본 빌드는 `latexmk`, 기본 보안 옵션은 `-no-shell-escape`, 기본 output/aux 위치는 프로젝트 내부 `.paperforge-build/`로 한다.
6. SyncTeX는 빌드 산출물 생성과 데이터 모델은 MVP에 준비하되, 안정적인 source-to-PDF와 PDF-to-source 탐색은 Beta 범위로 둔다.
7. 테스트 fixture를 구현과 동시에 만든다. 로그 파서, 명령 생성, 인덱서, PDF reload는 golden/fixture 기반 회귀 테스트를 둔다.

## 3. 8-Week Implementation Roadmap

| Week | 목표 | 주요 산출물 | Exit Criteria |
| --- | --- | --- | --- |
| 1 | 앱 기반 구조와 개발 골격 | SwiftUI app shell, dependency container, 기본 window layout, settings/recent project 저장소 skeleton, 테스트 fixture 구조 | 앱이 실행되고 빈 workspace/main window/start flow가 열린다. Unit test target이 동작한다. |
| 2 | 프로젝트 열기와 파일 접근 | `FileAccessService`, bookmark store, open project flow, project tree scan, root `.tex` 탐지 v1 | 사용자가 폴더를 열면 파일 트리와 root file 후보가 표시된다. 권한/경로 오류가 사용자 메시지로 드러난다. |
| 3 | macOS native editor vertical slice | `LaTeXEditorView` `NSTextView` adapter, load/save, dirty state, line numbers v1, tokenizer/highlighter v1 | `.tex` 파일을 열고 편집/저장할 수 있다. 기본 LaTeX highlighting과 line number가 보인다. |
| 4 | 빌드 파이프라인 | TeX toolchain detection, `BuildConfiguration`, command generation, `ProcessRunner`, cancellation, `.paperforge-build/` 생성 | `001-basic-article` fixture가 `latexmk`로 빌드되고 PDF/log/synctex 산출물이 생성된다. |
| 5 | 로그 파싱과 이슈 패널 | `BuildLogParser`, `BuildIssue`, issue grouping v1, issue panel UI, issue click -> editor jump | `007-invalid-syntax`의 대표 오류가 파일/라인과 함께 표시되고 클릭하면 해당 줄로 이동한다. |
| 6 | PDF viewer와 빌드 결과 연결 | `PDFKitView`, data-based PDF reload, page/zoom 유지, build success reload, stale PDF 표시 | 빌드 성공 후 PDF가 자동 갱신되고, 실패 시 마지막 성공 PDF와 실패 상태가 유지된다. |
| 7 | 프로젝트 인덱싱과 자동완성 | multi-file graph v1, outline/label/citation 추출, `.bib` key parser, citation/reference autocomplete v1 | `002-multifile`, `003-bibtex` fixture에서 outline과 citation key 후보가 동작한다. |
| 8 | 안정화, QA, MVP cut | Preferences MVP, recent project restore, path edge cases, smoke fixtures, performance baseline, release checklist | 대표 fixture 5종 이상에서 open/edit/build/issue/PDF 루프가 통과한다. MVP DoD를 충족한다. |

## 4. Sprint-by-Sprint Task List

### Sprint 1: Foundation and App Shell (Week 1)

목표: 이후 기능을 얹을 수 있는 앱/테스트/의존성 구조를 만든다.

- Xcode project 또는 Swift package 구조 정리
- `PaperForgeApp`, `AppModel`, `DependencyContainer` 생성
- `Core/Models`: `Workspace`, `WorkspaceID`, `TextLocation`, `SourceRange`, `BuildIssue`, `PaperForgeError`
- `Infrastructure/Persistence`: `SettingsStore`, `RecentProjectsStore`, `CacheStore` skeleton
- SwiftUI `MainWindowView` 3-pane layout skeleton
- `ProjectSidebarView`, `EditorView`, `PDFPaneView`, `IssueNavigatorView`, `BuildToolbarView` placeholder
- 테스트 target 생성: `CoreTests`, `ProjectIndexerTests`, `BuildSystemTests`
- fixture 폴더 구조 생성: `Tests/Fixtures/LaTeXProjects`

검증:

- 앱 launch smoke
- settings load/save unit test
- `Workspace` Codable/Hashable test

### Sprint 2: File Access and Project Open (Week 2)

목표: 사용자가 프로젝트 폴더를 열고 root `.tex` 후보를 볼 수 있게 한다.

- `FileAccessService` protocol과 direct build용 구현
- sandbox-compatible `SecurityScopeManager` interface
- `BookmarkStore` 구현 및 stale/permission error 모델링
- `OpenPanelClient` AppKit adapter
- project open command와 recent project update
- root `.tex` 탐지 v1
  - `\documentclass`
  - `\begin{document}`
  - 파일명 점수
  - 다른 `.tex`에서 참조 여부
- 파일 트리 scan과 ignored/build artifact filtering
- missing/moved project recovery UI skeleton

검증:

- `001-basic-article` root detection
- 공백/한글 경로 open smoke
- 없는 최근 프로젝트를 열 때 missing badge 또는 repair action 표시

### Sprint 3: Editor Vertical Slice (Week 3)

목표: PaperForge의 중심 편집면을 만든다.

- `LaTeXEditorView` + `NSViewRepresentable`
- `EditorTextView` `NSTextView` subclass
- `TextBuffer`, `EditorViewModel`, `DocumentStore`
- load/save/dirty state/tab title indicator
- `LaTeXTokenizer` v1
- `SyntaxHighlighter` v1
- line number ruler v1
- basic bracket matching
- built-in command autocomplete v0
- save event -> pending build notification hook

검증:

- 긴 `.tex` fixture를 열어 typing latency smoke
- tokenizer unit tests: command/comment/math/braces
- save 후 파일 내용 유지
- IME/한글 입력 수동 smoke

### Sprint 4: Build System (Week 4)

목표: 실제 LaTeX 프로젝트를 안전한 기본값으로 빌드한다.

- TeX binary discovery
  - `/Library/TeX/texbin`
  - `/opt/homebrew/bin`
  - `/usr/local/bin`
  - resolved absolute path 저장
- `BuildConfiguration`, `LatexEngine`, `LatexBuildTool`, `ShellEscapePolicy`
- `BuildCommandGenerator`
- `ExternalCommand`/`ProcessRunner` 구현
- stdout/stderr async capture
- cancellation과 timeout v1
- `.paperforge-build/.paperforge-owned` marker 생성
- cleanup은 marker가 있는 build directory 내부만 허용
- build toolbar state: idle/building/success/failed/missing toolchain
- build result model: PDF/log/synctex/artifact paths

검증:

- command generation unit tests
- `-no-shell-escape`, `-file-line-error`, `-synctex=1`, `-outdir`, `-auxdir` 포함 확인
- `001-basic-article` integration build
- missing `latexmk` fake runner test

### Sprint 5: Log Parser and Issue Workflow (Week 5)

목표: 빌드 실패를 사용자가 고칠 수 있는 이슈 목록으로 바꾼다.

- `BuildLogParser` v1
  - file-line-error 형식
  - undefined control sequence
  - missing file
  - missing `$`
  - runaway argument
  - environment mismatch
  - undefined citation/reference warning
  - overfull/underfull warning 분류
- `BuildIssue` grouping과 raw log excerpt
- `IssueNavigatorViewModel`
- issue panel filters: Errors, Warnings, Logs
- build failure 시 issue panel auto-open
- first error auto-select
- issue click -> editor tab open -> line jump
- gutter issue marker v1

검증:

- `007-invalid-syntax` golden log tests
- included file line mapping smoke
- 경로를 찾지 못하면 root file + raw log fallback

### Sprint 6: PDF Viewer and Artifact Sync (Week 6)

목표: 빌드 성공 후 PDF 확인 루프를 완성한다.

- `PDFViewerModel`, `PDFViewerState`
- `PDFKitView` `NSViewRepresentable`
- data-based PDF loading
- reload retry/backoff
- page/zoom/visible rect capture and restore
- PDF toolbar: page, zoom in/out, fit width, search placeholder
- build success -> PDF reload
- build failure -> last successful PDF 유지 + stale badge
- issue/source/PDF artifact를 연결하는 `PDFSyncCoordinator` skeleton
- SyncTeX 파일 존재 여부와 disabled state 표시

검증:

- `001-basic-article` PDF reload
- rebuild 후 page/zoom 유지
- corrupt/incomplete PDF read failure가 앱 crash로 이어지지 않음
- dark mode viewer chrome smoke

### Sprint 7: Indexing, Outline, Citation Completion (Week 7)

목표: 논문 프로젝트 구조를 이해하고 자동완성 기반을 제공한다.

- `ProjectIndexer` actor 또는 background service
- immutable `ProjectIndex` snapshot
- file graph v1: `\input`, `\include`, `\subfile`, `\bibliography`, `\addbibresource`
- outline extractor: part/chapter/section/subsection 계층
- label/ref/cite extractor
- `.bib` parser v1
- `SidebarIndexModel`
- file watcher + debounced incremental index
- citation key autocomplete provider
- reference/label autocomplete provider v1
- missing file index diagnostic

검증:

- `002-multifile-input-include` graph tests
- `003-bibtex-classic` citation key extraction
- `004-biber-biblatex` addbibresource extraction
- 저장 후 증분 인덱싱 smoke

### Sprint 8: MVP Hardening and QA Cut (Week 8)

목표: 기능을 넓히기보다 MVP 루프를 끊기지 않게 다듬는다.

- Preferences MVP
  - General
  - Editor
  - Build
  - PDF
  - Issues
- recent project restore
- last root file, layout, opened tabs, build profile persistence
- toolchain missing/changed diagnostics
- `.latexmkrc` 발견 경고
- shell escape opt-in은 hidden advanced 또는 disabled state로만 노출
- path edge case fixes: space, Korean, iCloud Drive smoke
- performance baseline:
  - initial indexing
  - save-to-build
  - PDF reload
  - typing latency
- fixture smoke automation
- MVP release notes and known limitations

검증:

- 대표 fixture 5종 이상 통과
  - `001-basic-article`
  - `002-multifile-input-include`
  - `003-bibtex-classic`
  - `007-invalid-syntax`
  - `012-path-edge-cases`
- 앱 재시작 후 recent project/root/layout 복원
- direct distribution profile smoke
- sandbox-compatible build target compile smoke

## 5. First Vertical Slice Plan

첫 vertical slice는 2주 내에 “샘플 프로젝트를 열고, 한 파일을 편집하고, 저장 후 빌드 버튼으로 PDF가 생성되는 것”까지 관통한다. 이 단계에서는 문법 강조, 고급 로그 파싱, PDFKit 내장 뷰어를 완성하지 않는다. 대신 서비스 경계와 실제 외부 프로세스 실행을 빨리 검증한다.

### Slice Scope

포함:

- 앱 실행과 main window
- Open Project
- root `.tex` 후보 탐지
- 파일 트리에서 `main.tex` 열기
- plain `NSTextView` 기반 편집/저장
- TeX toolchain detection
- `latexmk -pdf -interaction=nonstopmode -file-line-error -synctex=1 -no-shell-escape`
- `.paperforge-build/` output
- build status 표시
- PDF 파일 경로 reveal 또는 placeholder viewer에 “PDF generated” 상태 표시

제외:

- full syntax highlighting
- autocomplete
- full issue panel
- PDFKit page/zoom 유지
- SyncTeX navigation
- bibliography special handling
- Quick Fix

### Slice Task Order

1. `Workspace`, `DependencyContainer`, `MainWindowView` 생성
2. `FileAccessService` direct 구현과 `OpenPanelClient`
3. root `.tex` 탐지 최소 구현
4. `EditorViewModel` load/save
5. plain `NSTextView` adapter 연결
6. `BuildConfiguration.default(rootFile:)`
7. TeX binary discovery 최소 구현
8. `BuildCommandGenerator` unit test
9. `ProcessRunner`로 실제 `latexmk` 실행
10. build status와 generated PDF path 표시
11. `001-basic-article` fixture 추가
12. smoke test 문서화

### Slice Success Criteria

- 새 사용자가 `001-basic-article` 폴더를 열 수 있다.
- `main.tex`를 편집하고 저장할 수 있다.
- Build 버튼을 누르면 `.paperforge-build/main.pdf`가 생성된다.
- 실패 시 최소한 exit code와 raw log path가 보인다.
- 모든 외부 명령은 shell 없이 absolute executable + argument array로 실행된다.

## 6. Concrete Coding Checklist

### Core and Architecture

- [ ] `Core/Models/Workspace.swift`
- [ ] `Core/Models/TextLocation.swift`
- [ ] `Core/Models/SourceRange.swift`
- [ ] `Core/Models/BuildIssue.swift`
- [ ] `Core/Models/PaperForgeError.swift`
- [ ] `App/AppModel.swift`
- [ ] `App/DependencyContainer.swift`
- [ ] `App/MainWindowView.swift`
- [ ] `Core/Utilities/AsyncDebouncer.swift`
- [ ] `Core/Utilities/FilePath.swift`
- [ ] `Core/Utilities/Logger.swift`

### Persistence and File Access

- [ ] `Infrastructure/Persistence/SettingsStore.swift`
- [ ] `Infrastructure/Persistence/RecentProjectsStore.swift`
- [ ] `Infrastructure/Persistence/BookmarkStore.swift`
- [ ] `Infrastructure/Persistence/CacheStore.swift`
- [ ] `Infrastructure/FileAccess/FileAccessService.swift`
- [ ] `Infrastructure/FileAccess/SecurityScopeManager.swift`
- [ ] `Infrastructure/FileAccess/OpenPanelClient.swift`
- [ ] bookmark stale/permission denied error types
- [ ] recent project restore metadata

### Editor

- [ ] `Features/Editor/EditorView.swift`
- [ ] `Features/Editor/EditorViewModel.swift`
- [ ] `Features/Editor/TextBuffer.swift`
- [ ] `Features/Editor/DocumentStore.swift`
- [ ] `Infrastructure/AppKitAdapters/MacTextView.swift`
- [ ] `Features/Editor/Syntax/LaTeXTokenizer.swift`
- [ ] `Features/Editor/Syntax/SyntaxHighlighter.swift`
- [ ] `Features/Editor/LineNumberRulerView.swift`
- [ ] `Features/Editor/BracketMatcher.swift`
- [ ] `Features/Editor/Autocomplete/AutocompleteProvider.swift`
- [ ] built-in LaTeX command provider
- [ ] citation/reference provider hooks

### Project Indexing

- [ ] `Features/ProjectIndexer/ProjectIndexer.swift`
- [ ] `Features/ProjectIndexer/ProjectIndex.swift`
- [ ] `Features/ProjectIndexer/ProjectIndexerViewModel.swift`
- [ ] `Features/ProjectIndexer/RootDocumentDetector.swift`
- [ ] `Features/ProjectIndexer/LatexDependencyParser.swift`
- [ ] `Features/ProjectIndexer/BibParser.swift`
- [ ] `Features/ProjectIndexer/FileWatcher.swift`
- [ ] immutable snapshot versioning
- [ ] debounced incremental reindex
- [ ] missing file diagnostics

### Build System

- [ ] `Features/BuildSystem/BuildConfiguration.swift`
- [ ] `Features/BuildSystem/BuildRecipes.swift`
- [ ] `Features/BuildSystem/BuildCommandGenerator.swift`
- [ ] `Features/BuildSystem/ToolchainDetector.swift`
- [ ] `Features/BuildSystem/ProcessRunner.swift`
- [ ] `Features/BuildSystem/BuildService.swift`
- [ ] `Features/BuildSystem/BuildCoordinator.swift`
- [ ] `Features/BuildSystem/BuildResult.swift`
- [ ] `Features/BuildSystem/BuildLogParser.swift`
- [ ] cancellation and process group strategy
- [ ] `.paperforge-build/.paperforge-owned`
- [ ] safe cleanup guard

### Issue Navigator

- [ ] `Features/IssueNavigator/IssueNavigatorView.swift`
- [ ] `Features/IssueNavigator/IssueNavigatorViewModel.swift`
- [ ] `Features/IssueNavigator/IssueFilter.swift`
- [ ] issue grouping
- [ ] raw log excerpt view
- [ ] issue click jump routing
- [ ] gutter marker integration

### PDF Viewer

- [ ] `Features/PDFViewer/PDFPaneView.swift`
- [ ] `Features/PDFViewer/PDFViewerViewModel.swift`
- [ ] `Features/PDFViewer/PDFViewerState.swift`
- [ ] `Features/PDFViewer/PDFDocumentController.swift`
- [ ] `Features/PDFViewer/PDFSyncCoordinator.swift`
- [ ] `Infrastructure/AppKitAdapters/MacPDFView.swift`
- [ ] data-based reload
- [ ] page/zoom/scroll state preservation
- [ ] stale PDF badge
- [ ] SyncTeX availability state

### UX and Preferences

- [ ] toolbar build state
- [ ] sidebar segmented views: Files, Outline
- [ ] source/PDF split layout
- [ ] issue panel collapse/open behavior
- [ ] start window or empty project state
- [ ] `Features/Preferences/PreferencesView.swift`
- [ ] `Features/Preferences/PreferencesViewModel.swift`
- [ ] General/Editor/Build/PDF/Issues settings
- [ ] standard shortcuts: open, save, build, preferences, sidebar toggle

### Security

- [ ] no shell command execution assertion in command layer
- [ ] absolute executable path validation
- [ ] PATH excludes project directory
- [ ] `-no-shell-escape` default test
- [ ] `.latexmkrc` detection warning
- [ ] shell escape per-project trust model placeholder
- [ ] output directory canonical path containment check
- [ ] symlink outside root warning
- [ ] external include permission issue model

### QA and Fixtures

- [ ] `001-basic-article`
- [ ] `002-multifile-input-include`
- [ ] `003-bibtex-classic`
- [ ] `004-biber-biblatex`
- [ ] `007-invalid-syntax`
- [ ] `012-path-edge-cases`
- [ ] command generation unit tests
- [ ] tokenizer unit tests
- [ ] indexer graph tests
- [ ] log parser golden tests
- [ ] PDF reload state tests
- [ ] integration smoke script or XCTest plan

## 7. Definition of Done

### Feature-Level DoD

각 기능은 다음 조건을 만족해야 완료로 본다.

- 사용자 시나리오가 main window에서 실제로 실행된다.
- 오류 상태, 빈 상태, 권한 실패 상태가 UI에 표시된다.
- unit test 또는 fixture 기반 integration test가 있다.
- async task cancellation 또는 중복 실행 정책이 정의되어 있다.
- 파일 경로에 공백/한글이 있어도 동작한다.
- 앱 재시작 후 보존되어야 하는 상태는 persistence test가 있다.
- 로그 또는 diagnostic에는 민감한 bookmark data를 남기지 않는다.

### MVP DoD

MVP는 다음 조건을 모두 만족해야 한다.

- 대표 샘플 프로젝트 5종에서 프로젝트 열기, 편집, 저장, 빌드, PDF 확인이 동작한다.
- `latexmk` 기반 빌드가 기본이고, TeX toolchain이 없을 때 복구 가능한 안내를 제공한다.
- `shell-escape`는 기본 비활성이며 command argument에 명시된다.
- 빌드 산출물은 기본적으로 `.paperforge-build/` 아래에 생성된다.
- 주요 오류 20종 이상이 `BuildIssue`로 표시될 수 있는 parser 기반을 갖춘다.
- issue 클릭 시 가능한 경우 정확한 파일/라인으로 이동한다.
- PDF reload는 앱 crash 없이 수행되고 page/zoom을 가능한 보존한다.
- citation key autocomplete가 `.bib` fixture에서 동작한다.
- 최근 프로젝트, root file, build settings, 열린 tab 또는 최소한 마지막 파일이 복원된다.
- macOS dark mode에서 주요 pane이 깨지지 않는다.
- direct distribution profile이 smoke 통과한다.
- sandbox-compatible file access interface와 build target compile smoke가 유지된다.

### Release Candidate DoD

- 모든 P0/P1 MVP 버그가 triage되어 blocker가 없다.
- `001`, `002`, `003`, `007`, `012` fixture가 자동 또는 수동 smoke를 통과한다.
- crash-free exploratory session 2시간 이상.
- BasicTeX 또는 missing package 상태에서 실패 메시지가 이해 가능하다.
- iCloud Drive 경로에서 build directory/reload race에 대한 known issue 또는 완화책이 있다.
- notarization/direct distribution checklist가 작성되어 있다.

## 8. 충돌사항과 통합 결정

### 8.1 Forward Search의 MVP 여부

충돌:

- PRD는 Forward search를 MVP/P1로 둔다.
- PDF/SyncTeX 설계는 source-to-PDF와 PDF-to-source를 Beta로 둔다.
- UX 문서는 MVP에서 source-to-PDF “기본 지원 목표”라고 표현한다.

통합 결정:

- MVP는 SyncTeX 기반 forward search를 필수 완료 기준으로 삼지 않는다.
- MVP에는 `-synctex=1`, `.synctex.gz` artifact tracking, SyncTeX availability UI, `PDFSyncCoordinator` skeleton만 포함한다.
- 실제 source-to-PDF jump는 Week 8 이후 Beta hardening 항목으로 이동한다.
- 단, issue -> source jump는 SyncTeX와 무관하므로 MVP 필수로 유지한다.

이유:

- 핵심 MVP 성공 지표는 빌드 실패 후 문제 위치 도달과 PDF reload다.
- SyncTeX path/coordinate 안정화는 프로젝트 구조별 변수가 커서 8주 MVP 리스크가 높다.

### 8.2 Build Directory 기본 위치

충돌:

- Build 설계는 `.paperforge-build/`를 기본 output/aux 위치로 제안한다.
- Security 설계는 project root 내부 `.paperforge-build/` 또는 app container cache를 모두 언급하며, iCloud Drive에서는 app cache 옵션을 권장한다.

통합 결정:

- 기본값은 `<project-root>/.paperforge-build/`로 한다.
- iCloud Drive 감지 시 “App cache build directory” 추천 옵션을 제공하되 MVP에서는 기본값 변경을 강제하지 않는다.
- cleanup은 `.paperforge-owned` marker가 있는 build directory 내부에서만 허용한다.

### 8.3 `latexmk`와 `.latexmkrc`

충돌:

- LaTeX 호환성 관점에서는 `.latexmkrc`가 중요하다.
- Security 설계는 `.latexmkrc`를 arbitrary command 실행 표면으로 보고 기본 off/경고를 권장한다.

통합 결정:

- MVP는 project root `.latexmkrc` 존재를 감지하고 경고/표시한다.
- MVP 기본 빌드는 PaperForge-generated arguments를 사용한다.
- `.latexmkrc` opt-in은 trusted project 기능으로 Week 8 이후 또는 Beta로 둔다.
- home directory global `.latexmkrc`는 MVP에서 사용하지 않는다.

### 8.4 Direct Distribution vs App Store Sandbox

충돌:

- 제품은 macOS-native 독립 앱이며 App Store 가능성을 열어두어야 한다.
- Security 설계는 초기 상용/Beta 배포는 direct distribution을 권장한다.

통합 결정:

- 8주 MVP는 direct distribution profile을 기본으로 개발한다.
- 모든 파일 접근과 process 실행은 sandbox-compatible protocol 뒤에 둔다.
- CI 또는 local scheme에 sandboxed compile smoke를 유지한다.
- App Store 제출 정책 결정은 MVP 검증 뒤로 미룬다.

### 8.5 Editor Parser 정확도

충돌:

- PRD는 citation/reference/label 자동완성과 프로젝트 구조 탐색을 MVP에 둔다.
- Editor 설계는 lightweight tokenizer의 정확도 한계를 인정한다.
- Project Indexing 설계는 별도 graph/parser를 상세히 제안한다.

통합 결정:

- 편집기 syntax highlighting용 tokenizer와 프로젝트 인덱서 parser를 분리한다.
- MVP 자동완성은 인덱서 snapshot에서 labels/citation keys를 받아 제공한다.
- 편집기 tokenizer는 UI highlighting과 command context 판단에만 사용한다.
- tree-sitter/custom parser 도입은 MVP 이후로 둔다.

### 8.6 BibTeX/Biber 자동 실행 범위

충돌:

- PRD는 참고문헌 기본 지원과 citation key 자동완성을 MVP로 둔다.
- QA fixture는 BibTeX/Biber workflow를 포함한다.
- Build 설계는 direct fallback에서 BibTeX/Biber 자동 실행을 MVP 후속으로 둔다.

통합 결정:

- `latexmk` 경로에서는 BibTeX/Biber pass를 `latexmk`에 위임한다.
- direct engine fallback에서는 bibliography 필요 신호를 issue/warning으로 표시하고 자동 BibTeX/Biber pass는 Beta로 둔다.
- citation key parsing/autocomplete는 MVP 필수로 유지한다.

### 8.7 Quick Fix 범위

충돌:

- PRD v1.0은 Quick Fix를 중요한 차별화로 둔다.
- UX 문서는 MVP Quick Fix를 자동 수정이 아니라 안전한 안내로 제한한다.

통합 결정:

- MVP에는 자동 diff 적용 Quick Fix를 넣지 않는다.
- MVP의 “Quick Fix 영역”은 관련 위치 이동, 후보 key 표시, raw log/context 표시까지로 제한한다.
- 원클릭 소스 수정은 v1.0 범위로 유지한다.

## 9. 주요 리스크와 완화책

| 리스크 | 영향 | 완화책 |
| --- | --- | --- |
| TeX 설치 상태가 다양함 | 첫 빌드 실패 | toolchain detector와 missing toolchain UX를 Week 4에 조기 구현 |
| LaTeX 로그 형식이 다양함 | issue 위치 부정확 | `-file-line-error` 강제, golden log fixture 확장 |
| PDFKit reload race | 빈 화면 또는 crash | data-based loading, retry/backoff, last successful PDF 유지 |
| sandbox/permission 복잡도 | App Store 전환 비용 증가 | `FileAccessService`와 bookmark lifecycle을 Week 2에 먼저 고정 |
| SyncTeX 안정화 지연 | PRD MVP 기대와 차이 | MVP 범위를 artifact tracking으로 명확히 줄이고 Beta 항목으로 분리 |
| 편집기 성능 | typing latency | TextKit 1 incremental highlighting, 대형 파일 성능 baseline |
| iCloud Drive sync | build artifact race | `.paperforge-build/` 기본 + app cache option + stale PDF 표시 |

## 10. Post-MVP / Beta Backlog

- SyncTeX source-to-PDF
- SyncTeX PDF-to-source
- build profile UI: pdfLaTeX/XeLaTeX/LuaLaTeX/BibTeX/Biber presets
- `.latexmkrc` trusted project opt-in
- shell escape advanced opt-in
- richer error explanations and suggested actions
- template start flow
- references sidebar
- editor split
- Git changed files/lines
- Quick Fix diff application
- bibliography manager
- submission checklist

