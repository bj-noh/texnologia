# PaperForge Integrated Design

## Executive Summary

PaperForge is a macOS-native LaTeX writing IDE focused on the fastest reliable loop for research writing:

```text
Open project -> edit source -> build locally -> jump to issue -> inspect PDF
```

The product intentionally references only functional categories common to professional LaTeX tools. It does not copy any specific brand, visual system, iconography, terminology, or proprietary implementation. The differentiator is a quiet, native, error-repair-first workflow for academic and technical authors on macOS.

## Product Scope

### MVP

- Folder-based LaTeX project open
- Root `.tex` detection
- Native `NSTextView` source editor
- Lightweight LaTeX syntax highlighting
- Basic command, label, and citation completion foundations
- Multi-file indexing for `\input`, `\include`, bibliography resources, labels, citations, and outline
- `latexmk` build with `pdflatex`, `xelatex`, `lualatex` intent modeled
- `-file-line-error`, `-synctex=1`, `-no-shell-escape` by default
- Build issue parsing and clickable issue list
- PDFKit preview with reload after build
- Preferences for engine, build behavior, shell escape, output location, editor theme foundation
- Artifact hiding through `.paperforge-build/`

### Beta

- Robust SyncTeX forward and inverse search
- Better command/reference/citation autocomplete UI
- File watcher driven incremental indexing
- Build profiles for BibTeX/Biber and custom engines
- `.latexmkrc` trust workflow
- More complete issue explanations
- Template project creation

### v1.0

- Paper diagnostics dashboard
- Quick Fix actions with previewed diffs
- Bibliography manager and duplicate key checks
- Submission preparation checklist
- Review mode combining source comments, TODOs, PDF notes, and build diagnostics

### v2.0

- AI-assisted repair suggestions
- Collaboration and review workflows
- Journal/conference submission package generator
- Optional plugin or extension API
- Optional bundled TeX engine strategy

## Architecture

```text
PaperForgeApp
  AppModel / DependencyContainer
    MainWindowView
      ProjectSidebarView -> ProjectIndexer
      LaTeXEditorView    -> NSTextView adapter + tokenizer/highlighter
      PDFPaneView        -> PDFKit adapter
      IssueNavigatorView -> BuildIssue selection and source jump
      PreferencesView    -> AppSettings
    Services
      FileAccessService
      ProjectIndexer
      BuildService
      ProcessRunner
      LatexLogParser
      PDFSyncCoordinator
      SettingsStore
      BookmarkStore
```

The app should remain MVVM-ish rather than adopting a large architecture framework at MVP. SwiftUI owns composition and state display. AppKit is isolated in editor and PDF representables. Domain services stay UI-free and testable.

## Conflict Resolution

| Topic | Tension | Integrated decision |
| --- | --- | --- |
| SyncTeX | PRD mentions forward search in MVP, PDF agent moves SyncTeX to Beta | MVP stores SyncTeX artifacts and issue-based source jumps; real source/PDF SyncTeX navigation is Beta |
| Sandboxing | App Store compatibility vs external TeX process reality | Initial distribution: Developer ID + notarization, non-sandboxed. Architecture remains sandbox-compatible |
| Build directory | Project-local output vs app cache | Default `.paperforge-build/`; optional app cache for iCloud-heavy projects |
| `.latexmkrc` | Needed by advanced projects, risky for command execution | Detect in MVP, warn and disable trust-sensitive behaviors until Beta trust workflow |
| Parser depth | Full LaTeX semantics vs realistic MVP | Regex/tokenizer and index snapshots in MVP; parser/tree-sitter candidate later |
| Direct engine fallback | Useful but incomplete for bibliography | Fallback only when `latexmk` executable is missing or unusable, not when document compilation fails |

## Technical Design

### Editor

MVP uses `NSTextView` wrapped by `NSViewRepresentable`, with TextKit 1 for line layout and syntax attributes. The tokenizer is lexical, not semantic. It recognizes commands, comments, braces, brackets, math delimiters, and simple environment forms. Incremental highlighting should later expand from whole-document MVP to dirty paragraph ranges.

### Project Indexing

`ProjectIndex` is an immutable snapshot. A background indexer discovers root documents, file graph edges, section outline, labels, references, citation uses, and BibTeX keys. UI consumes derived sidebar models rather than reparsing files.

### Build System

`BuildConfiguration` describes engine, output directory, shell escape policy, and SyncTeX generation. Commands are generated as executable URL plus argument array. The app must never run user-controlled shell strings. Build logs are parsed into `BuildIssue` records with file, line, severity, message, and raw excerpt.

### PDF Viewer

PDFKit is wrapped through `NSViewRepresentable`. The viewer reloads from `Data` to avoid file replacement races, keeps page and zoom when possible, and treats failed builds as stale state rather than blanking the previous successful PDF.

### Security

Default policy:

- `-no-shell-escape`
- absolute executable paths
- no `/bin/sh -c`
- project root permission via user selection
- generated files only under `.paperforge-build/`
- cleanup only if `.paperforge-owned` marker exists
- external output directories require explicit user selection

## Implementation Roadmap

| Sprint | Goal |
| --- | --- |
| 1 | SwiftUI app shell, dependency container, core models, tests/fixtures structure |
| 2 | File access, project open, root `.tex` detection, recent projects |
| 3 | Native editor, load/save, tokenizer, syntax highlighting, line numbers |
| 4 | `latexmk` build pipeline, command generation, process execution, cancellation |
| 5 | Log parser, issue panel, source jump from issue |
| 6 | PDFKit viewer, reload preservation, stale PDF handling |
| 7 | Multi-file index, outline, labels, citation keys, autocomplete providers |
| 8 | Preferences, security warnings, path edge cases, fixture regression, MVP hardening |

## First Vertical Slice

The first runnable slice should open a project folder, detect `main.tex`, edit it, run `latexmk`, show parsed issues, and reload the generated PDF.

Files started in this workspace:

- `PaperForge/App/PaperForgeApp.swift`
- `PaperForge/App/AppModel.swift`
- `PaperForge/App/MainWindowView.swift`
- `PaperForge/Core/CoreModels.swift`
- `PaperForge/Editor/LaTeXEditorView.swift`
- `PaperForge/Editor/LatexSyntaxHighlighter.swift`
- `PaperForge/ProjectIndexing/ProjectIndexer.swift`
- `PaperForge/BuildSystem/LatexBuildService.swift`
- `PaperForge/BuildSystem/LatexLogParser.swift`
- `PaperForge/PDFViewer/PDFPaneView.swift`
- `PaperForge/IssueNavigator/IssueNavigatorView.swift`
- `PaperForge/Preferences/PreferencesView.swift`

## Risks and Mitigations

| Risk | Mitigation |
| --- | --- |
| LaTeX logs vary heavily across packages | Golden fixture logs and conservative parser fallback |
| External TeX missing or misconfigured | Toolchain diagnostics and explicit binary discovery |
| Sandboxed child process permissions fail | Direct distribution first, sandbox-compatible abstraction retained |
| PDFKit reads partial PDF during rebuild | Data-based reload plus retry/backoff |
| Large files make highlighting slow | Dirty-range highlighting and background tokenization after MVP |
| `shell-escape` and `.latexmkrc` execute unwanted commands | Disabled by default, trust workflow, visible command preview |

## Definition of Done for MVP

- Five fixture projects pass open/edit/build/PDF/issue workflows
- `latexmk` command includes `-file-line-error`, `-synctex=1`, and `-no-shell-escape`
- Build failure opens issue panel and issue click moves to source file/line
- Successful build reloads PDF without losing page/zoom in normal cases
- Recent project and build settings survive app restart
- Cleanup cannot delete outside the PaperForge-owned build directory
- App builds on supported macOS versions and has Apple Silicon/Intel smoke coverage

