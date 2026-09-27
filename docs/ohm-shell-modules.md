# OhmTabs shell modules (independent of Caelestia)

Caelestia (`caelestia-dots/shell`) is GPL-3.0. OhmTabs is MIT + BSD-3.
**Do not copy** anything from `/etc/xdg/quickshell/caelestia` or GitHub `caelestia-dots/shell`.
Reimplement behaviors in this plugin, gated by settings, drawn in OhmTabs style.

## Settings keys (defaults)

| Key | Default | Module |
| --- | --- | --- |
| `showAppsButton` | true | Apps grid → `omarchy-menu` |
| `showRunning` | true | Running app icons |
| `showWorkspaces` | false | Workspace pills on the dock |
| `showClock` | false | Clock on the dock |
| `showNotifs` | false | Notification drawer (not started) |
| `showDashboard` | false | Dashboard overlay (not started) |
| `showOsd` | false | Volume/brightness OSD (not started) |

## Rules

- One overlay, one context menu. Never Qt `Menu` + OhmTabs overlay together.
- Exclusive zone stays on for the compact pill (`panelSize`, not gated on `fullLength`).
- No `omarchy plugin add` of Caelestia, omadock, macos.dock, or animated.dock.
- No `hyprctl dispatch` without `-i <signature>`; prefer Quickshell `Hyprland` APIs.
- Do not start `caelestia-shell`.
