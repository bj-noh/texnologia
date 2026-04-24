# TEXnologia 
<img src="TEXnologia/Resources/TEXnologiaIcon.svg" alt="TEXnologia icon" width="96" />

TEXnologia is a macOS-native LaTeX writing IDE prototype focused on a fast research-writing loop:

open a project, edit `.tex`, build locally, jump to errors, and preview the PDF.

The current implementation is a Swift Package app using SwiftUI, AppKit, `NSTextView`, and PDFKit. It assumes a local TeX distribution such as MacTeX or BasicTeX is already installed.


![TEXnologia welcome screen](assets/texnologia-fullscreen1.png)

![TEXnologia with project explorer, editor, PDF preview, and AI pane](assets/texnologia-fullscreen2.png)

## Current Features

- LaTeX-aware source editor using AppKit `NSTextView` with debounced highlighting, line-number gutter, find/incremental find, toggle comment, duplicate/delete/move line, and adjustable font size
- Syntax highlighting for commands, comments, braces, and math delimiters
- BibTeX syntax highlighting for entry types, citation keys, field names, values, comments, numbers, and punctuation
- Word-based wrapping with horizontal scrolling disabled
- English spelling/grammar checking while suppressing red underlines for TeX syntax ranges
- Multi-session workspace with a session tab bar and per-session multi-file editor tab bar, including dirty/saved indicators
- Create empty projects, open folders/`.tex` files, or import `.zip` archives from the session `+` menu
- Project explorer with rename, delete-to-trash confirmation, drag/drop, new file/folder, refresh, Finder reveal, external filesystem change watcher, and saved/dirty dot states aggregated to folders
- Outline section that follows the currently open editor file
- Preview pane with a Preview A / Preview B split and focus indicator, routed rendering for PDF, images, JSON, and read-only generated log/aux/out/fls files
- Per-file edit history with GitHub-style diff hunks and DIF LaTeX export (`\DIFaddbegin`/`\DIFdelbegin`) for manuscript revisions
- AI Assistant side pane with configurable provider/model/API key, plus tool-use loop against the project (list, read, write, replace-in-file, apply-to-open-editor)
- Session persistence: open sessions, active session, open editor tabs, active tab, and chat-pane visibility are restored on next launch
- Local LaTeX build through `latexmk` when available, with direct engine fallback
- `pdflatex`, `xelatex`, and `lualatex` support
- TeX Live year selection limited to `2024` and `2025`; default is `pdfLaTeX` with `2024`
- Compile process wrapper and issue parsing
- Collapsed issue dock by default, expandable when needed
- Preferences for appearance, editor theme/font/line spacing, engine, TeX Live year, shell escape, auto-build, artifact visibility, spell checking, and AI provider/model/key/max tokens
- Generated build output under `.texnologia-build`
- Windows host plan under `platforms/windows`

## Requirements

- macOS 14 or newer
- Xcode Command Line Tools or Xcode with Swift 5.9+
- MacTeX or BasicTeX
- `latexmk` recommended

Check Swift:

```bash
swift --version
```

Check TeX:

```bash
/usr/local/texlive/2024/bin/universal-darwin/pdflatex --version
/Library/TeX/texbin/latexmk --version
```

If `latexmk` is missing but `pdflatex`, `xelatex`, or `lualatex` exists, TEXnologia can still use the direct-engine fallback.
TEXnologia searches the selected TeX Live year first, then falls back to the active `/Library/TeX/texbin` symlink.

## Run In Development

From the repository root:

```bash
swift run TEXnologia
```

This launches the app directly from Swift Package Manager.

## Build A macOS App Bundle

```bash
scripts/build_app_bundle.sh
```

The generated app appears at:

```text
dist/TEXnologia.app
```

Open it:

```bash
open dist/TEXnologia.app
```

Optional: copy it to Applications after building:

```bash
cp -R dist/TEXnologia.app /Applications/
```

## Use The App

1. Launch TEXnologia.
2. Click the `+` in the session tab bar to create an empty project, open a folder/`.tex` file, or import a `.zip` archive.
3. Select a `.tex` file in the explorer. Multiple files can stay open as editor tabs below the session bar.
4. Edit in the center editor.
5. Press `Command-S` to save (and compile) or click `Compile`.
6. Review issues in the bottom dock if the build fails.
7. Click an issue to jump to the source location.
8. Preview the generated PDF on the right. Use the split button for a two-pane preview.
9. Toggle the AI Assistant pane from the toolbar; configure the provider and API key under `Preferences → AI`.

Useful shortcuts:

| Shortcut | Action |
| --- | --- |
| `Command-O` | Open project, `.tex`, or `.zip` |
| `Shift-Command-O` | Import zip archive |
| `Command-S` | Save and compile |
| `Command-B` | Compile |
| `Command-F` | Find |
| `Command-/` | Toggle line comment |
| `Command-L` | Select line |
| `Shift-Command-D` | Duplicate line |
| `Shift-Command-K` | Delete line |
| `Option-Up/Down` | Move line up/down |
| `Command-=` / `Command--` / `Command-0` | Increase / decrease / reset editor font |
| `Control-Command-F` | Toggle fullscreen |

## Preferences

Open the macOS app settings window to configure:

- Appearance: system, light, or dark
- Editor theme
- Editor font family and size
- Line spacing
- Spell checking
- Default TeX engine
- TeX Live year: `2024` or `2025`
- Shell escape
- Auto-build on save
- Intermediate artifact hiding
- AI provider, model, API key, and max tokens

Shell escape is disabled by default. API keys are stored under `~/Library/Application Support/TEXnologia` and are not written into the project.

## Compile Output

TEXnologia writes generated build files into:

```text
<project>/.texnologia-build/
```

The explorer hides this folder by default when intermediate artifact hiding is enabled.

## Validation

Run the core checks:

```bash
swift build
scripts/verify_feature_contracts.sh
scripts/verify_editor_wrapping.sh
scripts/verify_comment_highlighting.sh
scripts/verify_app_icon_dimensions.sh
```

## Windows Status

The current app target is macOS-only because it depends on SwiftUI, AppKit, PDFKit, and `NSTextView`.

Windows support should be implemented as a separate desktop host under `platforms/windows/`. See [platforms/windows/README.md](platforms/windows/README.md) for the up-to-date porting plan and feature parity targets.

## Repository Layout

```text
TEXnologia/
  App/                  # SwiftUI app shell, app model, and session persistence
  BuildSystem/          # LaTeX process execution and log parsing
  Chat/                 # AI assistant models, clients, tools, and UI
  Core/                 # Shared domain models
  Editor/               # AppKit-backed LaTeX editor and syntax highlighter
  History/              # Per-file edit history and DIF LaTeX export
  IssueNavigator/       # Compile issue dock
  PDFViewer/            # PDFKit integration
  Preferences/          # User settings UI and persistence
  ProjectIndexing/      # File tree, outline, labels, citations
  Resources/            # App icon source
platforms/windows/      # Windows host planning scaffold
scripts/                # Build and verification scripts
```

## Notes

This project is independent and does not copy the branding, UI design, icons, proprietary names, or proprietary implementation of any existing LaTeX editor. It references the broad functional category of professional LaTeX writing tools while defining its own product direction and implementation.
