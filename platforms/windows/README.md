# TEXnologia.Windows

This directory is reserved for the Windows desktop host of TEXnologia.

The current macOS app is implemented with SwiftUI, AppKit, PDFKit, and `NSTextView`, so it intentionally does not compile on Windows. The Windows app should ship as a separate native host that reuses the same build/indexing/log-parsing semantics.

## Recommended Stack

- UI: .NET 8 + Avalonia (or WinUI 3 if Windows-only integration is preferred)
- Editor: Monaco in WebView2 for the first MVP; evaluate a native editor control afterwards
- PDF viewer: pdf.js in WebView2, or Pdfium for a native renderer
- LaTeX toolchain: MiKTeX or TeX Live installed externally
- Process runner: argument-array invocation, never `cmd.exe /C`

## Proposed Layout

```text
platforms/windows/
  README.md
  TEXnologia.Windows/          # future Avalonia app
  TEXnologia.Windows.Core/     # portable domain/build/indexing code
  TEXnologia.Windows.Tests/    # fixture-based regression tests
```

## Feature Parity Targets

The Windows host must reproduce the behaviors that the macOS app has already shipped:

### Project and Session

- Open folder, `.tex`, or `.zip`.
- Create empty projects with a starter `main.tex`.
- Multiple concurrent project sessions with a session tab bar.
- Per-session multi-tab editor bar with saved/dirty indicators.
- Persist open sessions, active session, open editor tabs, active tab, and chat-pane visibility across app restarts.
- Session state file under the OS user data directory, not inside the project.

### Editor

- LaTeX-aware syntax highlighting for commands, comments, braces, and math.
- BibTeX syntax highlighting for entry types, citation keys, field names, values.
- Word wrapping enabled by default; no horizontal scrolling.
- Spell/grammar checking that suppresses false positives on LaTeX syntax ranges.
- Find, incremental find, toggle line comment, duplicate line, delete line, move line up/down.
- Adjustable editor font size with increase/decrease/reset shortcuts.
- Line number gutter with adaptive width.
- Debounced syntax rehighlighting.

### Project Explorer

- File/folder rename, delete-to-trash confirmation, drag/drop move, new file, new folder.
- Finder reveal equivalent (Windows Explorer reveal).
- Inline rename with stem-selection default.
- External filesystem change watcher (Windows `ReadDirectoryChangesW` analogous to FSEvents).
- Saved/dirty dot states per file; aggregated state on folders.
- Outline section populated from the currently open editor file.
- Hidden artifact folder `.texnologia-build` by default.

### Preview

- Split or single preview pane (Preview A / Preview B) with focus indicator.
- Routed rendering for PDF, image, JSON, read-only generated LaTeX log/aux/out/fls, and unknown binary files.

### Build

- Local build through `latexmk.exe` first, falling back to direct engines.
- Support `pdflatex.exe`, `xelatex.exe`, `lualatex.exe`.
- `.texnologia-build` output directory.
- Parse compile log into navigable issues with click-to-source.
- Collapsed issue dock by default; expandable.
- Shell escape disabled by default.

### AI Assistant Pane

- Side pane with provider/model configuration in Preferences.
- Tool-use loop against the project: list/read/write files, replace-in-file, apply-to-open-editor.
- API keys stored in the OS user data directory, never in the project.

### History

- Track per-file edit history.
- GitHub-style diff hunks with additions and deletions colored.
- Copy/save DIF LaTeX (`\DIFaddbegin`/`\DIFdelbegin` markers) for manuscript revision workflows.

### Preferences

- Appearance: system/light/dark.
- Editor theme, font family, font size, line spacing.
- Spell checking toggle.
- Default TeX engine and TeX Live year.
- Shell escape toggle.
- Auto-build on save.
- Intermediate artifact hiding.
- AI provider, model, API key, max tokens.

## Portable Core Boundary

These macOS modules should be re-expressed as platform-neutral logic (C# port, shared contracts, or a shared native core):

| Capability | macOS source | Windows equivalent |
| --- | --- | --- |
| Domain models | `TEXnologia/Core/CoreModels.swift` | Shared spec or generated models |
| Project indexing | `TEXnologia/ProjectIndexing/ProjectIndexer.swift` | Port directly |
| Build config | `TEXnologia/BuildSystem/BuildConfiguration.swift` | Same fields and defaults |
| Build execution | `TEXnologia/BuildSystem/LatexBuildService.swift` | Windows process runner with `.exe` discovery |
| Log parsing | `TEXnologia/BuildSystem/LatexLogParser.swift` | Port parser and fixture tests exactly |
| File routing | URL extension logic in `AppModel.swift` | Shared file-type table |
| Editor tokenizer | `TEXnologia/Editor/LatexSyntaxHighlighter.swift` | Platform-neutral tokenizer, UI-specific colors |
| History diff | `TEXnologia/History/HistoryDiff.swift` | Port line-level diff and DIF exporter |
| Session persistence | `TEXnologia/App/SessionStateStore.swift` | JSON snapshot under `%APPDATA%/TEXnologia` |

These must stay platform-specific:

| Capability | macOS | Windows |
| --- | --- | --- |
| Main window | SwiftUI `HSplitView` | Avalonia split panes or WinUI layout |
| Editor view | AppKit `NSTextView` | Monaco/WebView2 or native editor control |
| PDF viewer | PDFKit | pdf.js/WebView2 or Pdfium |
| Open panels | `NSOpenPanel` | Windows folder/file picker |
| Drag/drop | SwiftUI/AppKit | Avalonia/WinUI drag-drop |
| Spell checking | AppKit text checking | Windows spell checker or editor extension |
| Fullscreen | `NSWindow.toggleFullScreen` | Win32/windowing API |
| External change watcher | FSEvents | `ReadDirectoryChangesW` |

## Toolchain Discovery

Search order:

1. User-configured absolute paths.
2. Current process `PATH`.
3. MiKTeX common paths under `%LOCALAPPDATA%`, `%PROGRAMFILES%`, `%PROGRAMFILES(X86)%`.
4. TeX Live paths under `C:\texlive\*\bin\windows`.

Expected executables: `latexmk.exe`, `pdflatex.exe`, `xelatex.exe`, `lualatex.exe`, `bibtex.exe`, `biber.exe`.

## Path and Encoding Rules

- Pass absolute paths to the process runner.
- Support spaces and non-ASCII paths (including CJK).
- Normalize line endings when parsing logs.
- Prefer UTF-8; fall back to other encodings only when reading existing files.

## Packaging

- MSIX for Microsoft Store-style packaging.
- MSI/WiX for direct distribution.
- Portable zip for internal QA.
- Windows bundle identifier: `dev.texnologia.windows`.

## First Vertical Slice

1. Create `platforms/windows/TEXnologia.Windows`.
2. Implement project open and file tree.
3. Port file-type routing and project indexing.
4. Port log parser.
5. Add process runner for `latexmk.exe`.
6. Show generated PDF in pdf.js.
7. Add issue list click-to-source.
8. Add session persistence snapshot under `%APPDATA%/TEXnologia`.

Definition of done:

- A folder with `main.tex` opens.
- Build creates `.texnologia-build/main.pdf`.
- Invalid LaTeX produces a clickable issue.
- JSON/image/PDF files do not open as binary text.
- Long paragraphs wrap by word.
- The Windows app restores its last project session when reopened.
