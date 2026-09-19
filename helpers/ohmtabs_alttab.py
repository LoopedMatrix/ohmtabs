#!/usr/bin/env python3
"""OhmTabs alt-tab: one key, three jobs.

Alt-tab is a habit, so it has to do the obvious thing wherever the user is:

  1. the pointer sits on a tab group's host window (or a tab group is focused)
     and that group holds two or more tabs   -> cycle the group's tabs
  2. the focused window is a browser          -> switch that browser's TAB
                                                 (Ctrl+PageDown / Ctrl+PageUp,
                                                 which Brave, Chrome, Chromium,
                                                 Edge, Firefox and friends all
                                                 use as next/previous tab)
  3. anything else                            -> the compositor's window cycle,
     which is exactly what Omarchy's own ALT+TAB did before this helper existed
     (cycle the window list, then raise the focused window - Omarchy bound both
     to ALT+TAB, so both are preserved).

Nothing here needs a privilege, a daemon or a browser extension: case 2 asks the
focused browser to switch its own tab, the same keystroke the browser's own
keybinding would send.

Usage:
    ohmtabs alttab next|prev [--decide]

`--decide` prints the decision as JSON and changes nothing at all (used by the
unit tests and for troubleshooting).

Environment:
    OHMTABS_ALTTAB_BROWSER_CLASSES   comma or colon separated window-class
                                     fragments that count as browsers; overrides
                                     both the `browserClasses` setting below and
                                     the built-in list.
    HYPRLAND_INSTANCE_SIGNATURE      the session to act on (passed to hyprctl as
                                     `-i`, so the helper never guesses).

Settings (the plugin's entry in ~/.config/omarchy/shell.json, hot-applied):
    browserClasses   list of window-class fragments to treat as browsers
    barHeight        the native title strip's height, used to tell whether the
                     pointer is on a group host's tab strip
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

PLUGIN_ID = "tech.loopedmatrix.ohmtabs"
HERE = Path(__file__).resolve().parent
BACKEND_PY = HERE / "ohmtabs_backend.py"
SHELL_JSON = Path(os.path.expanduser("~/.config/omarchy/shell.json"))

# The native strip's height in logical pixels (main.cpp registers
# `plugin:ohmtabs:bar_height` with a default of 34). The tab strip is drawn on
# that strip, which sits directly ABOVE the client box, so the pointer counts as
# being "on the host" anywhere in the client box or on the strip above it.
DEFAULT_STRIP_HEIGHT = 34

# Window-class fragments that mean "this window switches its own tabs with
# Ctrl+PageDown". The class is matched case-insensitively as a substring, so
# "brave-browser" and "Brave" both hit the "brave" entry.
DEFAULT_BROWSER_CLASSES = (
    "brave",
    "chrome",
    "chromium",
    "google-chrome",
    "microsoft-edge",
    "vivaldi",
    "opera",
    "firefox",
    "librewolf",
    "waterfox",
    "zen",
    "floorp",
    "qutebrowser",
    "epiphany",
    "falkon",
)

# Keysyms for the browser's previous/next tab. "Next" is Page_Down and "Prior"
# is Page_Up in X keysym naming, which is what wtype takes.
BROWSER_KEYS = {"next": "Next", "prev": "Prior"}


# --------------------------------------------------------------------- plumbing


def run(cmd, timeout=4, env=None):
    """Run a command; never raise. Returns (returncode, stdout, stderr)."""
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, env=env)
        return p.returncode, (p.stdout or "").strip(), (p.stderr or "").strip()
    except Exception as exc:  # missing binary, timeout, anything
        return 1, "", str(exc)


def instance_args():
    """`-i <signature>` when we know the session, so hyprctl never acts blind."""
    sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    return ["-i", sig] if sig else []


def hypr_json(command):
    """`hyprctl -j <command>` parsed, or {} when there is nothing to read."""
    rc, out, _ = run(["hyprctl", *instance_args(), "-j", command], timeout=4)
    if rc != 0 or not out:
        return {}
    try:
        return json.loads(out)
    except ValueError:
        return {}


def hypr_dispatch(lua):
    """Run one Lua dispatcher. Returns True when hyprctl accepted it."""
    rc, out, err = run(["hyprctl", *instance_args(), "dispatch", lua], timeout=4)
    return rc == 0 and "error" not in (out + err).lower()


def ipc(method, *args):
    """Call the plugin over its own IPC. Returns (ok, answer)."""
    exe = shutil.which("omarchy-shell")
    if not exe:
        return False, ""
    env = dict(os.environ, OMARCHY_SHELL_IPC_TIMEOUT="1s")
    rc, out, _ = run([exe, PLUGIN_ID, method, *[str(a) for a in args]], timeout=3, env=env)
    return rc == 0, out


def load_settings():
    """The plugin's own entry in shell.json, wherever it sits in the tree."""
    try:
        data = json.loads(SHELL_JSON.read_text())
    except Exception:
        return {}
    found = {}

    def walk(node):
        nonlocal found
        if isinstance(node, dict):
            if node.get("id") == PLUGIN_ID:
                found = node
            for value in node.values():
                walk(value)
        elif isinstance(node, list):
            for value in node:
                walk(value)

    walk(data)
    return found


def browser_classes(settings):
    env = os.environ.get("OHMTABS_ALTTAB_BROWSER_CLASSES")
    if env:
        parts = env.replace(":", ",").split(",")
        return [p.strip().lower() for p in parts if p.strip()]
    value = (settings or {}).get("browserClasses")
    if isinstance(value, list):
        cleaned = [str(v).strip().lower() for v in value if str(v).strip()]
        if cleaned:
            return cleaned
    return list(DEFAULT_BROWSER_CLASSES)


def strip_height(settings):
    for key in ("barHeight", "stripHeight"):
        value = (settings or {}).get(key)
        if isinstance(value, (int, float)) and not isinstance(value, bool) and value > 0:
            return int(value)
    return DEFAULT_STRIP_HEIGHT


# ------------------------------------------------------------------- pure logic


def is_browser(window_class, classes):
    """Case-insensitive substring match: 'brave-browser' hits 'brave'."""
    name = (window_class or "").lower()
    if not name:
        return False
    return any(fragment in name for fragment in classes if fragment)


def contains(window, x, y, strip):
    """Is (x, y) inside the window's client box, or on the strip above it?"""
    if not window:
        return False
    try:
        wx, wy = int(window["x"]), int(window["y"])
        ww, wh = int(window["w"]), int(window["h"])
    except (KeyError, TypeError, ValueError):
        return False
    if ww <= 0 or wh <= 0:
        return False
    return wx <= x <= wx + ww and (wy - strip) <= y <= wy + wh


def group_by_focus(groups, focus_token):
    """The group whose host/member is focused (the user is inside the tabs)."""
    if not focus_token:
        return None
    for group in groups or []:
        host = group.get("host")
        members = group.get("members") or []
        if not host or len(members) < 2:
            continue
        if focus_token == host or focus_token in members:
            return group
    return None


def group_by_pointer(groups, windows, pointer, strip):
    """The group whose host window the pointer is on, if it has 2+ tabs."""
    if not pointer:
        return None
    try:
        px, py = int(pointer["x"]), int(pointer["y"])
    except (KeyError, TypeError, ValueError):
        return None
    for group in groups or []:
        host = group.get("host")
        members = group.get("members") or []
        if not host or len(members) < 2:
            continue
        if contains(windows.get(host), px, py, strip):
            return group
    return None


def decide(ctx, direction):
    """The whole decision, as a value. No I/O, so the tests can pin it down.

    ctx keys: groups, windows (token -> record), pointer, focus (class/token),
    browserClasses, strip.
    """
    step = str(direction or "next").lower()
    step = "prev" if step in ("prev", "previous", "up", "back", "-1") else "next"

    focus = ctx.get("focus") or {}
    group = group_by_focus(ctx.get("groups") or [], focus.get("token"))
    if group is None:
        group = group_by_pointer(
            ctx.get("groups") or [],
            ctx.get("windows") or {},
            ctx.get("pointer"),
            ctx.get("strip", DEFAULT_STRIP_HEIGHT),
        )
    if group is not None:
        return {
            "action": "group",
            "host": group.get("host"),
            "direction": step,
            "tabs": len(group.get("members") or []),
            "reason": "a tab group is focused or the pointer is on its host",
        }

    if is_browser(focus.get("class"), ctx.get("browserClasses") or DEFAULT_BROWSER_CLASSES):
        return {
            "action": "browser",
            "direction": step,
            "class": focus.get("class"),
            "keys": BROWSER_KEYS[step],
            "reason": "the focused window is a browser: switch its own tab",
        }

    return {
        "action": "window",
        "direction": step,
        "reason": "no tab group, no browser: the compositor's window cycle",
    }


# ------------------------------------------------------------------- execution


def collect_context():
    """Everything `decide` needs, gathered defensively."""
    settings = load_settings()
    windows = backend_windows()
    focus_window = hypr_json("activewindow") or {}
    address = str(focus_window.get("address") or "").lower()
    token = None
    if address:
        try:
            stable = int(address, 16)
        except ValueError:
            stable = None
        if stable is not None:
            for candidate, record in windows.items():
                try:
                    if int(record.get("stableId", 0)) == stable:
                        token = candidate
                        break
                except (TypeError, ValueError):
                    continue
    return {
        "settings": settings,
        "strip": strip_height(settings),
        "browserClasses": browser_classes(settings),
        "groups": plugin_groups(),
        "windows": windows,
        "pointer": hypr_json("cursorpos"),
        "focus": {
            "class": focus_window.get("class") or "",
            "title": focus_window.get("title") or "",
            "address": address,
            "token": token,
        },
    }


def backend_windows():
    """Live windows from the native backend: token -> record (geometry, class)."""
    python = shutil.which("python3") or sys.executable
    rc, out, _ = run([python, str(BACKEND_PY), "--timeout", "3", "windows"], timeout=6)
    windows = {}
    if rc != 0 and not out:
        return windows
    for line in out.splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            record = json.loads(line)
        except ValueError:
            continue
        if str(record.get("kind", "window")) != "window":
            continue
        if str(record.get("alive", "")) != "1":
            continue
        token = record.get("token")
        if token:
            windows[token] = record
    return windows


def plugin_groups():
    """The plugin's tab groups (empty when tabGroups is off, which is the default)."""
    ok, out = ipc("status")
    if not ok or not out.strip().startswith("{"):
        return []
    try:
        data = json.loads(out)
    except ValueError:
        return []
    return ((data.get("tabGroups") or {}).get("groups")) or []


def execute(decision):
    """Do the thing. Returns (handled, how). Falls through, never dead-ends."""
    action = decision.get("action")
    step = decision.get("direction", "next")

    if action == "group":
        ok, answer = ipc("groupCycle", decision.get("host"), step, "true")
        if ok and answer.strip() == "ok":
            return True, "groupCycle"
        # A group that dissolved underneath us (or a stale host) must not eat the
        # keypress: fall through to the browser/window branches below.

    if action in ("group", "browser"):
        wtype = shutil.which("wtype")
        if wtype:
            key = BROWSER_KEYS.get(step, "Next")
            rc, _, _ = run([wtype, "-M", "ctrl", "-k", key], timeout=3)
            if rc == 0:
                return True, "ctrl+" + key

    lua = "hl.dsp.window.cycle_next()" if step == "next" else "hl.dsp.window.cycle_next({ next = false })"
    moved = hypr_dispatch(lua)
    # Omarchy binds ALT+TAB to both the cycle AND "reveal active window on top";
    # keep the second half so this helper is a superset of the old behaviour.
    hypr_dispatch("hl.dsp.window.bring_to_top()")
    return moved, "cycle_next"


def main(argv):
    args = [a for a in argv if not a.startswith("--")]
    dry = "--decide" in argv
    direction = args[0] if args else "next"

    decision = decide(collect_context(), direction)
    if dry:
        print(json.dumps({"decision": decision}, sort_keys=True))
        return 0

    handled, how = execute(decision)
    print(json.dumps({"decision": decision, "handled": bool(handled), "via": how}, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
