#!/usr/bin/env bash
# build.sh — build the virtual-pointer tool (vpointer) used by the nested-compositor
# integration tests to inject pointer events through zwlr_virtual_pointer_v1.
#
# The vpointer binary is gitignored (tests/integration/vpointer/vpointer) so it
# is NOT shipped in the tree. Every test that uses it MUST build it first, and
# MUST verify the binary exists before invoking it — otherwise every pointer
# command silently no-ops with "No such file or directory" and the cursor never
# moves.
#
# Idempotent: safe to run more than once. Fails loudly if the source or the
# build dependencies are missing.
set -euo pipefail

VP_DIR="$(cd "$(dirname "$0")" && pwd)"
VP_BIN="$VP_DIR/vpointer"
VP_SRC="$VP_DIR/vpointer.c"
PROTO_C="$VP_DIR/wlr-virtual-pointer-unstable-v1-protocol.c"
PROTO_H="$VP_DIR/wlr-virtual-pointer-unstable-v1-client-protocol.h"
ROOT="$(cd "$VP_DIR/../.." && pwd)"

# --- sanity: source files must exist (they are committed, not gitignored) ---
for f in "$VP_SRC" "$PROTO_C" "$PROTO_H"; do
  if [ ! -f "$f" ]; then
    echo "BUILD vpointer: MISSING SOURCE $f — git checkout incomplete?" >&2
    exit 1
  fi
done

# --- no-op if the binary is already fresh ---
if [ -x "$VP_BIN" ] && [ "$VP_BIN" -nt "$VP_SRC" ] && [ "$VP_BIN" -nt "$PROTO_C" ]; then
  echo "BUILD vpointer: binary already up-to-date ($VP_BIN)"
  exit 0
fi

# --- check build dependencies ---
if ! command -v cc >/dev/null 2>&1; then
  echo "BUILD vpointer: cc not found — install a C compiler" >&2
  exit 1
fi

if ! pkg-config --exists wayland-client 2>/dev/null; then
  echo "BUILD vpointer: pkg-config cannot find wayland-client — install libwayland-dev" >&2
  exit 1
fi

WAYLAND_CFLAGS=$(pkg-config --cflags --libs wayland-client) || {
  echo "BUILD vpointer: pkg-config wayland-client failed" >&2
  exit 1
}

echo "BUILD vpointer: cc -O2 -o $VP_BIN $VP_SRC $PROTO_C $WAYLAND_CFLAGS"
cc -O2 -o "$VP_BIN" "$VP_SRC" "$PROTO_C" $WAYLAND_CFLAGS || {
  echo "BUILD vpointer: cc FAILED (exit $?) — see above" >&2
  exit 1
}

# --- verify the binary exists and is executable ---
if [ ! -x "$VP_BIN" ]; then
  echo "BUILD vpointer: binary not found after build ($VP_BIN)" >&2
  exit 1
fi
# A bare invocation prints usage and exits 2 (correct). Exit 0 would also
# be acceptable. Exit 1 means it could not connect to a Wayland display,
# which is expected when there is no nested session running. We only need
# to confirm the ELF actually executes; any other non-zero exit is a real
# problem with the binary.
set +eo pipefail
"$VP_BIN" >/dev/null 2>&1
RC=$?
set -eo pipefail
if [ "$RC" -ne 0 ] && [ "$RC" -ne 2 ]; then
  echo "BUILD vpointer: binary built but exited $RC on bare invocation (expected 0 or 2)" >&2
  exit 1
fi
echo "BUILD vpointer: OK ($VP_BIN)"
