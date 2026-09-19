# Changelog

## Unreleased

### Alt-tab: tab groups, browser tabs, then the window cycle

- New `ohmtabs alttab next|prev` (helper `helpers/ohmtabs_alttab.py`), one key
  with three jobs decided per press: a tab group the pointer is on or that is
  focused cycles its tabs (`groupCycle`); a focused browser gets its own
  `Ctrl+PageDown`/`Ctrl+PageUp`, so Brave and Chrome switch tabs with no
  extension and no second process; anything else runs the compositor's window
  cycle (`hl.dsp.window.cycle_next()` + `bring_to_top()`), which is what the
  stock Omarchy `ALT + TAB` bindings did — this helper is a superset of them.
- The decision tree is a pure function with unit coverage
  (`tests/unit/test_alttab.py`, wired into `tests/run.sh`); `--decide` prints
  the decision as JSON without acting on it.
- The browser list is configurable (`browserClasses` in the plugin's shell.json
  entry, or `OHMTABS_ALTTAB_BROWSER_CLASSES` in the environment) and matches
  window classes case-insensitively as substrings.
- The compositor's own alt-tab cannot be intercepted by a plugin, so this is
  opt-in: the keybind is added by the user (see `docs/USAGE.md` → Alt-tab),
  replacing Omarchy's two `ALT + TAB` binds.
- Docs: `docs/USAGE.md` gains an **Alt-tab** section (including the two honest
  limitations) and documents `browserClasses`; `panelAutoHide`'s documented
  default is corrected to `false` (it had said `true` since auto-hide became
  opt-in).

### Taskbar: clickable buttons, right-click window menu, reserved space

- Taskbar buttons no longer collapse to zero width on a horizontal (top or
  bottom) panel. Their width was derived from the ListView's contentItem width,
  which is itself the sum of the delegates' widths - circular, so it settled at
  0 and the buttons were invisible and unclickable. This was the cause of the
  "I can't click the items in the side bar" report. Buttons now take their
  explicit extents (`length` by `thickness`).
- Right-clicking a taskbar button opens the window menu for that entry - the
  same menu the title strip shows - instead of restoring the window outright.
  A minimized window has no live surface for the menu to bind to, so the model
  snapshot (token, class, title, floating) is handed over; every menu action is
  token-based, so they all work on a parked window.
- Left-clicking a taskbar button restores that window (unchanged contract, now
  actually reachable).
- While the taskbar is shown and auto-hide is off, it reserves its strip
  (`exclusiveZone`), so a fixed taskbar no longer covers the bottom of another
  window. Compositors take the zone when the layer surface is mapped, so this
  applies from the next shell start, not on a live QML edit.

### Renamed: Grabbar / omarchy-tab -> OhmTabs

- Project, repository and plugin identity renamed: plugin id is now
  `tech.loopedmatrix.ohmtabs`, the native artifact is `ohmtabs.so`, the holding
  workspace is `special:ohmtabs-minimized`, and state moves to
  `~/.local/state/ohmtabs` (with a migration, so settings survive).
- Upstream attribution is unchanged: the `GreyforgeLabs/omarchy-grabbar` slug,
  the "Greyforge Labs" copyright notice and the `greyforge.hotbar` /
  `tech.greyforge.reprieve` compatibility notes keep their original names.
- Entries below this one describe the project under its previous name.

## 0.1.1 — 2026-09-15 (public preview)

- Keep native controls off when the compositor identity is missing or the
  startup-attempt marker cannot be saved; replace markers atomically.
- Require nine behavioral tests of the shipped Lua loader in CI.
- Retire the executable reload-loop reproducer from default/all startup tests.
- Return a failing exit code when nested startup assertions fail.
- Include the current external-focus restoration fix in the native build.
- Record exact build and nested startup/recovery evidence. Clean-install and
  full-login qualification remains pending; see `docs/RELEASE-SAFETY.md`.

## 0.1.0 — 2026-09-15 (public preview)

First public release: the complete core workflow on one qualified desktop
build (Omarchy 4.0.x, Hyprland 0.56.2 `efb50993…`, Quickshell 0.3.1).

### Native backend
- Control glyphs are cairo paths (menu, minimize, maximize, restore, close);
  crisp at 1.0/1.5/2.0 scale, no icon font.
- Strip colours and font follow the Omarchy theme pushed by the shell;
  Settings push control side, size (standard 34 px / large 46 px) and
  excluded classes. `plugin:grabbar:*` config values remain the fallback.
- Right-click on the strip opens the window menu; the menu button too.
- Press captures the window token, release re-validates and acts on that
  token (F02).
- Hover feedback only when the strip is really under the pointer.
- Dragging a maximized floating window keeps the pointer over the strip.
- Origin geometry is captured after leaving maximized mode, so a maximized
  floating window restores to its own size.
- Restore clamps floating windows into the work area (bar excluded).
- Unrecorded windows on `special:grabbar-minimized` can be restored
  (Recovered rows).
- `pause`/`resume` for the Settings switch; restore-all walks a token
  snapshot; `restored` window events after any return path.
- `plugin:grabbar:shell_grace_ms` (default 2000).
- Other tools focusing a hidden window (Hotbar, window switchers,
  `focuswindow`) or toggling `special:grabbar-minimized` no longer reveal
  the hidden workspace: the focused window is restored like a drawer
  click and the view is closed (scenarios X01/X02).
- No `reloadConfig()` in `PLUGIN_INIT`; boot-guard marker after 15 s.

### Shell
- Window menu (Minimize, Maximize/Restore size, Move freely, Close,
  Minimized windows, Hide Grabbar for this app with confirmation, Settings).
- Settings view: on/off, controls left/right, control size, excluded apps
  with "Show Grabbar again", setup check, technical details.
- Bar widget: window-stack glyph with count, left = drawer, middle =
  restore all, right = settings; keeps its space; pushes theme and the
  host's settings writer to the service.
- Fixed: title updates for minimized rows (wrong argument order); journal
  status stuck at `stale` after quarantine; `reconcile` IPC re-reads the
  journal.

### CLI and helpers
- Correct exit codes for shell answers (`restore`, `restore-all`).
- `disable`, `enable`, `uninstall` implemented; `setup`/`settings` open
  the Settings view.
- `vpointer` gains `rclick`/`mclick`.

### Tests and docs
- New nested suites: application matrix, shell-connected scenarios (F02,
  F05, F08, R05, R09, R10, R15), 500-cycle soak; harnesses work on
  Lua-config nested compositors and with a sandboxed `omarchy-shell`.
- README, ARCHITECTURE, PROTOCOL, COMPATIBILITY, QUALIFICATION rewritten;
  brand assets; GitHub Actions offline suite.

## 0.0.1-g0 — 2026-09-15 (internal)

G0 feasibility prototype: Hyprbars-derived backend with reserved strip,
token-based actions, owned hidden workspace, socket protocol, disconnect
recovery; shell service and drawer scaffold; the autoload incident, its
root cause and the boot guard (`docs/AUTOLOAD.md`).
