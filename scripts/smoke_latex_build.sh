#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENGINE="${ENGINE:-pdflatex}"
TEXLIVE_YEAR="${TEXLIVE_YEAR:-2024}"
TEXBIN=""
for candidate in \
  "/usr/local/texlive/$TEXLIVE_YEAR/bin/universal-darwin/$ENGINE" \
  "/usr/local/texlive/$TEXLIVE_YEAR/bin/x86_64-darwin/$ENGINE" \
  "/usr/local/texlive/$TEXLIVE_YEAR/bin/aarch64-darwin/$ENGINE" \
  "/Library/TeX/texbin/$ENGINE"; do
  if [[ -x "$candidate" ]]; then
    TEXBIN="$candidate"
    break
  fi
done

if [[ ! -x "$TEXBIN" ]]; then
  echo "Missing TeX engine for TeX Live $TEXLIVE_YEAR: $ENGINE" >&2
  exit 2
fi

run_case() {
  local project_dir="$1"
  local expect="$2"
  local root_tex="$project_dir/main.tex"
  local output_dir="$project_dir/.texnologia-build"

  rm -rf "$output_dir"
  mkdir -p "$output_dir"

  local status=0
  : > "$output_dir/stdout.log"
  for pass in 1 2 3; do
    status=0
    (
      cd "$project_dir"
      "$TEXBIN" \
        -interaction=nonstopmode \
        -file-line-error \
        -synctex=1 \
        -no-shell-escape \
        "-output-directory=$output_dir" \
        "main.tex" >> "$output_dir/stdout.log" 2>&1
    ) || status=$?

    if [[ "$expect" == "failure" || "$status" -ne 0 ]]; then
      break
    fi

    if ! grep -qE "Rerun to get cross-references right|Label\\(s\\) may have changed|undefined references" "$output_dir/stdout.log" "$output_dir/main.log" 2>/dev/null; then
      break
    fi
  done

  if [[ "$expect" == "success" ]]; then
    if [[ "$status" -ne 0 ]]; then
      echo "FAIL expected success: $project_dir" >&2
      tail -80 "$output_dir/stdout.log" >&2
      exit 1
    fi
    if [[ ! -s "$output_dir/main.pdf" ]]; then
      echo "FAIL missing PDF: $project_dir" >&2
      exit 1
    fi
    echo "PASS success: $project_dir"
    rm -rf "$output_dir"
  else
    if [[ "$status" -eq 0 ]]; then
      echo "FAIL expected failure: $project_dir" >&2
      exit 1
    fi
    if ! grep -q "Undefined control sequence" "$output_dir/stdout.log" "$output_dir/main.log"; then
      echo "FAIL expected undefined-control-sequence log: $project_dir" >&2
      tail -80 "$output_dir/stdout.log" >&2
      exit 1
    fi
    echo "PASS failure detected: $project_dir"
    rm -rf "$output_dir"
  fi
}

run_case "$ROOT_DIR/Tests/Fixtures/LaTeXProjects/001-basic-article" success
run_case "$ROOT_DIR/Tests/Fixtures/LaTeXProjects/012 path 한글 edge" success
run_case "$ROOT_DIR/Tests/Fixtures/LaTeXProjects/007-invalid-syntax" failure
