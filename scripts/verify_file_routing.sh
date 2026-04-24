#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_MODEL="$ROOT_DIR/TEXnologia/App/AppModel.swift"
MAIN_VIEW="$ROOT_DIR/TEXnologia/App/MainWindowView.swift"
CORE_MODELS="$ROOT_DIR/TEXnologia/Core/CoreModels.swift"
FIXTURES="$ROOT_DIR/Tests/Fixtures/FileRouting"

require_pattern() {
  local file="$1"
  local pattern="$2"
  local label="$3"

  if ! grep -q "$pattern" "$file"; then
    echo "FAIL missing $label in $file: $pattern" >&2
    exit 1
  fi
}

require_file() {
  local file="$1"
  if [[ ! -s "$file" ]]; then
    echo "FAIL missing fixture $file" >&2
    exit 1
  fi
}

require_file "$FIXTURES/sample.sty"
require_file "$FIXTURES/sample.log"
require_file "$FIXTURES/sample.out"

require_pattern "$APP_MODEL" '"sty"' "editable style file routing"
require_pattern "$APP_MODEL" "isGeneratedTextPreviewFile" "generated text routing branch"
require_pattern "$APP_MODEL" '"log", "aux", "bbl", "blg", "toc", "out", "fls"' "preview-only generated extension list"
require_pattern "$APP_MODEL" "maxPreviewBytes" "bounded preview read"
require_pattern "$APP_MODEL" "readPrefix" "partial read for large files"
require_pattern "$APP_MODEL" "looksBinary" "binary guard"
require_pattern "$APP_MODEL" "editorFileURL" "dedicated editor file state"
require_pattern "$APP_MODEL" "prepareEditorForPreviewSelection" "source editor restoration before preview routing"
require_pattern "$APP_MODEL" "if case .image = presentation" "image routes through preview path"
require_pattern "$APP_MODEL" "if case .pdf(let url) = presentation" "PDF routes through preview path"
require_pattern "$APP_MODEL" "try editorText.write(to: editorFileURL" "saving uses editor file instead of selected preview"

require_pattern "$CORE_MODELS" "TextFilePreview" "read-only preview model"
require_pattern "$CORE_MODELS" "readOnlyText" "read-only presentation case"
require_pattern "$MAIN_VIEW" "ReadOnlyTextPreviewPane" "read-only preview UI"
require_pattern "$MAIN_VIEW" "textSelection(.enabled)" "copyable preview text"
require_pattern "$MAIN_VIEW" "editorFileURL: appModel.editorFileURL" "center pane gets editor file state"
require_pattern "$MAIN_VIEW" "syntaxMode: editorFileURL?.editorSyntaxMode" "syntax mode remains tied to editor source"
require_pattern "$MAIN_VIEW" "max(proxy.size.width - 40" "large image previews are pane-constrained"
require_pattern "$MAIN_VIEW" ".fixedSize(horizontal: false, vertical: false)" "image preview avoids window resize pressure"

echo "PASS file routing safety"
