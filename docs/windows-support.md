# TEXnologia Windows Support Plan

TEXnologia's current app target is a macOS-native SwiftUI/AppKit/PDFKit application. It cannot be compiled or run as-is on Windows because the editor, PDF viewer, file dialogs, drag/drop, spell checking, and fullscreen behavior use Apple frameworks.

The Windows path should be a platform-specific shell over a shared LaTeX domain core.

## Recommendation

Build Windows as a separate native desktop host named `TEXnologia.Windows`, while keeping the macOS app as the reference implementation.

Recommended stack:

- UI: .NET 8 + Avalonia, or WinUI 3 if Windows-only native integration is preferred.
- Editor: Monaco in WebView2 for the first Windows MVP, then consider a native editor component later.
- PDF viewer: pdf.js in WebView2, or Pdfium for a native renderer.
- LaTeX toolchain: MiKTeX or TeX Live installed externally.
- Shared behavior: project indexing rules, log parsing rules, build configuration semantics, issue model, file presentation rules, and `.texnologia-build` output layout.

Avoid trying to run the AppKit UI through compatibility layers. It will not preserve the editor/PDF/workspace experience we need.

## Portable Core Boundary

The following modules should become platform-neutral:

| Capability | Current Swift Source | Windows Equivalent |
| --- | --- | --- |
| Domain models | `TEXnologia/Core/CoreModels.swift` | Shared spec or generated models |
| Project indexing | `TEXnologia/ProjectIndexing/ProjectIndexer.swift` | Port directly to C# or shared Rust/Swift core |
| Build config | `TEXnologia/BuildSystem/BuildConfiguration.swift` | Same fields and defaults |
| Build execution | `TEXnologia/BuildSystem/LatexBuildService.swift` | Windows process runner with `.exe` discovery |
| Log parsing | `TEXnologia/BuildSystem/LatexLogParser.swift` | Port parser and fixture tests exactly |
| File routing | `TEXnologia/App/AppModel.swift` URL extension logic | Shared file type table |
| Editor tokenizer | `TEXnologia/Editor/LatexSyntaxHighlighter.swift` tokenizer parts | Platform-neutral tokenizer, UI-specific colors |

The following must stay platform-specific:

| Capability | macOS | Windows |
| --- | --- | --- |
| Main window | SwiftUI `HSplitView` | Avalonia split panes or WinUI layout |
| Editor view | AppKit `NSTextView` | Monaco/WebView2 or native editor control |
| PDF viewer | PDFKit | pdf.js/WebView2 or Pdfium |
| Open panels | `NSOpenPanel` | Windows folder/file picker |
| Drag/drop | SwiftUI/AppKit | Avalonia/WinUI drag-drop |
| Spell checking | AppKit text checking | Windows spell checker or editor extension |
| Fullscreen | `NSWindow.toggleFullScreen` | Win32/windowing API |

## Windows MVP Scope

MVP on Windows should support:

- Open folder, `.tex`, or `.zip`.
- Explorer with rename/delete confirmation/drag-drop.
- Text editor for `.tex`, `.bib`, `.sty`, `.cls`, source, JSON, and logs.
- Word wrapping enabled by default.
- LaTeX syntax colors and command autocomplete.
- Local build through `latexmk.exe` first, then direct `pdflatex.exe`, `xelatex.exe`, `lualatex.exe`.
- `.texnologia-build` output directory.
- Build log parser and navigable issues.
- PDF preview.
- Preferences for engine, shell escape, output directory, theme, font, wrapping.

Beta on Windows:

- SyncTeX source/PDF navigation.
- BibTeX/Biber configuration.
- Project-specific security prompts.
- Recent projects and persisted workspace layout.

Not in the first Windows MVP:

- Apple sandbox/security-scoped bookmark parity.
- Exact macOS keyboard/window behavior.
- App Store style packaging.

## Toolchain Discovery

Windows should search for TeX binaries in this order:

1. User-configured absolute paths.
2. Current process `PATH`.
3. MiKTeX common paths under `%LOCALAPPDATA%`, `%PROGRAMFILES%`, and `%PROGRAMFILES(X86)%`.
4. TeX Live common paths under `C:\texlive\*\bin\windows`.

Expected executables:

- `latexmk.exe`
- `pdflatex.exe`
- `xelatex.exe`
- `lualatex.exe`
- `bibtex.exe`
- `biber.exe`

Shell escape remains disabled by default. On Windows, command execution must use argument arrays, not `cmd.exe /C`, unless a specific user-approved integration requires a shell.

## Path And Encoding Rules

- Always pass paths as absolute paths to the process runner where possible.
- Support spaces and non-ASCII paths.
- Keep the current smoke fixture requirement for paths like `012 path 한글 edge`.
- Normalize line endings when parsing logs.
- Prefer UTF-8, with fallback encodings only for opened text files.

## Packaging

Use one of these:

- MSIX for Microsoft Store-style packaging.
- MSI/WiX for direct distribution.
- Portable zip for early internal QA.

The Windows app should not share the macOS bundle identifier. Use:

`dev.texnologia.windows`

## First Windows Vertical Slice

1. Create `platforms/windows/TEXnologia.Windows`.
2. Implement project open and file tree.
3. Port file type routing and project indexing.
4. Port log parser and run the same invalid LaTeX fixture.
5. Add process runner for `latexmk.exe`.
6. Show generated PDF in pdf.js.
7. Add issue list click-to-source.

Definition of done:

- A folder with `main.tex` opens.
- Build creates `.texnologia-build/main.pdf`.
- Invalid LaTeX produces a clickable issue.
- JSON/image/PDF files do not open as binary text.
- Long paragraphs wrap by word.

