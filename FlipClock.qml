pragma ComponentBehavior: Bound
import QtQuick

// Split-flap / Solari-style digits. Probe-safe (no qs.Commons).
Item {
  id: root
  property var digits: ["0", "0", "0", "0"]
  property string ap: ""
  property int tile: 26
  property color ink: "#f4e4b8"
  property color plate: "#16130f"
  property color seam: "#4a4034"
  implicitWidth: row.implicitWidth
  implicitHeight: tile

  Row {
    id: row
    spacing: 3
    height: root.tile

    FlipTile { digit: (root.digits && root.digits[0]) ? root.digits[0] : "0"; size: root.tile; ink: root.ink; plate: root.plate; seam: root.seam }
    FlipTile { digit: (root.digits && root.digits[1]) ? root.digits[1] : "0"; size: root.tile; ink: root.ink; plate: root.plate; seam: root.seam }
    Text {
      text: ":"
      color: root.ink
      font.pixelSize: Math.round(root.tile * 0.7)
      font.family: "monospace"
      font.weight: Font.DemiBold
      anchors.verticalCenter: parent.verticalCenter
    }
    FlipTile { digit: (root.digits && root.digits[2]) ? root.digits[2] : "0"; size: root.tile; ink: root.ink; plate: root.plate; seam: root.seam }
    FlipTile { digit: (root.digits && root.digits[3]) ? root.digits[3] : "0"; size: root.tile; ink: root.ink; plate: root.plate; seam: root.seam }
    Text {
      visible: root.ap !== ""
      text: root.ap
      color: root.ink
      font.pixelSize: 9
      font.family: "monospace"
      font.weight: Font.DemiBold
      anchors.verticalCenter: parent.verticalCenter
      leftPadding: 2
    }
  }

  component FlipTile: Rectangle {
    property string digit: "0"
    property int size: 26
    property color ink: "#f4e4b8"
    property color plate: "#16130f"
    property color seam: "#4a4034"
    width: Math.round(size * 0.72)
    height: size
    radius: 4
    color: plate
    border.color: seam
    border.width: 1
    Text {
      anchors.centerIn: parent
      text: parent.digit
      color: parent.ink
      font.family: "monospace"
      font.pixelSize: Math.round(parent.size * 0.62)
      font.weight: Font.DemiBold
    }
    Rectangle {
      width: parent.width
      height: 1
      y: Math.floor(parent.height / 2)
      color: "#000000"
      opacity: 0.55
    }
    Rectangle {
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      height: Math.floor(parent.height / 2)
      radius: 3
      color: Qt.rgba(1, 1, 1, 0.04)
    }
  }
}
