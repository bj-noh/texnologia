#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HIGHLIGHTER="$ROOT_DIR/TEXnologia/Editor/LatexSyntaxHighlighter.swift"

require_pattern() {
  local pattern="$1"
  local label="$2"

  if ! grep -q "$pattern" "$HIGHLIGHTER"; then
    echo "Missing comment highlighting contract: $label" >&2
    exit 1
  fi
}

require_pattern "applyLatexTokens" "LaTeX token application pipeline"
require_pattern "applyBibTokens" "BibTeX token application pipeline"
require_pattern "applyCommentTokensLast" "comments are applied after command/keyword tokens"
require_pattern "overlapsCommentRange" "tokens inside comments are skipped"
require_pattern "NSIntersectionRange" "comment range intersection check"
require_pattern "green: 0.42" "darker system comment green"
require_pattern "green: 0.36" "darker paper comment green"
require_pattern "green: 0.55" "darker dusk comment green"
require_pattern "green: 0.58" "darker midnight comment green"

echo "PASS comment highlighting"
