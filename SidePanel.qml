import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Ui
import qs.Commons

// SidePanel — the Windows-style minimized-window strip for Grabbar.
//
// Behaviour (per spec §5.1):
//   * autoShows when minimizedCount > 0 and autoHideWithBar is on
//   * hides after idleTimeout if minimizedCount is 0 and autoHide is on
//   * reveals on edge approach when revealOnEdge is on, up to edgeRevealTimeout
//   * clicking outside clears the edge-reveal transient (edgeRevealTransient)
//   * Escape dismisses; focus returns to the panel (spec §4.5)
//
// The panel is the restore entry point for minimized windows. Like the bar
// widget, its presence is what lets the service declare restore access; it
// registers itself as a restore host and pushes the Omarchy palette + settings
// writer through the service.
//
// Appearance follows the Omarchy theme: active border, dimmed inactive entries,
// urgent side glow on the focused window, compact title rendering with
// ellipsis, and the same corner rounding + dim inactive behaviour used by the
// rest of the desktop.
Item {
  id: root
  property string moduleName: "tech.greyforge.grabbar"
  readonly property var service: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor(moduleName) : null

  // ---- settings (from this plugin's shell.json entry) ----
  property bool enabled: false
  readonly property bool autoShow: settings.autoShow !== false
  property real panelWidth: clampInt(settings.panelWidth, 160, 600, 260)
  readonly property bool autoHide: settings.autoHide !== false
  property bool autoHideWithBar: settings.autoHideWithBar !== false
  readonly property bool revealOnEdge: settings.revealOnEdge !== false
  property real edgeRevealTimeout: clampInt(settings.edgeRevealTimeout, 0, 2000, 400)
  readonly property bool compactTitles: settings.compactTitles !== false

  // ---- service-derived state ----
  readonly property int minimizedCount: service ? Number(service.minimizedCount || 0) : 0
  readonly property int failedCount: (service && service.failedCount !== undefined) ? Number(service.failedCount) : 0
  readonly property int recoveredCount: (service && service.recoveredCount !== undefined) ? Number(service.recoveredCount) : 0
  readonly property var entries: service ? (service.entries || []) : []
  readonly property string lastResult: service ? String(service.lastResult || "") : ""

  // ---- panel state ----
  property bool visible: false
  property bool edgeRevealTransient: false
  property int selectedIndex: -1

  // ---- theme colours (Omarchy palette through the service) ----
  readonly property var themeValues: ({
    panelActive: String(Color.bar.separator),
    panelInactive: String(Qt.tint(Color.bar.separator, Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.55))),
    panelText: String(Color.bar.text),
    panelTextInactive: String(Qt.tint(Color.bar.text, Qt.rgba(0.55, 0.55, 0.55, 1.0))),
    panelHover: String(Qt.rgba(Color.bar.text.r, Color.bar.text.g, Color.bar.text.b, 0.12)),
    panelUrgent: String(Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.9)),
    panelGlow: String(Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.35))
  })
  onThemeValuesChanged: pushTheme()
  function pushTheme() { if (service && service.setSidePanelTheme) service.setSidePanelTheme(themeValues) }

  // ---- chrome ----
  property bool showCloseButton: settings.showCloseButton !== false
  property string closeGlyph: settings.closeGlyph || "\uF05C4" // nf-md-close
  property real closeButtonWidth: 28

  // ---- idle timer for auto-hide ----
  Timer {
    id: idleTimer
    interval: 3000
    repeat: false
    onTriggered: {
      if (!root.autoHide) return
      if (root.minimizedCount === 0 && !root.edgeRevealTransient) {
        root.visible = false
      }
    }
  }

  // ---- edge-reveal transient timer ----
  Timer {
    id: edgeTimer
    interval: root.edgeRevealTimeout
    repeat: false
    onTriggered: { root.edgeRevealTransient = false; if (!root.minimizedCount) root.visible = false }
  }

  // ---- idle timer restart on activity ----
  function onActivity() {
    if (root.autoHide) idleTimer.restart()
    root.edgeRevealTransient = false
    edgeTimer.stop()
  }

  // ---- quit on Escape ----
  Shortcut {
    sequence: "Escape"
    onActivated: {
      if (!root.visible) return
      root.visible = false
      if (typeof root.service !== "undefined" && root.service) {
        try { if (typeof root.service.restoreFocus === "function") root.service.restoreFocus() } catch (e) {}
      }
    }
  }

  // ---- appearance ----
  property var panelColor: themeValues.panelActive
  property var panelText: themeValues.panelText
  property real panelOpacity: visible ? 1.0 : 0.0
  property real panelX: 0.0
  property real panelY: 0.0
  property real panelW: root.panelWidth
  property real panelH: 0.0   // set by the row layout

  // ---- geometry ----
  function computeGeometry() {
    if (!root.visible) return
    var maxH = 0
    var rows = root.entries
    for (var i = 0; i < rows.length; i++) {
      var e = rows[i]
      if (!e) continue
      var title = e.title || e.class || ""
      var approxLines = root.compactTitles ? 1 : Math.max(1, Math.ceil(title.length / 28))
      var rowH = 36 + (e.urgent ? 4 : 0)
      maxH = Math.max(maxH, rowH)
    }
    root.panelH = Math.min(600, Math.max(40, maxH * Math.min(rows.length, 40) + 12))
  }

  // ---- window row delegate ----
  Component {
    id: rowDelegate
    Item {
      id: row
      property var entry: null
      property int index: 0
      property bool selected: root.selectedIndex === index
      property bool urgent: !!(entry && entry.urgent)
      property bool failed: !!(entry && entry.status === "failed")
      property bool restoring: !!(entry && entry.status === "restoring")
      property bool minimized: !!(entry && entry.status === "minimized")
      property string title: (entry && entry.title) ? sanitizeLabel(entry.title, 96) : (entry && entry.class ? sanitizeLabel(entry.class, 48) : "A window")
      property string secondary: (entry && entry.origin && entry.origin.workspaceName) ? sanitizeLabel(entry.origin.workspaceName, 32) : ""
      property bool showRestore: entry && (entry.status === "minimized" || entry.status === "failed" || entry.status === "restoring")
      property bool showOriginal: entry && entry.origin && entry.origin.workspace

      property var panelColorLocal: row.selected ? panelActive : panelColor
      property var textColorLocal: row.selected ? panelText : (row.minimized ? panelText : panelTextInactive)

      width: root.panelWidth
      height: 36
      opacity: row.selected ? 1.0 : (row.urgent ? 0.95 : (row.minimized ? 0.92 : 0.85))

      Rectangle {
        anchors.fill: parent
        color: row.selected ? themeValues.panelActive : (row.urgent ? themeValues.panelUrgent : themeValues.panelInactive)
        radius: 6
        border.color: row.selected ? themeValues.panelActive : (row.urgent ? themeValues.panelUrgent : "transparent")
        border.width: row.selected ? 1.0 : 0.0
        Behavior on color { ColorAnimation { duration: 120 } }
      }

      if (row.urgent) {
        Rectangle {
          anchors.right: parent.right
          anchors.rightMargin: 0
          width: 6
          height: parent.height
          color: themeValues.panelUrgent
          radius: 3
        }
      }

      RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        anchors.topMargin: 6
        anchors.bottomMargin: 6
        spacing: 6
        clip: true

        Image {
          source: "image://quickshell/nf-md-window-restore"
          width: 16; height: 16
          fillMode: Image.PreserveAspectFit
          color: textColorLocal
          visible: row.showRestore
        }

        Text {
          text: row.title
          color: textColorLocal
          font.pixelSize: 12
          elide: Text.ElideRight
          maximumWidth: root.panelWidth - closeButtonWidth - 48 - 8 - 16 - 16
          visible: row.showRestore
        }

        Text {
          text: row.secondary
          color: textColorLocal
          font.pixelSize: 10
          elide: Text.ElideRight
          opacity: 0.7
          visible: row.showRestore && row.secondary
        }
      }

      // Right-side actions
      RowLayout {
        anchors.right: parent.right
        anchors.rightMargin: 4
        anchors.topMargin: 4
        anchors.bottomMargin: 4
        spacing: 4
        visible: row.showRestore

        if (row.showOriginal) {
          Button {
            text: "\uE838" // fa-location-arrow
            tooltip: "Restore to original workspace"
            font.pixelSize: 12
            onClicked: {
              onActivity()
              if (service && typeof service.restore === "function") {
                service.restore(entry.token, "original")
              }
              root.selectedIndex = -1
            }
          }
        }

        Button {
          text: row.restoring ? "\uE768" : (row.failed ? "\uE71A" : "\uE70F")   // fa-spinner / fa-redo / fa-check
          tooltip: row.restoring ? "Restoring..." : (row.failed ? "Retry restore" : "Restore here")
          font.pixelSize: 12
          enabled: !row.restoring
          onClicked: {
            onActivity()
            if (service && typeof service.restore === "function") {
              service.restore(entry.token, "current")
            }
            root.selectedIndex = -1
          }
        }
      }

      MouseArea {
        anchors.fill: parent
        onClicked: {
          onActivity()
          if (row.selected) {
            root.selectedIndex = -1
          } else {
            root.selectedIndex = index
          }
        }
        onPressed: root.selectedIndex = index
      }
    }
  }

  // ---- row list ----
  column: Column {
    id: rowList
    spacing: 4
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.topMargin: 8
    anchors.leftMargin: 8
    anchors.rightMargin: 8
    width: root.panelWidth - 16
    property var entries: root.entries
    property int selectedIndex: root.selectedIndex

    Repeater {
      model: root.entries
      delegate: rowDelegate
    }
  }

  // ---- Restore-all row ----
  Rectangle {
    id: restoreAllRow
    anchors.top: rowList.bottom
    anchors.topMargin: 4
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: 6
    anchors.rightMargin: 6
    height: 30
    color: "transparent"
    visible: root.entries.length > 0

    RowLayout {
      anchors.fill: parent
      anchors.leftMargin: 4
      anchors.rightMargin: 4
      anchors.topMargin: 4
      anchors.bottomMargin: 4
      spacing: 8

      Text {
        text: "\uE70E" // fa-redo-alt / restore all
        color: panelTextInactive
        font.pixelSize: 12
        enabled: true
      }

      Text {
        text: "Restore all"
        color: panelTextInactive
        font.pixelSize: 11
        elide: Text.ElideRight
        width: root.panelWidth - closeButtonWidth - 16 - 48 - 8
        visible: true
      }

      Button {
        text: "\uE70E"
        tooltip: "Restore all minimized windows"
        font.pixelSize: 11
        onClicked: {
          onActivity()
          if (service && typeof service.restoreAll === "function") {
            service.restoreAll()
          }
          root.selectedIndex = -1
        }
      }
    }
  }

  // ---- close button ----
  Rectangle {
    id: closeRow
    anchors.top: restoreAllRow.bottom
    anchors.topMargin: 4
    anchors.right: parent.right
    anchors.rightMargin: (root.showCloseButton ? root.closeButtonWidth + 8 : 8)
    anchors.left: parent.left
    anchors.leftMargin: 6
    height: root.showCloseButton ? 28 : 0
    color: "transparent"
    visible: root.showCloseButton && root.entries.length > 0

    Button {
      text: root.closeGlyph
      anchors.right: parent.right
      anchors.rightMargin: 0
      anchors.verticalCenter: parent.verticalCenter
      font.pixelSize: 12
      tooltip: "Close side panel"
      onClicked: { root.visible = false }
    }
  }

  // ---- geometry: set panel height from contents ----
  Component.onCompleted: {
    computeGeometry()
    if (typeof root.service !== "undefined" && root.service && typeof root.service.registerSidePanelHost === "function") {
      root.service.registerSidePanelHost("side-panel")
    }
  }

  // ---- service wiring: settings writer + theme + restore host ----
  Connections {
    target: root.service
    ignoreUnknownSignals: true
    function onWindowMinimized() { root.computeGeometry(); idleTimer.stop() }
    function onPanelVisibilityChanged(visible) { root.visible = visible }
  }

  // ---- keyboard navigation ----
  Shortcut {
    sequence: "Up|Key_W"
    onActivated: {
      if (!root.visible) return
      var n = root.entries.length
      if (n === 0) return
      var next = root.selectedIndex - 1
      if (next < 0) next = n - 1
      root.selectedIndex = next
      onActivity()
    }
  }

  Shortcut {
    sequence: "Down|Key_S"
    onActivated: {
      if (!root.visible) return
      var n = root.entries.length
      if (n === 0) return
      var next = root.selectedIndex + 1
      if (next >= n) next = 0
      root.selectedIndex = next
      onActivity()
    }
  }

  Shortcut {
    sequence: "Enter|Key_Enter"
    onActivated: {
      if (!root.visible) return
      if (root.selectedIndex >= 0 && root.selectedIndex < root.entries.length) {
        var e = root.entries[root.selectedIndex]
        if (e && (e.status === "minimized" || e.status === "failed" || e.status === "restoring")) {
          onActivity()
          if (service && typeof service.restore === "function") {
            service.restore(e.token, "current")
          }
          root.selectedIndex = -1
        }
      }
    }
  }

  Shortcut {
    sequence: "Ctrl+A|Ctrl+A"
    onActivated: {
      if (!root.visible) return
      onActivity()
      if (service && typeof service.restoreAll === "function") {
        service.restoreAll()
      }
      root.selectedIndex = -1
    }
  }

  // ---- edges: reveal on mouse approach ----
  MouseArea {
    id: edgeArea
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.NoButton
    onPositionChanged: {
      if (!root.revealOnEdge) return
      if (!root.visible && root.minimizedCount > 0) {
        var dx = mouse.x
        var threshold = 60
        if (!root.edgeRevealTransient && (dx < threshold || mouse.y < threshold)) {
          root.edgeRevealTransient = true
          root.visible = true
          edgeTimer.restart()
        }
      } else if (!root.edgeRevealTransient && root.visible) {
        var dx = mouse.x
        var dy = mouse.y
        var w = root.panelW
        var h = root.panelH
        var within = (mouse.x >= 0 && mouse.x <= w && mouse.y >= 0 && mouse.y <= h)
        if (!within) {
          root.visible = false
        }
      }
    }
    onEntered: {
      if (!root.revealOnEdge) return
      if (!root.visible && root.minimizedCount > 0 && !root.edgeRevealTransient) {
        root.edgeRevealTransparent = true
        root.visible = true
        edgeTimer.restart()
      }
    }
    onExited: {
      if (!root.revealOnEdge) return
      if (root.edgeRevealTransient && !root.visible) {
        root.edgeRevealTransient = false
        edgeTimer.stop()
      }
    }
  }

  // ---- panel background (the visible surface) ----
  Rectangle {
    id: panelBg
    anchors.fill: parent
    color: panelColor
    visible: root.visible || root.edgeRevealTransient
    radius: 8
    border.color: root.selectedIndex >= 0 ? themeValues.panelActive : (root.urgentCount > 0 ? themeValues.panelUrgent : "transparent")
    border.width: root.selectedIndex >= 0 ? 1.0 : 0.0
    opacity: root.panelOpacity

    Behavior on opacity { NumberAnimation { duration: 150 } }
    Behavior on color { ColorAnimation { duration: 120 } }

   layer.enabled: true
    layer.samples: 4
  }

  // ---- glow when a window is urgent (visible side strip) ----
  Rectangle {
    id: urgentGlow
    anchors.fill: panelBg
    anchors.rightMargin: -4
    width: 8
    color: themeValues.panelGlow
    visible: root.entries.some(function(e) { return e && e.urgent })
    radius: 4
    smooth: true
  }

  // ---- settings persistence ----
  function sanitizeLabel(value, maxLen) {
    var s = String(value === undefined || value === null ? "" : value)
    if (s.length > maxLen) s = s.slice(0, maxLen - 1) + "\u2026"
    return s
  }

  function writeSettings(next) {
    if (!bar || !bar.shell || typeof bar.shell.updateEntryInline !== "function") return false
    var entry = {}
    for (var k in next) entry[k] = next[k]
    return bar.shell.updateEntryInline(moduleName, entry) === true
  }

  // ---- service-side registration ----
  function registerSidePanelHost(name) {
    if (!service) return
    if (service.registerRestoreHost) service.registerRestoreHost(name)
    if (service.registerSidePanelHost) service.registerSidePanelHost(name)
    if ("settingsWriter" in service) service.settingsWriter = root.writeSettings
    root.pushTheme()
  }

  // ---- visible property (two-way with service) ----
  function setVisible(v) { root.visible = !!v }
}
