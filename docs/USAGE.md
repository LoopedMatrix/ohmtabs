# Usage — OhmTabs (shell widget)

This documents the **shell widget** side of the OhmTabs plugin — the Quickshell/QML bar, the minimized-window panel, the IPC the shell speaks with the native backend, and the configuration keys the bar reads from the user's layout entry. The native backend (title-strip drawing, window actions, protocol encoding) is covered separately in [ARCHITECTURE.md](ARCHITECTURE.md); the on-wire protocol is in [PROTOCOL.md](PROTOCOL.md).

The shell widget is one module of an Omarchy shell. It is described here on its own so the bar/panel can be configured without reading the whole shell manual, but it obeys the same config, autoload and recovery mechanics as every other shell module. See the host shell docs for things this page does not cover (layout syntax, entry lifecycle, per-monitor bars).

---

## What the bar widget does

The bar widget (`BarWidget.qml`) is the module Omarchy places on each monitor. It hosts the OhmTabs bar — a horizontal strip that draws a title button for every managed window, plus the window controls (menu, minimize, maximize, close). A minimized-window side panel (`Panel.qml`) can be enabled independently; it lists minimized windows and lets you restore or close them.

Feature-wise the bar currently provides:

- A title strip for every tracked non-hidden window, with the standard controls and the window menu.
- Minimize-to-drawer / panel behavior, with a two-phase minimize (the shell acknowledges before the backend actually hides the window) so a shell disconnect cannot lose a window.
- Per-window opt-out (`ohmtabs:no_bar` window rule, or the `excludedClasses` setting).
- A status readout and a config summary via `omarchy-shell tech.loopedmatrix.ohmtabs status`.
- IPC verbs for window actions, grouping primitives, and tab-group operations (the tab verbs are only wired when the `tabGroups` setting is on).

The tab strip itself — the visual tab segments on a host window's title strip — is drawn by the **native** backend, not the shell. The shell's job for tabs is the IPC wiring, the group state kept in `OhmTabsModel.js`, and the "close all windows in this group?" confirm prompt. See the [Tab groups](#tab-groups) section.

## Panel (minimized-window side panel)

The panel lists minimized windows grouped by workspace or origin as the model provides them, lets you sweep up recovered windows, and has its own per-panel closure confirm (dismiss the panel without closing its windows, or close the panel and its windows). It is separate from the tab-group close-all prompt — one is about hiding a UI surface, the other is about closing every window in a tab group.

## Configuration keys

Configuration for the bar lives in the bar's own entry in the shell layout (`~/.config/omarchy/shell.json` and the host shell's layout files), under the plugin's id. The bar reads these through `OhmTabsModel.js`'s `normalizeSettings`, which coerces and validates values and falls back to the defaults below for anything missing or malformed.

| Key | Type | Default | Meaning |
| --- | --- | --- | --- |
| `enabled` | bool | `true` | Whether the bar is active at all. Setting `false` disables the strip and the panel for this layout entry. |
| `buttonsLeft` | bool | `false` | Whether the window-menu / minimize / maximize / close controls sit on the **left** of the title text (`true`) or the right (`false`). |
| `controlSize` | number | `24` | Size (px) of the control buttons. |
| `excludedClasses` | string[] | `[]` | App classes whose windows get no strip. Same effect as the `ohmtabs:no_bar` window rule but settable per-bar from the shell config. |
| `sidePanel` | bool | `true` | Windows-style taskbar (`true`) vs the in-bar drawer only (`false`). |
| `panelPosition` | `"bottom"` \| `"left"` \| `"right"` | `"bottom"` | Screen edge the taskbar sits on. |
| `panelAutoHide` | bool | `false` | Opt-in. Park the taskbar off the edge until the pointer reaches it. When it is on, the panel shows only its reveal sliver until the pointer arrives, so it reserves nothing while parked. |
| `browserClasses` | string[] | `[]` (built-in list) | Window-class fragments the `alttab` helper treats as browsers, matched case-insensitively as substrings. Empty means the built-in list (Brave, Chrome, Chromium, Edge, Vivaldi, Opera, Firefox, LibreWolf, Waterfox, Zen, Floorp, qutebrowser, Epiphany, Falkon). This key is read by the `alttab` helper directly, so it is not part of the shell's own settings schema. |
| `tabGroups` | bool | `false` | If `true`, the bar accepts window-tab grouping: dropping one window onto another hosts a tab group, the `alttab` helper cycles a group's tabs when the pointer is on its host or the group is focused (see **Alt-tab** below), and closing a group with more than one window asks "are you sure you want to close all N windows?" before closing them. The tab strip itself is drawn by the native backend on the host window's title strip; the shell side is the IPC wiring, the group state in `OhmTabsModel.js`, and the close-all confirm prompt. When `tabGroups` is off (the default), the tab verbs are silently ignored and the panel behaves as before — turning it on does not, by itself, change the panel's appearance. |

Unknown keys are ignored; invalid values fall back to the default. Values are validated in [`OhmTabsModel.js`](OhmTabsModel.js) (`normalizeSettings`).

### Tab groups

When `tabGroups: true` is set on the bar's layout entry:

- **Dropping a window onto another** makes the target the *host* and turns the dragged window into a tab in the host's group. The host's native title strip gains the tab strip (drawn natively). The shell keeps the group state and the window list; the visual strip is the backend's.
- **Alt-tab is smart, and it is one key for three jobs.** `ohmtabs alttab next|prev` decides, every press, in this order:
  1. **A tab group** — if the focused window is in a tab group, or the pointer is on a host window (on its client box or on the tab strip above it), the group's tabs cycle. This is the `groupCycle` IPC call, and it works whether the pointer is inside the window or the window is simply focused.
  2. **A browser** — if the focused window's class matches the browser list, the helper sends the browser its own `Ctrl+PageDown` / `Ctrl+PageUp`, the keystroke every Chromium- and Firefox-family browser uses for next/previous tab. Brave and Chrome switch tabs without an extension or a second process.
  3. **Anything else** — the normal window cycle: Omarchy's own `hl.dsp.window.cycle_next()` followed by `bring_to_top()`, which is exactly what the stock `ALT + TAB` bindings did (both of them), so plain-desktop behaviour is unchanged.

  The decision tree is a pure function with its own unit tests (`tests/unit/test_alttab.py`), and `ohmtabs alttab --decide` prints the decision it would take without doing anything - the way to see why a press went where it went.

- **Closing a group** with more than one window triggers a confirm prompt: "are you sure you want to close all N windows?" with the tab titles listed, like a browser. Yes closes all the group's windows; Cancel/Escape dismisses the prompt with no action. There is no focus steal from the rest of the shell for the prompt.
- The `tabGroups` setting is off by default. Until it is turned on explicitly in the bar's layout entry, the tab verbs are not wired and nothing about the panel changes.

### Native config fallback

When the shell isn't connected yet, the native backend falls back to `plugin:ohmtabs:*` keys in `hyprland.lua` (these are overridden by the shell theme/settings once connected):

`enabled`, `buttons_left`, `bar_height` (34), `button_size` (32), `padding` (4), `text_size` (11), `text_font` (`"Sans"`), `bar_color`, `inactive_bar_color`, `text_color`, `hover_color`, `close_hover_color`, `shell_grace_ms` (2000). Per-window opt-out via the `ohmtabs:no_bar` window rule.

## Alt-tab

`ohmtabs alttab next|prev [--decide]` is the whole interface; bind it yourself:

```lua
-- in ~/.config/hypr/bindings.lua
local ohmtabs = os.getenv("HOME") .. "/.config/omarchy/plugins/tech.loopedmatrix.ohmtabs/bin/ohmtabs"
hl.unbind("ALT + TAB")
hl.unbind("ALT + SHIFT + TAB")
hl.bind("ALT + TAB", hl.dsp.exec_cmd(ohmtabs .. " alttab next"), { description = "OhmTabs: alt-tab" })
hl.bind("ALT + SHIFT + TAB", hl.dsp.exec_cmd(ohmtabs .. " alttab prev"), { description = "OhmTabs: alt-tab (back)" })
```

The `hl.unbind` lines matter: Omarchy binds `ALT + TAB` twice ("Focus on next window" and "Reveal active window on top"), and the helper's fallback reproduces both, so replacing them loses nothing. Delete the block to get the defaults back. Nothing here needs sudo, a daemon or a browser extension.

Two honest limitations:

- A **browser window inside a tab group** follows the group (job 1), not the browser (job 2): a group is an explicit instruction about where that window's tabs live.
- Case 2 asks the browser to switch its tab, so it does nothing in a browser that has only one tab open - which is also what pressing `Ctrl+PageDown` there would do.

## Command line & scripting

The shell exposes the plugin's IPC over the CLI as `omarchy-shell tech.loopedmatrix.ohmtabs <function> [args…]`, where the functions are exactly those declared in `Service.qml`'s `IpcHandler` (the shell rejects any other name):

`status` · `minimize TOKEN` · `restore TOKEN [MODE]` · `restoreAll` · `openDrawer` · `openSettings` · `reconcile` · `disable` · `enable` · `ping` · `groupCreate TOKEN` · `groupRemove TOKEN` · `groupAddMember HOST MEMBER` · `groupRemoveMember TOKEN` · `groupActivate HOST MEMBER` · `groupCycle HOST DIR POINTER_INSIDE` · `groupClose TOKEN` · `groupCloseForce TOKEN`

There is no `stats` function (use `status`) and no `tabs.*` CLI function. The tab verbs are the **shell ↔ native-backend messages** (`tabs.list`, `tabs.join`, `tabs.activate`, `tabs.detach`, `tabs.ungroup`, `tabs.closeAll`): `Service.qml`'s tab wrappers send them over the backend socket (`$XDG_RUNTIME_DIR/ohmtabs/<signature>/backend.sock`, wire format `<type>\t<key>=<value>`), and the panel's tab strip is what invokes them. `helpers/ohmtabs_backend.py` is a client of that same socket (subcommands: `status`, `windows`, `ready`, `minimize`, `restore`, `restore-all`, `maximize`, `restore-size`, `toggle-maximize`, `close`, `float`, `listen`) — it has no tabs subcommand today either.

### Querying tab-group state

`tabs verb=list` on that socket answers with a `tabsList` message carrying one `json` field, in the shape the shell's tab wrappers and the prompt's title list are built from:

`{"groups":[{"id":N,"host":"<token>","active":<index>,"tabs":[{"token":"<token>","title":"...","active":bool}]}]}`

The other tab verbs answer `result` (with `verb`, `status`, `error`), and `tabs.closeAll` is refused unless `confirm` is set — that is what the confirm prompt supplies. `tests/integration/tabs-ipc.py` is an instance-scoped client for these verbs (used by the nested integration test): it addresses one named Hyprland instance and never the running shell, so scripted checks cannot disturb a live session.

## The close-all confirm prompt

When a tab group with more than one window is about to be closed, the shell shows a theme-matched confirm prompt built on the shell's `PopupCard` UI component, so it picks up the user's theme rather than being a separate-styled ad-hoc card. The prompt lists the tab titles and offers **Cancel** and **Close all**; Escape dismisses it with no action. The prompt does not steal focus from the rest of the shell. This prompt is distinct from the panel's own close-confirm (which is about hiding the panel, not closing windows).

## Replaced-copy / shadow note

A parked plugin copy shadows the deployed one. Omarchy loads plugins by id, so two copies of `tech.loopedmatrix.ohmtabs` anywhere under the plugins directory is ambiguous. Keep replaced copies *outside* the plugins directory (that is exactly why `ohmtabs-off` parks them outside).

## Two stacked taskbar surfaces on one monitor

Omarchy creates one bar per monitor, and the taskbar panel doesn't bind a screen — so with two monitors you can get both panels stacked on the same monitor. A fix is in development; see [Known issues](#known-issues).

## Known issues

1. **Multi-monitor duplicate taskbar surfaces.** Because the panel doesn't bind a screen and Omarchy spawns one bar per monitor, two taskbar surfaces can end up stacked on one monitor. A fix is in development.
2. **`m_showOnHover` flag reuse.** In the native backend, `m_showOnHover` is reused both as the mode flag and as the revealed-state flag (a pre-existing, upstream-adjacent issue).
