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
require_pattern "TEXnologia/App/AppModel.swift" "isGeneratedTextPreviewFile" "generated file preview routing"
require_pattern "TEXnologia/App/AppModel.swift" "loadReadOnlyPreview" "read-only generated file preview"
require_pattern "TEXnologia/App/AppModel.swift" "maxEditableBytes" "large editable file guard"
require_pattern "TEXnologia/App/AppModel.swift" '"sty"' "sty remains editable"
require_pattern "TEXnologia/App/AppModel.swift" '"bib"' "bib remains editable"
require_pattern "TEXnologia/App/AppModel.swift" '"log", "aux", "bbl", "blg", "toc", "out", "fls"' "generated extensions are preview-only"
require_pattern "TEXnologia/App/AppModel.swift" '"json"' "JSON routing"
require_pattern "TEXnologia/App/AppModel.swift" "prettyPrintedJSONIfPossible" "JSON pretty print"
require_pattern "TEXnologia/App/AppModel.swift" "case \"pdf\"" "PDF routing"
require_pattern "TEXnologia/App/AppModel.swift" "case \"png\", \"jpg\", \"jpeg\"" "image routing"

require_pattern "TEXnologia/App/MainWindowView.swift" "CenterPaneView" "center pane dispatcher"
require_pattern "TEXnologia/App/MainWindowView.swift" "CompileOptionsControl" "attached compile options control"
require_pattern "TEXnologia/App/MainWindowView.swift" "compileBlue" "muted blue compile button"
require_pattern "TEXnologia/App/MainWindowView.swift" ".frame(width: 109)" "compact compile control"
require_pattern "TEXnologia/App/MainWindowView.swift" "Button(\"Compile\"" "compile button wording"
require_pattern "TEXnologia/App/MainWindowView.swift" "Compile Settings" "compile settings dropdown tooltip"
require_pattern "TEXnologia/App/MainWindowView.swift" "Section(\"Engine\")" "compile dropdown engine section"
require_pattern "TEXnologia/App/MainWindowView.swift" "Section(\"TeX Live Year\")" "compile dropdown TeX year section"
require_pattern "TEXnologia/App/MainWindowView.swift" "settings.defaultEngine = engine" "compile dropdown engine persistence"
require_pattern "TEXnologia/App/MainWindowView.swift" "settings.toolchainYear = year" "compile dropdown year persistence"
require_pattern "TEXnologia/App/MainWindowView.swift" "HistoryPopover" "history popover"
require_pattern "TEXnologia/App/MainWindowView.swift" "clock.arrow.circlepath" "history icon button"
require_pattern "TEXnologia/App/MainWindowView.swift" "square.and.arrow.down" "PDF export icon button"
require_pattern "TEXnologia/App/MainWindowView.swift" "Export PDF" "PDF export tooltip"
require_pattern "TEXnologia/App/AppModel.swift" "exportFocusedPDF" "focused PDF export action"
require_pattern "TEXnologia/App/AppModel.swift" "NSSavePanel" "PDF export save panel"
require_pattern "TEXnologia/App/MainWindowView.swift" "RightPreviewPane" "right preview pane"
require_pattern "TEXnologia/App/MainWindowView.swift" "VSplitView" "split preview pane"
require_pattern "TEXnologia/App/MainWindowView.swift" "@Binding var isSplit" "preview-local split control"
require_pattern "TEXnologia/Core/CoreModels.swift" "PreviewPaneID" "preview pane focus model"
require_pattern "TEXnologia/App/AppModel.swift" "focusedPreviewPane" "focused preview pane state"
require_pattern "TEXnologia/App/AppModel.swift" "showInFocusedPreview" "focused preview routing"
require_pattern "TEXnologia/App/MainWindowView.swift" "focusedPane" "preview focus binding"
require_pattern "TEXnologia/App/MainWindowView.swift" "Color.orange" "focused preview orange indicator"
require_pattern "TEXnologia/App/MainWindowView.swift" ".stroke(isFocused ? Color.orange" "focused preview border"
require_pattern "TEXnologia/App/MainWindowView.swift" "GeometryReader" "responsive welcome layout"
require_pattern "TEXnologia/App/MainWindowView.swift" "ScrollView(.vertical)" "welcome overflow protection"
require_pattern "TEXnologia/App/MainWindowView.swift" "compact(proxy)" "compact welcome sizing"
require_pattern "TEXnologia/ProjectIndexing/ProjectSidebarView.swift" "ProjectSessionsSidebarView" "multi-session explorer"
require_pattern "TEXnologia/App/MainWindowView.swift" "SessionTabBar" "session tab bar"
require_pattern "TEXnologia/App/MainWindowView.swift" "New Session" "new session button"
require_pattern "TEXnologia/ProjectIndexing/ProjectSidebarView.swift" "Use as Main File" "main file context menu"
require_pattern "TEXnologia/ProjectIndexing/ProjectSidebarView.swift" "InlineRenameTextField" "inline explorer rename"
require_pattern "TEXnologia/ProjectIndexing/ProjectSidebarView.swift" "ExplorerKeyboardMonitor" "explorer keyboard shortcuts"
require_pattern "TEXnologia/ProjectIndexing/ProjectSidebarView.swift" "deletePermanently" "actual filesystem delete"
require_pattern "TEXnologia/App/AppModel.swift" "saveSelectedFileAndBuildIfNeeded" "command-s compile on save"
require_pattern "TEXnologia/App/TEXnologiaApp.swift" "Save and Compile" "save menu compile wording"
require_pattern "TEXnologia/App/MainWindowView.swift" "appModel.openProjectPanel" "welcome/menu open action remains"
if grep -q 'Label("Open"' "$ROOT_DIR/TEXnologia/App/MainWindowView.swift"; then
  echo "FAIL toolbar Open button should not be present" >&2
  exit 1
fi
if grep -q 'Label("Zip"' "$ROOT_DIR/TEXnologia/App/MainWindowView.swift"; then
  echo "FAIL toolbar Zip button should not be present" >&2
  exit 1
fi
require_pattern "TEXnologia/App/MainWindowView.swift" "ReadOnlyTextPreviewPane" "read-only text preview pane"
require_pattern "TEXnologia/App/MainWindowView.swift" "doc.text.magnifyingglass" "generated text preview icon"
require_pattern "TEXnologia/App/MainWindowView.swift" "PDFPaneView(documentURL: url)" "center PDF rendering"
require_pattern "TEXnologia/App/MainWindowView.swift" "ImagePreviewPane" "image preview pane"
require_pattern "TEXnologia/App/MainWindowView.swift" "Open Externally" "external open action"
require_pattern "TEXnologia/App/MainWindowView.swift" "Reveal in Finder" "finder reveal action"

require_pattern "TEXnologia/IssueNavigator/IssueNavigatorView.swift" "IssueDockView" "collapsed issue dock"
require_pattern "TEXnologia/IssueNavigator/IssueNavigatorView.swift" "Show Issues" "manual issue expansion"
require_pattern "TEXnologia/IssueNavigator/IssueNavigatorView.swift" "Raw Log" "manual raw log disclosure"
require_pattern "TEXnologia/IssueNavigator/IssueNavigatorView.swift" "Jump to Source" "issue source jump"
require_pattern "TEXnologia/App/MainWindowView.swift" "shouldShowIssueDock" "issue dock hidden when no actionable issues"
require_pattern "TEXnologia/App/MainWindowView.swift" "issuePanelExpanded ? 260 : 36" "collapsed issue panel height"
require_pattern "TEXnologia/App/MainWindowView.swift" ".clipped()" "issue dock clipping guard"

require_pattern "TEXnologia/App/TEXnologiaApp.swift" "toggleFullScreen" "full screen shortcut"
require_pattern "TEXnologia/App/TEXnologiaApp.swift" ".command, .control" "Control-Command-F shortcut"

require_pattern "TEXnologia/Preferences/PreferencesView.swift" "TabView" "preferences tabs"
require_pattern "TEXnologia/App/AppModel.swift" "SettingsStore.save" "settings persistence"
require_pattern "Package.swift" "TEXnologia" "renamed executable product"
require_pattern "scripts/build_app_bundle.sh" "TEXnologia.app" "renamed app bundle"
require_pattern "TEXnologia/App/MainWindowView.swift" "TEXnologia" "renamed visible app title"
require_pattern "TEXnologia/BuildSystem/BuildConfiguration.swift" ".texnologia-build" "renamed build directory"
require_pattern "TEXnologia/BuildSystem/BuildConfiguration.swift" "TexToolchainYear" "TeX Live year model"
require_pattern "TEXnologia/BuildSystem/BuildConfiguration.swift" "texLive2024" "default TeX Live 2024 support"
require_pattern "TEXnologia/BuildSystem/BuildConfiguration.swift" "texLive2025" "TeX Live 2025 support"
require_pattern "TEXnologia/Preferences/AppSettings.swift" "toolchainYear: .texLive2024" "default pdflatex 2024 setting"
require_pattern "TEXnologia/BuildSystem/LatexBuildService.swift" "/usr/local/texlive/" "year-specific TeX path lookup"

require_pattern "TEXnologia/Editor/LatexSyntaxHighlighter.swift" "isSpellCheckExcluded" "LaTeX spellcheck exclusion test"
require_pattern "TEXnologia/Editor/LaTeXEditorView.swift" "shouldSetSpellingState" "LaTeX spellcheck veto"
require_pattern "TEXnologia/Editor/LaTeXEditorView.swift" "setSpellingState(0" "clearing LaTeX spelling markers"
require_pattern "TEXnologia/Editor/LaTeXEditorView.swift" "CheckingType.grammar" "English grammar checking"
require_pattern "TEXnologia/Editor/LatexSyntaxHighlighter.swift" "latexOnlyCommandNames" "citation/reference spellcheck filtering"
require_pattern "TEXnologia/Editor/LatexSyntaxHighlighter.swift" "BibTokenizer" "BibTeX syntax highlighting"
require_pattern "TEXnologia/Editor/LatexSyntaxHighlighter.swift" "applyCommentTokensLast" "comment highlighting precedence"
require_pattern "TEXnologia/Editor/LatexSyntaxHighlighter.swift" "overlapsCommentRange" "comment overlap guard"
require_pattern "TEXnologia/Editor/LaTeXEditorView.swift" "LineNumberRulerView" "editor line numbers"
require_pattern "TEXnologia/Editor/LaTeXEditorView.swift" "hasVerticalRuler = true" "line number ruler enabled"
require_pattern "TEXnologia/App/MainWindowView.swift" "editorSyntaxMode" "extension-based syntax routing"

echo "PASS feature contracts"
