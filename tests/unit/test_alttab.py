#!/usr/bin/env python3
"""Unit tests for the alt-tab decision helper.

The decision tree is a pure function on purpose: which of the three jobs
alt-tab takes (tab group / browser tab / window cycle) must be pinnable in a
test, because the alternative is testing it by pressing the key on the user's
live desktop.

Run: python3 tests/unit/test_alttab.py
"""

import importlib.util
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "helpers" / "ohmtabs_alttab.py"

spec = importlib.util.spec_from_file_location("ohmtabs_alttab", HELPER)
assert spec is not None and spec.loader is not None
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

FAILURES = []
CHECKS = 0


def check(label, got, want):
    global CHECKS
    CHECKS += 1
    if got != want:
        FAILURES.append(f"{label}: got {got!r}, want {want!r}")


def base_ctx(**over):
    ctx = {
        "groups": [],
        "windows": {},
        "pointer": {"x": 0, "y": 0},
        "focus": {"class": "", "token": None},
        "browserClasses": list(mod.DEFAULT_BROWSER_CLASSES),
        "strip": mod.DEFAULT_STRIP_HEIGHT,
    }
    ctx.update(over)
    return ctx


def group(host, members, active=None):
    return {"host": host, "members": members, "active": active or host}


# --- 1. tab groups win when they are focused --------------------------------

two_tabs = [group("0xabc", ["0xabc", "0xdef"])]

check(
    "focus on host -> group",
    mod.decide(base_ctx(groups=two_tabs, focus={"class": "foot", "token": "0xabc"}), "next")["action"],
    "group",
)
check(
    "focus on member -> group",
    mod.decide(base_ctx(groups=two_tabs, focus={"class": "foot", "token": "0xdef"}), "next")["action"],
    "group",
)
check(
    "direction passes through",
    mod.decide(base_ctx(groups=two_tabs, focus={"class": "foot", "token": "0xabc"}), "prev")["direction"],
    "prev",
)
check(
    "group reports its tab count",
    mod.decide(base_ctx(groups=two_tabs, focus={"class": "foot", "token": "0xabc"}), "next")["tabs"],
    2,
)

# a single-tab "group" is not a group: nothing to cycle
check(
    "one-member group is skipped",
    mod.decide(base_ctx(groups=[group("0xabc", ["0xabc"])], focus={"class": "foot", "token": "0xabc"}), "next")["action"],
    "window",
)
check(
    "focus in an unrelated group falls through",
    mod.decide(
        base_ctx(groups=two_tabs, focus={"class": "foot", "token": "0x999"}),
        "next",
    )["action"],
    "window",
)

# --- 2. the pointer on a host window counts --------------------------------

host_win = {"0xabc": {"x": 100, "y": 400, "w": 800, "h": 600, "alive": "1"}}

check(
    "pointer on the host box -> group",
    mod.decide(
        base_ctx(groups=two_tabs, windows=host_win, pointer={"x": 500, "y": 700}),
        "next",
    )["action"],
    "group",
)
check(
    "pointer on the strip above the host -> group",
    mod.decide(
        base_ctx(groups=two_tabs, windows=host_win, pointer={"x": 500, "y": 400 - mod.DEFAULT_STRIP_HEIGHT + 4}),
        "next",
    )["action"],
    "group",
)
check(
    "pointer above the strip -> not the group",
    mod.decide(
        base_ctx(groups=two_tabs, windows=host_win, pointer={"x": 500, "y": 400 - mod.DEFAULT_STRIP_HEIGHT - 20}),
        "next",
    )["action"],
    "window",
)
check(
    "pointer outside the host -> not the group",
    mod.decide(
        base_ctx(groups=two_tabs, windows=host_win, pointer={"x": 5000, "y": 700}),
        "next",
    )["action"],
    "window",
)
check(
    "zero-size window never matches",
    mod.decide(
        base_ctx(
            groups=two_tabs,
            windows={"0xabc": {"x": 100, "y": 400, "w": 0, "h": 0, "alive": "1"}},
            pointer={"x": 100, "y": 400},
        ),
        "next",
    )["action"],
    "window",
)

# --- 3. the browser branch --------------------------------------------------

for cls in ("brave-browser", "Brave", "google-chrome", "Chromium", "firefox", "zen"):
    check(
        f"{cls} -> browser tab switch",
        mod.decide(base_ctx(focus={"class": cls, "token": None}), "next")["action"],
        "browser",
    )

check(
    "browser next key is Page_Down",
    mod.decide(base_ctx(focus={"class": "brave-browser", "token": None}), "next")["keys"],
    "Next",
)
check(
    "browser prev key is Page_Up",
    mod.decide(base_ctx(focus={"class": "brave-browser", "token": None}), "prev")["keys"],
    "Prior",
)
check(
    "a browser is not a browser when it is grouped and focused",
    mod.decide(
        base_ctx(groups=two_tabs, windows=host_win, focus={"class": "brave-browser", "token": "0xabc"}),
        "next",
    )["action"],
    "group",
)
check(
    "non-browser focused -> window cycle",
    mod.decide(base_ctx(focus={"class": "Alacritty", "token": None}), "next")["action"],
    "window",
)
check(
    "empty class -> window cycle",
    mod.decide(base_ctx(focus={"class": ""}), "next")["action"],
    "window",
)

# --- 4. matching and overrides are case/format insensitive ------------------

check("substring match", mod.is_browser("brave-browser", ["brave"]), True)
check("case insensitive", mod.is_browser("Brave-Browser", ["brave"]), True)
check("empty class is never a browser", mod.is_browser("", ["brave"]), False)
check("empty settings list falls back", mod.browser_classes({"browserClasses": []}), list(mod.DEFAULT_BROWSER_CLASSES))
check("settings override is honoured", mod.browser_classes({"browserClasses": ["Mozilla", "  ", ""]}), ["mozilla"])
check("strip height default", mod.strip_height({}), 34)
check("strip height from settings", mod.strip_height({"barHeight": 46}), 46)
check("strip height ignores junk", mod.strip_height({"barHeight": "tall"}), 34)

# --- 5. direction normalisation --------------------------------------------

for alias in ("prev", "PREV", "previous", "up", "-1"):
    check(f"alias {alias} -> prev", mod.decide(base_ctx(), alias)["direction"], "prev")
for alias in ("next", "NEXT", "", None, "anything-else"):
    check(f"alias {alias!r} -> next", mod.decide(base_ctx(), alias)["direction"], "next")

# --- 6. the decision is JSON-serialisable (it is printed as JSON) -----------

try:
    json.dumps(mod.decide(base_ctx(groups=two_tabs, focus={"class": "foot", "token": "0xabc"}), "next"))
    check("decision serialises", True, True)
except TypeError as exc:  # pragma: no cover
    FAILURES.append(f"decision not serialisable: {exc}")

# --- 7. the helper's own CLI surface ---------------------------------------

text = HELPER.read_text()
for token in ("def decide(", "def execute(", "--decide", "groupCycle", "cycle_next", "Next", "Prior"):
    check(f"helper defines {token}", token in text, True)
check("helper is importable without a session", mod.PLUGIN_ID, "tech.loopedmatrix.ohmtabs")

print(f"test_alttab: {CHECKS - len(FAILURES)}/{CHECKS} checks passed")
if FAILURES:
    for line in FAILURES:
        print("  FAIL " + line)
    sys.exit(1)
sys.exit(0)
