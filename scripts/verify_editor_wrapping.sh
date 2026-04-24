#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
EDITOR_FILE="$ROOT_DIR/TEXnologia/Editor/LaTeXEditorView.swift"
HIGHLIGHTER_FILE="$ROOT_DIR/TEXnologia/Editor/LatexSyntaxHighlighter.swift"

required_editor_patterns=(
  "WrappingTextView"
  "LineNumberRulerView"
  "minGutterWidth: CGFloat"
  "NSColor.separatorColor"
  "textLeftInset: CGFloat"
  "hasVerticalRuler = true"
  "hasHorizontalScroller = false"
  "isHorizontallyResizable = false"
  "widthTracksTextView = true"
  "lineBreakMode = .byWordWrapping"
  "updateWrappingContainerWidth"
)

for pattern in "${required_editor_patterns[@]}"; do
  if ! grep -q "$pattern" "$EDITOR_FILE"; then
    echo "Missing editor wrapping setting: $pattern" >&2
    exit 1
  fi
done

if ! grep -q "paragraphStyle.lineBreakMode = .byWordWrapping" "$HIGHLIGHTER_FILE"; then
  echo "Missing highlighter paragraph wrapping style" >&2
  exit 1
fi

echo "PASS editor wrapping configuration"
