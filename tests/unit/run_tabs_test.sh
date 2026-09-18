#!/usr/bin/env bash
# Standalone TabStore unit test. Pure logic: no Hyprland, no session.
# Usage: ./run_tabs_test.sh   (from anywhere; resolves paths relative to itself)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SRC="$ROOT/native/ohmtabs"

CXX="${CXX:-g++}"
OUT="$HERE/tabs_store_test"

echo "== compiling $OUT =="
"$CXX" -std=c++20 -O2 -Wall -Wextra -Werror \
    -I"$SRC" \
    "$HERE/tabs_store_test.cpp" "$SRC/tabs.cpp" \
    -o "$OUT"

echo "== running =="
"$OUT"
