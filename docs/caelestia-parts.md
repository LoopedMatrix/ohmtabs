# Caelestia behaviors → OhmTabs parts

Caelestia (`caelestia-dots/shell`) is GPL-3. Reimplement **behavior** only.
Do not copy `/etc/xdg/quickshell/caelestia` or start `caelestia-shell`.
Lock, wallpaper, tray, sidebar stay Omarchy.

Caelestia bar entries (from their README example, not their QML):
logo · workspaces · activeWindow · tray · clock · statusIcons · power

Dashboard tabs: media, performance, weather.

| Part | Behavior | OhmTabs | Status |
| --- | --- | --- | --- |
| 1 | Workspace pips 1–N, empty/occupied/active, click + scroll | `DockWorkspaces.qml` | this batch |
| 1b | Focused window title on the dock | `DockActiveWindow.qml` | this batch |
| 2 | Hover title card on icons | dock flyout | next |
| 3 | Status chips (audio / network / bt) via Omarchy IPC | dock chips | later |
| 4 | Dashboard: media + weather + resources | overlay | later |
| — | Launcher | `omarchy-menu` (already) | done |
| — | Lock / wallpaper / tray / sidebar | Omarchy | out of scope |
