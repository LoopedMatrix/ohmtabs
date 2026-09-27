import QtQuick
import Quickshell.Hyprland
import qs.Commons

// Independent OhmTabs workspace chips. Do not copy Caelestia GPL.
Item {
  id: root
  property var bar: null
  property color ink: Color.foreground
  property color accent: Color.accent

  implicitWidth: row.implicitWidth
  implicitHeight: Math.max(22, row.implicitHeight)

  function go(id) {
    var n = String(id)
    if (!n.length) return
    if (root.bar && typeof root.bar.run === "function") {
      root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + n + "\" })"))
      return
    }
    if (typeof Hyprland.dispatch === "function")
      Hyprland.dispatch("hl.dsp.focus({ workspace = \"" + n + "\" })")
  }

  function isRegular(ws) {
    if (!ws) return false
    var id = Number(ws.id)
    if (!(id > 0)) return false
    var name = String(ws.name || "")
    if (name.indexOf("special") === 0) return false
    return true
  }

  Row {
    id: row
    spacing: 4
    Repeater {
      model: Hyprland.workspaces
      delegate: Rectangle {
        required property var modelData
        visible: root.isRegular(modelData)
        width: visible ? 22 : 0
        height: visible ? 22 : 0
        radius: 11
        color: (Hyprland.focusedWorkspace && modelData && Hyprland.focusedWorkspace.id === modelData.id)
               ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.85)
               : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.12)
        border.width: 1
        border.color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.22)
        Text {
          anchors.centerIn: parent
          text: modelData ? String(modelData.id) : ""
          color: root.ink
          font.pixelSize: 10
          font.bold: true
        }
        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton
          cursorShape: Qt.PointingHandCursor
          onClicked: root.go(modelData.id)
        }
      }
    }
  }
}
