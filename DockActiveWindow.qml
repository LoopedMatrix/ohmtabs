import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

// Focused-window title on the dock. Independent of Caelestia (GPL-3).
Item {
  id: root
  property color ink: Color.foreground
  property int maxWidth: 180

  readonly property var focused: {
    try { return ToplevelManager.activeToplevel } catch (e) { return null }
  }
  readonly property string title: focused ? String(focused.title || focused.appId || "") : ""

  implicitWidth: visible && title.length ? Math.min(maxWidth, label.implicitWidth + 8) : 0
  implicitHeight: 16
  visible: title.length > 0

  Text {
    id: label
    anchors.verticalCenter: parent.verticalCenter
    width: Math.min(root.maxWidth, implicitWidth)
    text: root.title
    elide: Text.ElideRight
    color: root.ink
    font.pixelSize: 11
    opacity: 0.9
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: {
      if (!root.focused) return
      try { root.focused.activate() } catch (e) {}
    }
  }
}
