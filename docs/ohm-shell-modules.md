# OhmTabs shell modules (independent of Caelestia)

Caelestia (`caelestia-dots/shell`) is GPL-3.0. OhmTabs is MIT + BSD-3.
**Do not copy** anything from `/etc/xdg/quickshell/caelestia` or GitHub `caelestia-dots/shell`.
Reimplement behaviors in this plugin, gated by settings, drawn in OhmTabs style.

## Settings keys (defaults)

| Key | Default | Module |
| --- | --- | --- |
| `showAppsButton` | true | Apps grid → `omarchy-menu` |
| `showRunning` | true | Running app icons |
| `showWorkspaces` | false | Workspace pills on the dock (`DockWorkspaces.qml`) |
| `showClock` | false | Clock on the dock |
| `showNotifs` | false | Notification drawer (not started) |
| `showDashboard` | false | Dashboard overlay (not started) |
| `showOsd` | false | Volume/brightness OSD (not started) |

## Implementation order (independent overlays)

Add each overlay as its own Quickshell QuickShell component, gated by the settings key above. Build in this order — later modules reuse earlier ones.

### 1. Workspaces click-to-switch (on the dock)
- **Trigger:** `showWorkspaces`=true, workspace pill clicked.
- **Behavior:** Switch Hyprland workspace via Quickshell `Hyprland` Lua dispatcher (Hyprland 0.56+). Do **not** use bare `hyprctl dispatch workspace <N>` — wrap in `-i <app signature>` or use the Quickshell API.
- **Drawable:** Compact pill icons on the pill dock; replicas for full-length mode. Each pill shows the active workspace highlight and a fade-in preview for the target workspace (optional, gated behind a separate `workspacePreview` key).
- **Depends on:** nothing.

### 2. Clock (on the dock)
- **Trigger:** `showClock`=true.
- **Behavior:** Qt `QTimer` polling `date`/`time` at 1 s; format via `Qt.formatDateTime`. Show weekday/date on hover in the pill.
- **Drawable:** Single text element on the pill dock; full-length mode shows a larger clock + date.
- **Depends on:** nothing.

### 3. Notification drawer (overlay)
- **Trigger:** `showNotifs`=true, notif count badge clicked or tray reserved slot.
- **Behavior:** Read `notification-list` from a provider (e.g. a small daemon or Quickshell plugin that listens to D-Bus `org.freedesktop.Notifications`). Render a scrollable list; click clears, click outside closes.
- **Drawable:** OhmTabs-style overlay anchored to the pill dock side; does **not** replace the dock.
- **Depends on:** 2 (layout anchors).
- **GPL note:** Caelestia's notif drawer is GPL-3 — reimplement the *behavior* (show list, dismiss) in MIT code; do not reuse its QML/QuickShell files.

### 4. OSD (volume / brightness overlay)
- **Trigger:** `showOsd`=true; user changes volume or brightness via keybinds or system events.
- **Behavior:** Listen for Hyprland `exec` signals or a D-Bus property change; show a floating bar with icon + percentage. Auto-hide after 2 s.
- **Drawable:** Overlay that fades in over the pill dock; does not obscure the dock entirely (animate `opacity`).
- **Depends on:** 2, 3 (shared overlay base).

### 5. Dashboard overlay (overview)
- **Trigger:** `showDashboard`=true; super/overlay keybind or dock button.
- **Behavior:** Show all open windows grouped by workspace, a search bar, and quick settings (WiFi, Bluetooth, volume) — each quick-setting is its own small overlay, not a monolithic menu.
- **Drawable:** Full-screen overlay, OhmTabs-styled; exit on Escape or click outside.
- **Depends on:** 4 (overlay primitives + quick-setting sub-overlays).

### 6. Apps grid (`omarchy-menu`) — already exists
- **Trigger:** `showAppsButton`=true, apps button clicked.
- **Behavior:** Launch `omarchy-menu`; do not reimplement the grid here.
- **Depends on:** nothing new.

## Rules
- One overlay, one context menu. Never Qt `Menu` + OhmTabs overlay together.
- Exclusive zone stays on for the compact pill (`panelSize`, not gated on `fullLength`).
- No `omarchy plugin add` of Caelestia, omadock, macos.dock, or animated.dock.
- No `hyprctl dispatch` without `-i <signature>`; prefer Quickshell `Hyprland` APIs.
- Do not start `caelestia-shell`.
