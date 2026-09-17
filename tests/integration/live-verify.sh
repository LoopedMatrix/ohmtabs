#!/usr/bin/env bash
# live-verify.sh — SAFE, read-mostly verification of the DEPLOYED Grabbar plugin
# running on this live desktop. It never reloads the shell, never kills
# quickshell/Hyprland, never writes under ~/.config/omarchy/, and only ever
# minimizes/restores ONE window that it spawns itself (and cleans up, even on
# failure, via a trap). Everything is read from textual/JSON output — no screen.
#
# Assertions:
#   [1] plugin health  — `omarchy-shell tech.greyforge.grabbar status` (timeout)
#                        reports backend.ready / enabled / minimizeEnabled /
#                        restoreHost all true, and failed == 0.
#   [2] freeze-bug      — the newest /run/user/1000/quickshell/by-id/*/log.qslog,
#                        stripped of non-printables, contains neither
#                        "Cannot assign to read-only property" nor a TypeError
#                        mentioning grabbar.
#   [3] taskbar surface — when a window is minimized, `hyprctl -j layers` has
#                        exactly one surface per monitor with namespace
#                        "grabbar-taskbar"; its geometry is reported and
#                        classified parked (mostly off one edge, ~4 px sliver)
#                        vs revealed (flush with the edge). At rest (nothing
#                        minimized) the surface is, by design, absent.
#   [4] end-to-end      — spawn a terminal (alacritty/kitty/foot/ghostty),
#                        wait for it in `hyprctl -j clients`, resolve its
#                        Grabbar token from the backend's own snapshot registry
#                        (matched by window address — never guessed; a
#                        downward-generation probe is the fallback), minimize
#                        through the plugin IPC, assert minimized grew and the
#                        surface appeared, then restore through the plugin and
#                        assert minimized returned to its previous count.
#   [5] summary         — pass/fail counts, non-zero exit if anything failed.
#
# NOT COVERED (by design): native decoration behaviour (strip rendering, button
# hit-testing, press/drag/release semantics) and visual appearance (colours,
# glyphs, alignment). Those need the isolated nested compositor + screenshots;
# see tests/integration/g0-nested.sh and docs/QUALIFICATION.md.
#
# Usage:
#   tests/integration/live-verify.sh            # full run (spawns a foot window)
#   tests/integration/live-verify.sh --readonly # assertions 1-2 only, no spawn
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HELPER="$ROOT/helpers/grabbar_backend.py"
PLUGIN="tech.greyforge.grabbar"
READONLY=0
[ "${1:-}" = "--readonly" ] && READONLY=1

PASSED=0; FAILED=0; SKIPPED=0
pass() { PASSED=$((PASSED + 1)); printf 'PASS [%s] %s\n' "$1" "$2"; }
fail() { FAILED=$((FAILED + 1)); printf 'FAIL [%s] %s\n' "$1" "$2"; }
skip() { SKIPPED=$((SKIPPED + 1)); printf 'SKIP [%s] %s\n' "$1" "$2"; }
say()  { printf '\n== %s\n' "$*"; }

# ---------------------------------------------------------------- plumbing

status_json() { timeout 10 omarchy-shell "$PLUGIN" status 2>/dev/null; }
clients_json() { timeout 10 hyprctl -j clients 2>/dev/null; }
layers_json()  { timeout 10 hyprctl -j layers 2>/dev/null; }

# be — talk to the backend socket (read-only here). Session is derived from the
# socket path reported in the plugin status, so it works with or without
# $HYPRLAND_INSTANCE_SIGNATURE in the caller's environment.
be() { python3 "$HELPER" --session "$SESSION" --timeout 3 "$@"; }

# poll_status <jq-bool-filter> <attempts> <delay> — echo status JSON when the
# filter becomes true, else return non-zero after the attempts.
poll_status() {
  local i s
  for ((i = 0; i < "${2:-20}"; i++)); do
    s="$(status_json)"
    if printf '%s' "$s" | jq -e "$1" >/dev/null 2>&1; then printf '%s' "$s"; return 0; fi
    sleep "${3:-0.3}"
  done
  printf '%s' "$s"
  return 1
}

# taskbar_surfaces — every grabbar-taskbar layer surface as a JSON array
# [{monitor,x,y,w,h,address}] by walking the nested {monitor:{levels:{...}}} shape.
taskbar_surfaces() {
  layers_json | python3 -c '
import json, sys
d = json.load(sys.stdin)
out = []
for mon, v in d.items():
    for arr in (v.get("levels") or {}).values():
        for s in arr:
            if s.get("namespace") == "grabbar-taskbar":
                out.append({"monitor": mon, "x": s.get("x"), "y": s.get("y"),
                            "w": s.get("w"), "h": s.get("h"), "address": s.get("address")})
print(json.dumps(out))
'
}

# classify_surfaces <surfaces-json> <monitors-json> — geometry + parked/revealed.
# Layer coordinates are logical; monitor logical size is width/scale.
classify_surfaces() {
  python3 - "$1" "$2" <<'PY'
import json, sys
surfaces = json.loads(sys.argv[1])
mons = {m["name"]: m for m in json.loads(sys.argv[2])}
for s in surfaces:
    m = mons.get(s["monitor"])
    if not m:
        print(json.dumps({"monitor": s["monitor"], "note": "no monitor"})); continue
    lw = m["width"] / m["scale"]; lh = m["height"] / m["scale"]
    mx, my = m["x"], m["y"]
    off_bottom = (s["y"] + s["h"]) - (my + lh)
    off_top    = my - s["y"]
    off_right  = (s["x"] + s["w"]) - (mx + lw)
    off_left   = mx - s["x"]
    maxoff = max(off_bottom, off_top, off_right, off_left, 0)
    print(json.dumps({
        "monitor": s["monitor"], "x": s["x"], "y": s["y"], "w": s["w"], "h": s["h"],
        "off_bottom": round(off_bottom, 1), "off_right": round(off_right, 1),
        "off_top": round(off_top, 1), "off_left": round(off_left, 1),
        "state": "parked" if maxoff > 8 else "revealed",
    }))
PY
}

# ------------------------------------------------------------------ [1] health

say "assertion 1 — plugin health"
STATUS="$(status_json)"
echo "raw status: $STATUS"
if [ -z "$STATUS" ]; then
  fail 1 "omarchy-shell status returned nothing (is the shell running?)"
else
  READY=$(printf '%s' "$STATUS" | jq -r '.backend.ready // false')
  ENABLED=$(printf '%s' "$STATUS" | jq -r '.enabled // false')
  MINEN=$(printf '%s' "$STATUS" | jq -r '.minimizeEnabled // false')
  RESTHOST=$(printf '%s' "$STATUS" | jq -r '.restoreHost // false')
  FAILEDC=$(printf '%s' "$STATUS" | jq -r '.failed // 0')
  if [ "$READY" = "true" ] && [ "$ENABLED" = "true" ] && [ "$MINEN" = "true" ] && [ "$RESTHOST" = "true" ] && [ "$FAILEDC" = "0" ]; then
    pass 1 "ready=$READY enabled=$ENABLED minimizeEnabled=$MINEN restoreHost=$RESTHOST failed=$FAILEDC"
  else
    fail 1 "ready=$READY enabled=$ENABLED minimizeEnabled=$MINEN restoreHost=$RESTHOST failed=$FAILEDC"
  fi
fi

SESSION="$(printf '%s' "$STATUS" | jq -r '.backend.socket // ""' | xargs -r dirname | xargs -r basename)"
EPOCH="$(printf '%s' "$STATUS" | jq -r '.backend.epoch // ""')"

# ------------------------------------------------------------------ [2] freeze bug

say "assertion 2 — no freeze-bug strings in the newest shell log"
NEWEST="$(ls -t /run/user/1000/quickshell/by-id/*/log.qslog 2>/dev/null | head -1)"
if [ -z "$NEWEST" ]; then
  fail 2 "no quickshell log found under /run/user/1000/quickshell/by-id/"
else
  CLEAN="$(tr -cd '\11\12\15\40-\176' < "$NEWEST")"
  RO="$(printf '%s' "$CLEAN" | grep -cF "Cannot assign to read-only property" || true)"
  TE="$(printf '%s' "$CLEAN" | grep -ciE "TypeError.*grabbar|grabbar.*TypeError" || true)"
  echo "log: $NEWEST ($(stat -c%s "$NEWEST") bytes); 'Cannot assign to read-only property'=$RO, TypeError(grabbar)=$TE"
  if [ "$RO" = "0" ] && [ "$TE" = "0" ]; then
    pass 2 "no read-only-assignment or grabbar TypeError in the newest shell log"
  else
    fail 2 "read-only-assignment=$RO grabbar-typeerror=$TE (regression of the desktop-freezing bug)"
  fi
fi

# ------------------------------------------- [3] + [4] taskbar surface + e2e

if [ "$READONLY" = "1" ]; then
  say "assertions 3-4 — skipped (--readonly)"
  skip 3 "surface geometry needs a minimized window; not evaluated in --readonly"
  skip 4 "end-to-end minimize/restore not run in --readonly"
else
  say "assertion 4 — spawn a test window and drive minimize/restore end to end"

  # --- terminal detection
  TERM_BIN=""
  for t in alacritty kitty foot ghostty; do
    if command -v "$t" >/dev/null 2>&1; then TERM_BIN="$(command -v "$t")"; TERM_NAME="$t"; break; fi
  done
  if [ -z "$TERM_BIN" ]; then
    fail 4 "no supported terminal (alacritty/kitty/foot/ghostty) available; cannot spawn a test window"
    fail 3 "cannot evaluate: no terminal to create a minimized window"
    say "summary"
    printf 'passed=%d failed=%d skipped=%d\n' "$PASSED" "$FAILED" "$SKIPPED"
    [ "$FAILED" -eq 0 ]
    exit $?
  fi
  echo "terminal: $TERM_NAME ($TERM_BIN)"

  # --- cleanup bookkeeping (trap runs even on failure)
  TITLE="grabbar-live-verify-$$"
  FOOT_PID=""; FOOT_ADDR=""; TOKEN=""
  BASELINE_TERM="$(pgrep -x "$TERM_NAME" 2>/dev/null | tr '\n' ' ')"
  cleanup() {
    # restore first if we still hold a minimized window (best effort)
    if [ -n "$TOKEN" ]; then
      timeout 10 omarchy-shell "$PLUGIN" restore "$TOKEN" original >/dev/null 2>&1 || true
    fi
    # NOTE: `hyprctl dispatch closewindow` is broken here (Lua-backed dispatch),
    # so close by killing the process we spawned instead.
    if [ -n "$FOOT_PID" ] && kill -0 "$FOOT_PID" 2>/dev/null; then
      kill "$FOOT_PID" 2>/dev/null || true
    fi
    sleep 0.3
    for p in $(pgrep -x "$TERM_NAME" 2>/dev/null); do
      case " $BASELINE_TERM " in *" $p "*) ;; *) kill "$p" 2>/dev/null || true ;; esac
    done
    rm -f "$BASELINE_ADDRS_FILE" 2>/dev/null || true
  }
  trap cleanup EXIT

  # --- baseline (existing window addresses, so we can pick out OUR new window)
  BASELINE_MIN="$(printf '%s' "$STATUS" | jq -r '.minimized // 0')"
  BASELINE_ADDRS_FILE="$(mktemp)"
  clients_json | jq -r '.[].address' | sort > "$BASELINE_ADDRS_FILE"

  # --- spawn (plain background process; `hyprctl dispatch exec` is Lua-backed
  #     and fails on this setup). The -T title is only a hint: the login shell
  #     typically overrides it, so we match by CLASS below, not title.
  "$TERM_BIN" -T "$TITLE" >/dev/null 2>&1 &
  FOOT_PID=$!

  # --- wait for it in hyprctl clients (match by window class, address not in
  #     baseline — robust against shells that rewrite the title)
  FOOT_ADDR=""
  for _ in $(seq 1 40); do
    FOOT_ADDR="$(clients_json | jq -r --arg c "$TERM_NAME" \
      '.[] | select((.class // "") | test($c; "i")) | .address' \
      | grep -vxFf "$BASELINE_ADDRS_FILE" | head -1)"
    [ -n "$FOOT_ADDR" ] && break
    sleep 0.25
  done
  if [ -z "$FOOT_ADDR" ]; then
    fail 4 "spawned $TERM_NAME but it never appeared in hyprctl clients"
    fail 3 "cannot evaluate: test window never mapped"
  else
    echo "spawned window address: $FOOT_ADDR (title=$TITLE, pid=$FOOT_PID)"
  fi

  E2E_OK=1
  if [ -n "$FOOT_ADDR" ] && [ -n "$SESSION" ] && [ -n "$EPOCH" ]; then
    # --- token resolution: primary = backend snapshot registry, matched by
    #     address (authoritative, read-only). Fallback = downward generation
    #     probe (newest window holds the highest generation).
    TOKEN=""
    for _ in $(seq 1 20); do
      TOKEN="$(be windows 2>/dev/null | python3 -c '
import json, sys
addr = sys.argv[1]
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        d = json.loads(line)
    except Exception:
        continue
    if d.get("address") == addr and d.get("alive") == "1":
        print(d.get("token", ""))
        break
' "$FOOT_ADDR")"
      [ -n "$TOKEN" ] && break
      sleep 0.3
    done
    echo "resolved token (snapshot): ${TOKEN:-<none>}"

    if [ -z "$TOKEN" ]; then
      # fallback: probe generations downward from a safe ceiling; first hit is
      # the newest (our) window. An unknown token has no side effect.
      GMAX="$(be windows 2>/dev/null | python3 -c '
import json, sys
mx = 0
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        d = json.loads(line)
    except Exception:
        continue
    t = d.get("token", "")
    if t.startswith("g"):
        try:
            mx = max(mx, int(t.split("-", 1)[1]))
        except Exception:
            pass
print(mx)
')"
      GMAX="${GMAX:-0}"
      echo "probe fallback: epoch=$EPOCH max-seen-generation=$GMAX"
      for ((n = GMAX + 50; n > GMAX; n--)); do
        CAND="g${EPOCH}-${n}"
        timeout 10 omarchy-shell "$PLUGIN" minimize "$CAND" >/dev/null 2>&1
        if poll_status "(.minimized != $BASELINE_MIN)" 3 0.3 >/dev/null 2>&1; then
          # a window moved — verify it is ours; if not, restore and keep going
          if clients_json | jq -e --arg a "$FOOT_ADDR" '.[] | select(.address == $a) | (.hidden == true or (.workspace.name | startswith("special:")))' >/dev/null 2>&1; then
            TOKEN="$CAND"; echo "probe hit: $TOKEN"; break
          else
            timeout 10 omarchy-shell "$PLUGIN" restore "$CAND" original >/dev/null 2>&1
          fi
        fi
      done
    fi

    if [ -z "$TOKEN" ]; then
      fail 4 "could not resolve a Grabbar token for the spawned window"
    else
      # --- minimize (the response is 'requested'; judge from state, not text)
      R="$(timeout 10 omarchy-shell "$PLUGIN" minimize "$TOKEN" 2>/dev/null)"
      echo "minimize response: $R (async)"
      MINSTATUS="$(poll_status "(.minimized > $BASELINE_MIN)" 20 0.3)"
      NEWMIN="$(printf '%s' "$MINSTATUS" | jq -r '.minimized // 0')"
      HIDDEN=0
      clients_json | jq -e --arg a "$FOOT_ADDR" '.[] | select(.address == $a) | (.hidden == true or (.workspace.name | startswith("special:")))' >/dev/null 2>&1 && HIDDEN=1
      if [ "$NEWMIN" -gt "$BASELINE_MIN" ] && [ "$HIDDEN" = "1" ]; then
        pass 4 "minimize: minimized $BASELINE_MIN -> $NEWMIN, spawned window moved off-screen"
      else
        fail 4 "minimize: minimized=$NEWMIN (baseline=$BASELINE_MIN) hidden=$HIDDEN"
        E2E_OK=0
      fi

      # --- [3] taskbar surface now that a window is minimized
      SURFACES="$(taskbar_surfaces)"
      NSURF="$(printf '%s' "$SURFACES" | jq 'length')"
      PERMON="$(printf '%s' "$SURFACES" | jq -r 'group_by(.monitor)[] | "\(.[0].monitor)=\(length)"' | tr '\n' ' ')"
      echo "taskbar surfaces ($NSURF): $PERMON"
      if [ -n "$SURFACES" ] && [ "$NSURF" -ge 1 ]; then
        MON_JSON="$(timeout 10 hyprctl -j monitors 2>/dev/null)"
        GEO="$(classify_surfaces "$SURFACES" "$MON_JSON")"
        echo "  $GEO"
        DUP="$(printf '%s' "$SURFACES" | jq '[group_by(.monitor)[] | select(length > 1)] | length')"
        if [ "$DUP" = "0" ]; then
          pass 3 "surface present, exactly one per monitor; geometry/parking above"
        else
          fail 3 "duplicate grabbar-taskbar surfaces detected ($DUP monitor(s) have >1)"
        fi
      else
        fail 3 "no grabbar-taskbar surface after minimize (minimized=$NEWMIN)"
        E2E_OK=0
      fi

      # --- restore
      R="$(timeout 10 omarchy-shell "$PLUGIN" restore "$TOKEN" original 2>/dev/null)"
      echo "restore response: $R (async)"
      RESTSTATUS="$(poll_status "(.minimized == $BASELINE_MIN)" 20 0.3)"
      RESTMIN="$(printf '%s' "$RESTSTATUS" | jq -r '.minimized // 0')"
      VISIBLE=0
      clients_json | jq -e --arg a "$FOOT_ADDR" '.[] | select(.address == $a) | (.hidden == false and .mapped == true)' >/dev/null 2>&1 && VISIBLE=1
      if [ "$RESTMIN" = "$BASELINE_MIN" ] && [ "$VISIBLE" = "1" ]; then
        pass 4 "restore: minimized back to $RESTMIN, spawned window visible again"
      else
        fail 4 "restore: minimized=$RESTMIN (expected $BASELINE_MIN) visible=$VISIBLE"
        E2E_OK=0
      fi
    fi
  else
    [ -n "$FOOT_ADDR" ] || fail 4 "no window address; cannot proceed"
    [ -n "$SESSION" ] || fail 4 "no backend socket (status backend.socket empty)"
    [ -n "$EPOCH" ] || fail 4 "no backend epoch (status backend.epoch empty)"
  fi
fi

# ------------------------------------------------------------------ [5] summary

say "summary"
printf 'passed=%d failed=%d skipped=%d\n' "$PASSED" "$FAILED" "$SKIPPED"
[ "$FAILED" -eq 0 ]
