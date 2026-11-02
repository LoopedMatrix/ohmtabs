pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "OhmTabsModel.js" as Model

// Super Menu — VIN Star-style Windows start page for OhmTabs.
// Columns follow superMenuLayout. Arrange drags a section into another column.
// Palette defaults are probe-safe (no qs.Commons). The live overlay overrides
// them with Color.bar / Color.accent so the card matches the dock pill.
Item {
  id: root

  property var shell: null
  property var service: null
  property string moduleName: "tech.loopedmatrix.ohmtabs"
  property var warm: DesktopEntries.applications

  property color bg: "#1a1b26"
  property color fg: "#c0caf5"
  property color accent: "#7aa2f7"
  property int radius: 18
  property real glass: 0.92
  property real borderOpacity: 0.45
  property string fontFamily: "sans-serif"
  implicitWidth: 1100
  implicitHeight: 640
  readonly property color hoverFill: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.14)
  readonly property color muted: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.55)
  readonly property string userName: {
    var home = ""
    try { home = String(Quickshell.env("HOME") || "") } catch (e) { home = "" }
    var parts = home.replace(/\/+$/, "").split("/")
    var last = parts.length ? parts[parts.length - 1] : ""
    return last || "User"
  }
  readonly property string homeDir: {
    var h = ""
    try { h = String(Quickshell.env("HOME") || "") } catch (e) { h = "" }
    return h
  }

  signal closeRequested()
  signal requestSettings()

  property bool arrangeMode: false
  property string draggingId: ""
  property string hoverColumn: ""
  property real dragY: 0
  property string placedSig: ""
  readonly property var menuSettings: (root.service && root.service.settings) ? root.service.settings : ({})
  readonly property var menuLayout: Model.normalizeMenuLayout(root.menuSettings.superMenuLayout)

  function sectionItem(id) {
    if (id === "apps") return appsBlock
    if (id === "pinned") return pinnedBlock
    if (id === "agents") return agentsBlock
    if (id === "files") return filesBlock
    if (id === "clocks") return clocksBlock
    if (id === "weather") return weatherBlock
    if (id === "calendar") return calendarBlock
    if (id === "crypto") return cryptoBlock
    if (id === "rss") return rssBlock
    if (id === "news") return newsBlock
    if (id === "alerts") return alertsBlock
    return null
  }
  function columnStack(column) {
    if (column === "left") return leftStack
    if (column === "center") return centerStack
    if (column === "right") return rightStack
    return null
  }
  function layoutSig(layout) {
    var cols = ["left", "center", "right"]
    var parts = []
    for (var c = 0; c < cols.length; c++)
      parts.push(cols[c] + ":" + (layout[cols[c]] || []).join(","))
    return parts.join("|")
  }
  function sectionFills(id) {
    var col = Model.menuSectionColumn(root.menuLayout, id)
    var list = col && root.menuLayout[col] ? root.menuLayout[col] : []
    return list.length === 1
  }
  function appsListHeight(hostHeight) {
    if (!root.sectionFills("apps")) return 220
    // Do not read the Flickable height here. This runs from Layout.preferredHeight
    // inside the column the Flickable sizes from, and that read is a polish loop.
    var h = hostHeight > 200 ? hostHeight - 220 : 420
    return Math.max(180, Math.round(h - 72))
  }
  function placeSections() {
    if (root.draggingId !== "") return
    if (!appsBlock || !leftStack || !centerStack || !rightStack) return
    var sig = root.layoutSig(root.menuLayout)
    if (sig === root.placedSig) return
    var ids = ["apps", "pinned", "agents", "clocks", "weather", "calendar", "files", "crypto", "rss", "news", "alerts"]
    var i
    for (i = 0; i < ids.length; i++) {
      var item = root.sectionItem(ids[i])
      if (item && item.parent !== sectionPark) item.parent = sectionPark
    }
    var cols = ["left", "center", "right"]
    var layout = root.menuLayout
    for (var c = 0; c < cols.length; c++) {
      var stack = root.columnStack(cols[c])
      var list = layout[cols[c]] || []
      for (i = 0; i < list.length; i++) {
        var sec = root.sectionItem(list[i])
        if (sec && stack) sec.parent = stack
      }
    }
    root.placedSig = sig
  }
  function schedulePlace() {
    // Reparenting while the card is hidden leaves the sections in the
    // scene graph but they never paint on the layer-shell overlay.
    if (root.parent && root.parent.visible)
      placeTimer.restart()
  }
  Timer {
    id: placeTimer
    interval: 40
    repeat: false
    onTriggered: root.placeSections()
  }
  property bool cardShown: root.parent ? root.parent.visible : false
  onCardShownChanged: if (root.cardShown) root.schedulePlace()
  function beginDrag(id) {
    root.draggingId = String(id || "")
    root.hoverColumn = Model.menuSectionColumn(root.menuLayout, root.draggingId)
  }
  function dragAt(x, y) {
    root.dragY = y
    var cols = [
      { id: "left", item: leftCard },
      { id: "center", item: centerCard },
      { id: "right", item: rightCard }
    ]
    var hit = ""
    for (var i = 0; i < cols.length; i++) {
      var card = cols[i].item
      if (!card) continue
      var p = card.mapToItem(root, 0, 0)
      if (x >= p.x && x <= p.x + card.width && y >= p.y && y <= p.y + card.height)
        hit = cols[i].id
    }
    root.hoverColumn = hit
  }
  function indexInColumn(column) {
    var stack = root.columnStack(column)
    if (!stack) return 0
    var local = stack.mapFromItem(root, 0, root.dragY)
    var y = local.y
    var kids = stack.children
    var acc = 0
    var idx = 0
    for (var i = 0; i < kids.length; i++) {
      var child = kids[i]
      if (!child || !child.sectionId || child.sectionId === root.draggingId) continue
      var h = child.height > 0 ? child.height : (child.implicitHeight || 0)
      if (y < acc + Math.max(12, h) / 2) return idx
      acc += Math.max(12, h) + (stack.spacing || 0)
      idx++
    }
    return idx
  }
  function endDrag() {
    var id = root.draggingId
    var col = root.hoverColumn
    var idx = col ? root.indexInColumn(col) : 0
    root.draggingId = ""
    root.hoverColumn = ""
    if (!id || !col) return
    if (!root.service || typeof root.service.saveSettings !== "function") return
    root.service.saveSettings({ superMenuLayout: Model.moveMenuSection(root.menuLayout, id, col, idx) })
  }
  function cancelDrag() {
    root.draggingId = ""
    root.hoverColumn = ""
  }
  onMenuLayoutChanged: root.schedulePlace()
  onArrangeModeChanged: if (!root.arrangeMode) root.cancelDrag()
  Component.onCompleted: root.schedulePlace()


  property string searchQuery: ""
  property int menuIndex: 0
  property bool powerMenuOpen: false
  property string pendingPower: ""
  property bool nightlightOn: false
  property bool focusOn: false
  property bool stayAwakeOn: false
  onSearchQueryChanged: menuIndex = 0
  property string recentXml: ""
  property string logoAscii: ""
  property var usageState: ({ launches: {} })

  FileView {
    id: recentFile
    path: root.homeDir + "/.local/share/recently-used.xbel"
    watchChanges: true
    printErrors: false
    onLoaded: root.recentXml = text()
    onLoadFailed: root.recentXml = ""
    onFileChanged: reload()
  }

  FileView {
    id: usageFile
    path: root.homeDir + "/.local/state/ohmtabs/supermenu-usage.json"
    watchChanges: true
    printErrors: false
    atomicWrites: true
    onLoaded: {
      try { root.usageState = JSON.parse(text()) || { launches: {} } } catch (e) { root.usageState = { launches: {} } }
    }
    onLoadFailed: root.usageState = { launches: {} }
  }

  Timer {
    id: toggleRefresh
    interval: 450
    repeat: false
    onTriggered: root.refreshToggles()
  }

  Process {
    id: nightProc
    command: ["omarchy", "toggle", "nightlight", "--status"]
    stdout: StdioCollector { id: nightOut; waitForEnd: true }
    onExited: function() { root.applyToggle("nightlight", nightOut.text, 0) }
  }

  Process {
    id: idleProc
    command: ["omarchy", "toggle", "idle", "status"]
    stdout: StdioCollector { id: idleOut; waitForEnd: true }
    onExited: function() { root.applyToggle("idle", idleOut.text, 0) }
  }

  FileView {
    id: focusFile
    path: root.homeDir + "/.local/state/omarchy/toggles/notification silencing"
    watchChanges: true
    printErrors: false
    onLoaded: root.focusOn = true
    onLoadFailed: root.focusOn = false
    onFileChanged: reload()
  }

  onVisibleChanged: if (visible) root.refreshToggles()

  FileView {
    id: calFile
    path: root.homeDir + "/.local/state/ohmtabs/calendar.json"
    watchChanges: true
    printErrors: false
    atomicWrites: true
    onLoaded: {
      try {
        var j = JSON.parse(text()) || {}
        root.appointments = Model.normalizeAppointments(j.appointments || j)
      } catch (e) { root.appointments = [] }
    }
    onLoadFailed: root.appointments = []
  }

  property var appointments: []

  function saveAppointments(list) {
    var next = Model.normalizeAppointments(list)
    root.appointments = next
    try { calFile.setText(JSON.stringify({ appointments: next })) } catch (e) {}
  }

  FileView {
    id: logoFile
    path: root.homeDir + "/.config/omarchy/branding/screensaver.txt"
    watchChanges: true
    printErrors: false
    onLoaded: root.logoAscii = text()
    onLoadFailed: root.logoAscii = ""
    onFileChanged: reload()
  }

  function entryList() {
    try { return DesktopEntries.applications ? (DesktopEntries.applications.values || []) : [] } catch (e) { return [] }
  }

  function lookupEntry(appId) {
    var id = Model.sanitizeAppId(appId)
    if (!id) return null
    var entry = null
    try { entry = DesktopEntries.heuristicLookup(id) || DesktopEntries.byId(id) } catch (e0) { entry = null }
    if (entry) return entry
    var found = Model.desktopEntryIdFor(id, root.entryList())
    if (!found) return null
    try { return DesktopEntries.byId(found) } catch (e1) { return null }
  }

  function displayNameFor(appId) {
    var entry = root.lookupEntry(appId)
    if (entry && entry.name) return String(entry.name)
    var id = String(appId || "").replace(/__/g, ".")
    var parts = id.split(".")
    var shortName = parts.length ? parts[parts.length - 1] : id
    if (!shortName) return id
    return shortName.charAt(0).toUpperCase() + shortName.slice(1)
  }

  readonly property var pinnedAppsList: {
    var result = []
    var pins = (service && service.settings && service.settings.pinnedApps) ? service.settings.pinnedApps : []
    var q = root.searchQuery.toLowerCase().trim()
    for (var i = 0; i < pins.length; i++) {
      var pid = Model.sanitizeAppId(pins[i])
      if (!pid) continue
      var name = root.displayNameFor(pid)
      if (q && name.toLowerCase().indexOf(q) < 0 && pid.toLowerCase().indexOf(q) < 0) continue
      result.push({ appId: pid, name: name, kind: "app" })
    }
    return result
  }

  readonly property var allApps: {
    var result = []
    var entries = root.entryList()
    for (var i = 0; i < entries.length; i++) {
      var e = entries[i]
      if (!e || e.noDisplay) continue
      var name = String(e.name || "")
      var id = String(e.id || "")
      if (!name || !id) continue
      result.push({ appId: id, name: name, kind: "app", letter: Model.appLetter(name) })
    }
    result.sort(function(a, b) {
      var an = a.name.toLowerCase()
      var bn = b.name.toLowerCase()
      if (an < bn) return -1
      if (an > bn) return 1
      return 0
    })
    return result
  }

  readonly property var filteredApps: {
    var ranked = Model.rankMenuApps(root.allApps, root.searchQuery)
    if (!String(root.searchQuery || "").trim()) return ranked
    var result = []
    for (var i = 0; i < ranked.length; i++) {
      var a = ranked[i]
      result.push({ appId: a.appId, name: a.name, kind: a.kind || "app", letter: "" })
    }
    return result
  }

  readonly property var mostUsed: {
    var ranked = Model.frecencyRank(root.usageState && root.usageState.launches, Date.now(), 5)
    var out = []
    for (var i = 0; i < ranked.length; i++) {
      var id = ranked[i].appId
      out.push({ appId: id, name: root.displayNameFor(id), kind: "app" })
    }
    return out
  }

  readonly property var agentApps: {
    var out = []
    var seen = {}
    var apps = root.allApps
    var re = /(claude|hermes|grok|codex|gemini|copilot)/i
    for (var i = 0; i < apps.length && out.length < 6; i++) {
      var a = apps[i]
      if (!(re.test(a.name) || re.test(a.appId))) continue
      var key = Model.dockAppId(a.appId) || a.appId.toLowerCase()
      if (!key || seen[key]) continue
      seen[key] = true
      out.push(a)
    }
    return out
  }

  readonly property bool superMenuWidgetsOn: {
    var s = root.service && root.service.settings
    if (!s) return false
    return !!(s.superMenuWeather || s.superMenuCalendar || s.superMenuRss || s.superMenuNews || s.superMenuCrypto || s.superMenuAlerts || s.superMenuWorldClock)
  }

  readonly property var recommendedFiles: {
    var cap = root.superMenuWidgetsOn ? 4 : 8
    var rows = Model.parseRecentlyUsed(root.recentXml, cap)
    var now = Date.now()
    var out = []
    for (var i = 0; i < rows.length; i++) {
      var r = rows[i]
      out.push({
        href: r.href,
        path: r.path,
        title: r.title,
        when: Model.relativeTime(r.visited, now),
        kind: "file"
      })
    }
    return out
  }

  property var iconCache: ({})
  property var fileIconCache: ({})
  readonly property real iconDpr: {
    var d = 0
    try { d = Screen.devicePixelRatio } catch (e) {}
    return d > 1 ? d : 1
  }

  function colorForString(s) {
    var hash = 0
    s = String(s || "?")
    for (var i = 0; i < s.length; i++) {
      hash = ((hash << 5) - hash) + s.charCodeAt(i)
      hash = hash & hash
    }
    return Qt.hsla((Math.abs(hash) % 360) / 360.0, 0.65, 0.45, 1.0)
  }

  // Same ladder as the dock: owner desktop entry Icon= first (claude →
  // claude-desktop), then id / last segment / hermes aliases, then letter tile.
  function resolveIcon(appId) {
    var key = String(appId || "")
    if (!key) return ""
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
    if (lower.indexOf("hermes") >= 0) { add("hermes"); add("hermes-desktop") }
    var entries = root.entryList()
    var ownerId = ""
    try { ownerId = Model.desktopEntryIdFor(key, entries) } catch (e0) { ownerId = "" }
    if (ownerId) {
      var owner = null
      try { owner = DesktopEntries.byId(ownerId) } catch (e1) { owner = null }
      if (owner && owner.icon) names.unshift(String(owner.icon))
      add(ownerId)
    }
    var path = ""
    for (var i = 0; i < names.length && !path; i++) {
      var entry = null
      try { entry = DesktopEntries.heuristicLookup(names[i]) } catch (e2) { entry = null }
      if (entry && entry.icon) path = Quickshell.iconPath(String(entry.icon), true)
      if (!path) path = Quickshell.iconPath(names[i], true)
    }
    if (path || entries.length > 0) root.iconCache[key] = path || ""
    return path
  }

  function resolveFileIcon(path) {
    var key = String(path || "")
    if (!key) return ""
    var cached = root.fileIconCache[key]
    if (cached) return cached
    var names = Model.fileIconNames(key)
    var src = ""
    for (var i = 0; i < names.length && !src; i++) {
      try { src = Quickshell.iconPath(names[i], true) } catch (e) { src = "" }
    }
    root.fileIconCache[key] = src || ""
    return src
  }

  function persistUsage(next) {
    root.usageState = next
    try { usageFile.setText(JSON.stringify(next)) } catch (e) {}
  }

  function pinnedNow(appId) {
    var pins = (root.service && root.service.settings && root.service.settings.pinnedApps) ? root.service.settings.pinnedApps : []
    return Model.isPinned(pins, appId)
  }

  function togglePin(appId) {
    if (!root.service || typeof root.service.saveSettings !== "function") return
    var pins = (root.service.settings && root.service.settings.pinnedApps) ? root.service.settings.pinnedApps : []
    root.service.saveSettings({ pinnedApps: Model.togglePinned(pins, appId) })
  }

  function moveSelection(delta) {
    if (root.pendingPower !== "" || root.powerMenuOpen) return
    var n = root.filteredApps.length
    root.menuIndex = Model.stepMenuIndex(root.menuIndex, delta, n)
    if (root.menuIndex >= 0) allAppsList.positionViewAtIndex(root.menuIndex, ListView.Contain)
  }

  function activateSelection() {
    if (root.pendingPower !== "" || root.powerMenuOpen) return
    var apps = root.filteredApps
    if (root.menuIndex < 0 || root.menuIndex >= apps.length) return
    root.launchApp(apps[root.menuIndex].appId)
  }

  function choosePower(action) {
    root.powerMenuOpen = false
    if (!action || !action.id) return
    if (action.confirm) root.requestPower(action.id)
    else root.runPower(action.id)
  }

  function launchApp(appId) {
    var id = Model.sanitizeAppId(appId)
    if (!id) return
    root.persistUsage(Model.recordLaunch(root.usageState, id, Date.now()))
    var desk = id
    var entry = root.lookupEntry(id)
    if (entry && entry.id) desk = String(entry.id)
    try { Quickshell.execDetached(["gtk-launch", desk]) } catch (e2) {}
    root.close()
  }

  function openPath(path) {
    var p = String(path || "")
    if (!p) return
    try { Quickshell.execDetached(["xdg-open", p]) } catch (e) {}
    root.close()
  }

  function runToggle(flag) {
    try { Quickshell.execDetached(["omarchy", "toggle", flag]) } catch (e) {}
    toggleRefresh.restart()
  }

  function toggleOn(flag) {
    if (flag === "nightlight") return root.nightlightOn
    if (flag === "notification silencing") return root.focusOn
    if (flag === "idle") return root.stayAwakeOn
    return false
  }

  function refreshToggles() {
    if (nightProc.running) nightProc.running = false
    if (idleProc.running) idleProc.running = false
    nightProc.running = true
    idleProc.running = true
    focusFile.reload()
  }

  function applyToggle(kind, text, exitCode) {
    var on = Model.parseToggleStatus(kind, text, exitCode).on
    if (kind === "nightlight") root.nightlightOn = on
    else if (kind === "idle") root.stayAwakeOn = on
    else if (kind === "focus") root.focusOn = on
  }

  function close() {
    root.pendingPower = ""
    root.closeRequested()
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.moduleName)
  }

  function requestPower(kind) {
    root.powerMenuOpen = false
    if (kind === "lock") { root.runPower("lock"); return }
    root.pendingPower = kind
  }

  function runPower(kind) {
    var argv = null
    if (kind === "lock") argv = ["omarchy", "system", "lock"]
    else if (kind === "suspend") argv = ["systemctl", "suspend"]
    else if (kind === "reboot") argv = ["systemctl", "reboot"]
    else if (kind === "shutdown") argv = ["systemctl", "poweroff"]
    if (!argv) return
    try { Quickshell.execDetached(argv) } catch (e) {}
    root.pendingPower = ""
    root.close()
  }

  function powerLabel(kind) {
    if (kind === "lock") return "Lock"
    if (kind === "suspend") return "Suspend"
    if (kind === "reboot") return "Reboot"
    if (kind === "shutdown") return "Shut down"
    return ""
  }

  Shortcut {
    sequence: "Escape"
    onActivated: {
      if (root.pendingPower) root.pendingPower = ""
      else if (root.powerMenuOpen) root.powerMenuOpen = false
      else root.close()
    }
  }
  Shortcut { sequence: "Up"; enabled: !searchInput.activeFocus; onActivated: root.moveSelection(-1) }
  Shortcut { sequence: "Down"; enabled: !searchInput.activeFocus; onActivated: root.moveSelection(1) }
  Shortcut { sequence: "Return"; enabled: !searchInput.activeFocus; onActivated: root.activateSelection() }
  Shortcut { sequence: "Enter"; enabled: !searchInput.activeFocus; onActivated: root.activateSelection() }

  component AppMark: Item {
    id: mark
    property string appId: ""
    property string label: "?"
    property int size: 22
    width: size
    height: size
    readonly property string iconSrc: root.resolveIcon(mark.appId)
    Rectangle {
      anchors.fill: parent
      radius: Math.max(4, mark.size / 5)
      color: root.colorForString(mark.label || mark.appId || "?")
      visible: mark.iconSrc === ""
    }
    TintedIcon {
      anchors.fill: parent
      visible: mark.iconSrc !== ""
      source: mark.iconSrc
      tinted: false
      sourceOversample: Math.round(mark.size * root.iconDpr * 2)
    }
    Text {
      anchors.centerIn: parent
      visible: mark.iconSrc === ""
      text: String(mark.label || "?").charAt(0).toUpperCase()
      color: "white"
      font.family: root.fontFamily
      font.pixelSize: Math.max(10, mark.size * 0.45)
      font.weight: Font.DemiBold
    }
  }

  component FileMark: Item {
    id: fmark
    property string path: ""
    property int size: 28
    width: size
    height: size
    readonly property string iconSrc: root.resolveFileIcon(fmark.path)
    Rectangle {
      anchors.fill: parent
      radius: 4
      color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.10)
      visible: fmark.iconSrc === ""
    }
    TintedIcon {
      anchors.fill: parent
      visible: fmark.iconSrc !== ""
      source: fmark.iconSrc
      tinted: false
      sourceOversample: Math.round(fmark.size * root.iconDpr * 2)
    }
    Text {
      anchors.centerIn: parent
      visible: fmark.iconSrc === ""
      text: Model.fileIconNames(fmark.path)[0] === "inode-directory" ? "▣" : "▤"
      color: root.fg
      font.pixelSize: Math.max(10, fmark.size * 0.42)
    }
  }

  Rectangle {
    anchors.fill: parent
    radius: root.radius
    color: "#000000"
    border.width: 0

    // Clip rain/veil inside the stroke. clip:true on the bordered rect
    // itself shears the rounded outline at the corners.
    Item {
      id: innerClip
      anchors.fill: parent
      anchors.margins: 2
      clip: true

      MatrixRain {
        id: matrixBg
        anchors.fill: parent
        z: 0
        running: root.visible && root.width > 8
        ink: "#00ff41"
        fontPx: 15
        fps: 16
      }

      Text {
        visible: root.logoAscii.length > 0
        anchors.centerIn: parent
        z: 1
        text: root.logoAscii
        color: Qt.rgba(0, 1, 0.25, 0.08)
        font.family: "monospace"
        font.pixelSize: 9
        font.weight: Font.Bold
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.NoWrap
      }

      Rectangle {
        id: menuVeil
        anchors.fill: parent
        z: 2
        radius: Math.max(0, root.radius - 2)
        gradient: Gradient {
          orientation: Gradient.Vertical
          GradientStop { position: 0.0; color: Qt.rgba(root.bg.r, root.bg.g, root.bg.b, 0.96) }
          GradientStop { position: 0.42; color: Qt.rgba(root.bg.r, root.bg.g, root.bg.b, 0.975) }
          GradientStop { position: 1.0; color: Qt.rgba(root.bg.r, root.bg.g, root.bg.b, 0.99) }
        }
      }
      Rectangle {
        z: 2
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 18
        anchors.rightMargin: 18
        anchors.topMargin: 1
        height: 1
        color: Qt.rgba(1, 1, 1, 0.12)
      }

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 10
        z: 3

      Item {
        Layout.fillWidth: true
        Layout.preferredHeight: 28
        Text {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "Start"
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: 16
          font.weight: Font.DemiBold
          font.letterSpacing: 0.6
        }
        Rectangle {
          id: arrangeBtn
          anchors.right: gearBtn.left
          anchors.rightMargin: 6
          anchors.verticalCenter: parent.verticalCenter
          width: arrangeLab.implicitWidth + 16
          height: 28
          radius: 14
          color: root.arrangeMode
                ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, arrangeArea.containsMouse ? 0.34 : 0.22)
                : (arrangeArea.containsMouse ? root.hoverFill : "transparent")
          border.width: 1
          border.color: root.arrangeMode
                       ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.75)
                       : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.16)
          Text {
            id: arrangeLab
            anchors.centerIn: parent
            text: root.arrangeMode ? "Done" : "Arrange"
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: 11
            font.weight: Font.DemiBold
          }
          MouseArea {
            id: arrangeArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.arrangeMode = !root.arrangeMode
          }
        }
        Rectangle {
          id: gearBtn
          anchors.right: closeBtn.left
          anchors.rightMargin: 6
          anchors.verticalCenter: parent.verticalCenter
          width: 28
          height: 28
          radius: 14
          color: gearArea.containsMouse ? root.hoverFill : "transparent"
          Text { anchors.centerIn: parent; text: "⚙"; color: root.fg; font.pixelSize: 14 }
          MouseArea {
            id: gearArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: function(m) {
              m.accepted = true
              root.requestSettings()
            }
          }
        }
        Rectangle {
          id: closeBtn
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: 28
          height: 28
          radius: 14
          color: closeArea.containsMouse ? root.hoverFill : "transparent"
          Item {
            anchors.centerIn: parent
            width: 10
            height: 10
            Rectangle { anchors.centerIn: parent; width: 12; height: 2; radius: 1; color: root.fg; rotation: 45 }
            Rectangle { anchors.centerIn: parent; width: 12; height: 2; radius: 1; color: root.fg; rotation: -45 }
          }
          MouseArea { id: closeArea; anchors.fill: parent; hoverEnabled: true; onClicked: root.close() }
        }
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08)
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: 8
        Repeater {
          model: [
            { label: "Nightlight", flag: "nightlight" },
            { label: "Focus", flag: "notification silencing" },
            { label: "Stay awake", flag: "idle" }
          ]
          delegate: Rectangle {
            id: pill
            required property var modelData
            readonly property bool on: root.toggleOn(modelData.flag)
            height: 26
            width: pillLabel.implicitWidth + (on ? 28 : 16)
            radius: 13
            color: on
                  ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, pillArea.containsMouse ? 0.34 : 0.2)
                  : (pillArea.containsMouse ? root.hoverFill : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06))
            border.width: 1
            border.color: on ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.75) : "transparent"
            Row {
              anchors.centerIn: parent
              spacing: 6
              Rectangle {
                visible: pill.on
                width: 6
                height: 6
                radius: 3
                anchors.verticalCenter: parent.verticalCenter
                color: root.accent
              }
              Text {
                id: pillLabel
                text: pill.modelData.label
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: 11
              }
            }
            MouseArea {
              id: pillArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.runToggle(pill.modelData.flag)
            }
          }
        }
        Item { Layout.fillWidth: true }
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 40
        radius: 20
        color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.05)
        border.color: searchInput.activeFocus
                     ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.75)
                     : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.10)
        border.width: 1
        Item {
          anchors.left: parent.left
          anchors.leftMargin: 14
          anchors.verticalCenter: parent.verticalCenter
          width: 14
          height: 14
          Rectangle {
            width: 8
            height: 8
            radius: 4
            anchors.left: parent.left
            anchors.top: parent.top
            color: "transparent"
            border.width: 1.4
            border.color: root.muted
          }
          Rectangle {
            width: 5
            height: 1.4
            radius: 1
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            rotation: 40
            color: root.muted
          }
        }
        TextInput {
          id: searchInput
          anchors.fill: parent
          anchors.leftMargin: 36
          anchors.rightMargin: 78
          verticalAlignment: Text.AlignVCenter
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: 13
          clip: true
          onTextChanged: root.searchQuery = text
          Keys.onUpPressed: function(event) { root.moveSelection(-1); event.accepted = true }
          Keys.onDownPressed: function(event) { root.moveSelection(1); event.accepted = true }
          Keys.onReturnPressed: function(event) { root.activateSelection(); event.accepted = true }
          Keys.onEnterPressed: function(event) { root.activateSelection(); event.accepted = true }
          Component.onCompleted: forceActiveFocus()
        }
        Text {
          visible: searchInput.text.length === 0
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          anchors.leftMargin: 36
          text: "Search apps"
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: 13
        }
        Text {
          visible: searchInput.text.length === 0
          anchors.verticalCenter: parent.verticalCenter
          anchors.right: parent.right
          anchors.rightMargin: 14
          text: "↑↓  Enter"
          color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.4)
          font.family: root.fontFamily
          font.pixelSize: 11
        }
      }

      Text {
        visible: root.arrangeMode
        Layout.fillWidth: true
        Layout.preferredHeight: visible ? 16 : 0
        text: root.draggingId !== "" && root.hoverColumn !== ""
              ? ("Drop " + Model.menuSectionTitle(root.draggingId) + " in " + root.hoverColumn)
              : "Drag a handle into another column. The gear opens Super Menu settings, not dock settings."
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: 11
        elide: Text.ElideRight
      }

      RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 12
        visible: root.pendingPower === ""

        Rectangle {
          id: leftCard
          Layout.preferredWidth: 280
          Layout.fillHeight: true
          radius: 16
          color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.045)
          border.width: root.draggingId !== "" && root.hoverColumn === "left" ? 2 : 1
          border.color: root.draggingId !== "" && root.hoverColumn === "left"
                        ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.85)
                        : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08)
          
          Text {
            visible: root.arrangeMode && leftStack.children.length === 0
            anchors.centerIn: parent
            text: "Drop here"
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: 12
          }
          Flickable {
            id: leftFlick
            anchors.fill: parent
            anchors.margins: 10
            clip: true
            contentWidth: width
            contentHeight: leftStack.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            Column {
              id: leftStack
              width: leftFlick.width
              spacing: 10
              Item {
                id: appsBlock
                property string sectionId: "apps"
                width: parent ? parent.width : 260
                height: appsGrip.height + appsBody.implicitHeight
                SuperMenuGrip { id: appsGrip; sectionId: "apps"; title: "All apps"; host: root }
                ColumnLayout {
                  id: appsBody
                  y: appsGrip.height
                  width: parent.width
                  spacing: 6
            Text {
              text: root.searchQuery ? ("Results  " + root.filteredApps.length) : "All"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: 12
              font.weight: Font.DemiBold
              font.letterSpacing: 0.8
            }
            Text {
              visible: !root.searchQuery && root.mostUsed.length > 0
              text: "Most used"
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: 11
              font.weight: Font.DemiBold
            }
            Repeater {
              model: root.searchQuery ? [] : root.mostUsed
              delegate: Rectangle {
                id: usedRow
                required property var modelData
                Layout.fillWidth: true
                height: 32
                radius: 8
                color: usedArea.containsMouse ? root.hoverFill : "transparent"
                Row {
                  anchors.fill: parent
                  anchors.leftMargin: 6
                  spacing: 8
                  AppMark { appId: usedRow.modelData.appId; label: usedRow.modelData.name; size: 20; anchors.verticalCenter: parent.verticalCenter }
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 36
                    text: usedRow.modelData.name
                    elide: Text.ElideRight
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: 12
                  }
                }
                MouseArea { id: usedArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; acceptedButtons: Qt.LeftButton | Qt.RightButton; onClicked: function(m) { if (m.button === Qt.RightButton) root.togglePin(usedRow.modelData.appId); else root.launchApp(usedRow.modelData.appId) } }
              }
            }
            ListView {
              id: allAppsList
              Layout.fillWidth: true
              Layout.preferredHeight: root.appsListHeight(root.height)
              Layout.fillHeight: false
              clip: true
              model: root.filteredApps
              currentIndex: root.menuIndex
              highlightFollowsCurrentItem: true
              highlightMoveDuration: 0
              highlight: Rectangle {
                radius: 8
                color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
                border.width: 1
                border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.55)
              }
              section.property: root.searchQuery ? "" : "letter"
              section.criteria: ViewSection.FullString
              section.delegate: Text {
                required property string section
                width: allAppsList.width
                height: 22
                text: section
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: 11
                font.weight: Font.DemiBold
                verticalAlignment: Text.AlignVCenter
              }
              delegate: Rectangle {
                id: allAppsRow
                required property var modelData
                required property int index
                width: allAppsList.width
                height: 36
                radius: 8
                color: allAppsArea.containsMouse ? root.hoverFill : "transparent"
                Row {
                  anchors.fill: parent
                  anchors.leftMargin: 6
                  spacing: 8
                  AppMark { appId: allAppsRow.modelData.appId; label: allAppsRow.modelData.name; size: 20; anchors.verticalCenter: parent.verticalCenter }
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 48
                    text: allAppsRow.modelData.name
                    elide: Text.ElideRight
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: 12
                  }
                }
                Rectangle {
                  anchors.right: parent.right
                  anchors.rightMargin: 8
                  anchors.verticalCenter: parent.verticalCenter
                  width: 6
                  height: 6
                  radius: 3
                  visible: root.pinnedNow(allAppsRow.modelData.appId)
                  color: root.accent
                }
                MouseArea { id: allAppsArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; acceptedButtons: Qt.LeftButton | Qt.RightButton; onClicked: function(m) { root.menuIndex = allAppsRow.index; if (m.button === Qt.RightButton) root.togglePin(allAppsRow.modelData.appId); else root.launchApp(allAppsRow.modelData.appId) } }
              }
            }
                }
              }

            }
          }
        }
        Rectangle {
          id: centerCard
          Layout.fillWidth: true
          Layout.fillHeight: true
          radius: 16
          color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.05)
          border.width: root.draggingId !== "" && root.hoverColumn === "center" ? 2 : 1
          border.color: root.draggingId !== "" && root.hoverColumn === "center"
                        ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.85)
                        : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08)
          
          Text {
            visible: root.arrangeMode && centerStack.children.length === 0
            anchors.centerIn: parent
            text: "Drop here"
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: 12
          }
          Flickable {
            id: centerFlick
            anchors.fill: parent
            anchors.margins: 10
            clip: true
            contentWidth: width
            contentHeight: centerStack.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            Column {
              id: centerStack
              width: centerFlick.width
              spacing: 10
              Item {
                id: pinnedBlock
                property string sectionId: "pinned"
                width: parent ? parent.width : 260
                height: pinnedGrip.height + pinnedBody.implicitHeight
                SuperMenuGrip { id: pinnedGrip; sectionId: "pinned"; title: "Pinned"; host: root }
                ColumnLayout {
                  id: pinnedBody
                  y: pinnedGrip.height
                  width: parent.width
                  spacing: 8
            Text {
              text: "Pinned"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: 12
              font.weight: Font.DemiBold
              font.letterSpacing: 0.8
            }
            Text {
              visible: root.pinnedAppsList.length === 0
              text: "Right-click an app to pin it"
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: 12
            }
            GridView {
              id: pinnedGrid
              Layout.fillWidth: true
              Layout.preferredHeight: Model.pinnedGridHeight(
                root.pinnedAppsList.length,
                Math.max(1, Math.floor(Math.max(width, 96) / 96)),
                88, 0, 264)
              clip: true
              cellWidth: 96
              cellHeight: 88
              model: root.pinnedAppsList
              delegate: Rectangle {
                id: pinnedRow
                required property var modelData
                width: 88
                height: 80
                radius: 10
                color: pinnedArea.containsMouse ? root.hoverFill : "transparent"
                Column {
                  anchors.centerIn: parent
                  spacing: 6
                  Item {
                    width: 46
                    height: 46
                    anchors.horizontalCenter: parent.horizontalCenter
                    Rectangle {
                      anchors.fill: parent
                      radius: 23
                      color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06)
                      border.width: 1
                      border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.10)
                    }
                    AppMark { anchors.centerIn: parent; appId: pinnedRow.modelData.appId; label: pinnedRow.modelData.name; size: 28 }
                  }
                  Text {
                    width: 80
                    text: pinnedRow.modelData.name
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.NoWrap
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: 10
                  }
                }
                MouseArea { id: pinnedArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; acceptedButtons: Qt.LeftButton | Qt.RightButton; onClicked: function(m) { if (m.button === Qt.RightButton) root.togglePin(pinnedRow.modelData.appId); else root.launchApp(pinnedRow.modelData.appId) } }
              }
            }
                }
              }
              Item {
                id: agentsBlock
                property string sectionId: "agents"
                width: parent ? parent.width : 260
                height: agentsGrip.height + agentsBody.implicitHeight
                SuperMenuGrip { id: agentsGrip; sectionId: "agents"; title: "Agents"; host: root }
                ColumnLayout {
                  id: agentsBody
                  y: agentsGrip.height
                  width: parent.width
                  spacing: 8
            Text {
              visible: root.agentApps.length > 0
              text: "Agents"
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: 11
              font.weight: Font.DemiBold
            }
            Row {
              spacing: 10
              Repeater {
                model: root.agentApps
                delegate: Rectangle {
                  id: agentRow
                  required property var modelData
                  width: 72
                  height: 64
                  radius: 10
                  color: agentArea.containsMouse ? root.hoverFill : "transparent"
                  Column {
                    anchors.centerIn: parent
                    spacing: 4
                    Item {
                      width: 36
                      height: 36
                      anchors.horizontalCenter: parent.horizontalCenter
                      Rectangle {
                        anchors.fill: parent
                        radius: 18
                        color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06)
                        border.width: 1
                        border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.10)
                      }
                      AppMark { anchors.centerIn: parent; appId: agentRow.modelData.appId; label: agentRow.modelData.name; size: 22 }
                    }
                    Text {
                      width: 68
                      text: agentRow.modelData.name
                      elide: Text.ElideRight
                      horizontalAlignment: Text.AlignHCenter
                      color: root.fg
                      font.family: root.fontFamily
                      font.pixelSize: 9
                    }
                  }
                  MouseArea { id: agentArea; anchors.fill: parent; hoverEnabled: true; onClicked: root.launchApp(agentRow.modelData.appId) }
                }
              }
            }
                }
              }

            }
          }
        }
        Rectangle {
          id: rightCard
          Layout.preferredWidth: 280
          Layout.fillHeight: true
          radius: 16
          color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.045)
          border.width: root.draggingId !== "" && root.hoverColumn === "right" ? 2 : 1
          border.color: root.draggingId !== "" && root.hoverColumn === "right"
                        ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.85)
                        : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08)
          Rectangle {
            visible: rightFlick.contentHeight > rightFlick.height + 8
            z: 2
            width: 4
            radius: 2
            color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.45)
            anchors.right: parent.right
            anchors.rightMargin: 4
            height: Math.max(18, rightFlick.visibleArea.heightRatio * Math.max(18, parent.height - 24))
            y: 12 + rightFlick.visibleArea.yPosition * Math.max(0, parent.height - 24 - height)
          }
          Text {
            visible: root.arrangeMode && rightStack.children.length === 0
            anchors.centerIn: parent
            text: "Drop here"
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: 12
          }
          Flickable {
            id: rightFlick
            anchors.fill: parent
            anchors.margins: 10
            clip: true
            contentWidth: width
            contentHeight: rightStack.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            Column {
              id: rightStack
              width: rightFlick.width
              spacing: 10
              Item {
                id: clocksBlock
                property string sectionId: "clocks"
                readonly property bool contentOn: clocksUi.anyOn
                width: parent ? parent.width : 240
                height: (root.arrangeMode || contentOn) ? (clocksGrip.height + (contentOn ? clocksUi.implicitHeight : 0)) : 0
                visible: height > 0
                SuperMenuGrip { id: clocksGrip; sectionId: "clocks"; title: "Clocks"; host: root }
                SuperMenuWidgets {
                  id: clocksUi
                  y: clocksGrip.height
                  width: parent.width
                  only: "clocks"
                  visible: clocksBlock.contentOn
                  settings: root.menuSettings
                  shell: root.shell
                  fg: root.fg
                  muted: root.muted
                  hoverFill: root.hoverFill
                  accent: root.accent
                  fontFamily: root.fontFamily
                  active: root.visible && clocksBlock.contentOn
                  appointments: root.appointments
                  onSaveAppointments: function(list) { root.saveAppointments(list) }
                }
              }
              Item {
                id: weatherBlock
                property string sectionId: "weather"
                readonly property bool contentOn: weatherUi.anyOn
                width: parent ? parent.width : 240
                height: (root.arrangeMode || contentOn) ? (weatherGrip.height + (contentOn ? weatherUi.implicitHeight : 0)) : 0
                visible: height > 0
                SuperMenuGrip { id: weatherGrip; sectionId: "weather"; title: "Weather"; host: root }
                SuperMenuWidgets {
                  id: weatherUi
                  y: weatherGrip.height
                  width: parent.width
                  only: "weather"
                  visible: weatherBlock.contentOn
                  settings: root.menuSettings
                  shell: root.shell
                  fg: root.fg
                  muted: root.muted
                  hoverFill: root.hoverFill
                  accent: root.accent
                  fontFamily: root.fontFamily
                  active: root.visible && weatherBlock.contentOn
                  appointments: root.appointments
                  onSaveAppointments: function(list) { root.saveAppointments(list) }
                }
              }
              Item {
                id: calendarBlock
                property string sectionId: "calendar"
                readonly property bool contentOn: calendarUi.anyOn
                width: parent ? parent.width : 240
                height: (root.arrangeMode || contentOn) ? (calendarGrip.height + (contentOn ? calendarUi.implicitHeight : 0)) : 0
                visible: height > 0
                SuperMenuGrip { id: calendarGrip; sectionId: "calendar"; title: "Calendar"; host: root }
                SuperMenuWidgets {
                  id: calendarUi
                  y: calendarGrip.height
                  width: parent.width
                  only: "calendar"
                  visible: calendarBlock.contentOn
                  settings: root.menuSettings
                  shell: root.shell
                  fg: root.fg
                  muted: root.muted
                  hoverFill: root.hoverFill
                  accent: root.accent
                  fontFamily: root.fontFamily
                  active: root.visible && calendarBlock.contentOn
                  appointments: root.appointments
                  onSaveAppointments: function(list) { root.saveAppointments(list) }
                }
              }
              Item {
                id: cryptoBlock
                property string sectionId: "crypto"
                readonly property bool contentOn: cryptoUi.anyOn
                width: parent ? parent.width : 240
                height: (root.arrangeMode || contentOn) ? (cryptoGrip.height + (contentOn ? cryptoUi.implicitHeight : 0)) : 0
                visible: height > 0
                SuperMenuGrip { id: cryptoGrip; sectionId: "crypto"; title: "Crypto"; host: root }
                SuperMenuWidgets {
                  id: cryptoUi
                  y: cryptoGrip.height
                  width: parent.width
                  only: "crypto"
                  visible: cryptoBlock.contentOn
                  settings: root.menuSettings
                  shell: root.shell
                  fg: root.fg
                  muted: root.muted
                  hoverFill: root.hoverFill
                  accent: root.accent
                  fontFamily: root.fontFamily
                  active: root.visible && cryptoBlock.contentOn
                  appointments: root.appointments
                  onSaveAppointments: function(list) { root.saveAppointments(list) }
                }
              }
              Item {
                id: rssBlock
                property string sectionId: "rss"
                readonly property bool contentOn: rssUi.anyOn
                width: parent ? parent.width : 240
                height: (root.arrangeMode || contentOn) ? (rssGrip.height + (contentOn ? rssUi.implicitHeight : 0)) : 0
                visible: height > 0
                SuperMenuGrip { id: rssGrip; sectionId: "rss"; title: "RSS"; host: root }
                SuperMenuWidgets {
                  id: rssUi
                  y: rssGrip.height
                  width: parent.width
                  only: "rss"
                  visible: rssBlock.contentOn
                  settings: root.menuSettings
                  shell: root.shell
                  fg: root.fg
                  muted: root.muted
                  hoverFill: root.hoverFill
                  accent: root.accent
                  fontFamily: root.fontFamily
                  active: root.visible && rssBlock.contentOn
                  appointments: root.appointments
                  onSaveAppointments: function(list) { root.saveAppointments(list) }
                }
              }
              Item {
                id: newsBlock
                property string sectionId: "news"
                readonly property bool contentOn: newsUi.anyOn
                width: parent ? parent.width : 240
                height: (root.arrangeMode || contentOn) ? (newsGrip.height + (contentOn ? newsUi.implicitHeight : 0)) : 0
                visible: height > 0
                SuperMenuGrip { id: newsGrip; sectionId: "news"; title: "News"; host: root }
                SuperMenuWidgets {
                  id: newsUi
                  y: newsGrip.height
                  width: parent.width
                  only: "news"
                  visible: newsBlock.contentOn
                  settings: root.menuSettings
                  shell: root.shell
                  fg: root.fg
                  muted: root.muted
                  hoverFill: root.hoverFill
                  accent: root.accent
                  fontFamily: root.fontFamily
                  active: root.visible && newsBlock.contentOn
                  appointments: root.appointments
                  onSaveAppointments: function(list) { root.saveAppointments(list) }
                }
              }
              Item {
                id: alertsBlock
                property string sectionId: "alerts"
                readonly property bool contentOn: alertsUi.anyOn
                width: parent ? parent.width : 240
                height: (root.arrangeMode || contentOn) ? (alertsGrip.height + (contentOn ? alertsUi.implicitHeight : 0)) : 0
                visible: height > 0
                SuperMenuGrip { id: alertsGrip; sectionId: "alerts"; title: "Alerts"; host: root }
                SuperMenuWidgets {
                  id: alertsUi
                  y: alertsGrip.height
                  width: parent.width
                  only: "alerts"
                  visible: alertsBlock.contentOn
                  settings: root.menuSettings
                  shell: root.shell
                  fg: root.fg
                  muted: root.muted
                  hoverFill: root.hoverFill
                  accent: root.accent
                  fontFamily: root.fontFamily
                  active: root.visible && alertsBlock.contentOn
                  appointments: root.appointments
                  onSaveAppointments: function(list) { root.saveAppointments(list) }
                }
              }
              Item {
                id: filesBlock
                property string sectionId: "files"
                readonly property bool contentOn: !root.service || !root.service.settings || root.service.settings.superMenuRecommended !== false
                width: parent ? parent.width : 240
                height: (root.arrangeMode || contentOn) ? (filesGrip.height + filesCol.implicitHeight) : 0
                visible: height > 0
                SuperMenuGrip { id: filesGrip; sectionId: "files"; title: "Recommended"; host: root }
                Column {
                  id: filesCol
                  y: filesGrip.height
                  width: parent.width
                  spacing: 8
              Text {
                visible: !root.service || !root.service.settings || root.service.settings.superMenuRecommended !== false
                text: "Recommended"
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: 13
                font.weight: Font.DemiBold
              }
              Text {
                visible: (!root.service || !root.service.settings || root.service.settings.superMenuRecommended !== false) && root.recommendedFiles.length === 0
                text: "No recent files"
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: 12
              }
              Repeater {
                model: (!root.service || !root.service.settings || root.service.settings.superMenuRecommended !== false) ? root.recommendedFiles : []
                delegate: Rectangle {
                  id: fileRow
                  required property var modelData
                  width: filesCol.width
                  height: 48
                  radius: 8
                  color: fileArea.containsMouse ? root.hoverFill : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.04)
                  Row {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 8
                    FileMark { path: fileRow.modelData.path; size: 28; anchors.verticalCenter: parent.verticalCenter }
                    Column {
                      anchors.verticalCenter: parent.verticalCenter
                      width: parent.width - 44
                      spacing: 2
                      Text {
                        width: parent.width
                        text: fileRow.modelData.title
                        elide: Text.ElideRight
                        color: root.fg
                        font.family: root.fontFamily
                        font.pixelSize: 12
                      }
                      Text {
                        width: parent.width
                        text: fileRow.modelData.when
                        color: root.muted
                        font.family: root.fontFamily
                        font.pixelSize: 10
                      }
                    }
                  }
                  MouseArea { id: fileArea; anchors.fill: parent; hoverEnabled: true; onClicked: root.openPath(fileRow.modelData.path) }
                }
              }
                }
              }

            }
          }
        }
      }
      Rectangle {
        visible: root.pendingPower !== ""
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: 14
        color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.03)
        Column {
          anchors.centerIn: parent
          spacing: 16
          width: Math.min(420, parent.width - 40)
          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.powerLabel(root.pendingPower) + "?"
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: 20
            font.weight: Font.DemiBold
          }
          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: root.pendingPower === "shutdown" ? "This will power the computer off." : (root.pendingPower === "reboot" ? "This will restart the computer." : "This will put the computer to sleep.")
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: 13
          }
          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 12
            Rectangle {
              width: 110
              height: 36
              radius: 8
              color: cancelPowerArea.containsMouse ? root.hoverFill : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06)
              Text { anchors.centerIn: parent; text: "Cancel"; color: root.fg; font.family: root.fontFamily; font.pixelSize: 13 }
              MouseArea { id: cancelPowerArea; anchors.fill: parent; hoverEnabled: true; onClicked: root.pendingPower = "" }
            }
            Rectangle {
              width: 110
              height: 36
              radius: 8
              color: confirmPowerArea.containsMouse ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.55) : Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.35)
              Text { anchors.centerIn: parent; text: root.powerLabel(root.pendingPower); color: root.fg; font.family: root.fontFamily; font.pixelSize: 13; font.weight: Font.DemiBold }
              MouseArea { id: confirmPowerArea; anchors.fill: parent; hoverEnabled: true; onClicked: root.runPower(root.pendingPower) }
            }
          }
        }
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08)
      }

      Item {
        Layout.fillWidth: true
        Layout.preferredHeight: 36
        z: 12
        Row {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: 8
          Rectangle {
            width: 28
            height: 28
            radius: 14
            color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16)
            border.width: 1
            border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.7)
            Text {
              anchors.centerIn: parent
              text: root.userName.charAt(0).toUpperCase()
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: 12
              font.weight: Font.Bold
            }
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.userName
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: 12
          }
        }
        Rectangle {
          id: powerBtn
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: powerLabel.implicitWidth + 28
          height: 32
          radius: 16
          color: powerArea.containsMouse || root.powerMenuOpen
                 ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.2)
                 : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06)
          border.width: 1
          border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, root.powerMenuOpen ? 0.75 : 0.35)
          Row {
            anchors.centerIn: parent
            spacing: 6
            Text { text: "⏻"; color: root.accent; font.family: root.fontFamily; font.pixelSize: 13 }
            Text {
              id: powerLabel
              text: "Power"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: 12
            }
          }
          MouseArea { id: powerArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.powerMenuOpen = !root.powerMenuOpen }
        }
        Rectangle {
          id: powerFlyout
          visible: root.powerMenuOpen
          anchors.right: powerBtn.right
          anchors.bottom: powerBtn.top
          anchors.bottomMargin: 8
          width: 160
          height: powerCol.implicitHeight + 8
          radius: 12
          color: Qt.rgba(root.bg.r, root.bg.g, root.bg.b, 0.96)
          border.width: 1
          border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.55)
          z: 30
          Column {
            id: powerCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 4
            spacing: 2
            Repeater {
              model: Model.powerActions()
              delegate: Rectangle {
                id: pRow
                required property var modelData
                width: powerCol.width
                height: 32
                radius: 8
                color: pArea.containsMouse ? root.hoverFill : "transparent"
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.left: parent.left
                  anchors.leftMargin: 10
                  text: pRow.modelData.label
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: 13
                }
                MouseArea {
                  id: pArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.choosePower(pRow.modelData)
                }
              }
            }
          }
        }
      }
    }
    }

    Rectangle {
      anchors.fill: parent
      radius: root.radius
      color: "transparent"
      border.width: 2
      border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, root.borderOpacity)
      z: 20
      enabled: false
    }
  }

  Item {
    id: sectionPark
    visible: false
    width: 0
    height: 0
  }

}
