#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

require_file() {
  local file="$1"
  if [[ ! -f "$ROOT_DIR/$file" ]]; then
    echo "FAIL missing $file" >&2
    exit 1
  fi
}

require_pattern() {
  local file="$1"
  local pattern="$2"
  local label="$3"

  if ! grep -q "$pattern" "$ROOT_DIR/$file"; then
    echo "FAIL missing $label in $file: $pattern" >&2
    exit 1
  fi
}

require_file "docs/windows-support.md"
require_file "platforms/windows/README.md"

require_pattern "docs/windows-support.md" "SwiftUI/AppKit/PDFKit" "macOS-only framework note"
require_pattern "docs/windows-support.md" "TEXnologia.Windows" "Windows host name"
require_pattern "docs/windows-support.md" "Avalonia" "recommended Windows UI stack"
require_pattern "docs/windows-support.md" "WebView2" "Windows editor/PDF host strategy"
require_pattern "docs/windows-support.md" ".texnologia-build" "shared build output"
require_pattern "docs/windows-support.md" "latexmk.exe" "Windows TeX discovery"
require_pattern "docs/windows-support.md" "MiKTeX" "MiKTeX support"
require_pattern "docs/windows-support.md" "TeX Live" "TeX Live support"

require_pattern "platforms/windows/README.md" "TEXnologia.Windows" "Windows scaffold"
require_pattern "platforms/windows/README.md" "not compiled for Windows" "platform split warning"
require_pattern "platforms/windows/README.md" "Word wrapping" "editor parity requirement"
require_pattern "platforms/windows/README.md" "PDF/image/JSON/source" "file rendering parity requirement"

echo "PASS Windows port readiness scaffold"

