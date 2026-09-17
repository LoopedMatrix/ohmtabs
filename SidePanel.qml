import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons

// SidePanel — the Windows-style minimized-window taskbar for Grabbar.
//
// A run of window buttons along one screen edge: click a button to restore
// that window. Like the bar widget it registers itself as a restore host, so
// its presence is what lets the service declare restore access.
//
// Position is configurable (left / right / bottom) and it can auto-hide. When
// parked, the surface stays mapped and slides just past its screen edge,
// leaving a few pixels on screen to catch the pointer — the same approach
// Omarchy's own bar uses. Parking beats unmapping because the surface,
// bindings and glyph textures stay alive, so revealing is only a margin
// change rather than a rebuild.
//
// Colours come from the Omarchy bar palette, so it follows theme switches.
Item {
  id: root

  property var shell: null
  property var service: null
  property string serviceName: "tech.greyforge.grabbar"

  // ---- settings (from this plugin's shell.json entry) ----
  property bool panelEnabled: true
  property string panelPosition: "bottom"    // "left" | "right" | "bottom"
  property bool panelAutoHide: true

  // ---- state ----
  property bool hovered: false
  property int selectedIndex: -1

  readonly property bool vertical: panelPosition === "left" || panelPosition === "right"
  readonly property int panelSize: vertical ? 268 : 46
  // Pixels of the parked surface left on screen so the pointer can find it.
  readonly property int revealSliver: 4

  readonly property var rows: (service && service.rows) ? service.rows : []
  readonly property int count: rows.length

  // Nothing to show -> no surface at all, and no stray edge strip either.
  readonly property bool live: panelEnabled && count > 0
  // Auto-hide parks it while the pointer is away and nothing is selected.
  readonly property bool parked: panelAutoHide && !hovered && selectedIndex < 0

  // ---- palette (bar surfaces: it lives on a screen edge) ----
  readonly property color background: Color.bar.background
  readonly property color foreground: Color.bar.text
  readonly property color hoverFill: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.14)
  readonly property color activeFill: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.22)
  readonly property color muted: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.55)
  readonly property color urgent: Color.urgent
  readonly property int radius: Style.cornerRadius
  readonly property string fontFamily: Style.font.menuFamily
  readonly property int buttonLength: vertical ? root.panelSize : 184

  // ------------------------------------------------------------- behaviour

  function restoreRow(row, original) {
    if (!service || !row) return
    service.restore(row.token, original ? "original" : "current", "")
    root.selectedIndex = -1
  }

  function restoreAll() {
    if (!service) return
    service.restoreAll()
    root.selectedIndex = -1
  }

  function move(delta) {
    if (root.count === 0) return
    var next = root.selectedIndex + delta
    if (next < 0) next = root.count - 1
    if (next >= root.count) next = 0
    root.selectedIndex = next
  }

  function dismiss() { root.selectedIndex = -1 }

  // Park after a short grace period so a diagonal pointer path across the
  // panel does not make it flicker away.
  Timer {
    id: hideDelay
    interval: 260
    repeat: false
    onTriggered: root.hovered = false
  }

  // Last window restored -> drop any selection so nothing lingers.
  onCountChanged: if (count === 0) root.selectedIndex = -1

  // ------------------------------------------------------ restore-host wiring

  function declareHost() {
    if (service && typeof service.registerRestoreHost === "function")
      service.registerRestoreHost("side-panel")
  }

  Component.onCompleted: declareHost()
  onServiceChanged: declareHost()
  Component.onDestruction: {
    if (service && typeof service.unregisterRestoreHost === "function")
      service.unregisterRestoreHost("side-panel")
  }

  // ------------------------------------------------------------- surface

  PanelWindow {
    id: panel
    visible: root.live
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "grabbar-taskbar"
    WlrLayershell.keyboardFocus: root.selectedIndex >= 0 ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // Anchoring follows the position; parking is a negative margin along the
    // edge it is anchored to, so the surface slides out of view while a sliver
    // of it stays on screen.
    anchors {
      top: root.vertical
      bottom: root.vertical || root.panelPosition === "bottom"
      left: root.panelPosition === "left" || root.panelPosition === "bottom"
      right: root.panelPosition === "right" || root.panelPosition === "bottom"
    }

    margins {
      bottom: root.parked && root.panelPosition === "bottom" ? -(root.panelSize - root.revealSliver) : 0
      left: root.parked && root.panelPosition === "left" ? -(root.panelSize - root.revealSliver) : 0
      right: root.parked && root.panelPosition === "right" ? -(root.panelSize - root.revealSliver) : 0
    }

    implicitWidth: root.vertical ? root.panelSize : 0
    implicitHeight: root.vertical ? 0 : root.panelSize

    Rectangle {
      id: surface
      anchors.fill: parent
      color: root.background
      border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14)
      border.width: 1

      MouseArea {
        id: panelArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onEntered: { hideDelay.stop(); root.hovered = true }
        onExited: hideDelay.restart()
      }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: root.selectedIndex >= 0
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) { root.dismiss(); event.accepted = true; return }
          if (event.key === Qt.Key_Down || event.key === Qt.Key_Right || event.key === Qt.Key_J) { root.move(1); event.accepted = true }
          else if (event.key === Qt.Key_Up || event.key === Qt.Key_Left || event.key === Qt.Key_K) { root.move(-1); event.accepted = true }
          else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.selectedIndex >= 0 && root.selectedIndex < root.count)
              root.restoreRow(root.rows[root.selectedIndex], event.modifiers & Qt.ShiftModifier)
            event.accepted = true
          }
          else if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier)) { root.restoreAll(); event.accepted = true }
        }
      }

      // "Restore all" sits at the far end of the strip, out of the button run.
      RestoreAllButton {
        id: allButton
        visible: root.count > 1
        horizontal: root.vertical
        anchors.right: root.vertical ? undefined : parent.right
        anchors.bottom: root.vertical ? parent.bottom : undefined
        anchors.rightMargin: root.vertical ? 0 : 6
        anchors.bottomMargin: root.vertical ? 6 : 0
        onActivated: root.restoreAll()
      }

      ListView {
        id: list
        orientation: root.vertical ? ListView.Vertical : ListView.Horizontal
        anchors.fill: parent
        anchors.margins: 5
        anchors.rightMargin: (!root.vertical && allButton.visible) ? allButton.width + 12 : 5
        anchors.bottomMargin: (root.vertical && allButton.visible) ? allButton.height + 12 : 5
        spacing: 4
        clip: true
        model: root.rows
        currentIndex: root.selectedIndex

        delegate: TaskButton {
          required property var modelData
          required property int index
          entry: modelData
          selected: index === root.selectedIndex
          horizontal: root.vertical
          length: root.buttonLength
          thickness: root.panelSize - 10
          onActivated: function(original) { root.restoreRow(modelData, original) }
          onHovered: root.selectedIndex = index
        }
      }
    }
  }

  // ------------------------------------------------------------ components

  // A taskbar button: app badge, elided title, origin line when there is room,
  // and an urgent marker. Left click restores here, right click to the
  // original workspace.
  component TaskButton: Rectangle {
    id: btn
    property var entry: null
    property bool selected: false
    property bool horizontal: false
    property real length: 184
    property real thickness: 36

    signal activated(bool original)
    signal hovered()

    readonly property bool failed: entry ? entry.status === "failed" : false
    readonly property bool urgent: entry ? !!entry.urgent : false
    readonly property string title: entry ? String(entry.label || entry.title || entry.class || "Window") : "Window"
    readonly property string where: entry ? String(entry.origin || "") : ""
    readonly property string badge: {
      var c = entry ? String(entry.class || entry.title || "?") : "?"
      return c.length ? c.charAt(0).toUpperCase() : "?"
    }

    width: btn.horizontal ? btn.length : (btn.parent ? btn.parent.width : 0)
    height: btn.horizontal ? (btn.parent ? btn.parent.height : 0) : btn.thickness
    radius: root.radius
    color: btn.selected ? root.activeFill : (btnArea.containsMouse ? root.hoverFill : "transparent")

    Behavior on color { ColorAnimation { duration: 110 } }

    MouseArea {
      id: btnArea
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onEntered: btn.hovered()
      onClicked: function(m) { btn.activated(m.button === Qt.RightButton) }
    }

    Row {
      anchors.fill: parent
      anchors.leftMargin: 7
      anchors.rightMargin: 7
      spacing: 7

      // App badge: the class initial in a tinted tile, standing in for an icon.
      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: 20
        height: 20
        radius: 5
        color: (btn.urgent || btn.failed) ? root.urgent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
        Text {
          anchors.centerIn: parent
          text: btn.badge
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: 11
          font.weight: Font.DemiBold
        }
      }

      Column {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - 20 - 7
        spacing: 0

        Text {
          width: parent.width
          text: btn.title
          elide: Text.ElideRight
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: 12
        }
        Text {
          width: parent.width
          visible: btn.where !== "" && !btn.horizontal
          text: btn.failed ? "Could not restore — click to retry" : btn.where
          elide: Text.ElideRight
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: 10
        }
      }
    }
  }

  // The "restore every minimized window" affordance at the strip's end.
  component RestoreAllButton: Rectangle {
    id: all
    property bool horizontal: false
    signal activated()

    width: all.horizontal ? (allText.implicitWidth + 34) : (all.parent ? all.parent.width - 10 : 0)
    height: all.horizontal ? (all.parent ? all.parent.height - 10 : 26) : 26
    radius: root.radius
    color: allArea.containsMouse ? root.hoverFill : "transparent"
    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.16)
    border.width: 1

    Row {
      anchors.centerIn: parent
      spacing: 6
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "⤢"
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: 11
      }
      Text {
        id: allText
        anchors.verticalCenter: parent.verticalCenter
        text: "Restore all"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: 11
      }
    }

    MouseArea {
      id: allArea
      anchors.fill: parent
      hoverEnabled: true
      onClicked: function(m) { m.accepted = true; all.activated() }
    }
  }
}