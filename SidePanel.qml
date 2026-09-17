import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons

// SidePanel — the Windows-style minimized-window bar for Grabbar.
//
// A left-edge panel that lists every minimized window and is the restore
// entry point for them. Like the bar widget it registers itself as a restore
// host, so its presence is what lets the service declare restore access.
//
// Loaded by BarWidget.qml, which passes `shell` and `service` explicitly
// (no reliance on dynamic scope). Colours come from the Omarchy palette the
// same way Panel.qml does, so it follows theme switches for free.
//
// Behaviour:
//   * shown when there is at least one minimized window and the setting is on
//   * hides itself when the list empties
//   * Escape dismisses; Up/Down/Enter navigate and restore
Item {
  id: root

  property var shell: null
  property var service: null
  property string serviceName: "tech.greyforge.grabbar"

  // Visible only while the panel is open. The host toggles this.
  property bool opened: false
  property int selectedIndex: -1

  readonly property var rows: (service && service.rows) ? service.rows : []
  readonly property int count: rows.length
  readonly property string notice: service ? String(service.notice || "") : ""

  readonly property color background: Color.menu.background
  readonly property color foreground: Color.menu.text
  readonly property color border: Color.menu.border
  readonly property color selectedBackground: Color.menu.selectedBackground
  readonly property color selectedText: Color.menu.selectedText
  readonly property color muted: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.55)
  readonly property int cornerRadius: Style.cornerRadius
  readonly property string fontFamily: Style.font.menuFamily
  readonly property int panelWidth: 280
  readonly property int rowHeight: Style.space(46)

  // The panel is open AND has something to show.
  readonly property bool shown: opened && count > 0

  // Open by itself when the first window is minimized, hide when the list
  // empties. Deliberately keyed to the 0 -> N transition so that closing the
  // panel by hand while windows are still minimized leaves it closed.
  property bool autoOpen: true
  property int lastCount: 0

  onCountChanged: {
    if (count === 0) {
      root.opened = false
      root.selectedIndex = -1
    } else if (root.lastCount === 0 && root.autoOpen) {
      root.opened = true
    }
    root.lastCount = count
  }

  function toggle() { root.opened = !root.opened }
  function open() { root.opened = true }
  function close() { root.opened = false; root.selectedIndex = -1 }

  function dismiss() {
    root.close()
    if (shell && typeof shell.hide === "function") shell.hide(serviceName)
  }

  function restoreRow(row, original) {
    if (!service || !row) return
    service.restore(row.token, original ? "original" : "current", "")
    if (root.count <= 1) root.close()
  }

  function restoreAll() {
    if (!service) return
    service.restoreAll()
    root.close()
  }

  function move(delta) {
    if (root.count === 0) return
    var next = root.selectedIndex + delta
    if (next < 0) next = root.count - 1
    if (next >= root.count) next = 0
    root.selectedIndex = next
  }

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
    visible: root.shown
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "grabbar-side-panel"
    WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // Left edge, full height, only as wide as the panel so clicks elsewhere
    // still reach the windows underneath.
    anchors { top: true; bottom: true; left: true }
    implicitWidth: root.panelWidth

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: root.shown
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) { root.dismiss(); event.accepted = true; return }
        if (event.key === Qt.Key_Down || event.key === Qt.Key_J) { root.move(1); event.accepted = true }
        else if (event.key === Qt.Key_Up || event.key === Qt.Key_K) { root.move(-1); event.accepted = true }
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          if (root.selectedIndex >= 0 && root.selectedIndex < root.count)
            root.restoreRow(root.rows[root.selectedIndex], event.modifiers & Qt.ShiftModifier)
          event.accepted = true
        }
        else if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier)) { root.restoreAll(); event.accepted = true }
      }
    }

    Rectangle {
      id: card
      anchors.fill: parent
      color: root.background
      radius: root.cornerRadius
      border.color: root.border
      border.width: 1

      Column {
        anchors.fill: parent
        anchors.margins: Style.space(8)
        spacing: Style.space(4)

        Item {
          id: header
          width: parent.width
          height: Style.space(30)

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.count + " minimized"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.weight: Font.Medium
          }
          PillButton {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            label: "Restore all"
            onActivated: root.restoreAll()
          }
        }

        Text {
          width: parent.width
          visible: root.notice !== ""
          text: root.notice
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        ListView {
          id: list
          width: parent.width
          height: parent.height - header.height - (root.notice !== "" ? Style.space(18) : 0) - Style.space(4)
          clip: true
          model: root.rows
          currentIndex: root.selectedIndex

          delegate: Rectangle {
            id: row
            required property var modelData
            required property int index
            width: list.width
            height: root.rowHeight
            radius: root.cornerRadius
            color: index === root.selectedIndex || rowArea.containsMouse ? root.selectedBackground : "transparent"

            MouseArea {
              id: rowArea
              anchors.fill: parent
              hoverEnabled: true
              acceptedButtons: Qt.LeftButton | Qt.RightButton
              onEntered: root.selectedIndex = row.index
              onClicked: function(m) { root.restoreRow(row.modelData, m.button === Qt.RightButton) }
            }

            Row {
              anchors.fill: parent
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              spacing: Style.space(8)

              Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - restorePill.width - Style.space(8)
                spacing: 1
                Text {
                  width: parent.width
                  text: row.modelData.label || row.modelData.title || row.modelData.class || "Window"
                  elide: Text.ElideRight
                  color: row.index === root.selectedIndex ? root.selectedText : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
                Text {
                  width: parent.width
                  text: (row.modelData.status === "failed" ? "Could not restore — try again · " : "") + (row.modelData.origin || "")
                  elide: Text.ElideRight
                  color: root.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              PillButton {
                id: restorePill
                anchors.verticalCenter: parent.verticalCenter
                label: row.modelData.status === "failed" ? "Retry" : "Restore"
                onActivated: root.restoreRow(row.modelData, false)
              }
            }
          }
        }
      }
    }
  }

  // ------------------------------------------------------------ components

  component PillButton: Rectangle {
    id: pill
    property string label: ""
    signal activated()
    width: pillText.implicitWidth + Style.space(14)
    height: Style.space(22)
    radius: root.cornerRadius
    color: pillArea.containsMouse ? root.selectedBackground : "transparent"
    border.color: root.border
    border.width: 1
    Text {
      id: pillText
      anchors.centerIn: parent
      text: pill.label
      color: pillArea.containsMouse ? root.selectedText : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
    MouseArea {
      id: pillArea
      anchors.fill: parent
      hoverEnabled: true
      onClicked: function(m) { m.accepted = true; pill.activated() }
    }
  }
}