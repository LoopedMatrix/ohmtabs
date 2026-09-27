# OhmTabs overlay build order & design rules

OhmTabs is **not a shell**. It is a dock + window-controls plugin (MIT + BSD-3). This doc captures what is shipped, what is in the current batch, what is explicitly out of scope, and the design constraints. Complements `docs/ohm-shell-modules.md` and `docs/caelestia-dock-inventory.md`.

---

## 1. Shipped

- **Dual-menu fix** — the taskbar context menu and the dock menu no longer conflict; one overlay, one menu per interaction point.
- **Workspace chips** — `DockWorkspaces.qml`: compact pills on the pill dock, click-to-switch via Quickshell `Hyprland` dispatcher (wrapped with `-i <signature>`, never bare `hyprctl dispatch`).
- **Toggles** — `showAppsButton`, `showRunning`, `showClock`, `showWorkspaces` all wired; defaults per `docs/ohm-shell-modules.md`.
- **Pin / launch** — pinned apps persist with no window open; click launches or restores. Running-window dots/badges computed from `liveCount`/`minCount`.
- **Glassy pill** — the compact pill dock uses the glassy aesthetic already established in OhmTabs.
- **Exclusive zone 62 px** — `panelSize` exclusive zone is on for the compact pill (not gated on `fullLength`).

## 2. This batch (independent overlays, OhmTabs style)

Each is its own Quickshell component, gated by a settings key, built in dependency order. Later modules reuse earlier primitives. None replaces the dock.

| # | Module | Trigger | Status |
|---|--------|---------|--------|
| 1 | **Notification drawer** | `showNotifs=true`, badge/tray-slot click | not started |
| 2 | **OSD** (volume/brightness) | `showOsd=true`, keybind/system event | not started |
| 3 | **Dashboard** (overview) | `showDashboard=true`, super/overlay keybind or dock button | not started |
| 4 | **Hover preview** (window thumbnail popout) | hover on a dock icon | not started |
| 5 | **Clock polish** | existing `showClock` — hover weekday/date, full-length larger clock + date | not started |

- **Notif drawer:** read from a notification provider (D-Bus `org.freedesktop.Notifications` or a small daemon); scrollable list; click clears, click outside closes. Anchored to the pill dock side — does **not** replace the dock. Reimplement *behavior* only; Caelestia's drawer is GPL-3 — no QML/QuickShell reuse.
- **OSD:** floating bar with icon + percentage; auto-hide after ~2 s; fades in over the pill dock (animate `opacity`), does not obscure it entirely. Depends on shared overlay base from #1.
- **Dashboard:** all open windows grouped by workspace, a search bar, quick settings (WiFi/Bluetooth/volume) as **small sub-overlays**, not a monolithic menu. Full-screen OhmTabs-styled; exit on Escape or click outside. Depends on #4.
- **Hover preview:** elided title + live thumbnail popout on dock icon hover. The *concept* is free; OhmTabs must use its own thumbnail path — no `ScreencopyView`/`Preview.qml` from Caelestia.
- **Clock polish:** 1 s `QTimer` polling, `Qt.formatDateTime`; hover shows weekday/date in the pill; full-length mode shows a larger clock + date.

## 3. Later — NOT in OhmTabs

These are owned by Omarchy already. We will **not** replace the shell or add a second dock plugin.

- **System tray** — Omarchy owns the tray; OhmTabs does not reimplement it.
- **Lock screen** — Omarchy/Caelestia territory; out of OhmTabs scope.
- **Wallpaper engine** — not a dock concern.
- **Sidebar** — not a dock concern.

If Omarchy later ships dock-relevant pieces (e.g. a tray integration), OhmTabs consumes them via settings/IPC — it does not duplicate them.

## 4. Design rules

- **Colors / shape:** use `Color.menu`, `Color.accent`, `Style.cornerRadius` — the pill dock speaks that language. New overlays match the same token set; no ad-hoc colors.
- **Pill dock first:** the compact pill (62 px exclusive zone) is the primary dock form. Full-length mode extends it; it does not replace it.
- **One overlay at a time:** a single overlay context per interaction. Never Qt `Menu` + OhmTabs overlay together on the same trigger.
- **No second dock plugin:** no `omarchy plugin add` of Caelestia, omadock, macos.dock, or animated.dock. OhmTabs is the dock.
- **No `caelestia-shell`:** do not start it; do not import from `/etc/xdg/quickshell/caelestia`.
- **No bare `hyprctl dispatch`:** wrap with `-i <signature>` or use the Quickshell `Hyprland` API.
- **Settings keys already exist:** `showNotifs`, `showDashboard`, `showOsd` (all default `false`). Wire each overlay to its key; no new settings needed for this batch.

## 5. Settings reference

Defaults are defined in `docs/ohm-shell-modules.md`; the keys relevant to this batch:

| Key | Default | Module |
| --- | --- | --- |
| `showNotifs` | false | Notification drawer |
| `showDashboard` | false | Dashboard overlay |
| `showOsd` | false | Volume/brightness OSD |

`showAppsButton`, `showRunning`, `showClock`, `showWorkspaces` are already wired and shipping.
