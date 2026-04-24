#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

require_pattern() {
  local file="$1"
  local pattern="$2"
  local label="$3"

  if ! grep -q "$pattern" "$ROOT_DIR/$file"; then
    echo "FAIL missing $label in $file: $pattern" >&2
    exit 1
  fi
}

require_pattern "TEXnologia/App/AppModel.swift" "isEditableTextFile" "text file routing"
require_pattern "TEXnologia/App/AppModel.swift" '"json"' "JSON routing"
require_pattern "TEXnologia/App/AppModel.swift" "prettyPrintedJSONIfPossible" "JSON pretty print"
require_pattern "TEXnologia/App/AppModel.swift" "case \"pdf\"" "PDF routing"
require_pattern "TEXnologia/App/AppModel.swift" "case \"png\", \"jpg\", \"jpeg\"" "image routing"

require_pattern "TEXnologia/App/MainWindowView.swift" "CenterPaneView" "center pane dispatcher"
require_pattern "TEXnologia/App/MainWindowView.swift" "PDFPaneView(documentURL: url)" "center PDF rendering"
require_pattern "TEXnologia/App/MainWindowView.swift" "ImagePreviewPane" "image preview pane"
require_pattern "TEXnologia/App/MainWindowView.swift" "Open Externally" "external open action"
require_pattern "TEXnologia/App/MainWindowView.swift" "Reveal in Finder" "finder reveal action"

require_pattern "TEXnologia/IssueNavigator/IssueNavigatorView.swift" "IssueDockView" "collapsed issue dock"
require_pattern "TEXnologia/IssueNavigator/IssueNavigatorView.swift" "Show Issues" "manual issue expansion"
require_pattern "TEXnologia/IssueNavigator/IssueNavigatorView.swift" "Raw Log" "manual raw log disclosure"
require_pattern "TEXnologia/IssueNavigator/IssueNavigatorView.swift" "Jump to Source" "issue source jump"
require_pattern "TEXnologia/App/MainWindowView.swift" "issuePanelExpanded ? 260 : 36" "collapsed issue panel height"

require_pattern "TEXnologia/App/TEXnologiaApp.swift" "toggleFullScreen" "full screen shortcut"
require_pattern "TEXnologia/App/TEXnologiaApp.swift" ".command, .control" "Control-Command-F shortcut"

require_pattern "TEXnologia/Preferences/PreferencesView.swift" "TabView" "preferences tabs"
require_pattern "TEXnologia/App/AppModel.swift" "SettingsStore.save" "settings persistence"
require_pattern "Package.swift" "TEXnologia" "renamed executable product"
require_pattern "scripts/build_app_bundle.sh" "TEXnologia.app" "renamed app bundle"
require_pattern "TEXnologia/App/MainWindowView.swift" "TEXnologia" "renamed visible app title"
require_pattern "TEXnologia/BuildSystem/BuildConfiguration.swift" ".texnologia-build" "renamed build directory"

require_pattern "TEXnologia/Editor/LatexSyntaxHighlighter.swift" "isSpellCheckExcluded" "LaTeX spellcheck exclusion test"
require_pattern "TEXnologia/Editor/LaTeXEditorView.swift" "shouldSetSpellingState" "LaTeX spellcheck veto"
require_pattern "TEXnologia/Editor/LaTeXEditorView.swift" "setSpellingState(0" "clearing LaTeX spelling markers"
require_pattern "TEXnologia/Editor/LaTeXEditorView.swift" "CheckingType.grammar" "English grammar checking"
require_pattern "TEXnologia/Editor/LatexSyntaxHighlighter.swift" "latexOnlyCommandNames" "citation/reference spellcheck filtering"

echo "PASS feature contracts"
