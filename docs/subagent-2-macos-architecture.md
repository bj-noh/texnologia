# Subagent 2: PaperForge macOS Architecture

## 목표

PaperForge는 SwiftUI를 기본 UI 계층으로 사용하되, 텍스트 편집기와 PDF 뷰어처럼 macOS 네이티브 제어가 중요한 영역은 AppKit을 감싸서 사용하는 LaTeX/PDF 작업 앱이다. TCA 없이도 관리 가능한 구조를 위해 전역 상태를 최소화하고, 기능별 `ViewModel`과 서비스 프로토콜을 조합하는 MVVM-ish 아키텍처를 채택한다.

핵심 원칙은 다음과 같다.

- SwiftUI View는 상태 표시와 사용자 액션 전달에 집중한다.
- ViewModel은 화면 상태, 사용자 액션, async task orchestration을 담당한다.
- 도메인 서비스는 파일, 인덱싱, 빌드, PDF, 설정, 영속성 등 외부 효과를 캡슐화한다.
- AppKit 의존성은 `Representable`, coordinator, adapter 계층으로 격리한다.
- sandboxed/non-sandboxed 파일 접근 차이는 `FileAccessService` 뒤로 숨긴다.

## Architecture Diagram

```text
PaperForgeApp
  |
  v
AppModel / DependencyContainer
  |-- AppSettings
  |-- WorkspaceRegistry
  |-- RecentProjectStore
  |-- Service protocols
  |
  +----------------------------- SwiftUI Shell -----------------------------+
  |                                                                         |
  |  MainWindowView                                                         |
  |    |                                                                    |
  |    |-- ProjectSidebarView        -> ProjectIndexerViewModel             |
  |    |-- EditorSplitView           -> EditorViewModel                     |
  |    |     `-- NSTextView adapter  -> TextEditingController               |
  |    |-- PDFPaneView               -> PDFViewerViewModel                  |
  |    |     `-- PDFKit/AppKit view  -> PDFDocumentController               |
  |    |-- IssueNavigatorView        -> IssueNavigatorViewModel             |
  |    |-- BuildToolbarView          -> BuildViewModel                      |
  |    `-- PreferencesWindow         -> PreferencesViewModel                |
  |                                                                         |
  +------------------------------- Feature Layer ---------------------------+
  |                                                                         |
  |  Editor        Project Indexer       Build System        PDF Viewer     |
  |  Issue Nav     Preferences           Persistence         File Access    |
  |                                                                         |
  +------------------------------- Service Layer ---------------------------+
  |                                                                         |
  |  FileAccessService       BookmarkStore          ProjectIndexer          |
  |  DocumentStore           BuildService           ProcessRunner           |
  |  LogParser               PDFSyncService         SettingsStore           |
  |  RecentProjectsStore     CacheStore             SecurityScopeManager    |
  |                                                                         |
  +---------------------------- OS / External Tools ------------------------+
                                                                           
     File system / security scoped bookmarks / xattr
     latexmk, tectonic, bibtex, biber, makeindex
     PDFKit, AppKit, UniformTypeIdentifiers, Combine, Swift Concurrency
```

## Module Responsibility Table

| Module | 책임 | 주요 타입 | UI 의존성 | 비고 |
| --- | --- | --- | --- | --- |
| AppCore | 앱 전역 모델, dependency composition, shared domain types | `AppModel`, `DependencyContainer`, `WorkspaceID`, `PaperForgeError` | 없음 | 가장 안쪽 shared module |
| Editor | TeX 소스 로딩/저장, dirty state, selection, syntax hooks, editor command | `EditorViewModel`, `TextBuffer`, `TextEditingController`, `EditorCommand` | SwiftUI + AppKit adapter | `NSTextView`를 직접 노출하지 않음 |
| ProjectIndexer | 프로젝트 루트 스캔, TeX graph, asset/bibliography discovery, file watcher | `ProjectIndexer`, `ProjectIndex`, `ProjectNode`, `FileWatcher` | 없음 | build input과 sidebar의 source of truth |
| BuildSystem | LaTeX 빌드 orchestration, process 실행, 로그 파싱, artifact 관리 | `BuildService`, `BuildRequest`, `BuildResult`, `IssueLogParser` | 없음 | actor 기반으로 중복 빌드 취소/직렬화 |
| PDFViewer | PDF 로딩, 페이지 이동, zoom, search, source-PDF sync | `PDFViewerViewModel`, `PDFDocumentController`, `PDFSyncService` | SwiftUI + PDFKit/AppKit adapter | PDFKit wrapper만 AppKit 의존 |
| IssueNavigator | 빌드 이슈 목록, 필터링, 소스 위치 이동 액션 | `IssueNavigatorViewModel`, `BuildIssue`, `IssueFilter` | SwiftUI | BuildSystem의 parsed issue를 소비 |
| Preferences | 앱 설정, toolchain 경로, build recipe, editor prefs | `PreferencesViewModel`, `AppSettings`, `ToolchainSettings` | SwiftUI | 저장은 Persistence에 위임 |
| Persistence | 설정, 최근 프로젝트, bookmarks, caches, window state 저장 | `SettingsStore`, `BookmarkStore`, `RecentProjectsStore`, `CacheStore` | 없음 | `Application Support`/`UserDefaults` 분리 |
| FileAccess | sandboxed/non-sandboxed 파일 접근 추상화 | `FileAccessService`, `SecurityScopeManager`, `FilePermissionGrant` | AppKit open panel adapter만 분리 | App Store 빌드 전환 지점 |
| AppKitAdapters | `NSViewRepresentable`, `NSWindow`, menus, panels bridge | `MacTextView`, `MacPDFView`, `OpenPanelClient`, `MenuCommandRouter` | AppKit | 기능 로직을 갖지 않음 |

## Directory Structure

```text
PaperForge/
  PaperForgeApp.swift
  App/
    AppModel.swift
    DependencyContainer.swift
    MainWindowView.swift
    Commands/
      AppCommands.swift
      MenuCommandRouter.swift
  Core/
    Models/
      Workspace.swift
      TextLocation.swift
      BuildIssue.swift
      PaperForgeError.swift
    Utilities/
      AsyncDebouncer.swift
      FilePath.swift
      Logger.swift
  Features/
    Editor/
      EditorView.swift
      EditorViewModel.swift
      TextBuffer.swift
      TextEditingController.swift
      Syntax/
        LatexSyntaxHighlighter.swift
    ProjectIndexer/
      ProjectSidebarView.swift
      ProjectIndexer.swift
      ProjectIndexerViewModel.swift
      ProjectIndex.swift
      FileWatcher.swift
    BuildSystem/
      BuildViewModel.swift
      BuildService.swift
      BuildRequest.swift
      BuildResult.swift
      ProcessRunner.swift
      LogParser.swift
      BuildRecipes.swift
    PDFViewer/
      PDFPaneView.swift
      PDFViewerViewModel.swift
      PDFDocumentController.swift
      PDFSyncService.swift
    IssueNavigator/
      IssueNavigatorView.swift
      IssueNavigatorViewModel.swift
      IssueFilter.swift
    Preferences/
      PreferencesView.swift
      PreferencesViewModel.swift
      AppSettings.swift
      ToolchainSettings.swift
  Infrastructure/
    FileAccess/
      FileAccessService.swift
      SecurityScopeManager.swift
      OpenPanelClient.swift
    Persistence/
      SettingsStore.swift
      BookmarkStore.swift
      RecentProjectsStore.swift
      CacheStore.swift
    AppKitAdapters/
      MacTextView.swift
      MacPDFView.swift
      WindowAccessor.swift
  Resources/
    Assets.xcassets
    DefaultBuildRecipes.json
  Tests/
    CoreTests/
    ProjectIndexerTests/
    BuildSystemTests/
    PersistenceTests/
```

Swift Package로 분리할 경우 `Core`, `ProjectIndexer`, `BuildSystem`, `Persistence`는 독립 library target으로 두고, `Features`와 `AppKitAdapters`는 app target에 남기는 구성이 가장 단순하다. 초기에는 Xcode group + 폴더 구조로 시작하고, 테스트 경계가 명확해진 뒤 package target을 나누는 편이 좋다.

## Core Swift Types / Interfaces

### App Composition

```swift
@MainActor
final class AppModel: ObservableObject {
    @Published var activeWorkspace: Workspace?
    @Published var settings: AppSettings

    let dependencies: DependencyContainer

    init(dependencies: DependencyContainer) {
        self.dependencies = dependencies
        self.settings = dependencies.settingsStore.load()
    }
}

struct DependencyContainer {
    let fileAccess: FileAccessService
    let bookmarkStore: BookmarkStore
    let settingsStore: SettingsStore
    let recentProjectsStore: RecentProjectsStore
    let projectIndexer: ProjectIndexing
    let buildService: BuildServicing
    let pdfSyncService: PDFSyncServicing
}
```

### Workspace and Paths

```swift
struct Workspace: Identifiable, Hashable, Codable {
    let id: WorkspaceID
    let rootURL: URL
    var mainFileURL: URL?
    var displayName: String
}

struct TextLocation: Hashable, Codable {
    var fileURL: URL
    var line: Int
    var column: Int
}

struct FilePath: Hashable, Codable, Sendable {
    let url: URL
}
```

### File Access

```swift
protocol FileAccessService: Sendable {
    func requestProjectDirectory() async throws -> FilePermissionGrant
    func resolveBookmark(for workspaceID: WorkspaceID) async throws -> FilePermissionGrant?
    func withAccess<T>(
        to grant: FilePermissionGrant,
        operation: @Sendable () async throws -> T
    ) async throws -> T
}

struct FilePermissionGrant: Hashable, Codable, Sendable {
    let workspaceID: WorkspaceID
    let rootURL: URL
    let bookmarkData: Data?
    let isSecurityScoped: Bool
}

actor SecurityScopeManager {
    func startAccessing(_ grant: FilePermissionGrant) throws
    func stopAccessing(_ grant: FilePermissionGrant)
}
```

Sandboxed build에서는 `requestProjectDirectory()`가 `NSOpenPanel`로 폴더 권한을 받고 security-scoped bookmark를 저장한다. Non-sandboxed build에서는 bookmark 없이 URL만 저장할 수 있지만, 같은 인터페이스를 사용해 코드 경로를 유지한다.

### Editor

```swift
@MainActor
final class EditorViewModel: ObservableObject {
    @Published private(set) var buffer: TextBuffer
    @Published private(set) var isDirty = false
    @Published var selection: TextRange?

    private let documentStore: DocumentStoring

    init(buffer: TextBuffer, documentStore: DocumentStoring) {
        self.buffer = buffer
        self.documentStore = documentStore
    }

    func open(_ fileURL: URL) async throws
    func applyEdit(_ edit: TextEdit)
    func save() async throws
    func jump(to location: TextLocation)
}

protocol TextEditingController: AnyObject {
    var onTextChanged: ((String) -> Void)? { get set }
    var onSelectionChanged: ((TextRange) -> Void)? { get set }

    func setText(_ text: String)
    func applyHighlighting(_ spans: [HighlightSpan])
    func scrollTo(location: TextLocation)
}
```

`MacTextView`는 `NSViewRepresentable`로 `NSTextView`를 감싸고, `TextEditingController`를 통해 ViewModel과 통신한다. 대용량 TeX 파일을 고려해 후속 단계에서는 line index, incremental highlighting, undo manager bridge를 별도 타입으로 분리한다.

### Project Indexer

```swift
protocol ProjectIndexing: Sendable {
    func indexWorkspace(_ workspace: Workspace) async throws -> ProjectIndex
    func updates(for workspace: Workspace) -> AsyncStream<ProjectIndexEvent>
}

struct ProjectIndex: Hashable, Codable, Sendable {
    var rootURL: URL
    var mainFileURL: URL?
    var nodes: [ProjectNode]
    var texGraph: [URL: Set<URL>]
    var bibliographyFiles: [URL]
    var assetFiles: [URL]
}

enum ProjectNode: Hashable, Codable, Sendable {
    case folder(ProjectFolder)
    case file(ProjectFile)
}
```

Indexer는 `\input`, `\include`, `\bibliography`, `\addbibresource`, graphics commands를 best-effort로 파싱한다. 정확성이 중요한 빌드 결과는 실제 LaTeX 로그를 신뢰하고, index는 탐색/추천/빌드 기본값 제공에 사용한다.

### Build System

```swift
protocol BuildServicing: Sendable {
    func build(_ request: BuildRequest) async throws -> BuildResult
    func cancel(workspaceID: WorkspaceID) async
    func events(for workspaceID: WorkspaceID) -> AsyncStream<BuildEvent>
}

struct BuildRequest: Hashable, Sendable {
    let workspace: Workspace
    let mainFileURL: URL
    let recipe: BuildRecipe
    let environment: [String: String]
}

struct BuildResult: Hashable, Sendable {
    let status: BuildStatus
    let outputPDFURL: URL?
    let issues: [BuildIssue]
    let transcriptURL: URL?
    let duration: Duration
}

actor BuildService: BuildServicing {
    private let processRunner: ProcessRunning
    private let logParser: LogParsing

    func build(_ request: BuildRequest) async throws -> BuildResult {
        // Serializes builds per workspace, streams output, parses logs, returns artifacts.
        fatalError("implementation")
    }
}
```

빌드는 workspace 단위로 직렬화한다. 사용자가 다시 빌드하면 이전 build task를 취소하고 새 요청을 시작한다. `ProcessRunner`는 `/usr/bin/env`, user-configured TeX path, bundled toolchain 가능성을 모두 지원하도록 분리한다.

### PDF Viewer and Sync

```swift
@MainActor
final class PDFViewerViewModel: ObservableObject {
    @Published private(set) var documentURL: URL?
    @Published var pageIndex: Int = 0
    @Published var zoom: PDFZoomMode = .fitWidth

    private let syncService: PDFSyncServicing

    func loadPDF(at url: URL) async throws
    func jump(to destination: PDFDestinationRef)
    func syncFromSource(_ location: TextLocation) async
    func syncToSource(page: Int, point: CGPoint) async -> TextLocation?
}

protocol PDFSyncServicing: Sendable {
    func pdfDestination(for source: TextLocation, in workspace: Workspace) async throws -> PDFDestinationRef?
    func sourceLocation(for pdfPoint: PDFPointRef, in workspace: Workspace) async throws -> TextLocation?
}
```

PDF sync는 SyncTeX 파일이 있으면 이를 우선 사용한다. 없으면 최근 build issue, current file, page state 기반의 graceful fallback을 둔다.

### Issue Navigator

```swift
@MainActor
final class IssueNavigatorViewModel: ObservableObject {
    @Published private(set) var issues: [BuildIssue] = []
    @Published var filter: IssueFilter = .all

    var visibleIssues: [BuildIssue] {
        issues.filter { filter.includes($0) }
    }

    func replaceIssues(_ newIssues: [BuildIssue])
    func select(_ issue: BuildIssue) -> TextLocation?
}

struct BuildIssue: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let severity: IssueSeverity
    let message: String
    let location: TextLocation?
    let rawLogExcerpt: String
}
```

### Preferences and Persistence

```swift
struct AppSettings: Codable, Equatable {
    var editor: EditorSettings
    var build: ToolchainSettings
    var pdf: PDFViewerSettings
}

protocol SettingsStore: Sendable {
    func load() -> AppSettings
    func save(_ settings: AppSettings) throws
}

protocol BookmarkStore: Sendable {
    func save(_ grant: FilePermissionGrant) throws
    func load(workspaceID: WorkspaceID) throws -> FilePermissionGrant?
    func remove(workspaceID: WorkspaceID) throws
}
```

설정처럼 작고 자주 읽는 값은 `UserDefaults` 또는 JSON in Application Support를 사용한다. Security-scoped bookmark, 최근 프로젝트, 캐시는 Application Support 아래에 버전이 있는 JSON/SQLite 파일로 저장한다. 처음에는 JSON으로 충분하고, symbol index나 full-text search가 필요해지면 SQLite로 확장한다.

## Data Flow Description

```text
Open Project
  User selects directory
    -> FileAccessService.requestProjectDirectory()
    -> BookmarkStore.save(grant)
    -> AppModel.activeWorkspace = Workspace(...)
    -> ProjectIndexer.indexWorkspace()
    -> Sidebar, Editor default file, Build defaults update

Edit Source
  NSTextView event
    -> TextEditingController.onTextChanged
    -> EditorViewModel.applyEdit()
    -> TextBuffer updated, isDirty = true
    -> Optional debounce: syntax highlight / project re-index for include changes

Save
  User command Cmd-S
    -> MenuCommandRouter routes to active EditorViewModel
    -> FileAccessService.withAccess(grant)
    -> DocumentStore.write(buffer)
    -> isDirty = false

Build
  User command Cmd-B
    -> BuildViewModel creates BuildRequest from workspace + index + settings
    -> BuildService.build()
    -> ProcessRunner streams stdout/stderr
    -> LogParser emits BuildIssue
    -> BuildViewModel updates progress/status
    -> IssueNavigatorViewModel.replaceIssues()
    -> PDFViewerViewModel.loadPDF(outputPDFURL)

Navigate Issue
  User selects issue
    -> IssueNavigatorViewModel.select(issue)
    -> EditorViewModel.open(file) if needed
    -> EditorViewModel.jump(to location)

PDF Sync
  Source cursor command
    -> PDFSyncService.pdfDestination(for source)
    -> PDFViewerViewModel.jump(destination)

  PDF double click / command click
    -> PDFSyncService.sourceLocation(for pdf point)
    -> EditorViewModel.jump(to source location)
```

ViewModel끼리 직접 강하게 참조하지 않는다. 조율이 필요한 경우 `MainWindowCoordinator` 또는 `AppModel`이 액션을 받아 각 ViewModel에 전달한다. 예를 들어 issue 선택은 `IssueNavigatorView`가 `onSelectIssue` closure를 호출하고, shell이 editor로 route한다.

## Build Pipeline Flow

```text
1. Prepare
   - Resolve workspace grant
   - Determine main .tex file
   - Select build recipe from settings/project override
   - Create build directory: .paperforge/build/<workspace-id> or system cache

2. Validate Toolchain
   - Resolve latexmk/tectonic path
   - Check executable availability
   - Build environment with PATH, TEXINPUTS, BIBINPUTS when needed

3. Execute
   - Start ProcessRunner with cancellable Task
   - Stream stdout/stderr as BuildEvent.output
   - Emit BuildEvent.phase changes: preparing, running, parsing, completed

4. Parse
   - Read .log, .fls, .synctex.gz if available
   - Parse errors/warnings/bad boxes into BuildIssue
   - Map relative paths to workspace URLs using project index and .fls

5. Collect Artifacts
   - Locate generated PDF
   - Locate transcript/log and SyncTeX
   - Store artifact metadata in CacheStore

6. Publish
   - BuildViewModel receives BuildResult
   - IssueNavigator updates issue list
   - PDF viewer reloads changed PDF with page preservation
   - Editor receives inline diagnostics if enabled
```

Recommended default recipes:

```text
latexmk-pdf:
  latexmk -pdf -interaction=nonstopmode -file-line-error <main.tex>

tectonic:
  tectonic --synctex --keep-logs --keep-intermediates <main.tex>

xelatex-latexmk:
  latexmk -xelatex -interaction=nonstopmode -file-line-error <main.tex>
```

## Sandboxed / Non-Sandboxed File Access Strategy

| Concern | Sandboxed | Non-sandboxed | 공통 추상화 |
| --- | --- | --- | --- |
| 프로젝트 열기 | `NSOpenPanel`로 user-selected read/write 권한 획득 | 일반 URL 접근 | `FileAccessService.requestProjectDirectory()` |
| 재실행 후 접근 | security-scoped bookmark resolve | 최근 URL 검증 | `BookmarkStore` |
| 파일 읽기/쓰기 | `startAccessingSecurityScopedResource()` scope 안에서 수행 | no-op scope | `withAccess(to:operation:)` |
| 빌드 프로세스 | child process가 sandbox 제한을 받으므로 권한/경로 검증 필요 | 일반 process 실행 | `ProcessRunner` + build directory policy |
| 외부 toolchain | App Store sandbox에서는 사용자 선택 또는 embedded helper 고려 | `/Library/TeX/texbin` 등 직접 접근 | `ToolchainSettings` |
| Drag and drop | security scope 획득 가능한 URL만 영속화 | URL 저장 | `FilePermissionGrant` |

초기 배포가 직접 다운로드(non-sandboxed)라면 파일 접근 구현은 단순해진다. 그래도 sandbox 추상화를 먼저 넣어두면 App Store, Setapp, enterprise 배포처럼 제약이 다른 빌드를 나중에 분기하기 쉽다.

## MVVM-ish State Ownership

```text
AppModel
  owns: active workspace, global settings, dependency container

MainWindowCoordinator
  owns: cross-feature routing only
  examples: issue -> editor jump, build result -> PDF reload

Feature ViewModel
  owns: screen state, loading/error state, user intent handling
  does not own: file system permissions, process logic, persistence format

Service / Actor
  owns: IO, indexing, build execution, parsing, persistence
  communicates: async functions + AsyncStream events
```

권장 패턴:

```swift
struct MainWindowView: View {
    @StateObject private var editor: EditorViewModel
    @StateObject private var build: BuildViewModel
    @StateObject private var pdf: PDFViewerViewModel
    @StateObject private var issues: IssueNavigatorViewModel

    var body: some View {
        // Feature views receive their own view model and route closures.
    }
}
```

전역 `EnvironmentObject`는 `AppModel` 정도로 제한한다. 모든 서비스와 feature state를 environment에 흩뿌리면 테스트와 추론이 어려워진다.

## AppKit Integration Boundaries

| AppKit 필요 영역 | 방식 | 금지할 것 |
| --- | --- | --- |
| 텍스트 편집 | `NSViewRepresentable` + coordinator + `TextEditingController` | ViewModel에서 `NSTextView` 직접 참조 |
| PDF 표시 | `PDFView` wrapper + `PDFDocumentController` | SwiftUI View에서 PDFKit 상태 직접 mutation |
| 메뉴/커맨드 | SwiftUI `Commands` + focused value + router | feature 간 singleton command bus |
| 파일 패널 | `OpenPanelClient` | 서비스 actor 내부에서 직접 AppKit 호출 |
| 윈도우 상태 | `WindowAccessor`, scene storage | 도메인 모델에 `NSWindow` 저장 |

## Testing Strategy

| Area | 테스트 |
| --- | --- |
| ProjectIndexer | fixture 프로젝트에서 include graph, asset discovery, main file detection 검증 |
| BuildSystem | fake `ProcessRunner`로 output stream, cancellation, log parser 검증 |
| Persistence | temp directory 기반 JSON/bookmark round-trip 검증 |
| Editor | `TextBuffer` edit application, dirty state, save flow 검증 |
| PDFSync | SyncTeX parser가 생긴 뒤 sample mapping 검증 |
| UI smoke | 주요 split view, preferences, issue navigation snapshot 또는 lightweight UI test |

## Implementation Order

1. `Core` 모델과 `DependencyContainer` 생성
2. `FileAccessService`, `SettingsStore`, `BookmarkStore` 구현
3. 프로젝트 열기 + sidebar index 표시
4. `NSTextView` 기반 editor wrapper와 save flow
5. `BuildService` + fake parser + toolbar progress
6. 로그 parser와 issue navigator 연결
7. `PDFView` wrapper와 build artifact reload
8. SyncTeX 기반 source/PDF navigation
9. Preferences와 build recipes 고도화

이 순서로 가면 초기에 "프로젝트 열기 -> 편집 -> 저장 -> 빌드 -> PDF 확인"의 수직 흐름을 빠르게 확보하고, 이후 고급 편집 기능이나 sync 정확도를 독립적으로 개선할 수 있다.
