import QtQuick
import qs.Commons

Item {
  id: root
  property color ink: Color.foreground
  implicitWidth: col.implicitWidth
  implicitHeight: col.implicitHeight

  property string clockText: Qt.formatTime(new Date(), "hh:mm")
  property string dateText: Qt.formatDate(new Date(), "ddd d MMM")

  Timer {
    interval: 15000
    running: root.visible
    repeat: true
    onTriggered: {
      root.clockText = Qt.formatTime(new Date(), "hh:mm")
      root.dateText = Qt.formatDate(new Date(), "ddd d MMM")
    }
  }

  Column {
    id: col
    spacing: 0
    Text {
      text: root.clockText
      color: root.ink
      font.pixelSize: 12
      font.bold: true
      horizontalAlignment: Text.AlignHCenter
      width: Math.max(implicitWidth, dateLabel.implicitWidth)
    }
    Text {
      id: dateLabel
      text: root.dateText
      color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.7)
      font.pixelSize: 9
      horizontalAlignment: Text.AlignHCenter
      width: parent.width
    }
  }
}
