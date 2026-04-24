#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HIGHLIGHTER="$ROOT_DIR/TEXnologia/Editor/LatexSyntaxHighlighter.swift"
EDITOR="$ROOT_DIR/TEXnologia/Editor/LaTeXEditorView.swift"
MAIN_VIEW="$ROOT_DIR/TEXnologia/App/MainWindowView.swift"
FIXTURE="$ROOT_DIR/Tests/Fixtures/FileRouting/references.bib"

require_pattern() {
  local file="$1"
  local pattern="$2"
  local label="$3"

  if ! grep -q "$pattern" "$file"; then
    echo "FAIL missing $label in $file: $pattern" >&2
    exit 1
  fi
}

if [[ ! -s "$FIXTURE" ]]; then
  echo "FAIL missing BibTeX fixture: $FIXTURE" >&2
  exit 1
fi

require_pattern "$HIGHLIGHTER" "case bibtex" "BibTeX syntax mode"
require_pattern "$HIGHLIGHTER" "final class BibTokenizer" "BibTeX tokenizer"
require_pattern "$HIGHLIGHTER" "case entryType" "BibTeX entry type token"
require_pattern "$HIGHLIGHTER" "case citationKey" "BibTeX citation key token"
require_pattern "$HIGHLIGHTER" "case fieldName" "BibTeX field token"
require_pattern "$HIGHLIGHTER" "case string" "BibTeX string token"
require_pattern "$HIGHLIGHTER" "bibEntryType" "BibTeX entry color"
require_pattern "$HIGHLIGHTER" "bibCitationKey" "BibTeX key color"
require_pattern "$HIGHLIGHTER" "bibFieldName" "BibTeX field color"
require_pattern "$HIGHLIGHTER" "bibString" "BibTeX string color"

require_pattern "$EDITOR" "syntaxMode" "editor syntax mode plumbing"
require_pattern "$EDITOR" "syntaxModeChanged" "syntax mode refresh"
require_pattern "$MAIN_VIEW" "editorSyntaxMode" "file extension syntax mode routing"
require_pattern "$MAIN_VIEW" 'case "bib"' "BibTeX file routing"

echo "PASS BibTeX highlighting"

