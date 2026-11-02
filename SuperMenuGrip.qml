import QtQuick

// Drag handle for one Super Menu section. Hidden unless the menu is in Arrange.
Item {
  id: grip
  property string sectionId: ""
  property string title: ""
  property var host: null
  visible: host !== null && host.arrangeMode
  implicitHeight: visible ? 22 : 0
  height: implicitHeight
  width: parent ? parent.width : 0

  Rectangle {
    anchors.fill: parent
    radius: 6
    visible: grip.visible
    color: !grip.host ? "transparent"
           : grip.host.draggingId === grip.sectionId
             ? Qt.rgba(grip.host.accent.r, grip.host.accent.g, grip.host.accent.b, 0.28)
             : Qt.rgba(grip.host.fg.r, grip.host.fg.g, grip.host.fg.b, 0.08)
    border.width: 1
    border.color: grip.host ? Qt.rgba(grip.host.accent.r, grip.host.accent.g, grip.host.accent.b, 0.45) : "transparent"
    Text {
      anchors.centerIn: parent
      text: "⋮⋮  " + grip.title
      color: grip.host ? grip.host.fg : "#c0caf5"
      font.pixelSize: 11
      font.weight: Font.DemiBold
    }
  }
  MouseArea {
    anchors.fill: parent
    enabled: grip.visible
    hoverEnabled: true
    preventStealing: true
    cursorShape: Qt.OpenHandCursor
    onPressed: function(m) {
      if (grip.host) grip.host.beginDrag(grip.sectionId)
    }
    onPositionChanged: function(m) {
      if (!grip.host || grip.host.draggingId !== grip.sectionId) return
      var p = mapToItem(grip.host, m.x, m.y)
      grip.host.dragAt(p.x, p.y)
    }
    onReleased: function(m) { if (grip.host) grip.host.endDrag() }
    onCanceled: function() { if (grip.host) grip.host.cancelDrag() }
  }
}
