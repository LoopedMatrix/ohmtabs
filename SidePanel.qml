import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls
import qs.Commons
import "OhmTabsModel.js" as Model

// SidePanel — the Windows-11-style minimized-window taskbar for OhmTabs.
//
// A run of window buttons along one screen edge: click a button to restore
// that window. Like the bar widget it registers itself as a restore host, so
// its presence is what lets the service declare restore access.
//
// One button per window, icons in a row — not a single "Restore all" that
// replaces the run. Same-class windows used to collapse into one grouped
// tile; the grouped flyout is still there if a caller builds a multi-member
// entry, but the default model does not group. With auto-hide off the strip
// stays mapped and running windows join the run (ToplevelManager.activate).
//
// Position is configurable (left / right / bottom) and it can auto-hide. When
// parked, the surface stays mapped and slides just past its screen edge,
// leaving a few pixels on screen to catch the pointer — the same approach
// Omarchy's own bar uses. Parking beats unmapping because the surface,
// bindings and glyph textures stay alive, so revealing is only a margin
// change rather than a rebuild. That margin change is animated so unparking
// reads as a smooth slide instead of a pop.
//
// Colours come from the Omarchy bar palette, so it follows theme switches.
Item {
  id: root

  property var shell: null
  property var service: null
  property var bar: null
  property string serviceName: "tech.loopedmatrix.ohmtabs"

  // ---- settings (from this plugin's shell.json entry) ----
  property bool panelEnabled: true
  property string panelPosition: "bottom"    // "left" | "right" | "bottom"
  property bool panelAutoHide: false   // opt-in: the edge reveal is unreliable
  property int iconPixelSize: 38
  property bool tintIcons: false       // colorize app icons to theme ink
  property bool showIconName: false    // hover label above the icon
  property bool magnify: true          // animated.dock-style hover zoom
  property real iconZoom: 0.48         // extra scale on hover (0–1)
  property bool panelBorder: true
  property real panelBorderOpacity: 0.95
  property real panelBgOpacity: 0.78
  property bool fullLength: false
  property string cornerShape: "pill"
  property var pinnedApps: []
  property bool showAppsButton: true
  property bool dockDodge: false
  property bool showRunning: true
  property bool showWorkspaces: false
  property bool showClock: false
  property bool showNotifs: false
  property bool showDashboard: false
  property string clockText: Qt.formatTime(new Date(), "hh:mm")
  property bool windowsOverlapDock: false
  // A taskbar that is always there must not sit on top of windows: it reserves
  // its own strip the way the Windows taskbar does, and tiled windows end above
  // it. Auto-hide deliberately overlays instead - reserving space that appears
  // and disappears under the pointer would relayout windows on every hover.
  readonly property bool panelReserveSpace: !root.panelAutoHide
  property bool panelIcons: true       // draw resolved app icons; off -> letter tile

  // ---- state ----
  property bool hovered: false
  property int selectedIndex: -1

  readonly property bool vertical: panelPosition === "left" || panelPosition === "right"
  readonly property int dockPad: 12
  readonly property int panelSize: Math.max(48, root.iconSize + root.dockPad * 2)
  readonly property int dockRadius: cornerShape === "square" ? 0 : (cornerShape === "pill" ? Math.round(root.panelSize / 2) : Math.max(root.radius, 14))
  readonly property color dockAccent: Color.accent
  readonly property int buttonLength: root.iconSize + 16
  // Pixels of the parked surface left on screen so the pointer can find it.
  readonly property int revealSliver: 4

  readonly property var rows: (service && service.rows) ? service.rows : []
  readonly property int count: rows.length

  // One button per window. `groups` is kept as an alias of `items` so the
  // leftover grouped-flyout path still compiles; the model itself does not
  // fold by class (that plus a full-width Restore-all hid every icon).
  property int toplevelGen: 0
  // Apps button + pinned + running (grouped by class) + leftover minimized.
  // Pinned icons stay even with no window (omadock launch-from-dock).
  readonly property var items: {
    var gen = root.toplevelGen
    var out = []
    var seen = {}
    function norm(c) {
      return Model.sanitizeAppId(c).toLowerCase()
    }
    if (root.showAppsButton)
      out.push({ key: "apps", kind: "apps", members: [], appId: "", pinned: false, liveCount: 0, minCount: 0, toplevel: null })

    var minBy = {}
    var list = root.rows
    for (var i = 0; i < list.length; i++) {
      var r = list[i]
      var cls = norm(r.class)
      if (!cls) cls = "__min" + i
      if (!minBy[cls]) minBy[cls] = []
      minBy[cls].push(r)
    }
    var liveBy = {}
    var tops = []
    try { tops = ToplevelManager.toplevels.values } catch (e) { tops = [] }
    for (var j = 0; j < tops.length; j++) {
      var t = tops[j]
      if (!t) continue
      var app = norm(t.appId)
      if (!app) continue
      if (!liveBy[app]) liveBy[app] = []
      liveBy[app].push(t)
    }
    function pushApp(appId, pinned) {
      var id = norm(appId)
      if (!id || seen[id]) return
      seen[id] = true
      var mem = minBy[id] || []
      var lt = liveBy[id] || []
      var stub = mem.length ? mem : [{ class: appId, title: appId, label: appId, token: "", status: lt.length ? "live" : "pinned" }]
      out.push({
        key: (pinned ? "pin:" : "run:") + id,
        kind: "app",
        appId: id,
        pinned: pinned,
        members: stub,
        toplevel: lt.length ? lt[0] : null,
        liveCount: lt.length,
        minCount: mem.length
      })
    }
    var pins = root.pinnedApps || []
    for (var p = 0; p < pins.length; p++) pushApp(pins[p], true)
    if (root.showRunning) {
      for (var app in liveBy) pushApp(app, false)
    }
    for (var mc in minBy) {
      if (seen[mc]) continue
      var mem3 = minBy[mc]
      for (var k = 0; k < mem3.length; k++) {
        out.push({ key: String(mem3[k].token || ("m" + k)), kind: "minimized", appId: mc, pinned: false, members: [mem3[k]], toplevel: null, liveCount: 0, minCount: 1 })
      }
    }
    if (root.showNotifs)
      out.push({ key: "notifs", kind: "notifs", members: [], appId: "", pinned: false, liveCount: 0, minCount: 0, toplevel: null })
    if (root.showDashboard)
      out.push({ key: "dash", kind: "dashboard", members: [], appId: "", pinned: false, liveCount: 0, minCount: 0, toplevel: null })
    return out
  }
  readonly property var groups: root.items

  // Nothing to show -> no surface at all, unless the strip is docked (auto-hide
  // off), in which case it stays mapped so running windows have somewhere to
  // sit and tiled windows keep the reserved edge.
  readonly property bool live: panelEnabled && (root.items.length > 0 || !panelAutoHide)
  readonly property bool parked: (root.panelAutoHide || (root.dockDodge && root.windowsOverlapDock)) && !hovered && selectedIndex < 0

  // The group currently expanded in the hover flyout, and the button it
  // anchored to. Kept as plain state so the flyout can be dismissed from
  // anywhere without touching selection.
  property var flyoutGroup: null
  property var flyoutButton: null
  property bool flyoutHovered: false

  // ---- palette (bar surfaces: it lives on a screen edge) ----
  readonly property color background: Color.bar.background
  readonly property color foreground: Color.bar.text
  readonly property color hoverFill: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.14)
  readonly property color activeFill: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.22)
  readonly property color muted: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.55)
  readonly property color urgent: Color.urgent
  readonly property int radius: Style.cornerRadius
  readonly property string fontFamily: Style.font.menuFamily

  // ------------------------------------------------- app-icon resolution
  //
  // The minimized-window buttons show the app's real icon (Windows-taskbar
  // style) instead of a class-initial tile. Resolution ladder, in order:
  //   1. resolved theme icon  — DesktopEntries.heuristicLookup(class), then
  //      Quickshell.iconPath(entry.icon, true). heuristicLookup matches by
  //      desktop-entry id OR StartupWMClass, so a window class that differs
  //      from the entry id still resolves (org.gnome.Nautilus vs nautilus,
  //      brave-browser, flatpak ids with dots) — the same lookup Omarchy's
  //      own AppLibrary / NotificationCard rely on.
  //   2. letter tile           — the class's own initial, so two unknown apps
  //      still look different.
  //   3. generic executable    — last; it identifies nothing.
  // iconPath's `check=true` returns "" for unknown names instead of Qt's
  // missing-texture placeholder.
  readonly property int iconSize: Math.max(16, Math.min(40, root.iconPixelSize))
  readonly property int magBloom: root.magnify ? Math.round(root.iconSize * root.iconZoom) + 10 : 0
  readonly property int flyoutIconSize: 16  // per-window flyout row icon

  // Monitors here are 1.25x (DP-1) and 1x (DP-2). sourceSize is handed to the
  // icon provider as its requestedSize, so raster icons are fetched at the
  // panel's device pixel ratio and stay crisp on the hidpi monitor; SVG theme
  // icons rasterize at the requested size too, so the same multiplier keeps
  // them crisp at any scale.
  readonly property real iconDpr: {
    var d = 0
    try { d = Screen.devicePixelRatio } catch (e) {}
    return d > 1 ? d : 1
  }

  // class string -> resolved icon source ("" = nothing resolved). Resolved
  // ONCE per class and cached in this JS map: the row list re-evaluates as
  // windows minimize/restore, DesktopEntries can reorder its values when an
  // app starts (Omarchy's Menu.qml guards against the same reorder), and
  // re-resolving per frame would be wasteful. Empty results are cached too so
  // unknown classes are not re-probed on every re-evaluation. (The scan runs
  // at shell startup, so by the time a window is minimized it is populated.)
  property var iconCache: ({})

  function resolveIcon(cls) {
    var key = String(cls || "")
    if (key === "") return ""
    var cached = root.iconCache[key]
    if (cached) return cached
    var names = []
    function add(n) {
      n = String(n || "")
      if (!n) return
      if (names.indexOf(n) < 0) names.push(n)
    }
    add(key)
    var parts = key.split(".")
    if (parts.length > 1) add(parts[parts.length - 1])
    var lower = key.toLowerCase()
    if (lower.indexOf("hermes") >= 0) {
      add("hermes")
      add("hermes-desktop")
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
    root.iconCache[key] = path || ""
    return path
  }

  // ------------------------------------------------------------- behaviour

  // The global position of an item inside this layer surface. Layer surfaces
  // have no mapToGlobal, so the panel's own anchor geometry is added to the
  // item's position within the surface.
  function pointOnScreen(item) {
    var sc = panel.screen
    if (!item) {
      if (!sc) return { x: 0, y: 0 }
      return { x: sc.x + sc.width / 2, y: sc.y + sc.height - Math.round(root.panelSize / 2) }
    }
    var p = item.mapToItem(panel.contentItem, item.width / 2, item.height / 2)
    if (!sc) return { x: p.x, y: p.y }
    var layerH = panel.height > 0 ? panel.height : (root.panelSize + root.magBloom)
    var layerW = panel.width > 0 ? panel.width : sc.width
    var layerX = 0
    var layerY = 0
    if (root.panelPosition === "bottom") layerY = sc.height - layerH
    else if (root.panelPosition === "top") layerY = 0
    else if (root.panelPosition === "right") layerX = sc.width - layerW
    else if (root.panelPosition === "left") layerX = 0
    return { x: sc.x + layerX + p.x, y: sc.y + layerY + p.y }
  }

  // A right-click on a taskbar button opens the window menu for that window -
  // the same menu the strip shows - instead of restoring it outright. Grouped
  // buttons target their newest member, the one a left-click would restore.
  function resolveToken(entry) {
    if (!entry) return ""
    var tok = String(entry.token || "")
    if (!tok && entry.members && entry.members.length)
      tok = String(entry.members[0].token || "")
    if (tok) return tok
    if (!service || !service.live) return ""
    var m = (entry.members && entry.members.length) ? entry.members[0] : entry
    var cls = String(m.class || "").toLowerCase()
    var title = String(m.title || m.label || "")
    var live = service.live
    for (var k in live) {
      var w = live[k]
      if (!w) continue
      if (String(w.class || "").toLowerCase() === cls && String(w.title || "") === title)
        return String(w.token || k)
    }
    return ""
  }

  function openBarMenu(item) {
    if (!service || root.suppressBandMenu) return
    var pt = root.pointOnScreen(item)
    var name = panel.screen ? String(panel.screen.name) : ""
    service.openOverlay({ view: "settings", x: pt.x, y: pt.y, monitor: name })
    root.selectedIndex = -1
  }

  function openEntryMenu(row, item) {
    if (!row || !item) return false
    if (row.kind === "apps" || row.kind === "clock" || row.kind === "workspaces") {
      root.openBarMenu(item)
      return true
    }
    if (row.kind === "notifs") { root.openNotifs(); return true }
    if (row.kind === "dashboard") { root.openDashboard(); return true }
    root.suppressBandMenu = true
    if (openEntryMenuClear.running) openEntryMenuClear.restart()
    else openEntryMenuClear.start()
    var tok = root.resolveToken(row)
    var pt = root.pointOnScreen(item)
    var name = panel.screen ? String(panel.screen.name) : ""
    if (tok && service) {
      var live = service.liveWindow ? service.liveWindow(tok) : null
      if (!live) {
        var m = (row.members && row.members.length) ? row.members[0] : row
        live = {
          token: tok,
          class: m ? String(m.class || row.appId || "") : String(row.appId || ""),
          title: m ? String(m.title || m.label || "") : String(row.appId || ""),
          floating: m ? !!m.floating : false,
          minimized: true,
          origin: m ? (m.origin || "") : "",
          maximized: m ? !!m.maximized : false,
          fullscreen: false,
          modal: false
        }
      }
      service.menuWindow = live
      service.menuX = pt.x
      service.menuY = pt.y
      service.openOverlay({ view: "menu", token: tok, x: pt.x, y: pt.y, monitor: name, appId: row.appId || live.class })
      root.selectedIndex = -1
      return true
    }
    if (service) {
      service.menuWindow = {
        token: "",
        class: String(row.appId || ""),
        title: String(row.appId || "App"),
        floating: false,
        minimized: false,
        origin: "",
        maximized: false,
        fullscreen: false,
        modal: false
      }
      service.openOverlay({ view: "menu", token: "", x: pt.x, y: pt.y, monitor: name, appId: row.appId || "" })
    }
    root.selectedIndex = -1
    return true
  }

  function restoreRow(row, original) {
    if (!service || !row) return
    service.restore(row.token, original ? "original" : "current", "")
    root.selectedIndex = -1
  }

  // A grouped button restores its newest member; the flyout is the route to
  // any specific one. This mirrors Windows, where clicking a grouped taskbar
  // button brings up the most recently used window of that app.
  function restoreGroup(group, original) {
    root.activateItem(group, original)
  }

  function activateItem(item, original) {
    if (!item) return
    if (item.kind === "apps") { root.openAppsMenu(); root.selectedIndex = -1; return }
    if (item.kind === "notifs") { root.openNotifs(); root.selectedIndex = -1; return }
    if (item.kind === "dashboard") { root.openDashboard(); root.selectedIndex = -1; return }
    if (item.kind === "clock") { root.selectedIndex = -1; return }
    if (item.kind === "app") {
      if (item.toplevel) {
        try { item.toplevel.activate() } catch (e) {}
        root.selectedIndex = -1
        return
      }
      if (item.minCount > 0 && item.members && item.members.length)
        root.restoreRow(item.members[0], original)
      else
        root.launchApp(item.appId)
      root.selectedIndex = -1
      return
    }
    if (item.kind === "open" && item.toplevel) {
      try { item.toplevel.activate() } catch (e) {}
      root.selectedIndex = -1
      return
    }
    if (!item.members || item.members.length === 0) return
    root.restoreRow(item.members[0], original)
  }

  function openAppsMenu() {
    try { Quickshell.execDetached(["omarchy-menu", "toggle", "root"]) } catch (e) {}
  }

  function openNotifs() {
    if (!service) return
    var name = panel.screen ? String(panel.screen.name) : ""
    service.openOverlay({ view: "notifs", monitor: name })
  }

  function openDashboard() {
    if (!service) return
    var name = panel.screen ? String(panel.screen.name) : ""
    service.openOverlay({ view: "dashboard", monitor: name })
  }

  function launchApp(appId) {
    var id = Model.sanitizeAppId(appId)
    if (!id) return
    var desk = id
    try {
      if (typeof DesktopEntries !== "undefined" && DesktopEntries) {
        var entry = DesktopEntries.heuristicLookup(id) || DesktopEntries.byId(id)
        if (entry && entry.id) desk = String(entry.id)
      }
    } catch (e) {}
    try { Quickshell.execDetached(["gtk-launch", desk]) } catch (e2) {}
  }

  function togglePinned(appId) {
    if (!service || typeof service.saveSettings !== "function") return
    service.saveSettings({ pinnedApps: Model.togglePinned(root.pinnedApps, appId) })
  }

  property bool suppressBandMenu: false
  property var menuEntry: null

  function restoreAll() {
    if (!service) return
    service.restoreAll()
    root.selectedIndex = -1
  }

  function move(delta) {
    var n = root.groups.length
    if (n === 0) return
    var next = root.selectedIndex + delta
    if (next < 0) next = n - 1
    if (next >= n) next = 0
    root.selectedIndex = next
  }

  function dismiss() { root.selectedIndex = -1 }

  // ------------------------------------------------------------ flyout

  // Hovering a multi-window group expands it. Opening is immediate; closing
  // gets a grace period so the pointer can cross the gap to the flyout without
  // it blinking shut mid-flight.
  function flyoutOpen(group, button) {
    if (!group || !group.members || group.members.length < 2) return
    flyoutHideDelay.stop()
    root.flyoutGroup = group
    root.flyoutButton = button
  }

  function flyoutMaybeClose() {
    if (root.flyoutGroup) flyoutHideDelay.restart()
  }

  Timer {
    id: flyoutHideDelay
    interval: 240
    repeat: false
    onTriggered: {
      if (!root.flyoutHovered) {
        root.flyoutGroup = null
        root.flyoutButton = null
      }
    }
  }

  // Park after a short grace period so a diagonal pointer path across the
  // panel does not make it flicker away.
  Timer {
    id: hideDelay
    interval: 260
    repeat: false
    onTriggered: root.hovered = false
  }
  Timer {
    id: openEntryMenuClear
    interval: 250
    repeat: false
    onTriggered: root.suppressBandMenu = false
  }
  Timer {
    interval: 15000
    running: root.showClock
    repeat: true
    onTriggered: root.clockText = Qt.formatTime(new Date(), "hh:mm")
  }

  Connections {
    target: ToplevelManager
    function onActiveToplevelChanged() { root.toplevelGen++ }
  }
  Connections {
    target: ToplevelManager.toplevels
    ignoreUnknownSignals: true
    function onValuesChanged() { root.toplevelGen++ }
  }

  // Last window restored -> drop any selection so nothing lingers, and drop a
  // flyout whose group just shrank below two members.
  onCountChanged: if (count === 0) root.selectedIndex = -1
  onGroupsChanged: {
    root.flyoutGroup = null
    root.flyoutButton = null
    if (root.selectedIndex >= root.groups.length) root.selectedIndex = root.groups.length - 1
  }

  // ------------------------------------------------------ restore-host wiring

  // The bar hosts one widget instance per monitor (Bar.qml builds a BarPanel
  // per screen, so this file is instantiated once per monitor). Without a
  // `screen:` binding every instance would land on the focused monitor and
  // stack N identical surfaces there while the other monitors stay empty. The
  // widget's own Screen attached property reports the monitor this bar lives
  // on, so resolve its name against Quickshell's screens and fall back to the
  // first screen, keeping exactly one panel per monitor.
  function resolveScreen() {
    var name = ""
    try { name = String(Screen.name || "") } catch (e) {}
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++) {
      var s = screens[i]
      if (name !== "" && s && String(s.name) === name) return s
    }
    return (screens && screens.length) ? screens[0] : null
  }

  function declareHost() {
    if (service && typeof service.registerRestoreHost === "function")
      service.registerRestoreHost("side-panel")
  }

  Component.onCompleted: {
    panel.screen = root.resolveScreen()
    // The enclosing window's screen can lag this widget's own completion by a
    // tick, so re-resolve once and let a now-populated Screen.name correct the
    // assignment rather than parking a panel on the wrong monitor.
    Qt.callLater(function() { panel.screen = root.resolveScreen() })
    declareHost()
  }
  onServiceChanged: declareHost()
  Component.onDestruction: {
    if (service && typeof service.unregisterRestoreHost === "function")
      service.unregisterRestoreHost("side-panel")
  }

  // ------------------------------------------------------------- surface

  PanelWindow {
    id: panel
    visible: root.live
    color: "transparent"
    exclusionMode: (root.panelReserveSpace && !root.parked) ? ExclusionMode.Normal : ExclusionMode.Ignore
    exclusiveZone: (root.panelReserveSpace && !root.parked) ? root.panelSize : 0
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "ohmtabs-taskbar"
    WlrLayershell.keyboardFocus: root.selectedIndex >= 0 ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // Anchoring follows the position; parking is a negative margin along the
    // edge it is anchored to, so the surface slides out of view while a sliver
    // of it stays on screen. The margin change is animated, so the reveal reads
    // as a slide rather than a pop; parking animates the same way for symmetry.
    anchors {
      top: root.vertical || root.panelPosition === "top"
      bottom: root.vertical || root.panelPosition === "bottom"
      left: root.panelPosition === "left" || root.panelPosition === "bottom" || root.panelPosition === "top"
      right: root.panelPosition === "right" || root.panelPosition === "bottom" || root.panelPosition === "top"
    }

    margins {
      bottom: root.parked && root.panelPosition === "bottom" ? -(root.panelSize - root.revealSliver) : 0
      top: root.parked && root.panelPosition === "top" ? -(root.panelSize - root.revealSliver) : 0
      left: root.parked && root.panelPosition === "left" ? -(root.panelSize - root.revealSliver) : 0
      right: root.parked && root.panelPosition === "right" ? -(root.panelSize - root.revealSliver) : 0
    }

    Behavior on margins.bottom { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    Behavior on margins.left { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    Behavior on margins.right { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

    implicitWidth: root.vertical ? (root.panelSize + root.magBloom) : 0
    implicitHeight: root.vertical ? 0 : (root.panelSize + root.magBloom)

    Rectangle {
      id: surface
      anchors.fill: parent
      color: "transparent"

      Rectangle {
        id: dockBand
        anchors.left: (root.fullLength || root.vertical) ? parent.left : undefined
        anchors.right: (root.fullLength && !root.vertical) || root.panelPosition === "right" ? parent.right : undefined
        anchors.horizontalCenter: (!root.fullLength && !root.vertical) ? parent.horizontalCenter : undefined
        anchors.top: root.vertical ? parent.top : (root.panelPosition === "top" ? parent.top : undefined)
        anchors.bottom: root.vertical ? parent.bottom : (root.panelPosition === "top" ? undefined : parent.bottom)
        anchors.verticalCenter: (!root.fullLength && root.vertical) ? parent.verticalCenter : undefined
        width: root.vertical ? root.panelSize : ((!root.fullLength) ? Math.min(parent.width - 48, Math.max(root.panelSize, list.contentWidth + 28)) : undefined)
        height: root.vertical ? ((!root.fullLength) ? Math.min(parent.height - 48, Math.max(root.panelSize, list.contentHeight + 28)) : undefined) : root.panelSize
        radius: root.dockRadius
        color: Qt.rgba(root.background.r, root.background.g, root.background.b, root.panelBgOpacity)
        border.color: root.panelBorder ? Qt.rgba(root.dockAccent.r, root.dockAccent.g, root.dockAccent.b, root.panelBorderOpacity) : "transparent"
        border.width: root.panelBorder ? 2 : 0
        z: 1
      }

      Repeater {
        model: root.panelBorder ? 4 : 0
        Rectangle {
          required property int index
          x: dockBand.x - (index + 2)
          y: dockBand.y - (index + 2)
          width: dockBand.width + (index + 2) * 2
          height: dockBand.height + (index + 2) * 2
          radius: dockBand.radius + index + 2
          color: "transparent"
          border.width: 2
          border.color: Qt.rgba(root.dockAccent.r, root.dockAccent.g, root.dockAccent.b, (0.42 - index * 0.09) * root.panelBorderOpacity)
          z: 0
        }
      }

      MouseArea {
        id: hoverCatch
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onEntered: { hideDelay.stop(); root.hovered = true }
        onExited: hideDelay.restart()
        z: 0
      }

      MouseArea {
        id: bandMenu
        anchors.fill: dockBand
        acceptedButtons: Qt.RightButton
        z: 1
        onClicked: function(m) {
          if (m.button === Qt.RightButton) root.openBarMenu(dockBand)
        }
      }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: root.selectedIndex >= 0
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) { root.dismiss(); event.accepted = true; return }
          if (event.key === Qt.Key_Down || event.key === Qt.Key_Right || event.key === Qt.Key_J) { root.move(1); event.accepted = true }
          else if (event.key === Qt.Key_Up || event.key === Qt.Key_Left || event.key === Qt.Key_K) { root.move(-1); event.accepted = true }
          else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.selectedIndex >= 0 && root.selectedIndex < root.groups.length)
              root.restoreGroup(root.groups[root.selectedIndex], event.modifiers & Qt.ShiftModifier)
            event.accepted = true
          }
          else if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier)) { root.restoreAll(); event.accepted = true }
        }
      }

      // "Restore all" sits at the far end of the strip, out of the button run.
      RestoreAllButton {
        id: allButton
        visible: root.fullLength && root.count > 1
        horizontal: root.vertical
        anchors.right: root.vertical ? undefined : parent.right
        anchors.verticalCenter: root.vertical ? undefined : dockBand.verticalCenter
        anchors.bottom: root.vertical ? parent.bottom : undefined
        anchors.horizontalCenter: root.vertical ? dockBand.horizontalCenter : undefined
        anchors.rightMargin: root.vertical ? 0 : 6
        anchors.bottomMargin: root.vertical ? 6 : 0
        onActivated: root.restoreAll()
      }

      ListView {
        id: list
        orientation: root.vertical ? ListView.Vertical : ListView.Horizontal
        anchors.fill: dockBand
        anchors.margins: 8
        spacing: 6
        clip: false
        z: 2
        model: root.items
        currentIndex: root.selectedIndex
        header: DockWorkspaces {
          bar: root.bar
          visible: root.showWorkspaces
          ink: root.foreground
          accent: root.dockAccent
          width: root.showWorkspaces ? implicitWidth : 0
          height: root.vertical ? (root.showWorkspaces ? implicitHeight : 0) : (root.panelSize - 16)
        }
        footer: DockClock {
          visible: root.showClock
          ink: root.foreground
          width: root.showClock ? implicitWidth : 0
          height: root.vertical ? (root.showClock ? implicitHeight : 0) : (root.panelSize - 16)
        }

        delegate: TaskButton {
          required property var modelData
          required property int index
          entry: modelData
          selected: index === root.selectedIndex
          horizontal: root.vertical
          length: root.buttonLength
          thickness: root.panelSize - 16
          onActivated: function(original) { root.activateItem(modelData, original) }
          onHovered: root.selectedIndex = index
        }
      }
    }
  }

  // -------------------------------------------------------------- flyout

  // The per-window list a grouped button expands into. A separate popup so it
  // can grow past the strip's edge instead of being clipped by it; mouse-only,
  // so it never competes with the panel's keyboard focus.
  PopupWindow {
    id: flyoutWindow
    visible: root.flyoutGroup !== null && root.flyoutGroup.members && root.flyoutGroup.members.length > 1
    color: "transparent"

    implicitWidth: 260
    implicitHeight: flyoutColumn.implicitHeight

    // The anchor is a 1x1 point placed next to the hovered button in the
    // panel's own coordinates, then handed to the popup machinery (which keeps
    // it on screen). Side is chosen by position: above for a bottom strip,
    // outside the edge for a side strip.
    anchor {
      id: flyoutAnchor
      window: panel
      edges: Edges.Top | Edges.Left
      gravity: Edges.Top | Edges.Left
      adjustment: PopupAdjustment.Slide
      rect.width: 1
      rect.height: 1
      onAnchoring: {
        if (!root.flyoutButton) return
        var b = root.flyoutButton
        var lx = 0
        var ly = 0
        if (root.panelPosition === "bottom") {
          lx = 0
          ly = -flyoutWindow.implicitHeight - 8
        } else if (root.panelPosition === "left") {
          lx = b.width + 8
          ly = (b.height - flyoutWindow.implicitHeight) / 2
        } else {
          lx = -flyoutWindow.implicitWidth - 8
          ly = (b.height - flyoutWindow.implicitHeight) / 2
        }
        var p = panel.contentItem.mapFromItem(b, lx, ly)
        flyoutAnchor.rect.x = Math.round(p.x)
        flyoutAnchor.rect.y = Math.round(p.y)
      }
    }

    Rectangle {
      id: flyoutSurface
      anchors.fill: parent
      radius: root.radius
      color: root.background
      border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.16)
      border.width: 1

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onEntered: { flyoutHideDelay.stop(); root.flyoutHovered = true }
        onExited: { root.flyoutHovered = false; root.flyoutMaybeClose() }
      }

      Column {
        id: flyoutColumn
        width: 260
        padding: 6
        spacing: 2

        Repeater {
          model: root.flyoutGroup ? root.flyoutGroup.members : []
          delegate: FlyoutRow {
            required property var modelData
            required property int index
            entry: modelData
          }
        }
      }
    }
  }

  // ------------------------------------------------------------ components

  // A taskbar button: a rounded app tile carrying the class initial, an
  // elided single-line title, a focused-window indicator and a flash for
  // urgent or failed members. Left click restores the newest member here,
  // right click to the original workspace.
  component TaskButton: Rectangle {
    id: btn
    property var entry: null
    property bool selected: false
    property bool horizontal: false
    property real length: 184
    property real thickness: 36

    signal activated(bool original)
    signal hovered()

    readonly property var members: btn.entry ? (btn.entry.members || []) : []
    readonly property var first: btn.members.length ? btn.members[0] : null
    readonly property int memberCount: btn.members.length
    readonly property bool grouped: btn.memberCount > 1

    readonly property bool failed: {
      for (var i = 0; i < btn.members.length; i++)
        if (btn.members[i].status === "failed") return true
      return false
    }
    readonly property bool urgent: {
      for (var i = 0; i < btn.members.length; i++)
        if (btn.members[i].urgent) return true
      return false
    }
    readonly property bool attention: btn.urgent || btn.failed

    // Grouped buttons name the app; a lone window keeps its own title so the
    // button still says something useful before the flyout exists.
    readonly property string title: {
      if (btn.entry && btn.entry.kind === "apps") return "Apps"
      if (btn.entry && btn.entry.kind === "clock") return root.clockText
      if (btn.entry && btn.entry.kind === "notifs") return "Notifs"
      if (btn.entry && btn.entry.kind === "dashboard") return "Overview"
      if (btn.entry && btn.entry.kind === "workspaces") return "WS"
      if (btn.first === null) return "Window"
      if (btn.grouped) {
        var c = String(btn.first.class || "")
        return c ? c : String(btn.first.label || btn.first.title || "Window")
      }
      return String(btn.first.label || btn.first.title || btn.first.class || "Window")
    }
    readonly property string badge: {
      if (btn.entry && btn.entry.kind === "apps") return "▦"
      if (btn.entry && btn.entry.kind === "clock") return root.clockText
      if (btn.entry && btn.entry.kind === "notifs") return "🔔"
      if (btn.entry && btn.entry.kind === "dashboard") return "▣"
      if (btn.entry && btn.entry.kind === "workspaces") return "W"
      var c = btn.first ? String(btn.first.class || btn.first.title || "?") : "?"
      return c.length ? c.charAt(0).toUpperCase() : "?"
    }
    readonly property string iconSource: {
      if (!root.panelIcons) return ""
      if (btn.entry && btn.entry.kind === "apps") return ""
      var cls = btn.entry && btn.entry.appId ? String(btn.entry.appId) : (btn.first ? String(btn.first.class || "") : "")
      return root.resolveIcon(cls)
    }

    // `horizontal` is passed as root.vertical (the panel's orientation), so the
    // true branch is the vertical panel.  Deriving the size from parent.width on
    // the horizontal axis is circular inside a ListView (its contentItem width
    // is the sum of the delegates' widths) and settled at 0 -> invisible,
    // unclickable buttons.  Use the explicit extents instead.
    width: btn.length
    height: btn.thickness
    radius: Math.round(Math.min(btn.length, btn.thickness) / 4)
    color: "transparent"

    Behavior on color { ColorAnimation { duration: 110 } }

    // Urgent and failed members flash the button fill so attention cannot be
    // missed even when the pointer is elsewhere.
    Rectangle {
      id: flash
      anchors.fill: parent
      radius: btn.radius
      color: Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.20)
      visible: btn.attention
      opacity: 0
      SequentialAnimation on opacity {
        running: btn.attention
        loops: Animation.Infinite
        NumberAnimation { to: 1; duration: 420 }
        NumberAnimation { to: 0.15; duration: 420 }
      }
    }

    MouseArea {
      id: btnArea
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onEntered: { btn.hovered(); if (btn.grouped) root.flyoutOpen(btn.entry, btn) }
      onExited: { if (btn.grouped) root.flyoutMaybeClose() }
      onClicked: function(m) {
        if (m.button === Qt.RightButton) { m.accepted = true; root.openEntryMenu(btn.entry, btn); return }
        btn.activated(false)
      }
      ToolTip.visible: root.showIconName && btnArea.containsMouse && btn.title !== ""
      ToolTip.text: btn.title
      ToolTip.delay: 350
    }

    Item {
      anchors.fill: parent
      Item {
        id: tileBox
        anchors.centerIn: parent
        width: root.iconSize + 6
        height: root.iconSize + 6

        Rectangle {
          id: tile
          anchors.fill: parent
          radius: 9
          color: "transparent"
          scale: (root.magnify && btnArea.containsMouse) ? (1 + root.iconZoom) : 1
          transformOrigin: root.vertical
            ? (root.panelPosition === "left" ? Item.Left : Item.Right)
            : Item.Bottom
          Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
          TintedIcon {
            id: tileIcon
            anchors.centerIn: parent
            width: root.iconSize
            height: root.iconSize
            sourceOversample: Math.round(root.iconSize * root.iconDpr * 2)
            visible: btn.iconSource !== ""
            source: btn.iconSource
            tinted: root.tintIcons && btn.iconSource !== ""
            ink: root.foreground
          }
          Text {
            anchors.centerIn: parent
            visible: btn.iconSource === ""
            text: btn.badge
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: 12
            font.weight: Font.DemiBold
          }
        }

        // A second tile peeking out behind the app tile is the "stacked
        // papers" cue Windows draws for a grouped button. Explicit geometry
        // (no anchors) so it can overhang the tile without fighting it.
        Rectangle {
          visible: btn.grouped
          x: -3
          y: -3
          z: -1
          width: 22
          height: 22
          radius: 7
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
        }

        Rectangle {
          visible: btn.grouped
          anchors.right: tile.right
          anchors.bottom: tile.bottom
          anchors.rightMargin: -4
          anchors.bottomMargin: -4
          width: 15
          height: 15
          radius: 7
          color: root.background
          border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.30)
          border.width: 1
          Text {
            anchors.centerIn: parent
            text: String(btn.memberCount)
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: 9
          }
        }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: false
        width: 0
        text: btn.title
        elide: Text.ElideRight
        color: btn.failed ? root.urgent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: 12
      }
    }

    // Focused-window indicator: a short rounded bar that lengthens and
    // brightens when this button is selected, like the running-app marker
    // under a Windows taskbar icon. Selection (hover or keyboard) is the
    // closest thing to focus a minimized-only list has.
    Rectangle {
      id: indicator
      radius: 4
      width: 8
      height: 8
      visible: btn.entry && btn.entry.kind !== "minimized"
      color: Qt.rgba(root.dockAccent.r, root.dockAccent.g, root.dockAccent.b, btn.selected ? 1 : 0.75)

      anchors.horizontalCenter: btn.horizontal ? parent.horizontalCenter : undefined
      anchors.bottom: btn.horizontal ? parent.bottom : undefined
      anchors.bottomMargin: btn.horizontal ? 0 : undefined
      anchors.verticalCenter: btn.horizontal ? undefined : parent.verticalCenter
      anchors.left: btn.horizontal ? undefined : parent.left
      anchors.leftMargin: btn.horizontal ? undefined : 0

      Behavior on color { ColorAnimation { duration: 110 } }
    }
  }

  // One row in the group flyout: the window's own title plus its origin, so
  // the detail the collapsed button dropped is still one click away.
  component FlyoutRow: Rectangle {
    id: frow
    required property var modelData
    required property int index
    property var entry: modelData
    readonly property bool failed: frow.entry ? frow.entry.status === "failed" : false
    readonly property string badge: {
      var c = frow.entry ? String(frow.entry.class || frow.entry.title || "?") : "?"
      return c.length ? c.charAt(0).toUpperCase() : "?"
    }
    // Same resolve-and-cache ladder as the button; "" -> the letter tile.
    readonly property string iconSource: root.panelIcons
      ? root.resolveIcon(frow.entry ? String(frow.entry.class || "") : "")
      : ""

    width: 248
    height: 40
    radius: root.radius
    color: frowArea.containsMouse ? root.hoverFill : "transparent"
    Behavior on color { ColorAnimation { duration: 90 } }

    // 16px app icon for the window, letter tile as fallback.
    Item {
      id: rowIconBox
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: parent.left
      anchors.leftMargin: 10
      width: 16
      height: 16
      TintedIcon {
        id: rowIcon
        anchors.fill: parent
        sourceOversample: Math.round(root.flyoutIconSize * root.iconDpr * 2)
        visible: frow.iconSource !== ""
        source: frow.iconSource
        tinted: root.tintIcons && frow.iconSource !== ""
        ink: root.foreground
      }
      Rectangle {
        anchors.fill: parent
        radius: 4
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.16)
        visible: frow.iconSource === ""
        Text {
          anchors.centerIn: parent
          text: frow.badge
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: 9
          font.weight: Font.DemiBold
        }
      }
    }

    Column {
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: rowIconBox.right
      anchors.right: parent.right
      anchors.leftMargin: 8
      anchors.rightMargin: 10
      spacing: 1

      Text {
        width: parent.width
        text: frow.entry ? String(frow.entry.label || frow.entry.title || frow.entry.class || "Window") : ""
        elide: Text.ElideRight
        color: frow.failed ? root.urgent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: 12
      }
      Text {
        width: parent.width
        visible: text !== ""
        text: frow.failed ? "Could not restore — click to retry" : (frow.entry ? String(frow.entry.origin || "") : "")
        elide: Text.ElideRight
        color: frow.failed ? root.urgent : root.muted
        font.family: root.fontFamily
        font.pixelSize: 10
      }
    }

    MouseArea {
      id: frowArea
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: function(m) {
        if (m.button === Qt.RightButton) {
          root.openEntryMenu(frow.entry, frowArea)
        } else {
          root.restoreRow(frow.entry, false)
        }
        root.flyoutGroup = null
        root.flyoutButton = null
      }
    }
  }

  // The "restore every minimized window" affordance at the strip's end.
  component RestoreAllButton: Rectangle {
    id: all
    property bool horizontal: false
    signal activated()

    width: all.horizontal ? 36 : (allText.implicitWidth + 34)
    height: 26
    radius: root.radius
    color: allArea.containsMouse ? root.hoverFill : "transparent"
    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.16)
    border.width: 1

    Row {
      anchors.centerIn: parent
      spacing: 6
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "⤢"
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: 11
      }
      Text {
        id: allText
        anchors.verticalCenter: parent.verticalCenter
        text: "Restore all"
        visible: !all.horizontal
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: 11
      }
    }

    MouseArea {
      id: allArea
      anchors.fill: parent
      hoverEnabled: true
      onClicked: function(m) { m.accepted = true; all.activated() }
    }
  }
}
