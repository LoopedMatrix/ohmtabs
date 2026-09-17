# Usage — Grabbar (shell widget)

This documents the **shell widget** side of the Grabbar plugin — the Quickshell/QML bar, the minimized-window panel, the IPC the shell speaks with the native backend, and the configuration keys the bar reads from the user's layout entry. The native backend (title-strip drawing, window actions, protocol encoding) is covered separately in [ARCHITECTURE.md](ARCHITECTURE.md); the on-wire protocol is in [PROTOCOL.md](PROTOCOL.md).

The shell widget is one module of an Omarchy shell. It is described here on its own so the bar/panel can be configured without reading the whole shell manual, but it obeys the same config, autoload and recovery mechanics as every other shell module. See the host shell docs for things this page does not cover (layout syntax, entry lifecycle, per-monitor bars).

---

## What the bar widget does

The bar widget (`BarWidget.qml`) is the module Omarchy places on each monitor. It hosts the Grabbar bar — a horizontal strip that draws a title button for every managed window, plus the window controls (menu, minimize, maximize, close). A minimized-window side panel (`Panel.qml`) can be enabled independently; it lists minimized windows and lets you restore or close them.

Feature-wise the bar currently provides:

- A title strip for every tracked non-hidden window, with the standard controls and the window menu.
- Minimize-to-drawer / panel behavior, with a two-phase minimize (the shell acknowledges before the backend actually hides the window) so a shell disconnect cannot lose a window.
- Per-window opt-out (`grabbar:no_bar` window rule, or the `excludedClasses` setting).
- A status readout and a config summary via `omarchy-shell tech.greyforge.grabbar stats`.
- IPC verbs for window actions, grouping primitives, and tab-group operations (the tab verbs are only wired when the `tabGroups` setting is on).

The tab strip itself — the visual tab segments on a host window's title strip — is drawn by the **native** backend, not the shell. The shell's job for tabs is the IPC wiring, the group state kept in `GrabbarModel.js`, and the "close all windows in this group?" confirm prompt. See the [Tab groups](#tab-groups) section.

## Panel (minimized-window side panel)

The panel lists minimized windows grouped by workspace or origin as the model provides them, lets you sweep up recovered windows, and has its own per-panel closure confirm (dismiss the panel without closing its windows, or close the panel and its windows). It is separate from the tab-group close-all prompt — one is about hiding a UI surface, the other is about closing every window in a tab group.

## Configuration keys

Configuration for the bar lives in the bar's own entry in the shell layout (`~/.config/omarchy/shell.json` and the host shell's layout files), under the plugin's id. The bar reads these through `GrabbarModel.js`'s `normalizeSettings`, which coerces and validates values and falls back to the defaults below for anything missing or malformed.

| Key | Type | Default | Meaning |
| --- | --- | --- | --- |
| `enabled` | bool | `true` | Whether the bar is active at all. Setting `false` disables the strip and the panel for this layout entry. |
| `buttonsLeft` | bool | `false` | Whether the window-menu / minimize / maximize / close controls sit on the **left** of the title text (`true`) or the right (`false`). |
| `controlSize` | number | `24` | Size (px) of the control buttons. |
| `excludedClasses` | string[] | `[]` | App classes whose windows get no strip. Same effect as the `grabbar:no_bar` window rule but settable per-bar from the shell config. |
| `sidePanel` | bool | `true` | Windows-style taskbar (`true`) vs the in-bar drawer only (`false`). |
| `panelPosition` | `"bottom"` \| `"left"` \| `"right"` | `"bottom"` | Screen edge the taskbar sits on. |
| `panelAutoHide` | bool | `true` | Park the taskbar off the edge until the pointer reaches it. |
| `tabGroups` | bool | `false` | If `true`, the bar accepts window-tab grouping: dropping one window onto another hosts a tab group, alt-tab cycles within the group's tabs while the pointer is over them (and otherwise falls through to normal alt-tab), and closing a group with more than one window asks "are you sure you want to close all N windows?" before closing them. The tab strip itself is drawn by the native backend on the host window's title strip; the shell side is the IPC wiring, the group state in `GrabbarModel.js`, and the close-all confirm prompt. When `tabGroups` is off (the default), the tab verbs are silently ignored and the panel behaves as before — turning it on does not, by itself, change the panel's appearance. |

Unknown keys are ignored; invalid values fall back to the default. Values are validated in [`GrabbarModel.js`](GrabbarModel.js) (`normalizeSettings`).

### Tab groups

When `tabGroups: true` is set on the bar's layout entry:

- **Dropping a window onto another** makes the target the *host* and turns the dragged window into a tab in the host's group. The host's native title strip gains the tab strip (drawn natively). The shell keeps the group state and the window list; the visual strip is the backend's.
- **Alt-tab behavior** changes while the pointer is over the host's tab strip: alt-tab cycles within the group's tabs instead of the global cycle. Once the pointer leaves the tab area, alt-tab falls back to the normal global alt-tab. This is a shell-side decision communicated to the backend; the backend honors it when the pointer is over the tab strip.
- **Closing a group** with more than one window triggers a confirm prompt: "are you sure you want to close all N windows?" with the tab titles listed, like a browser. Yes closes all the group's windows; Cancel/Escape dismisses the prompt with no action. There is no focus steal from the rest of the shell for the prompt.
- The `tabGroups` setting is off by default. Until it is turned on explicitly in the bar's layout entry, the tab verbs are not wired and nothing about the panel changes.

### Native config fallback

When the shell isn't connected yet, the native backend falls back to `plugin:grabbar:*` keys in `hyprland.lua` (these are overridden by the shell theme/settings once connected):

`enabled`, `buttons_left`, `bar_height` (34), `button_size` (32), `padding` (4), `text_size` (11), `text_font` (`"Sans"`), `bar_color`, `inactive_bar_color`, `text_color`, `hover_color`, `close_hover_color`, `shell_grace_ms` (2000). Per-window opt-out via the `grabbar:no_bar` window rule.

## Command line & scripting

The shell exposes the plugin's IPC over the CLI as:

`omarchy-shell tech.greyforge.grabbar <verb> '<json>'`

The helper `helpers/grabbar_backend.py` wraps this for Python callers. The verbs the shell accepts (from `Service.qml`'s `IpcHandler`) include window actions (`minimize`, `maximize`, `toggleMaximize`, `restore`, `kill`, `activate`, `focus`, `menu`), grouping primitives (`group.create`, `group.add`, `group.remove`, `group.removeMember`, `group.activate`, `group.cycle`, `group.close`, `group.closeForce`), and tab-group operations (`tabs.list`, `tabs.join`, `tabs.activate`, `tabs.detach`, `tabs.ungroup`, `tabs.closeAll`) — the tab verbs are only honored when `tabGroups` is on.

### Querying tab-group state

`omarchy-shell tech.greyforge.grabbar stats` prints a JSON status blob that includes a `tabGroups` field (`{ count, groups }`) when the setting is on. The `tabs.list` verb returns the same shape the shell keeps internally:

`omarchy-shell tech.greyforge.grabbar tabs.list '{}'`

→ `{"groups":[{"id":N,"host":"<token>","active":<index>,"tabs":[{"token":"<token>","title":"...","active":bool}]}]}`

This is the shape the shell's tab wrappers and the prompt's title list are built from; it is also what the native backend is expected to reply with once it implements the verb.

## The close-all confirm prompt

When a tab group with more than one window is about to be closed, the shell shows a theme-matched confirm prompt built on the shell's `PopupCard` UI component, so it picks up the user's theme rather than being a separate-styled ad-hoc card. The prompt lists the tab titles and offers **Cancel** and **Close all**; Escape dismisses it with no action. The prompt does not steal focus from the rest of the shell. This prompt is distinct from the panel's own close-confirm (which is about hiding the panel, not closing windows).

## Replaced-copy / shadow note

A parked plugin copy shadows the deployed one. Omarchy loads plugins by id, so two copies of `tech.greyforge.grabbar` anywhere under the plugins directory is ambiguous. Keep replaced copies *outside* the plugins directory (that is exactly why `grabbar-off` parks them outside).

## Two stacked taskbar surfaces on one monitor

Omarchy creates one bar per monitor, and the taskbar panel doesn't bind a screen — so with two monitors you can get both panels stacked on the same monitor. A fix is in development; see [Known issues](#known-issues).

## Known issues

1. **Multi-monitor duplicate taskbar surfaces.** Because the panel doesn't bind a screen and Omarchy spawns one bar per monitor, two taskbar surfaces can end up stacked on one monitor. A fix is in development.
2. **`m_showOnHover` flag reuse.** In the native backend, `m_showOnHover` is reused both as the mode flag and as the revealed-state flag (a pre-existing, upstream-adjacent issue).
