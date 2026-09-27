import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import "OhmTabsModel.js" as Model

// Dock-attached volume/brightness OSD. Independent of Caelestia (GPL-3).
// Does not steal notifications or replace Omarchy's OSD; gated by showOsd.
Item {
  id: root
  property bool enabled: false
  property color ink: Color.foreground
  property color fill: Color.menu.background
  property color accent: Color.accent
  property color line: Color.menu.border

  property int volume: 0
  property bool muted: false
  property int brightness: -1
  property string mode: "volume"
  property bool opened: false
  property int lastVolume: -1
  property int lastBright: -1

  function show(kind, value) {
    if (!root.enabled) return
    root.mode = kind
    if (kind === "brightness") root.brightness = value
    else root.volume = value
    root.opened = true
    hideTimer.restart()
  }

  Timer {
    interval: 500
    running: root.enabled
    repeat: true
    onTriggered: {
      volProc.running = false
      volProc.running = true
      brightProc.running = false
      brightProc.running = true
    }
  }

  Timer {
    id: hideTimer
    interval: 1800
    repeat: false
    onTriggered: root.opened = false
  }

  Process {
    id: volProc
    command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var v = Model.parseWpctlVolume(text)
        root.muted = v.muted
        root.volume = v.percent
        if (root.enabled && root.lastVolume >= 0 && v.percent !== root.lastVolume)
          root.show("volume", v.percent)
        root.lastVolume = v.percent
      }
    }
  }

  Process {
    id: brightProc
    command: ["brightnessctl", "-m"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parts = String(text || "").split(",")
        var pct = -1
        if (parts.length >= 4) {
          pct = parseInt(String(parts[3]).replace("%", ""), 10)
          if (!(pct >= 0)) pct = -1
        }
        if (pct < 0) return
        if (pct > 100) pct = 100
        if (root.enabled && root.lastBright >= 0 && pct !== root.lastBright)
          root.show("brightness", pct)
        root.lastBright = pct
        root.brightness = pct
      }
    }
  }

  PanelWindow {
    id: panel
    visible: root.enabled && root.opened
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "ohmtabs-osd"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    anchors { top: true; bottom: true; left: true; right: true }
    mask: Region {}

    Rectangle {
      id: card
      width: 280
      height: 52
      radius: 26
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 84
      color: Qt.rgba(root.fill.r, root.fill.g, root.fill.b, 0.92)
      border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.55)
      border.width: 1
      opacity: panel.visible ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 120 } }

      Row {
        anchors.centerIn: parent
        spacing: 12
        Text {
          text: root.mode === "brightness" ? "☀" : (root.muted ? "🔇" : "🔊")
          color: root.ink
          font.pixelSize: 16
          anchors.verticalCenter: parent.verticalCenter
        }
        Rectangle {
          width: 160
          height: 8
          radius: 4
          color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.15)
          anchors.verticalCenter: parent.verticalCenter
          Rectangle {
            width: parent.width * Math.max(0, Math.min(1, (root.mode === "brightness" ? root.brightness : root.volume) / 100))
            height: parent.height
            radius: 4
            color: root.accent
          }
        }
        Text {
          text: String(root.mode === "brightness" ? root.brightness : root.volume) + "%"
          color: root.ink
          font.pixelSize: 13
          font.bold: true
          anchors.verticalCenter: parent.verticalCenter
        }
      }
    }
  }
}
