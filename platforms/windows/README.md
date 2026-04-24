# TEXnologia.Windows

This directory is reserved for the Windows desktop host.

The current macOS app is implemented with SwiftUI, AppKit, PDFKit, and `NSTextView`, so it is intentionally not compiled for Windows. The Windows app should be a separate host that follows the shared product behavior documented in `docs/windows-support.md`.

Recommended first implementation:

- `.NET 8`
- `Avalonia`
- `WebView2` for Monaco editor and pdf.js
- Windows process runner for MiKTeX or TeX Live binaries

Initial project layout:

```text
platforms/windows/
  README.md
  TEXnologia.Windows/          # future Avalonia app
  TEXnologia.Windows.Core/     # future portable domain/build/indexing code
  TEXnologia.Windows.Tests/    # fixture-based regression tests
```

Shared behavior that must match macOS:

- Project root detection from `.tex` files.
- `\input`, `\include`, bibliography, labels, citations, and outline indexing.
- `.texnologia-build` output directory.
- Build issues parsed from LaTeX logs.
- Word wrapping in the editor.
- TeX syntax should not be marked as spelling/grammar errors.
- PDF/image/JSON/source files must render with type-aware previews.

