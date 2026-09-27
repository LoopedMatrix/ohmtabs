import QtQuick
import Quickshell.Hyprland
import qs.Commons

// Workspace pips on the OhmTabs dock. Independent of Caelestia (GPL-3).
// Always shows `shown` slots (empty / occupied / active). Click or scroll to switch.
Item {
  id: root
  property var bar: null
  property color ink: Color.foreground
  property color accent: Color.accent
  property int shown: 5

  implicitWidth: row.implicitWidth
  implicitHeight: 18

  function clampId(id) {
    var n = Math.round(Number(id))
    if (!(n >= 1)) n = 1
    if (n > root.shown) n = root.shown
    if (n < 1) n = 1
    return n
  }

  function go(id) {
    var n = String(root.clampId(id))
    if (root.bar && typeof root.bar.run === "function") {
      root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + n + "\" })"))
      return
    }
    if (typeof Hyprland.dispatch === "function")
      Hyprland.dispatch("hl.dsp.focus({ workspace = \"" + n + "\" })")
  }

  function goRel(delta) {
    var cur = Hyprland.focusedWorkspace ? Number(Hyprland.focusedWorkspace.id) : 1
    root.go(cur + delta)
  }

  function exists(id) {
    var wss = Hyprland.workspaces
    if (!wss) return false
    var n = wss.length !== undefined ? wss.length : (wss.count || 0)
    for (var i = 0; i < n; i++) {
      var w = wss[i] !== undefined ? wss[i] : (wss.get ? wss.get(i) : null)
      if (w && Number(w.id) === id) return true
    }
    return false
  }

  function isActive(id) {
    return !!(Hyprland.focusedWorkspace && Number(Hyprland.focusedWorkspace.id) === id)
  }

  Row {
    id: row
    spacing: 6
    Repeater {
      model: Math.max(1, root.shown)
      delegate: Item {
        required property int index
        readonly property int wsId: index + 1
        readonly property bool active: root.isActive(wsId)
        readonly property bool occupied: root.exists(wsId)
        width: active ? 18 : 10
        height: 14
        Rectangle {
          anchors.centerIn: parent
          width: active ? 16 : (occupied ? 8 : 6)
          height: active ? 8 : (occupied ? 8 : 6)
          radius: height / 2
          color: active ? root.accent
                        : (occupied ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.55)
                                    : "transparent")
          border.width: occupied && !active ? 0 : 1
          border.color: active ? root.accent : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.35)
        }
        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton
          cursorShape: Qt.PointingHandCursor
          onClicked: root.go(wsId)
        }
      }
    }
  }

  WheelHandler {
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onWheel: function(event) {
      root.goRel(event.angleDelta.y > 0 ? -1 : 1)
      event.accepted = true
    }
  }
}
