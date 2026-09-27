# User guide — OhmTabs

OhmTabs is the window chrome plugin for Omarchy: a title strip on each app, a pill taskbar, and an Alt+Tab HUD. This page is the day-to-day guide. Architecture and the on-wire protocol live in [ARCHITECTURE.md](ARCHITECTURE.md) and [PROTOCOL.md](PROTOCOL.md).

---

## What you get

1. **Title strip** on ordinary application windows (menu, minimize, maximize, close, drag).
2. **Pill taskbar** on the bottom edge (open windows, minimized windows, pins). Compact by default; it still reserves **62 px** so tiled windows are not clipped.
3. **Alt+Tab HUD** when you bind `ohmtabs alttab`.
4. **Dock Settings** from a right-click on empty dock (or the bar widget).

Optional extras (all **off** unless you turn them on): workspace pips, focused-window title, clock, mute/Wi-Fi/Bluetooth chips, notification drawer, window overview, volume/brightness OSD, − □ × on the Omarchy top bar, window tab groups.

---

## Title strip

Every managed window gets a **glass pill** strip above its top edge (same fill and accent outline as the dock). Tabbed windows (drop one onto another) show that app’s icon on each tab.

| Control | Action |
| --- | --- |
| Menu (hamburger) or right-click the strip | Window menu |
| **−** | Minimize to the dock |
| **□** | Maximize / restore |
| **×** | Close |
| Drag the strip | Move. A tiled window detaches to floating at 60 %. |
| Double-click the title | Toggle maximize |

Controls sit on the right (`buttonsLeft: true` moves them left). Hide the strip for one app with **Hide OhmTabs for …** on that window’s menu, or `excludedClasses` in settings.

The native half draws the strip. If Minimize is refused and there is no strip, the `.so` is not loaded — see [Troubleshooting](#troubleshooting).

---

## Taskbar

Minimizing parks the window on `special:ohmtabs-minimized`. The dock is a **centered pill** (not a full-width bar unless *Full length* is on).

| Gesture | Action |
| --- | --- |
| Left-click, running | Focus that window |
| Left-click, minimized | Restore to the **current** workspace |
| Left-click, pin with no window | Launch (`gtk-launch` / desktop id) |
| Right-click an icon | Pin, launch, restore, minimize, maximize, float, close. Close of a minimized window asks first. |
| Right-click empty dock | Dock Settings |
| Hover | Name card when *Icon name on hover* is on; icons magnify when *Icon magnify* is on |
| Restore-all chip | Appears when two or more windows are minimized |

Pinned id and running class are the same dock identity: `com.vendor.app`, `app`, and `app.desktop` collapse to one icon.

Leave **Hide when windows overlap** off unless you want the dock to dodge — the reserved 62 px strip is what stops windows sitting under the pill.

### Optional dock modules

Turn these on in Dock Settings if you want them. Defaults keep the dock as **apps only**.

| Setting | Default | Notes |
| --- | --- | --- |
| Apps button | on | Opens the Omarchy menu |
| Running apps | on | Live windows |
| Workspaces | off | Pips 1–N, click or scroll |
| Active window | off | Focused title next to the icons (easy to mistake for a second app) |
| Clock | off | |
| Status chips | off | Mute, Wi-Fi, Bluetooth — open Omarchy panels |
| Notifications | off | Bell; uses Omarchy’s notification history (no second daemon) |
| Dashboard | off | Overview of open windows |
| OSD | off | Volume / brightness pill |
| Omarchy bar controls | off | − □ × on the **top bar**, not the per-window strip |

---

## Bar widget

The OhmTabs item on the Omarchy bar is a window-stack glyph plus a count.

- **Left-click** — minimized-windows drawer
- **Middle-click** — restore all
- **Right-click** — Dock Settings

It does **not** put − □ × on the top bar unless *Omarchy bar controls* is on.

Drawer keys while focused: `j`/`k` or arrows to move, `Enter` restore, `Shift+Enter` restore to original workspace, `Ctrl+A` restore all, `Esc` dismiss.

---

## Alt+Tab

OhmTabs does not steal the compositor bind by itself. Add this to `~/.config/hypr/bindings.lua`:

```lua
local ohmtabs = os.getenv("HOME") .. "/.config/omarchy/plugins/tech.loopedmatrix.ohmtabs/bin/ohmtabs"
hl.unbind("ALT + TAB")
hl.unbind("ALT + SHIFT + TAB")
hl.bind("ALT + TAB", hl.dsp.exec_cmd(ohmtabs .. " alttab next"), { description = "OhmTabs: alt-tab" })
hl.bind("ALT + SHIFT + TAB", hl.dsp.exec_cmd(ohmtabs .. " alttab prev"), { description = "OhmTabs: alt-tab (back)" })
```

`hl.unbind` matters: Omarchy binds Alt+Tab twice. Each press then:

1. **Tab group** — if the focused window is in a group, or the pointer is on that host, cycle its tabs.
2. **Otherwise** — OhmTabs HUD on the focused monitor. Release Alt to switch, Escape to cancel.
3. Browser *document* tabs stay on `Ctrl+PageDown` / `Ctrl+PageUp` inside the browser.

`ohmtabs alttab --decide` prints the decision as JSON without switching.

---

## Window tabs (opt-in)

Set `tabGroups: true`.

- Drop a window onto another — the target becomes the **host**; its strip grows tabs.
- Click a tab to switch; drag a tab out to detach. One remaining tab dissolves the group.
- Closing a group with more than one window asks *close all N windows?* Cancel / Escape does nothing.

---

## Settings reference

Keys live on the plugin’s `shell.json` entry and hot-apply. Invalid values fall back to the default (`OhmTabsModel.js`).

| Key | Type | Default |
| --- | --- | --- |
| `enabled` | bool | `true` |
| `buttonsLeft` | bool | `false` |
| `showOnHover` | bool | `false` |
| `controlSize` | `"standard"` \| `"large"` | `"standard"` |
| `excludedClasses` | string[] | `[]` |
| `sidePanel` | bool | `true` |
| `panelPosition` | `"bottom"` \| `"top"` \| `"left"` \| `"right"` | `"bottom"` |
| `panelAutoHide` | bool | `false` |
| `barWindowControls` | bool | `false` |
| `iconSize` | 16–48 | `38` |
| `tintIcons` | bool | `false` |
| `showIconName` | bool | `false` |
| `magnify` | bool | `true` |
| `iconZoom` | 0–1 | `0.48` |
| `panelBorder` | bool | `true` |
| `panelBorderOpacity` | 0–1 | `0.95` |
| `panelBgOpacity` | 0.15–1 | `0.78` |
| `fullLength` | bool | `false` |
| `cornerShape` | `"pill"` \| `"rounded"` \| `"square"` | `"pill"` |
| `pinnedApps` | string[] | `[]` |
| `showAppsButton` | bool | `true` |
| `showRunning` | bool | `true` |
| `dockDodge` | bool | `false` |
| `showWorkspaces` | bool | `false` |
| `workspaceCount` | 1–10 | `5` |
| `showActiveWindow` | bool | `false` |
| `showClock` | bool | `false` |
| `showStatus` | bool | `false` |
| `showNotifs` | bool | `false` |
| `showDashboard` | bool | `false` |
| `showOsd` | bool | `false` |
| `tabGroups` | bool | `false` |

`browserClasses` is read by the `alttab` helper only (not the QML schema). Empty means the built-in browser list.

### Native fallback (before the shell connects)

`plugin:ohmtabs:*` in `hyprland.lua`: `enabled`, `buttons_left`, `bar_height` (34), `button_size` (32), `padding` (4), `text_size` (11), `text_font` (`"Sans"`), colours, `shell_grace_ms` (2000). Per-window opt-out: window rule `ohmtabs:no_bar`.

Apply a patch without opening Settings:

```sh
omarchy-shell tech.loopedmatrix.ohmtabs applySettings '{"showWorkspaces":false,"showStatus":false}'
```

---

## Command line & IPC

`bin/ohmtabs` wraps the plugin. `omarchy-shell tech.loopedmatrix.ohmtabs <method>` is the same surface.

Useful methods: `ping`, `status`, `settingsDump`, `applySettings`, `minimize`, `restore`, `restoreAll`, `openDrawer`, `openSettings`, `openNotifs`, `openDashboard`, `altTabNext`, `altTabPrev`, `altTabCancel`, tab-group verbs (`groupCreate`, `groupCycle`, `groupClose`, …).

Tokens are `g<epoch>-<generation>` from `ohmtabs status --json`. Full table: [PROTOCOL.md](PROTOCOL.md).

---

## Troubleshooting

**No title strips.** `hyprctl plugin list` should include OhmTabs. Load `native/ohmtabs/ohmtabs.so`, then `ohmtabs autoload enable`. After a crash the autoload fuse may sit off — `ohmtabs autoload retry` only against a known-good `.so`.

**Dock vanished but windows still inset ~62 px.** Exclusive zone is up; the pill width went to 0 (conflicting anchors). Restart the shell after a QML fix; do not turn auto-hide on as a workaround.

**Two icons for one app.** Pin id and window class now share a dock key. If a **word** sits next to a real icon, that is the *Active window* chip — turn it off.

**Two menus on right-click.** Current builds use one overlay. If you still see a Qt menu, you are not on this checkout.

**Do not run a second dock or minimize plugin.** They share `special:…-minimized` or the bottom layer.

**Never write into a mapped `.so`.** Replace the inode with `mv`. A compositor restart is required to pick up a new native binary.

Parked plugin copies must live **outside** `~/.config/omarchy/plugins/` or Omarchy may load the wrong tree for the same id.

---

## Known issues

1. Native `m_showOnHover` is both mode and revealed-state (upstream).
2. Auto-hide reveal is unreliable — default is off.
3. Tab-strip selected/unselected contrast is weak.
