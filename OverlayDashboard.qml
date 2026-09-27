import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

// Window overview overlay. OhmTabs style — not Caelestia's dashboard.
Item {
  id: root
  property var bar: null
  property color ink: Color.menu.text
  property color muted: Qt.rgba(ink.r, ink.g, ink.b, 0.55)
  property color fill: Color.menu.background
  property color line: Color.menu.border
  property color accent: Color.accent
  property string fontFamily: Style.font.menuFamily
  property string query: ""
  signal closeRequested()

  width: 520
  implicitHeight: 420

  function matches(tl) {
    if (!tl) return false
    var q = root.query.trim().toLowerCase()
    if (!q) return true
    var t = String(tl.title || "").toLowerCase()
    var c = String(tl.appId || tl.class || "").toLowerCase()
    return t.indexOf(q) !== -1 || c.indexOf(q) !== -1
  }

  function activate(tl) {
    if (!tl) return
    try { tl.activate() } catch (e) {}
    root.closeRequested()
  }

  Column {
    anchors.fill: parent
    anchors.margins: 16
    spacing: 10

    Text {
      text: "Overview"
      color: root.ink
      font.family: root.fontFamily
      font.pixelSize: 16
      font.weight: Font.DemiBold
    }

    Rectangle {
      width: parent.width
      height: 32
      radius: 16
      color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.06)
      border.color: root.line
      border.width: 1
      TextInput {
        id: search
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        verticalAlignment: Text.AlignVCenter
        color: root.ink
        font.pixelSize: 13
        clip: true
        onTextChanged: root.query = text
      }
      Text {
        visible: search.text.length === 0
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: 12
        text: "Filter windows"
        color: root.muted
        font.pixelSize: 13
      }
    }

    Row {
      spacing: 8
      Repeater {
        model: [
          { label: "Apps", cmd: ["omarchy-menu", "toggle", "root"] },
          { label: "DND", cmd: ["omarchy-shell", "notifications", "toggleDnd"] },
          { label: "Network", cmd: ["omarchy-menu", "toggle", "network"] }
        ]
        delegate: Rectangle {
          required property var modelData
          width: chipText.implicitWidth + 16
          height: 26
          radius: 13
          color: "transparent"
          border.color: root.line
          border.width: 1
          Text { id: chipText; anchors.centerIn: parent; text: modelData.label; color: root.ink; font.pixelSize: 11 }
          MouseArea {
            anchors.fill: parent
            onClicked: {
              try { Quickshell.execDetached(modelData.cmd) } catch (e) {}
            }
          }
        }
      }
    }

    GridView {
      id: grid
      width: parent.width
      height: parent.height - 110
      cellWidth: 160
      cellHeight: 72
      clip: true
      model: ToplevelManager.toplevels
      delegate: Rectangle {
        required property var modelData
        width: 152
        height: 64
        radius: 12
        visible: root.matches(modelData)
        color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.06)
        border.color: root.line
        border.width: 1
        Column {
          anchors.centerIn: parent
          width: parent.width - 16
          spacing: 2
          Text {
            width: parent.width
            text: modelData ? String(modelData.appId || modelData.title || "Window") : ""
            elide: Text.ElideRight
            color: root.accent
            font.pixelSize: 11
          }
          Text {
            width: parent.width
            text: modelData ? String(modelData.title || "") : ""
            elide: Text.ElideRight
            color: root.ink
            font.pixelSize: 12
          }
        }
        MouseArea {
          anchors.fill: parent
          onClicked: root.activate(modelData)
        }
      }
    }
  }
}
