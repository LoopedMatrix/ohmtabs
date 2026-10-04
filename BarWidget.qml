import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "OhmTabsModel.js" as Model

// OhmTabs bar widget: the stable place a minimized window can be found again.
//
//   glyph [count]   — always visible (spec §5.1), highlighted when attention is needed
//
// Stateless: everything comes from the live service. Its presence is what
// lets the service declare restore access to the native backend; without a
// mounted widget Minimize stays disabled. It also hands the service the two
// things only a bar widget can see: the Omarchy palette (for the strip) and
// the host's settings writer (for this plugin's shell.json entry).
BarWidget {
  id: root
  moduleName: "tech.loopedmatrix.ohmtabs"

  readonly property var service: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor(moduleName) : null
  readonly property int count: service ? Number(service.minimizedCount || 0) : 0
  readonly property bool attention: !!(service && service.attention)
  readonly property string attentionReason: service ? String(service.attentionReason || "") : ""
  // The Omarchy bar owns this property: Bar.qml's injectProps()/applySettingsDelta()
  // assign to it directly ("if ('settings' in item) item.settings = settings"). It
  // must stay WRITABLE — declaring `settings` readonly makes every settings write
  // throw TypeError: Cannot assign to read-only property, inside the bar's reload.
  property var settings: (service && service.settings) ? service.settings : null
  readonly property bool sidePanelEnabled: settings ? settings.sidePanel !== false : false
  readonly property string glyph: String.fromCodePoint(0xF05B2)   // nf-md-window_restore: a window stack
  property bool pulse: false

  readonly property bool barWindowControls: settings ? settings.barWindowControls === true : false
  readonly property var focusedToplevel: {
    try { return ToplevelManager.activeToplevel } catch (e) { return null }
  }
  readonly property bool haveFocusedWindow: !!(root.focusedToplevel)

  function focusedToken() {
    var t = root.focusedToplevel
    if (!t || !service || !service.live) return ""
    var app = String(t.appId || "").toLowerCase()
    var title = String(t.title || "")
    var live = service.live
    var classHits = []
    for (var k in live) {
      var w = live[k]
      if (!w || !w.token) continue
      var cls = String(w.class || "").toLowerCase()
      var wt = String(w.title || "")
      if (cls === app && wt === title) return w.token
      if (cls === app) classHits.push(w.token)
    }
    return classHits.length === 1 ? classHits[0] : ""
  }

  function focusedMinimize() {
    var tok = root.focusedToken()
    if (tok && service && service.minimizeToken) { service.minimizeToken(tok); return }
  }
  function focusedMaximize() {
    var tok = root.focusedToken()
    if (tok && service && service.toggleMaximize) { service.toggleMaximize(tok); return }
  }
  function focusedClose() {
    var tok = root.focusedToken()
    if (tok && service && service.closeWindow) { service.closeWindow(tok); return }
    var t = root.focusedToplevel
    if (t && typeof t.close === "function") t.close()
  }

  visible: true
  implicitWidth: vertical ? barSize : layout.implicitWidth
  implicitHeight: vertical ? layout.implicitHeight : barSize

  function tooltip() {
    if (attention) return attentionReason
    if (!service) return "OhmTabs — click for minimized windows"
    if (count === 0) return "No minimized windows\nright-click: OhmTabs settings"
    return count + " minimized window" + (count === 1 ? "" : "s") + "\nclick: open · middle: restore all · right: settings"
  }

  function openDrawer() {
    if (service && service.openDrawer) { service.openDrawer(); return }
    if (bar) bar.run("omarchy-shell shell toggle " + moduleName + " '{\"view\":\"drawer\"}'")
  }

  function openSettings() {
    if (service && service.openSettings) { service.openSettings(); return }
    if (bar) bar.run("omarchy-shell shell toggle " + moduleName + " '{\"view\":\"settings\"}'")
  }

  // ------------------------------------------------------ service wiring

  // The service may be published after this widget mounts (plugin reloads,
  // shell start order), so register whenever it becomes available, not only
  // once at creation. Registration is idempotent on the service side.
  function declareRestoreHost() {
    if (!service) return
    if (service.registerRestoreHost) service.registerRestoreHost("bar-widget")
    if ("settingsWriter" in service) service.settingsWriter = root.writeSettings
    root.pushTheme()
  }
  Component.onCompleted: {
    declareRestoreHost()
    debugGeometry()
  }

  function debugGeometry() {
    console.log("=== BarWidget geometry ===")
    console.log("  implicitWidth:", implicitWidth)
    console.log("  implicitHeight:", implicitHeight)
    console.log("  width:", width)
    console.log("  height:", height)
    console.log("  visible:", visible)
    console.log("  bar:", bar ? "set" : "null")
    console.log("  vertical:", vertical)
    console.log("  barSize:", barSize)
    var btn = startMenuButton
    if (btn) {
      console.log("  startMenuButton: visible:", btn.visible,
        "w:", btn.width, "h:", btn.height,
        "x:", btn.x, "y:", btn.y,
        "implicitW:", btn.implicitWidth,
        "hasVisualContent:", btn.hasVisualContent,
        "opacity:", btn.opacity)
    } else {
      console.log("  startMenuButton: NOT FOUND")
    }
    var flow = layout
    if (flow) {
      console.log("  layout: visible:", flow.visible,
        "w:", flow.width, "h:", flow.height,
        "x:", flow.x, "y:", flow.y,
        "implicitW:", flow.implicitWidth)
    }
  }
  onServiceChanged: declareRestoreHost()
  Component.onDestruction: {
    if (!service) return
    if (service.unregisterRestoreHost) service.unregisterRestoreHost("bar-widget")
    if ("settingsWriter" in service && service.settingsWriter === root.writeSettings) service.settingsWriter = null
  }

  // Settings are persisted through the host's own writer: the whole layout
  // entry is rewritten atomically and nothing else in shell.json changes.
  function writeSettings(next) {
    if (!bar || !bar.shell || typeof bar.shell.updateEntryInline !== "function") return false
    var entry = {}
    for (var k in next) entry[k] = next[k]
    return bar.shell.updateEntryInline(moduleName, entry) === true
  }

  function hexArgb(c, a) {
    function h(n) {
      var v = Math.round(Math.max(0, Math.min(1, Number(n))) * 255)
      var s = v.toString(16)
      return s.length < 2 ? ("0" + s) : s
    }
    if (!c) return ""
    var alpha = (a === undefined || a === null || isNaN(a)) ? c.a : a
    return "#" + h(alpha) + h(c.r) + h(c.g) + h(c.b)
  }

  // 6-digit RGB only. Native owns fill alpha so an accent ring cannot bleed
  // through a translucent interior (that was the solid-red strip).
  function hexRgb(c) {
    function h(n) {
      var v = Math.round(Math.max(0, Math.min(1, Number(n))) * 255)
      var s = v.toString(16)
      return s.length < 2 ? ("0" + s) : s
    }
    if (!c) return ""
    return "#" + h(c.r) + h(c.g) + h(c.b)
  }

  readonly property real stripGlass: {
    var n = root.settings && root.settings.panelBgOpacity !== undefined ? Number(root.settings.panelBgOpacity) : 0.78
    if (!(n >= 0.15)) n = 0.78
    if (n > 1) n = 1
    return n
  }

  // Deterministic colour for a fallback tile, derived from the app name.
  function colorForString(s) {
    var hash = 0
    s = String(s || "?")
    for (var i = 0; i < s.length; i++) {
      hash = ((hash << 5) - hash) + s.charCodeAt(i)
      hash = hash & hash
    }
    var hue = Math.abs(hash) % 360
    return Qt.hsla(hue / 360.0, 0.65, 0.45, 1.0)
  }

  function resolveStripIcon(cls) {
    var key = String(cls || "")
    if (!key) return ""
    var names = [key]
    var parts = key.split(".")
    if (parts.length > 1) names.push(parts[parts.length - 1])
    var lower = key.toLowerCase()
    if (lower.indexOf("hermes") >= 0) {
      names.push("hermes")
      names.push("hermes-desktop")
    }
    // The entry that owns this dock id can be named quite differently from it
    // (pin "claude" -> com.anthropic.Claude, Icon=claude-desktop). Resolve the
    // owner and try its Icon= first — the native half only gets a real file path
    // out of this map, so a name that resolves nowhere means no tab icon.
    var entries = []
    try { entries = DesktopEntries.applications ? (DesktopEntries.applications.values || []) : [] } catch (e0) { entries = [] }
    var ownerId = Model.desktopEntryIdFor(key, entries)
    if (ownerId) {
      var owner = null
      try { owner = DesktopEntries.byId(ownerId) } catch (e1) { owner = null }
      if (owner && owner.icon) names.unshift(String(owner.icon))
    }
    var path = ""
    for (var i = 0; i < names.length && !path; i++) {
      var entry = null
      try { entry = DesktopEntries.heuristicLookup(names[i]) } catch (e) { entry = null }
      if (entry && entry.icon)
        path = Quickshell.iconPath(String(entry.icon), true)
      if (!path)
        path = Quickshell.iconPath(names[i], true)
    }
    if (path && path.charAt(0) !== "/") path = ""
    return path
  }

  readonly property string stripIconMap: {
    var seen = {}
    var parts = []
    function addCls(c) {
      var id = Model.dockAppId(c)
      if (!id || seen[id]) return
      var p = root.resolveStripIcon(c)
      if (!p) p = root.resolveStripIcon(id)
      if (!p) return
      seen[id] = true
      parts.push(id + ":" + p)
    }
    try {
      var hts = Hyprland.toplevels.values
      for (var h = 0; h < hts.length; h++) {
        var ht = hts[h]
        if (!ht) continue
        addCls(ht.class || (ht.lastIpcObject ? ht.lastIpcObject.class : "") || "")
      }
    } catch (e1) {}
    try {
      var tops = ToplevelManager.toplevels.values
      for (var j = 0; j < tops.length; j++) {
        if (tops[j]) addCls(tops[j].appId)
      }
    } catch (e2) {}
    return parts.join("|")
  }

  // Omarchy palette → strip. Glass fill like the dock; accent is the outline.
  readonly property var themeValues: ({
    barColor: root.hexArgb(Color.background, root.stripGlass),
    inactiveBarColor: root.hexArgb(Color.background, Math.max(0.15, root.stripGlass * 0.62)),
    textColor: root.hexArgb(Color.bar.text, 1),
    hoverColor: root.hexArgb(Color.bar.text, 0.18),
    closeHoverColor: root.hexArgb(Color.urgent, 0.85),
    accentColor: root.hexRgb(Color.accent),
    textFont: String((bar && bar.fontFamily) || Style.font.family || ""),
    iconMap: root.stripIconMap
  })
  onThemeValuesChanged: pushTheme()
  function pushTheme() { if (service && service.setTheme) service.setTheme(themeValues) }

  Connections {
    target: root.service
    ignoreUnknownSignals: true
    function onWindowMinimized() { root.pulse = true; pulseTimer.restart() }
  }
  Timer { id: pulseTimer; interval: 1200; repeat: false; onTriggered: root.pulse = false }

  function openSuperMenu() {
    if (service && service.openSuperMenu) { service.openSuperMenu(); return }
    if (bar) bar.run("omarchy-shell shell toggle " + moduleName + ' \'{"view":"supermenu"}\'')
  }

  Flow {
    id: layout
    anchors.centerIn: parent
    flow: root.vertical ? Flow.TopToBottom : Flow.LeftToRight
    spacing: 0

    // Start menu button — Windows-style, opens the Super Menu
    Item {
      id: startMenuButton
      implicitWidth: 40
      implicitHeight: barSize

      Text {
        anchors.centerIn: parent
        text: "S"
        color: root.bar ? root.bar.barForeground : "#c0caf5"
        font.family: root.bar ? root.bar.fontFamily : "sans-serif"
        font.pixelSize: Style.font.body
        visible: true
      }

      MouseArea {
        anchors.fill: parent
        onClicked: function(mouse) { if (mouse.button === Qt.LeftButton) root.openSuperMenu() }
        cursorShape: Qt.PointingHandCursor
      }
    }

    WidgetButton {
      bar: root.bar
      text: root.vertical || root.count === 0 ? root.glyph : (root.glyph + " " + root.count)
      fontSize: Style.font.caption
      keepSpace: true   // the restore entry point must never collapse to nothing
      active: root.attention || root.pulse
      tooltipText: root.tooltip()
      onPressed: function(button) {
        if (button === Qt.RightButton) { root.openSettings(); return }
        if (button === Qt.MiddleButton) { if (root.service && root.count > 0) root.service.restoreAll(); return }
        // The taskbar panel appears on its own when windows are minimized, so
        // the widget opens the drawer for the detail view instead.
        root.openDrawer()
      }
    }

    WidgetButton {
      visible: root.barWindowControls && !root.vertical
      bar: root.bar
      text: "−"
      fontSize: Style.font.caption
      dimmed: !root.haveFocusedWindow
      tooltipText: "Minimize focused window"
      onPressed: function(button) { if (button === Qt.LeftButton) root.focusedMinimize() }
    }
    WidgetButton {
      visible: root.barWindowControls && !root.vertical
      bar: root.bar
      text: "□"
      fontSize: Style.font.caption
      dimmed: !root.haveFocusedWindow
      tooltipText: "Maximize / restore focused window"
      onPressed: function(button) { if (button === Qt.LeftButton) root.focusedMaximize() }
    }
    WidgetButton {
      visible: root.barWindowControls && !root.vertical
      bar: root.bar
      text: "×"
      fontSize: Style.font.caption
      dimmed: !root.haveFocusedWindow
      tooltipText: "Close focused window"
      onPressed: function(button) { if (button === Qt.LeftButton) root.focusedClose() }
    }
  }

  // The minimized-window side panel. It registers itself as a restore host,
  // so mounting it here is what lets the service declare restore access.
  SidePanel {
    id: sidePanel
    shell: root.bar ? root.bar.shell : null
    service: root.service
    bar: root.bar
    panelEnabled: root.sidePanelEnabled
    panelPosition: root.settings ? String(root.settings.panelPosition || "bottom") : "bottom"
    panelAutoHide: root.settings ? root.settings.panelAutoHide === true : false
    iconPixelSize: root.settings && root.settings.iconSize ? Number(root.settings.iconSize) : 38
    tintIcons: root.settings ? root.settings.tintIcons === true : false
    showIconName: root.settings ? root.settings.showIconName === true : false
    magnify: root.settings ? root.settings.magnify !== false : true
    iconZoom: root.settings && root.settings.iconZoom !== undefined ? Number(root.settings.iconZoom) : 0.48
    panelBorder: root.settings ? root.settings.panelBorder !== false : true
    panelBorderOpacity: root.settings && root.settings.panelBorderOpacity !== undefined ? Number(root.settings.panelBorderOpacity) : 0.95
    panelBgOpacity: root.settings && root.settings.panelBgOpacity !== undefined ? Number(root.settings.panelBgOpacity) : 0.78
    fullLength: root.settings ? root.settings.fullLength === true : false
    cornerShape: root.settings ? String(root.settings.cornerShape || "pill") : "pill"
    pinnedApps: root.settings && root.settings.pinnedApps ? root.settings.pinnedApps : []
    showAppsButton: root.settings ? root.settings.showAppsButton !== false : true
    dockDodge: root.settings ? root.settings.dockDodge === true : false
    showRunning: root.settings ? root.settings.showRunning !== false : true
    showWorkspaces: root.settings ? root.settings.showWorkspaces === true : false
    showClock: root.settings ? root.settings.showClock === true : false
    showStatus: root.settings ? root.settings.showStatus === true : false
    showActiveWindow: root.settings ? root.settings.showActiveWindow === true : false
    workspaceCount: root.settings && root.settings.workspaceCount ? Number(root.settings.workspaceCount) : 5
    showNotifs: root.settings ? root.settings.showNotifs === true : false
    showDashboard: root.settings ? root.settings.showDashboard === true : false
  }

  OverlayOsd {
    enabled: root.settings ? root.settings.showOsd === true : false
  }
}
