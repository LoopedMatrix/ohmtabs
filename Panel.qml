import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "OhmTabsModel.js" as Model

// OhmTabs overlay. One overlay entry point hosts three views:
//
//   drawer   — the minimized windows drawer (spec §5.2): newest first, Restore
//              as the main action, Original workspace as the secondary one,
//              Restore all in the header. No close, delete or relaunch here.
//   menu     — the window menu (spec §3.4) for one window, opened from the
//              strip's menu button or a right-click on the strip.
//   settings — the short settings panel (spec §9) with Restore all, Check
//              setup and the OhmTabs on/off switch.
//   supermenu — Windows-style start page: All Apps, Pinned, Recommended.
//
// The host calls open(payloadJson) / close(); `opened` reports the state.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property var service: null

  property bool opened: false
  property string view: "drawer"
  property int selectedIndex: 0
  property string monitorName: ""
  property var menuTarget: null       // live window snapshot the menu acts on
  property real menuX: 0
  property real menuY: 0
  property bool menuAnchored: false
  property bool confirmHide: false
  property bool confirmClose: false
  property bool showTechnical: false

  readonly property color background: Color.menu.background
  readonly property color foreground: Color.menu.text
  readonly property color border: Color.menu.border
  readonly property color scrim: Color.menu.scrim
  readonly property color selectedBackground: Color.menu.selectedBackground
  readonly property color selectedText: Color.menu.selectedText
  readonly property color muted: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.55)
  readonly property color accent: Color.accent
  readonly property color barBackground: Color.bar.background
  readonly property color barForeground: Color.bar.text
  readonly property real glass: {
    var n = settings && settings.panelBgOpacity !== undefined ? Number(settings.panelBgOpacity) : 0.78
    if (!(n >= 0.15)) n = 0.78
    if (n > 1) n = 1
    return n
  }
  readonly property real barBorderOpacity: {
    var n = settings && settings.panelBorderOpacity !== undefined ? Number(settings.panelBorderOpacity) : 0.95
    if (!(n >= 0)) n = 0.95
    if (n > 1) n = 1
    return n
  }
  readonly property int cornerRadius: Style.cornerRadius
  readonly property string fontFamily: Style.font.menuFamily
  readonly property int contentMargin: Style.spacing.panelPadding
  readonly property int cardWidth: Math.min(Style.space(520), panel.width - Style.gapsOut * 2)
  readonly property int cardHeight: Math.min(Style.space(440), panel.height - Style.gapsOut * 2)
  readonly property int rowHeight: Math.max(Style.space(48), Style.font.body + Style.font.caption + Style.spacing.rowPaddingX * 2)
  readonly property int menuRowHeight: Style.space(30)
  readonly property string pluginId: (manifest && manifest.id) || Model.PLUGIN_ID
  readonly property var rows: service && service.rows ? service.rows : []
  readonly property string notice: service ? String(service.notice || "") : ""
  readonly property var settings: service && service.settings ? service.settings : Model.normalizeSettings({})
  readonly property bool ohmtabsOn: service ? !service.paused && settings.enabled !== false : false

  // The live snapshot for the menu's window refreshes while the menu is open
  // (maximized / floating state may change under it); the token never does.
  readonly property var menuLive: menuTarget && service && service.liveWindow ? (service.liveWindow(menuTarget.token) || menuTarget) : menuTarget

  // ------------------------------------------------------------ screens

  function screenAt(x, y) {
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++) {
      var s = screens[i]
      if (x >= s.x && x < s.x + s.width && y >= s.y && y < s.y + s.height) return s
    }
    return null
  }

  function screenNamed(name) {
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++) if (String(screens[i].name) === String(name)) return screens[i]
    return screens.length ? screens[0] : null
  }

  // ------------------------------------------------------------ open/close

  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(String(payloadJson || "{}")) || {} } catch (e) {}
    var wanted = String(payload.view || "drawer")
    if (wanted !== "menu" && wanted !== "settings" && wanted !== "notifs" && wanted !== "dashboard" && wanted !== "supermenu" && wanted !== "supermenu-settings") wanted = "drawer"
    root.confirmHide = false
    root.confirmClose = false
    root.selectedIndex = 0
    // The destination is captured when the drawer opens, not when a row is
    // hovered or focus changes later (spec §5.2).
    root.monitorName = service && service.currentMonitorName ? service.currentMonitorName() : ""
    if (payload.monitor) {
      var named = root.screenNamed(payload.monitor)
      if (named) panel.screen = named
    } else if (payload.x || payload.y) {
      var at = root.screenAt(Number(payload.x) || 0, Number(payload.y) || 0)
      if (at) panel.screen = at
    }
    root.menuAnchored = !!(payload.x || payload.y)
    root.menuX = Number(payload.x) || 0
    root.menuY = Number(payload.y) || 0
    if (wanted === "menu") {
      var token = String(payload.token || "")
      var live = service && service.liveWindow ? service.liveWindow(token) : null
      if (!live && service && service.menuWindow && (!token || service.menuWindow.token === token)) live = service.menuWindow
      if (!live && payload.appId) {
        live = { token: token, class: String(payload.appId), title: String(payload.appId), minimized: false, floating: false, origin: "", maximized: false, fullscreen: false, modal: false }
      }
      if (!live) { wanted = "settings" } else {
        root.menuTarget = live
        var s = root.screenAt(root.menuX, root.menuY)
        if (s) panel.screen = s
      }
    }
    if (wanted !== "menu" && !payload.monitor && !(payload.x || payload.y)) {
      var ms = root.screenNamed(root.monitorName)
      if (ms) panel.screen = ms
    }
    root.view = wanted
    root.opened = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() { root.opened = false; root.menuTarget = null }

  function dismiss() {
    root.opened = false
    root.menuTarget = null
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
  }

  function toggle() { if (root.opened) root.dismiss(); else root.open("{}") }

  function switchView(name) {
    root.confirmHide = false
    root.confirmClose = false
    root.selectedIndex = 0
    root.view = name
    var ms = root.screenNamed(root.monitorName)
    if (ms && name !== "menu") panel.screen = ms
  }

  // ------------------------------------------------------------- actions

  function restoreRow(row, original) {
    if (!service || !row) return
    service.restore(row.token, original ? "original" : "current", root.monitorName)
    if (root.rows.length <= 1) root.dismiss()
  }

  function restoreAll() {
    if (!service) return
    service.restoreAll()
    root.dismiss()
  }

  function select(delta, count) {
    if (count === 0) return
    var next = root.selectedIndex + delta
    if (next < 0) next = 0
    if (next >= count) next = count - 1
    root.selectedIndex = next
  }

  // Window menu entries (spec §3.4). Window actions first, product entries
  // after the separator. Disabled items keep a short reason.
  readonly property var menuItems: {
    var w = root.menuLive
    if (!w) return []
    var parked = !!w.minimized
    var minimizeOk = service && service.minimizeEnabled && !w.fullscreen && !w.modal && !parked
    var minimizeWhy = parked ? "This window is already minimized"
      : (!service || !service.minimizeEnabled ? "Minimize is unavailable until the taskbar is ready"
      : (w.fullscreen ? "Leave fullscreen first" : (w.modal ? "Dialogs are minimized with their window" : "")))
    var parkedWhy = "Restore the window first"
    return [
      { id: "pin", label: service && service.settings && Model.isPinned(service.settings.pinnedApps, w.class) ? "Unpin from dock" : "Pin to dock", enabled: !!w.class, why: w.class ? "" : "No application id" },
      { id: "launch", label: "Launch", enabled: !!w.class, why: w.class ? "" : "No application id" },
      { id: "sep0" },
      { id: "minimize", label: "Minimize", enabled: !!minimizeOk, why: minimizeWhy },
      { id: "original", label: "Restore", enabled: parked && !!w.origin, why: parked ? (w.origin ? "" : "No original workspace recorded") : "Only minimized windows can restore" },
      { id: "maximize", label: w.maximized ? "Restore size" : "Maximize", enabled: !w.fullscreen && !parked, why: w.fullscreen ? "Leave fullscreen first" : (parked ? parkedWhy : "") },
      { id: "float", label: "Move freely", enabled: !parked, checked: !!w.floating, why: parked ? parkedWhy : "" },
      { id: "close", label: "Close", enabled: true },
      { id: "sep" },
      { id: "hide", label: "Hide OhmTabs for " + (w.class || "this window"), enabled: !!w.class, why: w.class ? "" : "This window has no application class" }
    ]
  }

  function runMenuItem(item) {
    if (!item || !item.enabled || !root.menuLive || !service) return
    var token = root.menuLive.token
    switch (item.id) {
      case "pin":
        if (service.saveSettings) service.saveSettings({ pinnedApps: Model.togglePinned(service.settings.pinnedApps, root.menuLive.class) })
        root.dismiss(); break
      case "launch":
        try {
          var desk = String(root.menuLive.class || "")
          Quickshell.execDetached(["gtk-launch", desk])
        } catch (e) {}
        root.dismiss(); break
      case "minimize": service.minimizeToken(token); root.dismiss(); break
      case "original": service.restore(token, "original", ""); root.dismiss(); break
      case "maximize": service.toggleMaximize(token); root.dismiss(); break
      case "float": service.setFloating(token, !root.menuLive.floating); root.dismiss(); break
      case "close":
        if (root.menuLive.minimized) { root.confirmClose = true; break }
        service.closeWindow(token); root.dismiss(); break
      case "hide": root.confirmHide = true; break
      default: break
    }
  }

  function confirmHideNow() {
    if (root.menuLive && service && service.excludeClass) service.excludeClass(root.menuLive.class)
    root.confirmHide = false
    root.dismiss()
  }

  function confirmCloseNow() {
    if (root.menuLive && service) service.closeWindow(root.menuLive.token)
    root.confirmClose = false
    root.dismiss()
  }

  function setOhmTabsOn(on) {
    if (!service) return
    if (on) service.enable(); else service.disable()
  }

  // Setup facts for "Check setup": plain, actionable lines.
  readonly property var setupLines: {
    if (!service) return [{ ok: false, text: "The OhmTabs service is not running" }]
    var out = []
    out.push({ ok: service.backendConnected, text: service.backendConnected ? "Native backend loaded (" + service.backendVersion + ")" : "Native backend is not loaded — see README: Enabling the native controls" })
    out.push({ ok: service.restoreHost, text: service.restoreHost ? "Bar widget in place; minimized windows can be found" : "Bar widget missing — Minimize stays off" })
    out.push({ ok: service.minimizeEnabled || service.paused, text: service.paused ? "OhmTabs is turned off" : (service.minimizeEnabled ? "Minimize enabled" : "Minimize disabled") })
    out.push({ ok: service.journalStatus === "ok" || service.journalStatus === "empty", text: "Recovery journal: " + service.journalStatus })
    if (service.busy) out.push({ ok: false, text: "Another OhmTabs shell service holds the backend" })
    return out
  }

  // ------------------------------------------------------------- window

  PanelWindow {
    id: panel
    visible: root.opened
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "ohmtabs-overlay"
    WlrLayershell.keyboardFocus: {
      if (!root.opened) return WlrKeyboardFocus.None
      if (root.view === "supermenu") return WlrKeyboardFocus.OnDemand
      return WlrKeyboardFocus.Exclusive
    }
    anchors { top: true; bottom: true; left: true; right: true }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
      Rectangle { anchors.fill: parent; color: (root.view === "menu" || root.view === "supermenu") ? "transparent" : root.scrim }
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          if (root.confirmHide) root.confirmHide = false
          else if (root.view !== "drawer" && root.view !== "menu" && root.view !== "supermenu" && root.rows.length > 0) root.switchView("drawer")
          else root.dismiss()
          event.accepted = true; return
        }
        var count = root.view === "menu" ? root.menuItems.length : (root.view === "drawer" ? root.rows.length : 0)
        if (event.key === Qt.Key_Down || event.key === Qt.Key_J) { root.select(1, count); event.accepted = true }
        else if (event.key === Qt.Key_Up || event.key === Qt.Key_K) { root.select(-1, count); event.accepted = true }
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          if (root.view === "menu") root.runMenuItem(root.menuItems[root.selectedIndex])
          else if (root.view === "drawer") root.restoreRow(root.rows[root.selectedIndex], event.modifiers & Qt.ShiftModifier)
          event.accepted = true
        }
        else if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier) && root.view === "drawer") { root.restoreAll(); event.accepted = true }
      }
    }

    // ------------------------------------------------------------ drawer

    Rectangle {
      id: card
      visible: root.view === "drawer"
      width: root.cardWidth
      height: Math.min(root.cardHeight, header.height + Math.max(1, root.rows.length) * root.rowHeight + root.contentMargin * 2 + Style.space(8) + (root.notice ? noticeRow.height + Style.space(4) : 0))
      anchors.horizontalCenter: parent.horizontalCenter
      y: Style.gapsOut + Style.space(8)
      radius: root.cornerRadius
      color: root.background
      border.color: root.border
      border.width: 1

      MouseArea { anchors.fill: parent; onClicked: function(m) { m.accepted = true } }

      Column {
        anchors.fill: parent
        anchors.margins: root.contentMargin
        spacing: Style.space(4)

        Item {
          id: header
          width: parent.width
          height: Style.space(32)
          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.rows.length === 0 ? "No minimized windows" : (root.rows.length + " minimized window" + (root.rows.length === 1 ? "" : "s"))
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.weight: Font.Medium
          }
          Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)
            PillButton { label: "Restore all"; visible: root.rows.length > 1; onActivated: root.restoreAll() }
            PillButton { label: "Settings"; onActivated: root.switchView("settings") }
          }
        }

        Text {
          id: noticeRow
          visible: root.notice !== ""
          width: parent.width
          text: root.notice
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        ListView {
          id: list
          width: parent.width
          height: parent.height - header.height - (root.notice ? noticeRow.height + Style.space(4) : 0) - Style.space(4)
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
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(10)
              spacing: Style.space(10)

              Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - actions.width - Style.space(10)
                spacing: 2
                Text {
                  width: parent.width
                  text: row.modelData.label
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

              Row {
                id: actions
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(6)
                PillButton {
                  label: row.modelData.status === "failed" ? "Retry" : "Restore"
                  onActivated: root.restoreRow(row.modelData, false)
                }
                PillButton {
                  label: "Original workspace"
                  visible: !!(row.modelData.where && (row.modelData.where.workspaceName || row.modelData.where.workspace))
                  onActivated: root.restoreRow(row.modelData, true)
                }
              }
            }
          }
        }
      }
    }

    // ------------------------------------------------------- window menu

    Rectangle {
      id: menuCard
      visible: root.view === "menu" && root.menuLive !== null
      width: Style.space(260)
      height: menuColumn.implicitHeight + Style.space(12)
      radius: root.cornerRadius
      color: root.background
      border.color: root.border
      border.width: 1
      // Anchor at the pointer, kept inside the screen.
      x: Math.max(Style.gapsOut, Math.min(root.menuX - (panel.screen ? panel.screen.x : 0), panel.width - width - Style.gapsOut))
      y: Math.max(Style.gapsOut, Math.min(root.menuY - (panel.screen ? panel.screen.y : 0), panel.height - height - Style.gapsOut))

      MouseArea { anchors.fill: parent; onClicked: function(m) { m.accepted = true } }

      Column {
        id: menuColumn
        anchors.fill: parent
        anchors.margins: Style.space(6)
        spacing: 0

        Text {
          width: parent.width
          height: root.menuRowHeight
          verticalAlignment: Text.AlignVCenter
          leftPadding: Style.space(10)
          text: root.menuLive ? (root.menuLive.title || root.menuLive.class || "Window") : ""
          elide: Text.ElideRight
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Repeater {
          model: (root.confirmHide || root.confirmClose) ? [] : root.menuItems
          delegate: Item {
            required property var modelData
            required property int index
            width: menuColumn.width
            height: modelData.id === "sep" ? Style.space(9) : root.menuRowHeight
            Rectangle {
              visible: modelData.id === "sep"
              anchors.centerIn: parent
              width: parent.width - Style.space(16)
              height: 1
              color: root.border
            }
            Rectangle {
              visible: modelData.id !== "sep"
              anchors.fill: parent
              radius: root.cornerRadius
              color: (index === root.selectedIndex || itemArea.containsMouse) && modelData.enabled ? root.selectedBackground : "transparent"
              Row {
                anchors.fill: parent
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(10)
                spacing: Style.space(8)
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(14)
                  text: modelData.checked ? "✓" : ""
                  color: root.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - Style.space(22)
                  text: modelData.label + (modelData.enabled || !modelData.why ? "" : " — " + modelData.why)
                  elide: Text.ElideRight
                  color: modelData.enabled ? ((index === root.selectedIndex || itemArea.containsMouse) ? root.selectedText : root.foreground) : root.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
              }
              MouseArea {
                id: itemArea
                anchors.fill: parent
                hoverEnabled: true
                onEntered: root.selectedIndex = index
                onClicked: root.runMenuItem(modelData)
              }
            }
          }
        }

        Column {
          visible: root.confirmHide
          width: parent.width
          spacing: Style.space(6)
          padding: Style.space(6)
          Text {
            width: parent.width - Style.space(12)
            text: "Hide OhmTabs for " + (root.menuLive ? root.menuLive.class : "") + "? Its windows lose the title strip. You can undo this in OhmTabs settings."
            wrapMode: Text.WordWrap
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          Row {
            spacing: Style.space(6)
            PillButton { label: "Hide"; onActivated: root.confirmHideNow() }
            PillButton { label: "Cancel"; onActivated: root.confirmHide = false }
          }
        }

        Column {
          visible: root.confirmClose
          width: parent.width
          spacing: Style.space(6)
          padding: Style.space(6)
          Text {
            width: parent.width - Style.space(12)
            text: "Close this minimized window? It will exit, not just leave the taskbar."
            wrapMode: Text.WordWrap
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          Row {
            spacing: Style.space(6)
            PillButton { label: "Close"; onActivated: root.confirmCloseNow() }
            PillButton { label: "Cancel"; onActivated: root.confirmClose = false }
          }
        }
      }
    }

    // ----------------------------------------------------------- settings

    Rectangle {
      id: settingsCard
      visible: root.view === "settings"
      width: 360
      height: Math.min(panel.height - Style.gapsOut * 2, dockSettings.implicitHeight)
      anchors.horizontalCenter: parent.horizontalCenter
      y: Style.gapsOut + Style.space(8)
      radius: 18
      color: "transparent"

      MouseArea { anchors.fill: parent; onClicked: function(m) { m.accepted = true } }

      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: dockSettings.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        DockSettingsUi {
          id: dockSettings
          width: 360
          service: root.service
          settings: root.settings
          ohmtabsOn: root.ohmtabsOn
          minimizedCount: root.rows.length
          excludedClasses: root.settings.excludedClasses || []
          onCloseRequested: root.dismiss()
          onRestoreAll: root.restoreAll()
          onOpenDrawer: root.switchView("drawer")
          onSetOhmTabsOn: function(on) { root.setOhmTabsOn(on) }
        }
      }
    }

    Rectangle {
      id: superMenuSettingsCard
      visible: root.view === "supermenu-settings"
      width: 400
      height: Math.min(panel.height - Style.gapsOut * 2, superMenuSettings.implicitHeight)
      anchors.horizontalCenter: parent.horizontalCenter
      y: Style.gapsOut + Style.space(8)
      radius: 18
      color: "transparent"
      MouseArea { anchors.fill: parent; onClicked: function(m) { m.accepted = true } }
      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: superMenuSettings.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        SuperMenuSettings {
          id: superMenuSettings
          width: 400
          service: root.service
          settings: root.settings
          onCloseRequested: root.dismiss()
        }
      }
    }

    Rectangle {
      id: notifsCard
      visible: root.view === "notifs"
      width: 360
      height: Math.min(panel.height - Style.gapsOut * 2, notifsUi.implicitHeight)
      anchors.horizontalCenter: parent.horizontalCenter
      y: Style.gapsOut + Style.space(8)
      radius: 18
      color: root.background
      border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.45)
      border.width: 1
      MouseArea { anchors.fill: parent; onClicked: function(m) { m.accepted = true } }
      OverlayNotifs {
        id: notifsUi
        anchors.fill: parent
        notifService: (root.shell && typeof root.shell.serviceFor === "function") ? root.shell.serviceFor("omarchy.notifications") : null
        onCloseRequested: root.dismiss()
      }
    }

    Rectangle {
      id: dashCard
      visible: root.view === "dashboard"
      width: Math.min(560, panel.width - Style.gapsOut * 2)
      height: Math.min(460, panel.height - Style.gapsOut * 2)
      anchors.horizontalCenter: parent.horizontalCenter
      y: Style.gapsOut + Style.space(8)
      radius: 18
      color: root.background
      border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.45)
      border.width: 1
      MouseArea { anchors.fill: parent; onClicked: function(m) { m.accepted = true } }
      OverlayDashboard {
        id: dashUi
        anchors.fill: parent
        onCloseRequested: root.dismiss()
      }
    }

    // --------------------------------------------------------- super menu
    // Windows Start flyout: sit just above (or beside) the Start tile.
    // Overlay coords are global; convert to this PanelWindow's screen.
    Item {
      id: superMenuCard
      visible: root.view === "supermenu"
      width: Math.min(1100, panel.width - Style.gapsOut * 2)
      height: Math.min(640, panel.height - 96)
      x: {
        var gap = Style.gapsOut
        var w = width
        if (!root.menuAnchored)
          return Math.max(gap, Math.round((panel.width - w) / 2))
        var sx = panel.screen ? panel.screen.x : 0
        var localX = root.menuX - sx
        var x = localX - 28
        return Math.max(gap, Math.min(x, panel.width - w - gap))
      }
      y: {
        var gap = 12
        var h = height
        var ph = panel.height
        if (!root.menuAnchored)
          return Math.max(gap, ph - h - 80)
        var sy = panel.screen ? panel.screen.y : 0
        var localY = root.menuY - sy
        var yAbove = localY - h - gap
        if (yAbove >= gap) return yAbove
        var yBelow = localY + 32 + gap
        if (yBelow + h <= ph - gap) return yBelow
        return Math.max(gap, Math.min(localY - Math.round(h / 2), ph - h - gap))
      }
      MouseArea { anchors.fill: parent; onClicked: function(m) { m.accepted = true } }
      SuperMenu {
        id: superMenuUi
        anchors.fill: parent
        shell: root.shell
        service: root.service
        moduleName: root.pluginId
        bg: root.barBackground
        fg: root.barForeground
        accent: root.accent
        fontFamily: root.fontFamily
        radius: Math.max(root.cornerRadius, 14)
        glass: 0.92
        borderOpacity: Math.max(0.85, root.barBorderOpacity)
        onCloseRequested: root.dismiss()
        onRequestSettings: root.switchView("supermenu-settings")
      }
    }

  }

  // ---------------------------------------------------------- components

  component PillButton: Rectangle {
    id: pill
    property string label: ""
    signal activated()
    width: pillText.implicitWidth + Style.space(14)
    height: Style.space(24)
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
    MouseArea { id: pillArea; anchors.fill: parent; hoverEnabled: true; onClicked: function(m) { m.accepted = true; pill.activated() } }
  }

  component SettingRow: Item {
    id: settingRow
    property string label: ""
    property string hint: ""
    property var options: []
    property int current: 0
    signal chosen(int index)
    width: settingsColumn.width
    height: Style.space(40)
    Column {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - choices.width - Style.space(10)
      spacing: 2
      Text { text: settingRow.label; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body }
      Text { width: parent.width; text: settingRow.hint; elide: Text.ElideRight; color: root.muted; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
    }
    Row {
      id: choices
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(4)
      Repeater {
        model: settingRow.options
        delegate: Rectangle {
          required property var modelData
          required property int index
          width: choiceText.implicitWidth + Style.space(16)
          height: Style.space(26)
          radius: root.cornerRadius
          color: index === settingRow.current ? root.selectedBackground : (choiceArea.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05) : "transparent")
          border.color: index === settingRow.current ? root.accent : root.border
          border.width: 1
          Text {
            id: choiceText
            anchors.centerIn: parent
            text: modelData
            color: index === settingRow.current ? root.selectedText : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          MouseArea { id: choiceArea; anchors.fill: parent; hoverEnabled: true; onClicked: settingRow.chosen(index) }
        }
      }
    }
  }
}
