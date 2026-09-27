import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

// macOS-style window switcher HUD. Hyprland consumes ALT+TAB (ohmtabs alttab
// next|prev → IPC altTabNext/Prev), so this surface only sees Alt-release,
// Escape, Enter, and arrows. Visible only while a switch is in progress.
PanelWindow {
  id: root

  property bool active: false
  property var windows: []
  property int selectedIndex: -1

  property int iconSize: 96
  property int slotWidth: 112
  property int slotSpacing: 14
  property int sidePadding: 32
  property int surfaceHeight: 176

  readonly property int count: root.windows.length
  readonly property int surfaceWidth: count < 1
    ? 0
    : (root.sidePadding * 2) + (count * root.slotWidth) + (Math.max(0, count - 1) * root.slotSpacing)

  function collectWindows() {
    var tops = []
    try { tops = ToplevelManager.toplevels.values } catch (e) { return [] }
    var out = []
    for (var i = 0; i < tops.length; i++) {
      var t = tops[i]
      if (!t) continue
      var appId = String(t.appId || "")
      var title = String(t.title || "")
      if (!appId && !title) continue
      out.push({
        key: appId + ":" + i,
        appId: appId,
        title: title,
        name: title || appId,
        toplevel: t
      })
    }
    return out
  }

  function focusedIndex(list) {
    var active = null
    try { active = ToplevelManager.activeToplevel } catch (e) { return 0 }
    if (!active) return 0
    for (var i = 0; i < list.length; i++) {
      if (list[i].toplevel === active) return i
    }
    return 0
  }

  function iconSource(appId) {
    var key = String(appId || "")
    if (!key) return ""
    var entry = null
    try { entry = DesktopEntries.heuristicLookup(key) } catch (e) {}
    if (entry && entry.icon) return Quickshell.iconPath(String(entry.icon), true)
    return Quickshell.iconPath(key, true)
  }

  function step(direction) {
    if (root.active) {
      if (direction === "prev") root.prev()
      else root.next()
      watchdog.restart()
      return "ok"
    }
    var list = root.collectWindows()
    if (list.length < 1) return "empty"
    var idx = root.focusedIndex(list)
    if (direction === "prev")
      idx = (idx - 1 + list.length) % list.length
    else
      idx = (idx + 1) % list.length
    root.open(list, idx)
    return "ok"
  }

  function open(list, initialIndex) {
    root.windows = list || []
    root.selectedIndex = initialIndex >= 0 && initialIndex < root.windows.length ? initialIndex : 0
    root.active = true
    watchdog.restart()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function next() {
    if (root.count === 0) return
    root.selectedIndex = (root.selectedIndex + 1) % root.count
  }

  function prev() {
    if (root.count === 0) return
    root.selectedIndex = (root.selectedIndex - 1 + root.count) % root.count
  }

  function cancel() {
    watchdog.stop()
    root.active = false
    root.windows = []
    root.selectedIndex = -1
  }

  function activateSelected() {
    if (root.selectedIndex < 0 || root.selectedIndex >= root.count) {
      root.cancel()
      return
    }
    var win = root.windows[root.selectedIndex]
    var top = win ? win.toplevel : null
    root.cancel()
    if (top) {
      try { top.activate() } catch (e) {}
    }
  }

  visible: root.active
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "ohmtabs-alt-tab"
  WlrLayershell.keyboardFocus: root.active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
  anchors { top: true; bottom: true; left: true; right: true }
  mask: Region { item: dockSurface }

  Timer {
    id: watchdog
    interval: 8000
    onTriggered: root.cancel()
  }

  Rectangle {
    id: dockSurface
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.verticalCenter: parent.verticalCenter
    width: Math.max(root.surfaceWidth, root.slotWidth + root.sidePadding * 2)
    height: root.surfaceHeight
    radius: 22
    color: Qt.rgba(Color.menu.background.r, Color.menu.background.g, Color.menu.background.b, 0.88)
    border.color: Qt.rgba(Color.menu.border.r, Color.menu.border.g, Color.menu.border.b, 0.55)
    border.width: 1

    Row {
      id: dockRow
      anchors.centerIn: parent
      spacing: root.slotSpacing

      Repeater {
        model: root.windows

        delegate: Item {
          id: slot
          required property var modelData
          required property int index
          width: root.slotWidth
          height: root.iconSize + 18

          Rectangle {
            anchors.centerIn: parent
            width: root.iconSize + 12
            height: root.iconSize + 12
            radius: 20
            color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.10)
            visible: root.selectedIndex === slot.index
          }

          Image {
            id: icon
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            width: root.iconSize
            height: root.iconSize
            source: root.iconSource(slot.modelData.appId)
            sourceSize: Qt.size(root.iconSize * 2, root.iconSize * 2)
            fillMode: Image.PreserveAspectFit
            cache: true

            Text {
              textFormat: Text.PlainText
              anchors.centerIn: parent
              visible: parent.status !== Image.Ready
              text: {
                var n = String(slot.modelData.name || "?")
                return n.charAt(0).toUpperCase()
              }
              color: Color.menu.text
              font.pixelSize: root.iconSize * 0.42
            }
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: root.selectedIndex = slot.index
            onClicked: {
              root.selectedIndex = slot.index
              root.activateSelected()
            }
          }
        }
      }
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          root.cancel(); event.accepted = true; return
        }
        if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
          if (root.active) { event.accepted = true; return }
          if (event.key === Qt.Key_Backtab) root.prev(); else root.next()
          event.accepted = true; return
        }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.activateSelected(); event.accepted = true; return
        }
        if (event.key === Qt.Key_Left) {
          root.prev(); event.accepted = true; return
        }
        if (event.key === Qt.Key_Right) {
          root.next(); event.accepted = true; return
        }
      }
      Keys.onReleased: function(event) {
        var scan = event.nativeScanCode
        if (event.key === Qt.Key_Alt || scan === 64 || scan === 108) {
          root.activateSelected(); event.accepted = true
        }
      }
    }
  }
}
