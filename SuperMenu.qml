import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Super Menu — Windows-style start page.
// Three columns: All Apps (left), Pinned (middle), Recommended (right).
// Theme: matches the OhmTabs taskbar (dark glass, accent border, rounded).
Item {
  id: root

  property var shell: null
  property var service: null
  property string moduleName: "tech.loopedmatrix.ohmtabs"

  // Warm up DesktopEntries async scan
  property var warm: DesktopEntries.applications

  // ---- palette ----
  readonly property color bg: "#1a1b26"
  readonly property color fg: "#c0caf5"
  readonly property color hoverFill: Qt.rgba(0.75, 0.79, 0.96, 0.14)
  readonly property color activeFill: Qt.rgba(0.75, 0.79, 0.96, 0.22)
  readonly property color muted: Qt.rgba(0.75, 0.79, 0.96, 0.55)
  readonly property color accent: "#7aa2f7"
  readonly property int radius: 12
  readonly property string fontFamily: "sans-serif"

  signal closeRequested()

  // ---- state ----
  property string searchQuery: ""

  // ---- data ----
  readonly property var pinnedAppsList: {
    var result = []
    var pins = (service && service.settings && service.settings.pinnedApps) ? service.settings.pinnedApps : []
    for (var i = 0; i < pins.length; i++) {
      var pid = String(pins[i] || "")
      if (pid) result.push({ appId: pid, name: pid, kind: "app" })
    }
    return result
  }

  readonly property var allApps: {
    var result = []
    try {
      var entries = DesktopEntries.applications ? (DesktopEntries.applications.values || []) : []
      for (var i = 0; i < entries.length; i++) {
        var e = entries[i]
        if (!e) continue
        var name = String(e.name || e.id || "")
        var id = String(e.id || "")
        if (name && id) result.push({ appId: id, name: name, kind: "app", icon: e.icon ? String(e.icon) : "" })
      }
    } catch (e2) {}
    result.sort(function(a, b) { return a.name.toLowerCase() < b.name.toLowerCase() ? -1 : 1 })
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
        result.push(a)
    }
    return result
  }

  readonly property var recentApps: {
    var seen = {}
    var result = []
    var pins = root.pinnedAppsList
    for (var i = 0; i < pins.length; i++) {
      var p = pins[i]
      if (p.appId && !seen[p.appId]) {
        seen[p.appId] = true
        result.push(p)
      }
    }
    try {
      var hts = Hyprland.toplevels.values
      for (var h = 0; h < hts.length; h++) {
        var ht = hts[h]
        if (!ht) continue
        var cls = String(ht.class || (ht.lastIpcObject ? ht.lastIpcObject.class : "") || "")
        var app = ht.wayland ? String(ht.wayland.appId || "") : ""
        var id = (cls && cls !== "electron" && cls !== "chromium") ? cls : app
        if (id && !seen[id]) {
          seen[id] = true
          result.push({ appId: id, name: id, kind: "app" })
        }
      }
    } catch (e) {}
    return result
  }

  readonly property var recentAppsModel: root.recentApps.slice(0, 6)

  // ---- icon resolution ----
  function resolveIcon(appId) {
    var key = String(appId || "")
    if (!key) return ""
    var names = [key]
    var parts = key.split(".")
    if (parts.length > 1) names.push(parts[parts.length - 1])
    var lower = key.toLowerCase()
    if (lower.indexOf("hermes") >= 0) { names.push("hermes"); names.push("hermes-desktop") }
    var entries = []
    try { entries = DesktopEntries.applications ? (DesktopEntries.applications.values || []) : [] } catch (e0) { entries = [] }
    var ownerId = ""
    for (var i = 0; i < entries.length; i++) {
      var e = entries[i]
      if (!e) continue
      var eid = String(e.id || "")
      var swc = String(e.startupWMClass || e.startupClass || "")
      if (eid === key || swc === key || eid.replace(/\.desktop$/, "") === key || swc.replace(/\.desktop$/, "") === key) {
        ownerId = eid
        break
      }
    }
    if (ownerId) {
      var owner = null
      try { owner = DesktopEntries.byId(ownerId) } catch (e1) { owner = null }
      if (owner && owner.icon) names.unshift(String(owner.icon))
    }
    var path = ""
    for (var i = 0; i < names.length && !path; i++) {
      var entry = null
      try { entry = DesktopEntries.heuristicLookup(names[i]) } catch (e) { entry = null }
      if (entry && entry.icon) path = Quickshell.iconPath(String(entry.icon), true)
      if (!path) path = Quickshell.iconPath(names[i], true)
    }
    return path
  }

  // ---- actions ----
  function launchApp(appId) {
    var id = String(appId || "")
    if (!id) return
    var desk = id
    try {
      if (typeof DesktopEntries !== "undefined" && DesktopEntries) {
        var entry = DesktopEntries.heuristicLookup(id) || DesktopEntries.byId(id)
        if (entry && entry.id) desk = String(entry.id)
        else {
          var values = DesktopEntries.applications ? (DesktopEntries.applications.values || []) : []
          for (var i = 0; i < values.length; i++) {
            var e = values[i]
            if (!e) continue
            var eid = String(e.id || "")
            var swc = String(e.startupWMClass || e.startupClass || "")
            if (eid === id || swc === id || eid.replace(/\.desktop$/, "") === id) { desk = eid; break }
          }
        }
      }
    } catch (e) {}
    try { Quickshell.execDetached(["gtk-launch", desk]) } catch (e2) {}
    root.close()
  }

  function close() {
    root.closeRequested()
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.moduleName)
  }

  // Escape key to close
  Shortcut {
    sequence: "Escape"
    onActivated: root.close()
  }

  // ---- UI ----
  width: 900
  implicitHeight: 620

  Rectangle {
    anchors.fill: parent
    radius: root.radius + 4
    color: Qt.rgba(root.bg.r, root.bg.g, root.bg.b, 0.96)
    border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.45)
    border.width: 2

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: 20
      spacing: 12

      // Header
      Item {
        Layout.fillWidth: true
        height: 32

        Text {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "Super Menu"
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: 22
          font.weight: Font.Bold
        }

        Rectangle {
          id: closeBtn
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: 32; height: 32
          radius: 16
          color: closeArea.containsMouse ? root.hoverFill : "transparent"

          Item {
            anchors.centerIn: parent
            width: 12; height: 12
            Rectangle {
              anchors.centerIn: parent
              width: 13; height: 2; radius: 1
              color: root.fg
              rotation: 45
            }
            Rectangle {
              anchors.centerIn: parent
              width: 13; height: 2; radius: 1
              color: root.fg
              rotation: -45
            }
          }

          MouseArea {
            id: closeArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.close()
          }
        }
      }

      // Search
      Rectangle {
        Layout.fillWidth: true
        height: 36
        radius: 18
        color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06)
        border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.15)
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
        }

        Text {
          visible: searchInput.text.length === 0
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          anchors.leftMargin: 14
          text: "Search apps and files..."
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: 13
        }
      }

      // 3-column content
      RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 12

        // Left: All Apps
        Rectangle {
          Layout.preferredWidth: 220
          Layout.fillHeight: true
          radius: 10
          color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.03)
          border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08)
          border.width: 1

          ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 4

            Text {
              text: root.searchQuery ? "Search results" : "All Apps"
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: 11
              font.weight: Font.DemiBold
              Layout.bottomMargin: 4
            }

            ListView {
              id: allAppsList
              Layout.fillWidth: true
              Layout.fillHeight: true
              clip: true
              model: root.filteredApps
              delegate: Rectangle {
                required property var modelData
                width: allAppsList.width
                height: 36
                radius: 6
                color: allAppsArea.containsMouse ? root.hoverFill : "transparent"

                Row {
                  anchors.fill: parent
                  anchors.leftMargin: 8
                  anchors.rightMargin: 8
                  spacing: 8

                  Item {
                    width: 20; height: 20
                    anchors.verticalCenter: parent.verticalCenter
                    property string iconSrc: root.resolveIcon(modelData.appId)
                    Image {
                      anchors.fill: parent
                      source: parent.iconSrc
                      visible: parent.iconSrc !== ""
                      fillMode: Image.PreserveAspectFit
                    }
                    Text {
                      anchors.centerIn: parent
                      visible: parent.iconSrc === ""
                      text: modelData.name.charAt(0).toUpperCase()
                      color: root.fg
                      font.family: root.fontFamily
                      font.pixelSize: 12
                      font.weight: Font.DemiBold
                    }
                  }

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.name
                    elide: Text.ElideRight
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: 12
                    Layout.fillWidth: true
                  }
                }

                MouseArea {
                  id: allAppsArea
                  anchors.fill: parent
                  hoverEnabled: true
                  onClicked: root.launchApp(modelData.appId)
                }
              }
            }
          }
        }

        // Middle: Pinned (or Search results)
        Rectangle {
          Layout.fillWidth: true
          Layout.fillHeight: true
          radius: 10
          color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.03)
          border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08)
          border.width: 1

          ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 4

            Text {
              text: root.searchQuery ? "Search results" : "Pinned"
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: 11
              font.weight: Font.DemiBold
              Layout.bottomMargin: 4
            }

            GridView {
              id: pinnedGrid
              Layout.fillWidth: true
              Layout.fillHeight: true
              clip: true
              cellWidth: 90
              cellHeight: 80
              model: root.searchQuery ? root.filteredApps : root.pinnedAppsList
              delegate: Rectangle {
                required property var modelData
                width: 80
                height: 70
                radius: 10
                color: pinnedArea.containsMouse ? root.hoverFill : "transparent"

                Column {
                  anchors.centerIn: parent
                  spacing: 4

                  Item {
                    width: 32; height: 32
                    anchors.horizontalCenter: parent.horizontalCenter
                    property string iconSrc: root.resolveIcon(modelData.appId)
                    Image {
                      anchors.fill: parent
                      source: parent.iconSrc
                      visible: parent.iconSrc !== ""
                      fillMode: Image.PreserveAspectFit
                    }
                    Text {
                      anchors.centerIn: parent
                      visible: parent.iconSrc === ""
                      text: modelData.name.charAt(0).toUpperCase()
                      color: root.fg
                      font.family: root.fontFamily
                      font.pixelSize: 18
                      font.weight: Font.DemiBold
                    }
                  }

                  Text {
                    width: 70
                    text: modelData.name
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: 10
                  }
                }

                MouseArea {
                  id: pinnedArea
                  anchors.fill: parent
                  hoverEnabled: true
                  onClicked: root.launchApp(modelData.appId)
                }
              }
            }
          }
        }

        // Right: Recommended
        Rectangle {
          Layout.preferredWidth: 220
          Layout.fillHeight: true
          radius: 10
          color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.03)
          border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08)
          border.width: 1

          ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8

            // Recent Apps
            Text {
              text: "Recent"
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: 11
              font.weight: Font.DemiBold
            }

            Column {
              Layout.fillWidth: true
              spacing: 2
              Repeater {
                model: root.recentAppsModel
                delegate: Rectangle {
                  required property var modelData
                  width: parent.width
                  height: 32
                  radius: 6
                  color: recentArea.containsMouse ? root.hoverFill : "transparent"

                  Row {
                    anchors.fill: parent
                    anchors.leftMargin: 6
                    anchors.rightMargin: 6
                    spacing: 6

                    Item {
                      width: 18; height: 18
                      anchors.verticalCenter: parent.verticalCenter
                      property string iconSrc: root.resolveIcon(modelData.appId)
                      Image {
                        anchors.fill: parent
                        source: parent.iconSrc
                        visible: parent.iconSrc !== ""
                        fillMode: Image.PreserveAspectFit
                      }
                      Text {
                        anchors.centerIn: parent
                        visible: parent.iconSrc === ""
                        text: modelData.name.charAt(0).toUpperCase()
                        color: root.fg
                        font.family: root.fontFamily
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                      }
                    }

                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      text: modelData.name
                      elide: Text.ElideRight
                      color: root.fg
                      font.family: root.fontFamily
                      font.pixelSize: 11
                      Layout.fillWidth: true
                    }
                  }

                  MouseArea {
                    id: recentArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.launchApp(modelData.appId)
                  }
                }
              }
            }

            // Recent Files (placeholder)
            Text {
              text: "Files"
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: 11
              font.weight: Font.DemiBold
              Layout.topMargin: 8
            }

            Text {
              text: "Recent files coming soon"
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: 11
              Layout.fillWidth: true
            }

            // System toggles
            Text {
              text: "System"
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: 11
              font.weight: Font.DemiBold
              Layout.topMargin: 8
            }

            Column {
              Layout.fillWidth: true
              spacing: 2
              Repeater {
                model: [
                  { label: "Lock", action: "hyprctl dispatch lock" },
                  { label: "Suspend", action: "systemctl suspend" },
                  { label: "Reboot", action: "systemctl reboot" },
                  { label: "Shutdown", action: "systemctl poweroff" }
                ]
                delegate: Rectangle {
                  required property var modelData
                  width: parent.width
                  height: 32
                  radius: 6
                  color: sysArea.containsMouse ? root.hoverFill : "transparent"

                  Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.label
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: 11
                  }

                  MouseArea {
                    id: sysArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                      Quickshell.execDetached(["sh", "-c", modelData.action])
                      root.close()
                    }
                  }
                }
              }
            }
          }
        }
      }

      // Footer
      Item {
        Layout.fillWidth: true
        height: 32

        Row {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: 8

          Rectangle {
            width: 28; height: 28
            radius: 14
            color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.2)
            Text {
              anchors.centerIn: parent
              text: "U"
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: 12
              font.weight: Font.Bold
            }
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "User"
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: 12
          }
        }

        Rectangle {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: 32; height: 32
          radius: 16
          color: powerArea.containsMouse ? root.hoverFill : "transparent"

          Text {
            anchors.centerIn: parent
            text: "⏻"
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: 14
          }

          MouseArea {
            id: powerArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.close()
          }
        }
      }
    }
  }
}
