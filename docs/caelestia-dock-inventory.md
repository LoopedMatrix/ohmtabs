# Caelestia vs OhmTabs — Dock/Taskbar Feature Inventory

**Scope:** what a standalone Omarchy dock (omadock-in-taskbar) can reimplement independently, versus what must not be copied from Caelestia (`caelestia-dots/shell`, GPL-3.0).

**Sourcing:** Caelestia = `/etc/xdg/quickshell/caelestia`; OhmTabs = this worktree. No file copied from `/etc/xdg/quickshell/caelestia`. No `caelestia-shell` started.

---

## Caelestia (GPL-3.0) — full desktop shell

Caelestia is a **complete shell**: `shell.qml` boots `Background`, `Drawers`, `AreaPicker`, `Lock`, plus `modules/` (bar, launcher, dashboard, lock, sidebar, notifications, OSD, session, utilities, windowinfo, nexus settings). The bar module is one slice of that shell.

Key bar-module pieces we inspected:

- **`modules/bar/Bar.qml`** — the top bar: workspaces, active-window title, system tray, clock, status icons, popouts.
- **`modules/bar/components/ActiveWindow.qml`** — the focused-window title block (icon + elided title, hover/click popout wiring).
- **`modules/bar/popouts/ActiveWindow.qml`** — the active-window details popout: app icon, title, class, `ScreencopyView` preview.
- **`modules/windowinfo/Preview.qml`** — `ScreencopyView` live preview of a `HyprlandToplevel`.
- **`modules/launcher/`** — full app launcher (`AppList.qml`, `AppItem.qml`, `Apps` service, search, calc/scheme/variant actions).
- **`modules/nexus/pages/panels/taskbar/`** — settings pages for bar active-window, tray, workspaces, clock.
- **`modules/dashboard/`, `modules/lock/`, `modules/sidebar/`, `modules/background/`** — dashboard, lock screen, sidebar, wallpaper engine.

## OhmTabs (MIT + BSD-3 inherited) — window-controls + dock

OhmTabs is **not a shell**. It is a Quickshell plugin + native Hyprland plugin that adds:

- **Window title strips** (menu, minimize, maximize/restore, close, drag-to-move) on ordinary windows.
- **A 46 px taskbar** (`SidePanel.qml`): one icon per window, open + minimized, left/right/bottom, opt-in auto-hide, app icons, right-click menus, restore-all chip.
- **Browser-style tab groups** (opt-in): drop a window onto another to make it the host, smart alt-tab, drag-out to detach, close-all confirmation.
- **Hot-applied settings** + IPC/CLI surface (`OhmTabsModel.js`, protocol codec, journal, reconciliation logic).

## Dock-relevant behaviors — safe to reimplement (independently)

These are **generic taskbar/dock concepts** OhmTabs already implements in this worktree; they can be extended without copying Caelestia code:

- **Pin apps to the dock** — `SidePanel.qml` already has `pinnedApps` + `pushApp(appId, true)`; pinned icons persist with no window open (launch-from-dock).
- **Launch apps from the dock** — pinned + running icons are click-to-launch/restore; the model merges pinned, live, and minimized entries.
- **Hover labels on icons** — `SidePanel.qml` has `showIconName` + hover zoom (`magnify`, `iconZoom`); a text label above the icon on hover is a small addition.
- **Running-window dots / window count badges** — the model already computes `liveCount`/`minCount` per app; a dot or badge on the pinned icon is a natural extension.
- **Apps-grid / launcher button** — `SidePanel.qml` already has `showAppsButton` + an `apps` entry in `items`; wiring it to an app grid/launcher is the omadock goal.
- **Window preview titles** — OhmTabs has window titles via `ToplevelManager.toplevels`; showing an elided title under/over a dock icon is straightforward (Caelestia's *approach* is GPL, but the idea — show the focused/window title — is not protectable).
- **Window preview thumbnail popout** — the *concept* of a hover popout showing a window preview is generic; OhmTabs would use its own thumbnail/preview path, not Caelestia's `ScreencopyView`/`Preview.qml`.

## Must NOT copy (GPL-3.0 contagion surface)

These are Caelestia-specific implementations — **do not reuse their QML/JS/assets**:

- **Bar module internals** — `modules/bar/Bar.qml`, `ActiveWindow.qml`, `Workspaces.qml`, `Clock.qml`, `Tray.qml`, `StatusIcons.qml`, all bar popouts. These are Caelestia's bar, not a generic dock.
- **Active-window title popout + preview popout** — `modules/bar/popouts/ActiveWindow.qml`, `modules/windowinfo/Preview.qml`, `modules/windowinfo/WindowInfo.qml`. Any preview/title-popout in omadock must be its own component.
- **App launcher** — `modules/launcher/` (AppList, AppItem, Actions/Apps/Schemes services, Content, ContentList, search). A dock launcher must be built from scratch or reuse OhmTabs' existing app model.
- **Dashboard, lock, sidebar, wallpaper engine** — `modules/dashboard/`, `modules/lock/`, `modules/sidebar/`, `modules/background/`. Whole modules, not dock-relevant.
- **Nexus settings pages** — `modules/nexus/pages/...` including `taskbar/` subpages. Settings UI for omadock must be its own.
- **Caelestia utilities & services** — `utils/`, `services/` (Colours, Icons, Screencopy wiring, Notifs, Wallpapers, etc.), `shell.qml` module orchestration.
- **Assets** — `assets/` (logo.svg, bongocat.gif, dino.png, GoogleSansFlex font, pam.d scripts, wallpaper.webp).

## Gray area — concept vs implementation

- **"Show the active window title on hover"** — the *idea* is free; Caelestia's `ActiveWindow.qml` + `activeWindow` popout are not. OhmTabs shows titles on its taskbar buttons already; a separate preview popout is omadock's to design.
- **"Window preview on hover"** — generic concept; Caelestia's `ScreencopyView`-based preview in `Preview.qml`/`ActiveWindow popout` is the GPL implementation to avoid.
- **"App grid / launcher"** — concept is free; Caelestia's `modules/launcher/` is not reusable. OhmTabs already has an `apps` entry; the grid UI is omadock's.

## Bottom line

A dock built on OhmTabs can have: pinned apps, launch-from-dock, running-window indicators/dots, hover labels, apps-grid button, window preview titles, and a hover preview popout — all implemented as new/extended OhmTabs code in this worktree.

It must not import, subclass, or copy Caelestia QML/JS/assets for: the bar itself, the active-window title block, the active-window / window-info popouts, the launcher, the dashboard, the lock, the sidebar, the wallpaper engine, or the nexus settings pages.
