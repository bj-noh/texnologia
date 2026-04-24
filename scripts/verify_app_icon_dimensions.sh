#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ICONSET_DIR="$ROOT_DIR/dist/AppIcon.iconset"

if [[ ! -d "$ICONSET_DIR" ]]; then
  echo "Missing iconset directory. Run scripts/build_app_bundle.sh first." >&2
  exit 1
fi

check_size() {
  local file="$1"
  local expected="$2"
  local actual
  actual="$(sips -g pixelWidth -g pixelHeight "$ICONSET_DIR/$file" 2>/dev/null | awk '/pixelWidth|pixelHeight/ {print $2}' | paste -sd x -)"
  if [[ "$actual" != "${expected}x${expected}" ]]; then
    echo "FAIL $file expected ${expected}x${expected}, got $actual" >&2
    exit 1
  fi
}

check_size "icon_16x16.png" 16
check_size "icon_16x16@2x.png" 32
check_size "icon_32x32.png" 32
check_size "icon_32x32@2x.png" 64
check_size "icon_128x128.png" 128
check_size "icon_128x128@2x.png" 256
check_size "icon_256x256.png" 256
check_size "icon_256x256@2x.png" 512
check_size "icon_512x512.png" 512
check_size "icon_512x512@2x.png" 1024

echo "PASS app icon dimensions"

