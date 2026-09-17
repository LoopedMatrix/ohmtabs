<h1 align="center">omarchy-tab</h1>

<p align="center">
  <img src="docs/brand/grabbar-banner.png" alt="Grabbar — familiar window controls for Omarchy" width="100%">
</p>

<p align="center">
  <a href="https://github.com/LoopedMatrix/omarchy-tab/actions/workflows/test.yml"><img alt="tests" src="https://github.com/LoopedMatrix/omarchy-tab/actions/workflows/test.yml/badge.svg"></a>
  <a href="LICENSE"><img alt="MIT + BSD-3" src="https://img.shields.io/badge/license-MIT%20%2B%20BSD--3-aab3bc?labelColor=0b0f14"></a>
  <img alt="Omarchy 4" src="https://img.shields.io/badge/Omarchy-4-fda52b?labelColor=0b0f14">
  <img alt="Hyprland 0.56.2" src="https://img.shields.io/badge/Hyprland-0.56.2-38c8e8?labelColor=0b0f14">
</p>

**omarchy-tab** gives ordinary application windows a Windows/macOS-style title strip — a window menu, Minimize, Maximize/Restore, Close, and drag-to-move — and **adds a Windows-style minimized-window taskbar** to [Omarchy](https://github.com/cyberus-technology/omarchy) (Arch + Hyprland). It is a [Quickshell](https://github.com/outfoxxed/quickshell) plugin.

> **Name vs. label.** The repository and project are **omarchy-tab**, but the plugin's id (`tech.greyforge.grabbar`) and its visible label (**Grabbar**) are intentionally kept unchanged, so live installs and saved settings keep working. In the UI and in file paths you will still see "Grabbar"; that is the same plugin.

<img src="docs/screenshots/desktop.png" alt="Title strips on focused and unfocused windows" width="100%">

## Why a fork?

omarchy-tab is a personal fork of [GreyforgeLabs/omarchy-grabbar](https://github.com/GreyforgeLabs/omarchy-grabbar) ("Grabbar"), which is itself based on [hyprbars](https://github.com/hyprwm/hyprland-plugins). We forked it because **our version deviates substantially from upstream** — it replaces the drawer-first minimized-window UX with a real taskbar and adds a scripting/IPC surface, hot-applied settings, and a critical freeze fix — changes we wanted to live under our own repo name rather than as an upstream patch. The core strip work, the journal/recovery machinery, and the test suite are inherited from upstream and credited in [License & credits](#license--credits).

### What our version adds

| Area | What changed |
| --- | --- |
| **Minimized-window taskbar** | A Windows-style taskbar ([`SidePanel.qml`](SidePanel.qml)) replaces the drawer-first UX. Bottom/left/right placement, auto-hide-until-hover with a 4 px reveal sliver, app badge + title + origin rows, and **Restore all**. It draws *no surface at all* when nothing is minimized (`live = panelEnabled && count > 0`). |
| **Hot-applied settings** | Every setting in the plugin's `shell.json` entry is watched and applied live — changing `panelPosition` or `panelAutoHide` takes effect with **no shell restart**. |
| **The freeze fix** | Upstream's bar assigns `settings`/`moduleName`/`bar` onto every widget. We made those writable, fixing a `TypeError: Cannot assign to read-only property "settings"` that wedged the whole shell (commit `0d79811`). See [Troubleshooting](#troubleshooting). |
| **Scripting / IPC surface** | A complete command surface — `status`, `minimize`, `restore`, `restoreAll`, `openDrawer`, `openSettings`, `reconcile`, `disable`, `enable`, `ping` — plus the `bin/grabbar` CLI and a stable token format. |
| **Kept from upstream** | The native title-strip backend, the drawer view, the menu, the autoload journal, and the offline test suite. |

## Install

Two parts: the **shell plugin** (widget, taskbar, settings, IPC) and the **native strip backend** (an Hyprland plugin that draws the strips and moves minimized windows).

### 1. Shell plugin

```sh
omarchy plugin add https://github.com/LoopedMatrix/omarchy-tab.git --enable
```

This installs the plugin to `~/.config/omarchy/plugins/tech.greyforge.grabbar` (the id is kept from upstream for compatibility) and enables it.

### 2. Native strip backend

```sh
cd ~/.config/omarchy/plugins/tech.greyforge.grabbar
make -C native/grabbar CXX=g++
hyprctl plugin load ./native/grabbar/grabbar.so
```

> **Without the native part** there are no strips and Minimize stays off; the shell side (bar widget, taskbar/drawer, settings, IPC) still mounts and the drawer still lists nothing to restore.

### 3. Autoload (optional)

```sh
cd ~/.config/omarchy/plugins/tech.greyforge.grabbar
ln -s "$(pwd)/bin/grabbar" ~/.local/bin/grabbar   # optional, for the CLI
grabbar autoload enable                           # survive shell restarts
```

See [docs/AUTOLOAD.md](docs/AUTOLOAD.md) for what autoload does under the hood.

## Everyday use

### The title strip

Every ordinary application window gets a strip above its top edge:

- **Menu** (hamburger) or **right-click the strip** — window menu (Restore, Minimize, Maximize/Restore, Close).
- **Minimize** — moves the window off-screen to the minimized workspace and shows it in the taskbar.
- **Maximize/Restore** — the button reflects the current state.
- **Close** — closes the window.
- **Drag the strip** — move the window; dragging a tiled window detaches it to floating at 60 %.
- **Double-click the title** — toggle maximize.
- **Resize** — drag the strip's edge/corners with `general:resize_on_border = true`.

Window controls sit on the right by default; set `buttonsLeft` to put them on the left. Hide the strip for specific apps with `excludedClasses`.

### Minimizing and the taskbar

Minimizing moves a window to the special workspace `special:grabbar-minimized`; the taskbar shows one row per minimized window (app badge, title, and the workspace it came from):

- **Left-click** a row → restore to the **current** workspace.
- **Right-click** a row → restore to its **original** workspace.
- **Restore all** (far end) → restore everything.
- The taskbar sits on the bottom by default; `panelPosition` moves it to `left` or `right`, and `panelAutoHide` parks it off-screen with a 4 px sliver that expands on hover.
- When the taskbar is empty it is entirely hidden (by design).

### The bar drawer

The bar widget shows a window-stack glyph and a count of minimized windows:

- **Left-click** the widget → open the drawer (newest-first list with Restore / Original workspace / Restore all).
- **Middle-click** the widget → restore all.
- **Right-click** the widget → open settings.

When `sidePanel` is `true` (the default), the taskbar appears on its own and the drawer doubles as the detail view.

### Keyboard navigation in the taskbar

Hovering or clicking a row gives the panel keyboard focus, after which:

| Key | Action |
| --- | --- |
| `↓` / `→` / `j` | Move selection down |
| `↑` / `←` / `k` | Move selection up |
| `Enter` | Restore selected (to current workspace) |
| `Shift`+`Enter` | Restore selected to its original workspace |
| `Ctrl`+`A` | Restore all |
| `Esc` | Dismiss |

## Configuration

Settings live in the plugin's `shell.json` entry (edit through **Settings**, or directly in the shell config). All of them hot-apply — the service watches the entry and re-reads it live, no shell restart needed.

| Key | Type | Default | Effect |
| --- | --- | --- | --- |
| `enabled` | bool | `true` | Master switch for strips + Minimize. Turning it off restores minimized windows first. |
| `buttonsLeft` | bool | `false` | Window controls on the left (`true`) or right (`false`). |
| `showOnHover` | bool | `false` | *Legacy* — draw the strip only while the pointer is near the window's top edge. |
| `controlSize` | `"standard"` \| `"large"` | `"standard"` | Strip thickness: 34 px (standard) vs 46 px (large). |
| `excludedClasses` | string[] | `[]` | App classes whose windows get no strip (same as "Hide Grabbar for this app"). |
| `sidePanel` | bool | `true` | Windows-style taskbar (`true`) vs the in-bar drawer only (`false`). |
| `panelPosition` | `"bottom"` \| `"left"` \| `"right"` | `"bottom"` | Screen edge the taskbar sits on. |
| `panelAutoHide` | bool | `true` | Park the taskbar off the edge until the pointer reaches it. |
| `tabGroups` | bool | `false` | *Reserved* — tab groups are in development (see [Roadmap](#roadmap)). |

Unknown keys are ignored; invalid values fall back to the default. Values are validated in [`GrabbarModel.js`](GrabbarModel.js) (`normalizeSettings`).

### Native config fallback

When the shell isn't connected yet, the native backend falls back to `plugin:grabbar:*` keys in `hyprland.lua` (these are overridden by the shell theme/settings once connected):

`enabled`, `buttons_left`, `bar_height` (34), `button_size` (32), `padding` (4), `text_size` (11), `text_font` (`"Sans"`), `bar_color`, `inactive_bar_color`, `text_color`, `hover_color`, `close_hover_color`, `shell_grace_ms` (2000). Per-window opt-out via the `grabbar:no_bar` window rule.

## Command line & scripting

`bin/grabbar` (optionally linked into `~/.local/bin`) wraps the plugin's IPC:

```
grabbar                 open the drawer
grabbar settings        open settings
grabbar status [--json] show backend + minimized-window state
grabbar windows         list known windows
grabbar restore TOKEN [--original]   restore one minimized window
grabbar restore-all     restore all minimized windows
grabbar doctor          diagnose the install
grabbar autoload status|enable|disable|retry
grabbar enable|disable  toggle the plugin
grabbar uninstall       remove autoload + backend
```

Exit codes: `0` ok · `2` usage · `3` backend unavailable · `4` stale target · `5` restore UI unavailable (shell service not running) · `6` state write failed · `7` incomplete recovery.

### IPC surface

The plugin's `IpcHandler` (in [`Service.qml`](Service.qml)) exposes these methods over Quickshell's IPC — call them via `omarchy-shell tech.greyforge.grabbar <method> [args]`:

| Method | Args | Returns |
| --- | --- | --- |
| `status` | — | JSON: `backend.ready`, `enabled`, `minimizeEnabled`, `restoreHost`, `failed`, `backend.epoch`, `entries[]`, `minimized` |
| `minimize` | `token` | Minimizes the window identified by `token` |
| `restore` | `token`, `mode` | Restores `token`; `mode` is `"original"` or `"current"` |
| `restoreAll` | — | Restores every minimized window |
| `openDrawer` | — | Opens the bar drawer |
| `openSettings` | — | Opens settings |
| `reconcile` | — | Re-syncs model state with the backend |
| `disable` / `enable` | — | Toggle the plugin |
| `ping` | — | Liveness check |

**Token format.** Each minimized window is identified by a token `g<epoch>-<generation>` (e.g. `g1789644541-6`), minted by `tokenFor()` in [`native/grabbar/backend.cpp`](native/grabbar/backend.cpp). Read the token from `grabbar status --json` (`entries[].token`), then `grabbar restore g1789644541-6 --original`. Tokens are stable until the backend restarts.

A full, machine-oriented write-up is in [docs/PROTOCOL.md](docs/PROTOCOL.md).

## Development

### Build & test

```sh
# native backend
make -C native/grabbar CXX=g++

# QML syntax (import-path warnings are expected and fine)
/usr/lib/qt6/bin/qmllint --bare BarWidget.qml

# offline test suite (must be green)
tests/run.sh
```

**Validate before you deploy:** `tests/run.sh` green, and `qmllint --bare` on any QML you touched. The nested-Hyprland rig in [tests/integration/](tests/integration/) and [docs/QUALIFICATION.md](docs/QUALIFICATION.md) let you exercise the plugin in a nested session, so the live desktop is never needed for testing.

### Worktree layout

Development happens in git worktrees, one per branch:

```sh
git worktree add ../omarchy-window-wt-docs docs/readme   # e.g. this docs branch
```

The live deployed plugin is a separate checkout; **never edit the deployed checkout** — validate in a worktree, then deploy with the rollback path below.

## Deployment, rollback & recovery

The author's daily-driver desktop deploys this fork through the `omarchy-rescue` helper rather than `omarchy plugin add`:

```sh
omarchy-rescue grabbar-on    # symlink this fork into the plugins dir + restart shell
omarchy-rescue grabbar-off   # restore the stable copy
```

Parked/replaced plugin copies are deliberately kept **outside** the plugins directory, so a same-id parked copy can never shadow the deployed one (see [Troubleshooting](#troubleshooting)). A shell restart is `omarchy restart shell`; the native service is `keepLoaded`, so hot reloads keep the old backend.

### Keeping the desktop alive

The operator's desktop runs a small recovery toolkit alongside the plugin (not part of this repository):

- **`omarchy-rescue`** — subcommands `status`, `shell`, `grabbar-off`, `grabbar-on`, `logs`, `sysrq`, `reboot`.
- **systemd --user watchdog** — `omarchy-shell-watchdog.timer` probes the shell every 15 s and restarts it after 3 consecutive failures.
- **Keybind** — `SUPER+CTRL+SHIFT+R` = "Rescue desktop".
- **Root-level half** — hardware watchdog / sysrq / panic handling, installed once with `sudo install.sh`.

## Troubleshooting

**Shell frozen with `TypeError: Cannot assign to read-only property "settings"`.**
Upstream's bar assigns `settings` (and `moduleName`, `bar`) onto every widget. If those are `readonly`, the assignment throws and wedges the shell. Fixed in commit `0d79811`. **Rule for contributors: never make `settings`, `moduleName`, or `bar` `readonly` in a widget.** Full write-up: [SYSTEM-BREAKING-BUG.md](SYSTEM-BREAKING-BUG.md).

**A parked plugin copy shadows the deployed one.**
Omarchy loads plugins by id, so two copies of `tech.greyforge.grabbar` anywhere under the plugins directory is ambiguous. Keep replaced copies *outside* the plugins directory (that is exactly why `grabbar-off` parks them outside).

**Two stacked taskbar surfaces on one monitor.**
Omarchy creates one bar per monitor, and the taskbar panel doesn't bind a screen — so with two monitors you can get both panels stacked on the same monitor. A fix is in development; see [Known issues](#known-issues).

## Known issues

1. **Multi-monitor duplicate taskbar surfaces.** Because the panel doesn't bind a screen and Omarchy spawns one bar per monitor, two taskbar surfaces can end up stacked on one monitor. A fix is in development.
2. **`m_showOnHover` flag reuse.** In the native backend, `m_showOnHover` is reused both as the mode flag and as the revealed-state flag (a pre-existing, upstream-adjacent issue).

## Roadmap (in development)

- **Windows-style snap-lock** — dragging a window to a screen edge snaps it into a tiled/locked position (native).
- **Browser-like tab groups** — dropping a window onto another makes the target the *host* and adds a tab strip to its bar; alt-tab cycles within the tabs while the pointer is over those windows and otherwise falls through to normal alt-tab; closing a group asks "are you sure you want to close all the windows?" like a browser, with a future tab-save feature. (`tabGroups` is the reserved setting.)
- **Live verification harness** — `tests/integration/live-verify.sh` to run the qualification checks against the real desktop.

## Documentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — how the pieces fit together
- [docs/PROTOCOL.md](docs/PROTOCOL.md) — the IPC/status protocol in detail
- [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md) — what works on which Omarchy/Hyprland/Quickshell versions
- [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md) — install/uninstall mechanics
- [docs/QUALIFICATION.md](docs/QUALIFICATION.md) — the test suite and nested rig
- [docs/AUTOLOAD.md](docs/AUTOLOAD.md) — autoload and the recovery journal
- [docs/UPSTREAM.md](docs/UPSTREAM.md) — lineage and upstream differences
- [docs/RELEASE-SAFETY.md](docs/RELEASE-SAFETY.md) — release checklist
- [CHANGELOG.md](CHANGELOG.md) — version history
- [CONTRIBUTING.md](CONTRIBUTING.md) / [SECURITY.md](SECURITY.md)

## License & credits

MIT — the original Grabbar plugin is Copyright (c) 2024 GreyforgeLabs (see [LICENSE](LICENSE)). The native title-bar backend derives from **hyprbars** and is BSD-3-Clause (see [THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES)). Both notices are retained intact, as required for a fork.
