import QtQuick
import Quickshell
import qs.Commons

// Status chips on the OhmTabs dock. Opens Omarchy panels; does not copy Caelestia.
Item {
  id: root
  property color ink: Color.foreground
  property color accent: Color.accent

  implicitWidth: row.implicitWidth
  implicitHeight: 22

  function run(cmd) {
    try { Quickshell.execDetached(cmd) } catch (e) {}
  }

  Row {
    id: row
    spacing: 4
    Repeater {
      model: [
        { key: "audio", glyph: "♪", cmd: ["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"] },
        { key: "net", glyph: "⌂", cmd: ["omarchy-shell", "omarchy.network", "toggle"] },
        { key: "bt", glyph: "◉", cmd: ["omarchy-shell", "omarchy.bluetooth", "toggle"] }
      ]
      delegate: Rectangle {
        required property var modelData
        width: 22
        height: 22
        radius: 11
        color: chipArea.containsMouse ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.28) : "transparent"
        Text {
          anchors.centerIn: parent
          text: modelData.glyph
          color: root.ink
          font.pixelSize: 12
        }
        MouseArea {
          id: chipArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.run(modelData.cmd)
        }
      }
    }
  }
}
