pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "OhmTabsModel.js" as Model

// Super Menu — VIN Star-style Windows start page for OhmTabs.
// Left All (+ Most used), center Pinned + Agents, right Recommended files.
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

  property string searchQuery: ""
  property string pendingPower: ""
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
    var q = root.searchQuery.toLowerCase().trim()
    if (!q) return root.allApps
    var result = []
    var apps = root.allApps
    for (var i = 0; i < apps.length; i++) {
      var a = apps[i]
      if (a.name.toLowerCase().indexOf(q) >= 0 || a.appId.toLowerCase().indexOf(q) >= 0)
        result.push({ appId: a.appId, name: a.name, kind: "app", letter: "" })
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
  }

  function close() {
    root.pendingPower = ""
    root.closeRequested()
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.moduleName)
  }

  function requestPower(kind) {
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
      else root.close()
    }
  }

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
        color: Qt.rgba(0, 1, 0.25, 0.22)
        font.family: "monospace"
        font.pixelSize: 9
        font.weight: Font.Bold
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.NoWrap
      }

      Rectangle {
        anchors.fill: parent
        z: 2
        radius: Math.max(0, root.radius - 2)
        color: Qt.rgba(root.bg.r, root.bg.g, root.bg.b, 0.58)
      }

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 10
        z: 3

      Item {
        Layout.fillWidth: true
        height: 28
        Text {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "Start"
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: 18
          font.weight: Font.DemiBold
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
            height: 26
            width: pillLabel.implicitWidth + 16
            radius: 13
            color: pillArea.containsMouse ? root.hoverFill : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06)
            Text {
              id: pillLabel
              anchors.centerIn: parent
              text: pill.modelData.label
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: 11
            }
            MouseArea {
              id: pillArea
              anchors.fill: parent
              hoverEnabled: true
              onClicked: root.runToggle(pill.modelData.flag)
            }
          }
        }
        Item { Layout.fillWidth: true }
      }

      Rectangle {
        Layout.fillWidth: true
        height: 36
        radius: 18
        color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06)
        border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)
        border.width: 1
        TextInput {
          id: searchInput
          anchors.fill: parent
          anchors.leftMargin: 14
          anchors.rightMargin: 14
          verticalAlignment: Text.AlignVCenter
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: 13
          clip: true
          onTextChanged: root.searchQuery = text
          Component.onCompleted: forceActiveFocus()
        }
        Text {
          visible: searchInput.text.length === 0
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          anchors.leftMargin: 14
          text: "Search apps..."
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: 13
        }
      }

      RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 12
        visible: root.pendingPower === ""

        Rectangle {
          Layout.preferredWidth: 280
          Layout.fillHeight: true
          radius: 14
          color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.03)
          ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 6
            Text {
              text: root.searchQuery ? "Search results" : "All"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: 13
              font.weight: Font.DemiBold
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
                radius: 6
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
                MouseArea { id: usedArea; anchors.fill: parent; hoverEnabled: true; onClicked: root.launchApp(usedRow.modelData.appId) }
              }
            }
            ListView {
              id: allAppsList
              Layout.fillWidth: true
              Layout.fillHeight: true
              clip: true
              model: root.filteredApps
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
                width: allAppsList.width
                height: 34
                radius: 6
                color: allAppsArea.containsMouse ? root.hoverFill : "transparent"
                Row {
                  anchors.fill: parent
                  anchors.leftMargin: 6
                  spacing: 8
                  AppMark { appId: allAppsRow.modelData.appId; label: allAppsRow.modelData.name; size: 20; anchors.verticalCenter: parent.verticalCenter }
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 36
                    text: allAppsRow.modelData.name
                    elide: Text.ElideRight
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: 12
                  }
                }
                MouseArea { id: allAppsArea; anchors.fill: parent; hoverEnabled: true; onClicked: root.launchApp(allAppsRow.modelData.appId) }
              }
            }
          }
        }

        Rectangle {
          Layout.fillWidth: true
          Layout.fillHeight: true
          radius: 14
          color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.05)
          ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 8
            Text {
              text: "Pinned"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: 13
              font.weight: Font.DemiBold
            }
            Text {
              visible: root.pinnedAppsList.length === 0
              text: "No pinned apps"
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: 12
            }
            GridView {
              id: pinnedGrid
              Layout.fillWidth: true
              Layout.preferredHeight: 360
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
                  AppMark { appId: pinnedRow.modelData.appId; label: pinnedRow.modelData.name; size: 36; anchors.horizontalCenter: parent.horizontalCenter }
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
                MouseArea { id: pinnedArea; anchors.fill: parent; hoverEnabled: true; onClicked: root.launchApp(pinnedRow.modelData.appId) }
              }
            }
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
                    AppMark { appId: agentRow.modelData.appId; label: agentRow.modelData.name; size: 28; anchors.horizontalCenter: parent.horizontalCenter }
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

        Rectangle {
          Layout.preferredWidth: 280
          Layout.fillHeight: true
          radius: 14
          color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.03)
          Flickable {
            id: rightFlick
            anchors.fill: parent
            anchors.margins: 12
            clip: true
            contentWidth: width
            contentHeight: rightCol.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            Column {
              id: rightCol
              width: rightFlick.width
              spacing: 8
              SuperMenuWidgets {
                width: parent.width
                settings: (root.service && root.service.settings) ? root.service.settings : ({})
                shell: root.shell
                fg: root.fg
                muted: root.muted
                hoverFill: root.hoverFill
                accent: root.accent
                fontFamily: root.fontFamily
                active: root.visible
                appointments: root.appointments
                onSaveAppointments: function(list) { root.saveAppointments(list) }
              }
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
                  width: rightCol.width
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

      Item {
        Layout.fillWidth: true
        height: 36
        Row {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: 8
          Rectangle {
            width: 28
            height: 28
            radius: 14
            color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.2)
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
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: 32
          height: 32
          radius: 16
          color: powerArea.containsMouse ? root.hoverFill : "transparent"
          Text { anchors.centerIn: parent; text: "⏻"; color: root.fg; font.family: root.fontFamily; font.pixelSize: 14 }
          MouseArea { id: powerArea; anchors.fill: parent; hoverEnabled: true; onClicked: root.requestPower("shutdown") }
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
}
