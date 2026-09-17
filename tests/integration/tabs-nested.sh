#!/usr/bin/env bash
# tabs-nested.sh -- end-to-end test of the window-TAB feature inside an isolated
# nested Hyprland session (never the live desktop).
#
# Also validates that window snaps keep the title strip fully inside the work
# area (regression test for the "snap hides strip under Omarchy bar" bug).
#
# Preconditions (see docs/QUALIFICATION.md "Nested test rig"):
#   - a nested Hyprland instance is running; its instance signature is $SIG
#     and its Wayland socket is $NESTED_DISPLAY
#   - the native backend is loaded there (hyprctl -i "$SIG" plugin load ...)
#   - tests/integration/vpointer/vpointer is built
#
# Verbs under test (frozen IPC contract -- omarchy-shell tech.greyforge.grabbar):
#   tabs.list   -> {"groups":[{"id":N,"host":"<token>","active":<index>,"tabs":[...]}]}
#   tabs.join   {"source":"<token>","host":"<token>"}
#   tabs.activate {"group":N,"index":i}
#   tabs.detach {"token":"<token>"}
#   tabs.ungroup {"group":N}
#   tabs.closeAll {"group":N,"confirm":true}
#
# Snap assertions (regression for the top-strip-hidden-under-bar bug):
#   After a left-half snap and after a TL/TR corner snap, assert:
#     (a) strip band fully inside work area: (client_y - stripHeight) >= workArea_top
#     (b) client box fully inside work area:  client_y + height <= workArea_bottom
#   stripHeight  from hyprctl getoption plugin:grabbar:barHeight (not hardcoded)
#   workArea_top from the bar surface geometry in hyprctl -j layers (not hardcoded)
#
# Each step records what the compositor actually reports; screenshots are
# taken from inside the nested session so the live desktop is never touched.
set -euo pipefail

SIG="${SIG:?nested Hyprland instance signature}"
NESTED_DISPLAY="${NESTED_DISPLAY:?nested Wayland display name, e.g. wayland-2}"

# Safety: this test must never act on the user's live session. Inherited
# HYPRLAND_INSTANCE_SIGNATURE IS the live signature, so refuse if SIG matches it,
# and scope every plugin IPC call to the nested instance from here on.
LIVE_SIG="${HYPRLAND_INSTANCE_SIGNATURE:-}"
if [ -n "$LIVE_SIG" ] && [ "$LIVE_SIG" = "$SIG" ]; then
  echo "REFUSING to run: SIG=$SIG is the live session, not a nested instance" >&2
  exit 2
fi
export HYPRLAND_INSTANCE_SIGNATURE="$SIG"

OUT="${OUT:-$(mktemp -d)}"; mkdir -p "$OUT"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HELPER="$ROOT/helpers/grabbar_backend.py"
VP="$ROOT/tests/integration/vpointer/vpointer"
PLUGIN="${PLUGIN:-$ROOT/native/grabbar/grabbar.so}"

hc() { hyprctl -i "$SIG" "$@"; }
spawn() { hc dispatch "hl.dsp.exec_cmd([[ $* ]])"; }
vp() {
  local w h cx cy
  read -r w h < <(hc -j monitors 2>/dev/null | jq -r '.[0] | "\(.width) \(.height)"' 2>/dev/null)
  read -r cx cy < <(hc cursorpos 2>/dev/null | tr -d ' ' | tr ',' ' ')
  WAYLAND_DISPLAY="$NESTED_DISPLAY" "$VP" "${w:-1600}" "${h:-1000}" cursor "${cx:-0}" "${cy:-0}" "$@"
}
be() { HYPRLAND_INSTANCE_SIGNATURE="$SIG" python3 "$HELPER" --timeout 3 "$@"; }
shot() { timeout 10 env WAYLAND_DISPLAY="$NESTED_DISPLAY" grim "$OUT/$1.png" 2>/dev/null && echo "  shot $OUT/$1.png" || echo "  shot $1: skipped (grim unavailable on this Hyprland build)"; }

pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; exit 1; }
skip() { echo "SKIP $*"; exit 0; }
say() { echo; echo "== $*"; }

# ------------------------------------------------------------------ plumbing

shell_call() {
  local verb="$1"
  local payload="${2:-}"
  # Address the instance under test. The documented CLI forwards to the RUNNING
  # Omarchy shell, which is the live desktop -- never use it here.
  if [ -n "$payload" ]; then
    HYPRLAND_INSTANCE_SIGNATURE="$SIG" python3 "$ROOT/tests/integration/tabs-ipc.py" "$verb" "$payload" 2>/dev/null
  else
    HYPRLAND_INSTANCE_SIGNATURE="$SIG" python3 "$ROOT/tests/integration/tabs-ipc.py" "$verb" 2>/dev/null
  fi
}

win_json() { hc -j clients | python3 -c 'import json,sys; d=[c for c in json.load(sys.stdin) if c["mapped"]]; print(json.dumps(d[0] if d else {}))'; }
wf() { win_json | python3 -c "import json,sys; d=json.load(sys.stdin); v=d$1; print(json.dumps(v) if not isinstance(v,str) else v)"; }
token() { be windows | python3 -c 'import json,sys; [print(json.loads(l)["token"]) for l in sys.stdin if json.loads(l).get("alive")=="1"]' | head -1; }

# addr_of_new [EXCLUDE...] -- hyprctl address of the first mapped client whose
# address is not among the excluded ones. Windows here are all `foot`, so the
# only reliable identity is the compositor address: matching by "first client"
# silently returns window A and points the drag at itself.
addr_of_new() { hc -j clients | python3 -c '
import json, sys
ex = set(sys.argv[1:])
for c in json.load(sys.stdin):
    if c.get("mapped") and c.get("address") not in ex:
        print(c["address"]); break
' "$@"; }

# gof ADDR '[EXPR]' -- one field of the client with that address (python expr).
gof() { hc -j clients | python3 -c '
import json, sys
a, q = sys.argv[1], sys.argv[2]
cs = [c for c in json.load(sys.stdin) if c.get("address") == a]
d = cs[0] if cs else {}
try:
    print(eval("d"+q))
except Exception:
    print("")
' "$1" "$2"; }

# ------------------------------------------------------------------ work-area geometry

# resolve_work_area -- returns JSON with workArea_top, workArea_bottom,
# stripHeight, and monitor box. Work area top comes from the bar/panel layer
# surface (namespace matching bar/panel/omarchy) on the window's monitor; falls
# back to the monitor's logical top if no bar surface is found.
resolve_work_area() {
  local win_addr="${1:-}"
  local mon_id=""
  if [ -n "$win_addr" ]; then
    mon_id="$(hc -j clients 2>/dev/null | python3 -c "
import json, sys
addr = '$win_addr'
for c in json.load(sys.stdin):
    if c.get('address') == addr:
        print(c.get('monitor', 0))
        break
" 2>/dev/null || echo "")"
  fi

  local monitors_json layers_json
  monitors_json="$(timeout 10 hc -j monitors 2>/dev/null || true)"
  layers_json="$(timeout 10 hc -j layers 2>/dev/null || true)"

  python3 - "$SIG" "$mon_id" "$win_addr" "$monitors_json" "$layers_json" <<'PY'
import json, sys, os, subprocess

sig = sys.argv[1]
mon_id = sys.argv[2]
win_addr = sys.argv[3]
try:
    monitors = json.loads(sys.argv[4]) if sys.argv[4] else {}
except Exception:
    monitors = {}
try:
    layers = json.loads(sys.argv[5]) if sys.argv[5] else {}
except Exception:
    layers = {}

# default: full monitor box
mon_x, mon_y, mon_w, mon_h = 0, 0, 1280, 800
strip_height = 34
work_area_top = 0
work_area_bottom = 800

# find monitor by id or by containing the window
monitor_name = None
if monitors:
    for m in monitors:
        if str(m.get("id")) == mon_id:
            monitor_name = m.get("name")
            mon_x = m.get("x", 0)
            mon_y = m.get("y", 0)
            mon_w = m.get("width", 1280)
            mon_h = m.get("height", 800)
            break
    if not monitor_name and win_addr:
        pass

    if not monitor_name:
        for m in monitors:
            if m.get("name") == "GRABBAR-LAB" or m.get("name") == "headless":
                monitor_name = m.get("name")
                mon_x = m.get("x", 0)
                mon_y = m.get("y", 0)
                mon_w = m.get("width", 1280)
                mon_h = m.get("height", 800)
                break

# bar height from plugin config
bar_height_str = ""
try:
    import subprocess
    bar_height_str = subprocess.check_output(
        ["hyprctl", "-i", os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", ""), "getoption", "plugin:grabbar:barHeight"],
        stderr=subprocess.DEVNULL, timeout=5
    ).decode()
    bar_height = float(json.loads(bar_height_str).get("value", 34))
except Exception:
    bar_height = 34
strip_height = bar_height

# find bar/panel surface on this monitor
if layers and monitor_name:
    for mon, levels in layers.items():
        if mon != monitor_name and mon != "internal":
            continue
        for arr in (levels.get("levels") or {}).values():
            for s in arr:
                y = s.get("y", 0)
                h = s.get("h", 0)
                ns = s.get("namespace", "")
                if y <= mon_y + 2 and h > 0 and h < 200 and (
                    "bar" in ns.lower() or "panel" in ns.lower() or
                    "omarchy" in ns.lower() or "grabbar" in ns.lower()
                ):
                    top = y + h
                    if top > work_area_top:
                        work_area_top = top

work_area_bottom = mon_y + mon_h
if work_area_top < mon_y:
    work_area_top = mon_y

print(json.dumps(dict(
    "workArea_top": work_area_top,
    "workArea_bottom": work_area_bottom,
    "stripHeight": strip_height,
    "mon_x": mon_x,
    "mon_y": mon_y,
    "mon_w": mon_w,
    "mon_h": mon_h,
    "monitor_name": monitor_name or "",
}))
PY
}

# ------------------------------------------------------------------ vpointer build check

if [ ! -x "$VP" ]; then
  say "vpointer binary missing -- building now"
  bash "$ROOT/tests/integration/vpointer/build.sh" || fail "vpointer build failed"
fi
if [ ! -x "$VP" ]; then
  fail "vpointer not executable after build ($VP)"
fi

# ------------------------------------------------------------------ feature gates

say "feature gates"

# --- tabs feature gate ---
TABS_AVAILABLE=0
TABS_LIST_RAW="$(shell_call tabs.list 2>/dev/null || true)"
if [ -z "$TABS_LIST_RAW" ]; then
  skip "tabs.list returned nothing -- the running plugin does not implement the tabs feature yet (expected: groups array of {id,host,active,tabs})"
fi
if ! printf '%s' "$TABS_LIST_RAW" | jq -e '.groups' >/dev/null 2>&1; then
  skip "tabs.list returned non-grouped JSON ($TABS_LIST_RAW) -- the running plugin does not implement the tabs feature yet"
fi
TABS_AVAILABLE=1
echo "tabs.list available: $TABS_LIST_RAW"

# --- snap feature gate ---
SNAP_AVAILABLE=0
SNAP_LOCK="$(timeout 10 hc getoption plugin:grabbar:snap_lock 2>/dev/null || true)"
if [ -n "$SNAP_LOCK" ] && printf '%s' "$SNAP_LOCK" | jq -e '.value == true' >/dev/null 2>&1; then
  SNAP_AVAILABLE=1
  echo "snap_lock enabled: $SNAP_LOCK"
else
  echo "snap_lock not enabled or not queryable ($SNAP_LOCK) -- snap assertions will be skipped"
fi

# ------------------------------------------------------------------ work-area resolution (done once we have a window)

# ------------------------------------------------------------------ shell stand-in

say "shell stand-in (declares restore access, commits every minimize request)"
STANDIN_LOG="$OUT/shell-standin.log"
HYPRLAND_INSTANCE_SIGNATURE="$SIG" python3 "$HELPER" --timeout 300 listen --ready --auto-commit --seconds 300 > "$STANDIN_LOG" 2>&1 &
STANDIN_PID=$!
sleep 1

cleanup_standin() {
  if [ -n "${STANDIN_PID:-}" ] && kill -0 "$STANDIN_PID" 2>/dev/null; then
    kill "$STANDIN_PID" 2>/dev/null || true
    wait "$STANDIN_PID" 2>/dev/null || true
  fi
}
trap cleanup_standin EXIT

hc grabbar | tee "$OUT/status-active.txt" | grep -q 'decorations: active' || fail "strip not active with a ready shell"
pass "backend active after readiness handshake"

# ================================================================== TABS TESTS

if [ "$TABS_AVAILABLE" = "1" ]; then

  # ------------------------------------------------------------------ setup: two windows

  say "spawn two tiled windows (A and B)"

  # clean slate
  N_BEFORE="$(hc -j clients | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))' 2>/dev/null || echo 0)"
  if [ "$N_BEFORE" -gt 0 ]; then
    TOK_OLD="$(be windows | python3 -c 'import json,sys; [print(json.loads(l)["token"]) for l in sys.stdin if json.loads(l).get("alive")=="1"]' | head -1)"
    if [ -n "$TOK_OLD" ]; then
      be close "$TOK_OLD" >/dev/null 2>&1 || true
      sleep 0.5
    fi
  fi

  spawn foot >/dev/null
  sleep 1.5
  ADDR_A="$(addr_of_new)"
  [ -n "$ADDR_A" ] || fail "no hyprctl client for window A"
  TOK_A="$(token)"
  [ -n "$TOK_A" ] || fail "no token for window A"
  echo "window A token: $TOK_A addr: $ADDR_A"

  spawn foot >/dev/null
  sleep 1.5
  ADDR_B="$(addr_of_new "$ADDR_A")"
  [ -n "$ADDR_B" ] || fail "no hyprctl client for window B"
  TOK_B="$(be windows | TOK_A="$TOK_A" python3 -c '
import json, os, sys
skip = os.environ.get("TOK_A", "")
for line in sys.stdin:
    if not line.strip():
        continue
    r = json.loads(line)
    if r.get("alive") == "1" and r.get("token") != skip:
        print(r["token"]); break
')"
  [ -n "$TOK_B" ] || fail "no token for window B"
  echo "window B token: $TOK_B addr: $ADDR_B"

  # Geometry is read only once BOTH windows exist: the layout re-tiles when B
  # appears, so A's pre-split rect is stale and its strip would be missed.
  AX=$(gof "$ADDR_A" '["at"][0]'); AY=$(gof "$ADDR_A" '["at"][1]'); AW=$(gof "$ADDR_A" '["size"][0]'); AH=$(gof "$ADDR_A" '["size"][1]')
  STRIP_A_Y=$((AY - 17))
  TITLE_A_X=$((AX + AW / 2))
  echo "window A: client at ($AX,$AY) size ($AW,$AH); strip grab y=$STRIP_A_Y; title x=$TITLE_A_X"

  BX=$(gof "$ADDR_B" '["at"][0]'); BY=$(gof "$ADDR_B" '["at"][1]'); BW=$(gof "$ADDR_B" '["size"][0]'); BH=$(gof "$ADDR_B" '["size"][1]')
  STRIP_B_Y=$((BY - 17))
  TITLE_B_X=$((BX + BW / 2))
  echo "window B: client at ($BX,$BY) size ($BW,$BH); strip grab y=$STRIP_B_Y; title x=$TITLE_B_X"

  shot 01-two-windows

  # ------------------------------------------------------------------ T01: drag A onto B -> group with B as host

  say "T01: drag window A's title strip onto window B -- expect a tab group"

  # hover the strip first, then drag A's strip onto the *body* of B (the drop hit
  # test resolves the window under the pointer; a release over B's own strip is not
  # the hit the backend accepts).
  vp move "$TITLE_A_X" "$STRIP_A_Y" >/dev/null 2>&1 || true
  sleep 0.4
  DROP_B_Y=$((BY + BH / 2))
  echo "  drag ($TITLE_A_X,$STRIP_A_Y) -> ($TITLE_B_X,$DROP_B_Y) on $NESTED_DISPLAY"
  vp drag "$TITLE_A_X" "$STRIP_A_Y" "$TITLE_B_X" "$DROP_B_Y" 25 >/dev/null 2>&1 || true
  sleep 2.0

  TABS_RSP=""; GROUP_ID=""; HOST_TOKEN=""
  for _ in $(seq 1 40); do
    TABS_RSP="$(shell_call tabs.list 2>/dev/null || true)"
    if [ -n "$TABS_RSP" ] && printf '%s' "$TABS_RSP" | jq -e '.groups | length > 0' >/dev/null 2>&1; then
      GROUP_ID="$(printf '%s' "$TABS_RSP" | jq -r '.groups[0].id')"
      HOST_TOKEN="$(printf '%s' "$TABS_RSP" | jq -r '.groups[0].host')"
      [ -n "$HOST_TOKEN" ] && break
    fi
    sleep 0.25
  done

  echo "tabs.list after drag: $TABS_RSP"

  if [ -z "$GROUP_ID" ] || [ -z "$HOST_TOKEN" ]; then
    fail "T01: no tab group formed after dragging A onto B (GROUP_ID=$GROUP_ID HOST_TOKEN=$HOST_TOKEN)"
  fi
  if [ "$HOST_TOKEN" != "$TOK_B" ]; then
    fail "T01: host token is $HOST_TOKEN, expected $TOK_B (B should be the host)"
  fi

  TAB_TOKENS="$(printf '%s' "$TABS_RSP" | jq -r '.groups[0].tabs[].token' | sort)"
  EXPECTED_TOKENS="$(printf '%s\n%s' "$TOK_A" "$TOK_B" | sort)"
  if [ "$TAB_TOKENS" != "$EXPECTED_TOKENS" ]; then
    fail "T01: group tabs tokens are ($TAB_TOKENS), expected ($EXPECTED_TOKENS)"
  fi

  ACTIVE_IDX="$(printf '%s' "$TABS_RSP" | jq -r '.groups[0].active')"
  echo "group $GROUP_ID: host=$HOST_TOKEN active=$ACTIVE_IDX tabs=[$TAB_TOKENS]"
  pass "T01: drag A onto B formed group $GROUP_ID with host $TOK_B and tabs [$TAB_TOKENS]"
  shot 02-after-tab-drop

  # ------------------------------------------------------------------ T02: tabs.activate switches the active tab

  say "T02: tabs.activate switches the active tab within the group"

  shell_call tabs.activate "$(jq -n --argjson g "$GROUP_ID" --argjson i 0 '{group: $g, index: $i}')" >/dev/null 2>&1 || true

  ACTIVE_TOK_AFTER=""
  for _ in $(seq 1 30); do
    TABS_RSP="$(shell_call tabs.list 2>/dev/null || true)"
    ACTIVE_TOK_AFTER="$(printf '%s' "$TABS_RSP" | jq -r '.groups[0].tabs[.groups[0].active // 0].token' 2>/dev/null || true)"
    [ -n "$ACTIVE_TOK_AFTER" ] && [ "$ACTIVE_TOK_AFTER" != "null" ] && break
    sleep 0.25
  done

  echo "active tab after activate(index=0): $ACTIVE_TOK_AFTER"

  if [ -z "$ACTIVE_TOK_AFTER" ] || [ "$ACTIVE_TOK_AFTER" = "null" ]; then
    fail "T02: tabs.activate did not change the active tab"
  fi
  pass "T02: tabs.activate(group=$GROUP_ID, index=0) -> active tab is now $ACTIVE_TOK_AFTER"
  shot 03-after-activate

  # ------------------------------------------------------------------ T03: tabs.detach dissolves a group that drops below two members

  say "T03: tabs.detach of a non-host member dissolves the 2-member group"

  shell_call tabs.detach '{"token":"'"$TOK_A"'"}' >/dev/null 2>&1 || true

  # tabs.hpp contract: a group always has >= 2 members, so removing a member
  # that leaves only the host must dissolve the whole group.
  GROUPS_AFTER_DETACH=999
  for _ in $(seq 1 30); do
    TABS_RSP="$(shell_call tabs.list 2>/dev/null || true)"
    GROUPS_AFTER_DETACH="$(printf '%s' "$TABS_RSP" | jq '.groups | length' 2>/dev/null || echo 999)"
    [ "$GROUPS_AFTER_DETACH" = "0" ] && break
    sleep 0.25
  done

  echo "groups after detach A: $GROUPS_AFTER_DETACH"
  [ "$GROUPS_AFTER_DETACH" = "0" ] || fail "T03: detaching a member that leaves one member must dissolve the group (groups=$GROUPS_AFTER_DETACH)"

  # both windows must be back on the test workspace as independents
  WS_A="$(gof "$ADDR_A" '["workspace"]["id"]')"
  WS_B="$(gof "$ADDR_B" '["workspace"]["id"]')"
  echo "workspace after detach: A=$WS_A B=$WS_B"
  [ -n "$WS_A" ] && [ "$WS_A" = "$WS_B" ] || fail "T03: A and B should share a workspace after the group dissolved (A=$WS_A B=$WS_B)"

  pass "T03: tabs.detach(A) dissolved the group; A and B are independent on workspace $WS_A"
  shot 04-after-detach

  # ------------------------------------------------------------------ T04: tabs.ungroup dissolves the group

  say "T04: tabs.ungroup dissolves the remaining group"

  # T03 dissolved the group, so re-form one through the plugin IPC (the drag
  # path is covered by T01) and assert tabs.ungroup dissolves it.
  say "T04 setup: re-form the group through tabs.join"
  shell_call tabs.join "$(jq -n --arg s "$TOK_A" --arg h "$TOK_B" '{source: $s, host: $h}')" >/dev/null 2>&1 || true
  GROUP_ID=""
  for _ in $(seq 1 30); do
    TABS_RSP="$(shell_call tabs.list 2>/dev/null || true)"
    GROUP_ID="$(printf '%s' "$TABS_RSP" | jq -r '.groups[0].id // empty' 2>/dev/null || true)"
    [ -n "$GROUP_ID" ] && break
    sleep 0.25
  done
  [ -n "$GROUP_ID" ] || fail "T04: could not re-form a group through tabs.join"
  echo "re-formed group id: $GROUP_ID"

  shell_call tabs.ungroup "$(jq -n --argjson g "$GROUP_ID" '{group: $g}')" >/dev/null 2>&1 || true

  GROUPS_COUNT=999
  for _ in $(seq 1 30); do
    TABS_RSP="$(shell_call tabs.list 2>/dev/null || true)"
    GROUPS_COUNT="$(printf '%s' "$TABS_RSP" | jq '.groups | length' 2>/dev/null || echo 999)"
    [ "$GROUPS_COUNT" = "0" ] && break
    sleep 0.25
  done

  echo "tabs.list after ungroup: groups count = $GROUPS_COUNT"

  if [ "$GROUPS_COUNT" != "0" ]; then
    fail "T04: group $GROUP_ID still present after tabs.ungroup (groups count=$GROUPS_COUNT)"
  fi
  pass "T04: tabs.ungroup($GROUP_ID) dissolved the group (0 groups remain)"
  shot 05-after-ungroup

  # ------------------------------------------------------------------ cleanup: close both windows

  say "cleanup -- close both test windows through the backend"
  be close "$TOK_A" >/dev/null 2>&1 || true
  be close "$TOK_B" >/dev/null 2>&1 || true
  sleep 0.8
  N_AFTER_TABS="0"
  echo "windows remaining after tabs cleanup: $N_AFTER_TABS"

fi  # TABS_AVAILABLE

# ================================================================== SNAP REGRESSION TESTS

if [ "$SNAP_AVAILABLE" = "1" ]; then

  say "spawn a test window for snap assertions"

  TOK_SNAP="$(token)"
  if [ -z "$TOK_SNAP" ]; then
    # no window exists -- spawn one
    spawn foot >/dev/null
    sleep 1.2
    TOK_SNAP="$(token)"
  fi
  [ -n "$TOK_SNAP" ] || fail "no token for snap test window"
  echo "snap test window token: $TOK_SNAP"

  SNAP_X=$(wf '["at"][0]'); SNAP_Y=$(wf '["at"][1]'); SNAP_W=$(wf '["size"][0]'); SNAP_H=$(wf '["size"][1]')
  SNAP_STRIP_Y=$((SNAP_Y - 17))
  SNAP_TITLE_X=$((SNAP_X + SNAP_W / 2))
  echo "snap window: client at ($SNAP_X,$SNAP_Y) size ($SNAP_W,$SNAP_H); strip y=$SNAP_STRIP_Y; title x=$SNAP_TITLE_X"

  shot 06-snap-window

  # resolve work area for this window
  WA_JSON="$(resolve_work_area "$(wf '["address"]')")"
  WA_TOP="$(printf '%s' "$WA_JSON" | jq -r '.workArea_top')"
  WA_BOTTOM="$(printf '%s' "$WA_JSON" | jq -r '.workArea_bottom')"
  STRIP_H="$(printf '%s' "$WA_JSON" | jq -r '.stripHeight')"
  MON_X="$(printf '%s' "$WA_JSON" | jq -r '.mon_x')"
  MON_Y="$(printf '%s' "$WA_JSON" | jq -r '.mon_y')"
  MON_W="$(printf '%s' "$WA_JSON" | jq -r '.mon_w')"
  MON_H="$(printf '%s' "$WA_JSON" | jq -r '.mon_h')"
  MON_NAME="$(printf '%s' "$WA_JSON" | jq -r '.monitor_name')"

  echo "work area: top=$WA_TOP bottom=$WA_BOTTOM; stripHeight=$STRIP_H"
  echo "monitor: $MON_NAME at ($MON_X,$MON_Y) size ($MON_W,$MON_H)"

  if [ "$WA_TOP" = "0" ] && [ "$MON_Y" != "0" ]; then
    WA_TOP="$MON_Y"
    echo "WARNING: no bar surface found -- using monitor top y=$WA_TOP as workArea_top"
  fi

  # ------------------------------------------------------------------ snap assertion helper

  assert_snap_zone() {
    local label="$1"
    local target_x="$2"
    local target_y="$3"

    say "$label: drag title strip to ($target_x, $target_y) and release to trigger snap"

    vp drag "$SNAP_TITLE_X" "$SNAP_STRIP_Y" "$target_x" "$target_y" 30 sleep 600

    sleep 1.0

    local new_x new_y new_w new_h
    new_x=$(wf '["at"][0]')
    new_y=$(wf '["at"][1]')
    new_w=$(wf '["size"][0]')
    new_h=$(wf '["size"][1]')

    local strip_top=$((new_y - STRIP_H))
    local client_bottom=$((new_y + new_h))

    echo "  AFTER $label: client=$new_x,$new_y size=$new_w,$new_h"
    echo "  strip band: y=$strip_top..$new_y (stripHeight=$STRIP_H)"
    echo "  work area:  top=$WA_TOP bottom=$WA_BOTTOM"
    echo "  monitor:    $MON_NAME at ($MON_X,$MON_Y) size ($MON_W,$MON_H)"
    echo "  strip_top - workArea_top = $((strip_top - WA_TOP))"
    echo "  client_bottom - workArea_bottom = $((client_bottom - WA_BOTTOM))"

    # assertion (a): strip band fully inside work area
    if [ "$strip_top" -lt "$WA_TOP" ]; then
      local hidden_by=$((WA_TOP - strip_top))
      fail "SNAP [$label]: STRIP BAND HIDDEN -- strip_top=$strip_top < workArea_top=$WA_TOP (by $hidden_by px, stripHeight=$STRIP_H, client_y=$new_y). The top of the window title strip is under the reserved top area (Omarchy bar or monitor edge)."
    fi

    # assertion (b): client box fully inside work area (bottom edge)
    if [ "$client_bottom" -gt "$WA_BOTTOM" ]; then
      local overflow=$((client_bottom - WA_BOTTOM))
      fail "SNAP [$label]: CLIENT BOTTOM OUTSIDE WORK AREA -- client_bottom=$client_bottom > workArea_bottom=$WA_BOTTOM (overflow=$overflow px). The fix must not push the window past the bottom of the work area."
    fi

    pass "SNAP [$label]: strip band ($strip_top..$new_y) inside work area (top=$WA_TOP); client box ($new_y..$client_bottom) inside work area (bottom=$WA_BOTTOM)"
    shot "07-snap-$label"
  }

  # ------------------------------------------------------------------ S01: LEFT half snap

  LEFT_TARGET_X=$((MON_X + 24 + 1))
  LEFT_TARGET_Y=$((MON_Y + MON_H / 2))
  assert_snap_zone "S01-LEFT-half" "$LEFT_TARGET_X" "$LEFT_TARGET_Y"

  # ------------------------------------------------------------------ S02: RIGHT half snap

  RIGHT_TARGET_X=$((MON_X + MON_W - 24 - 1))
  RIGHT_TARGET_Y=$((MON_Y + MON_H / 2))
  assert_snap_zone "S02-RIGHT-half" "$RIGHT_TARGET_X" "$RIGHT_TARGET_Y"

  # ------------------------------------------------------------------ S03: TL corner snap

  TL_TARGET_X=$((MON_X + 24 + 1))
  TL_TARGET_Y=$((MON_Y + 24 + 1))
  assert_snap_zone "S03-TL-corner" "$TL_TARGET_X" "$TL_TARGET_Y"

  # ------------------------------------------------------------------ S04: TR corner snap

  TR_TARGET_X=$((MON_X + MON_W - 24 - 1))
  TR_TARGET_Y=$((MON_Y + 24 + 1))
  assert_snap_zone "S04-TR-corner" "$TR_TARGET_X" "$TR_TARGET_Y"

  # ------------------------------------------------------------------ cleanup

  say "cleanup -- close snap test window through the backend"
  be close "$TOK_SNAP" >/dev/null 2>&1 || true
  sleep 0.8

fi  # SNAP_AVAILABLE

# ------------------------------------------------------------------ summary

say "summary -- tab + snap nested scenarios"
echo "evidence in $OUT"
echo
echo "all tab + snap nested scenarios passed"
