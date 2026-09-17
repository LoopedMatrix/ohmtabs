import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons

// SidePanel — the Windows-11-style minimized-window taskbar for Grabbar.
//
// A run of window buttons along one screen edge: click a button to restore
// that window. Like the bar widget it registers itself as a restore host, so
// its presence is what lets the service declare restore access.
//
// Windows groups a taskbar entry by application, so windows of the same class
// collapse into ONE button here too. A stacked marker plus a count chip on the
// tile advertises the group; hovering the button pops a flyout listing each
// member so a specific window can still be restored. Single-window buttons keep
// the window title; grouped buttons show the app name and leave the per-window
// titles to the flyout, the way Windows leaves them to thumbnail previews.
//
// Position is configurable (left / right / bottom) and it can auto-hide. When
// parked, the surface stays mapped and slides just past its screen edge,
// leaving a few pixels on screen to catch the pointer — the same approach
// Omarchy's own bar uses. Parking beats unmapping because the surface,
// bindings and glyph textures stay alive, so revealing is only a margin
// change rather than a rebuild. That margin change is animated so unparking
// reads as a smooth slide instead of a pop.
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
  property bool panelIcons: true       // draw resolved app icons; off -> letter tile

  // ---- state ----
  property bool hovered: false
  property int selectedIndex: -1

  readonly property bool vertical: panelPosition === "left" || panelPosition === "right"
  readonly property int panelSize: vertical ? 268 : 46
  // Pixels of the parked surface left on screen so the pointer can find it.
  readonly property int revealSliver: 4

  readonly property var rows: (service && service.rows) ? service.rows : []
  readonly property int count: rows.length

  // Windows groups by application: fold rows of the same class into one group,
  // ordered by their newest member so a group sits where its most recent
  // window is. Each group carries its members (newest first) and nothing else;
  // the button derives badge/title/attention from them so there is one source
  // of truth for how a group reads.
  readonly property var groups: {
    var out = []
    var byKey = {}
    var list = root.rows
    for (var i = 0; i < list.length; i++) {
      var r = list[i]
      // Class is the app identity; a window without one falls back to its
      // title so it still gets a button rather than vanishing into the crowd.
      var key = String(r.class || r.title || "?")
      var g = byKey[key]
      if (!g) {
        g = { key: key, members: [] }
        byKey[key] = g
        out.push(g)
      }
      g.members.push(r)
    }
    return out
  }

  // Nothing to show -> no surface at all, and no stray edge strip either.
  readonly property bool live: panelEnabled && count > 0
  // Auto-hide parks it while the pointer is away and nothing is selected.
  readonly property bool parked: panelAutoHide && !hovered && selectedIndex < 0

  // The group currently expanded in the hover flyout, and the button it
  // anchored to. Kept as plain state so the flyout can be dismissed from
  // anywhere without touching selection.
  property var flyoutGroup: null
  property var flyoutButton: null
  property bool flyoutHovered: false

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

  // ------------------------------------------------- app-icon resolution
  //
  // The minimized-window buttons show the app's real icon (Windows-taskbar
  // style) instead of a class-initial tile. Resolution ladder, in order:
  //   1. resolved theme icon  — DesktopEntries.heuristicLookup(class), then
  //      Quickshell.iconPath(entry.icon, true). heuristicLookup matches by
  //      desktop-entry id OR StartupWMClass, so a window class that differs
  //      from the entry id still resolves (org.gnome.Nautilus vs nautilus,
  //      brave-browser, flatpak ids with dots) — the same lookup Omarchy's
  //      own AppLibrary / NotificationCard rely on.
  //   2. generic executable    — Quickshell.iconPath("application-x-executable", true).
  //   3. ""                    — the caller keeps the existing letter tile.
  // iconPath's `check=true` returns "" for unknown names instead of Qt's
  // missing-texture placeholder.
  readonly property int iconSize: 20        // logical px, inside the 26px tile
  readonly property int flyoutIconSize: 16  // per-window flyout row icon

  // Monitors here are 1.25x (DP-1) and 1x (DP-2). sourceSize is handed to the
  // icon provider as its requestedSize, so raster icons are fetched at the
  // panel's device pixel ratio and stay crisp on the hidpi monitor; SVG theme
  // icons rasterize at the requested size too, so the same multiplier keeps
  // them crisp at any scale.
  readonly property real iconDpr: {
    var d = 0
    try { d = Screen.devicePixelRatio } catch (e) {}
    return d > 1 ? d : 1
  }

  // class string -> resolved icon source ("" = nothing resolved). Resolved
  // ONCE per class and cached in this JS map: the row list re-evaluates as
  // windows minimize/restore, DesktopEntries can reorder its values when an
  // app starts (Omarchy's Menu.qml guards against the same reorder), and
  // re-resolving per frame would be wasteful. Empty results are cached too so
  // unknown classes are not re-probed on every re-evaluation. (The scan runs
  // at shell startup, so by the time a window is minimized it is populated.)
  property var iconCache: ({})

  function resolveIcon(cls) {
    var key = String(cls || "")
    if (key === "") return ""
    var cached = root.iconCache[key]
    if (cached !== undefined) return cached
    var path = ""
    var entry = DesktopEntries.heuristicLookup(key)
    if (entry && entry.icon) path = Quickshell.iconPath(String(entry.icon), true)
    if (path === "") path = Quickshell.iconPath("application-x-executable", true)
    root.iconCache[key] = path
    return path
  }

  // ------------------------------------------------------------- behaviour

  function restoreRow(row, original) {
    if (!service || !row) return
    service.restore(row.token, original ? "original" : "current", "")
    root.selectedIndex = -1
  }

  // A grouped button restores its newest member; the flyout is the route to
  // any specific one. This mirrors Windows, where clicking a grouped taskbar
  // button brings up the most recently used window of that app.
  function restoreGroup(group, original) {
    if (!group || !group.members || group.members.length === 0) return
    root.restoreRow(group.members[0], original)
  }

  function restoreAll() {
    if (!service) return
    service.restoreAll()
    root.selectedIndex = -1
  }

  function move(delta) {
    var n = root.groups.length
    if (n === 0) return
    var next = root.selectedIndex + delta
    if (next < 0) next = n - 1
    if (next >= n) next = 0
    root.selectedIndex = next
  }

  function dismiss() { root.selectedIndex = -1 }

  // ------------------------------------------------------------ flyout

  // Hovering a multi-window group expands it. Opening is immediate; closing
  // gets a grace period so the pointer can cross the gap to the flyout without
  // it blinking shut mid-flight.
  function flyoutOpen(group, button) {
    if (!group || !group.members || group.members.length < 2) return
    flyoutHideDelay.stop()
    root.flyoutGroup = group
    root.flyoutButton = button
  }

  function flyoutMaybeClose() {
    if (root.flyoutGroup) flyoutHideDelay.restart()
  }

  Timer {
    id: flyoutHideDelay
    interval: 240
    repeat: false
    onTriggered: {
      if (!root.flyoutHovered) {
        root.flyoutGroup = null
        root.flyoutButton = null
      }
    }
  }

  // Park after a short grace period so a diagonal pointer path across the
  // panel does not make it flicker away.
  Timer {
    id: hideDelay
    interval: 260
    repeat: false
    onTriggered: root.hovered = false
  }

  // Last window restored -> drop any selection so nothing lingers, and drop a
  // flyout whose group just shrank below two members.
  onCountChanged: if (count === 0) root.selectedIndex = -1
  onGroupsChanged: {
    root.flyoutGroup = null
    root.flyoutButton = null
    if (root.selectedIndex >= root.groups.length) root.selectedIndex = root.groups.length - 1
  }

  // ------------------------------------------------------ restore-host wiring

  // The bar hosts one widget instance per monitor (Bar.qml builds a BarPanel
  // per screen, so this file is instantiated once per monitor). Without a
  // `screen:` binding every instance would land on the focused monitor and
  // stack N identical surfaces there while the other monitors stay empty. The
  // widget's own Screen attached property reports the monitor this bar lives
  // on, so resolve its name against Quickshell's screens and fall back to the
  // first screen, keeping exactly one panel per monitor.
  function resolveScreen() {
    var name = ""
    try { name = String(Screen.name || "") } catch (e) {}
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++) {
      var s = screens[i]
      if (name !== "" && s && String(s.name) === name) return s
    }
    return (screens && screens.length) ? screens[0] : null
  }

  function declareHost() {
    if (service && typeof service.registerRestoreHost === "function")
      service.registerRestoreHost("side-panel")
  }

  Component.onCompleted: {
    panel.screen = root.resolveScreen()
    // The enclosing window's screen can lag this widget's own completion by a
    // tick, so re-resolve once and let a now-populated Screen.name correct the
    // assignment rather than parking a panel on the wrong monitor.
    Qt.callLater(function() { panel.screen = root.resolveScreen() })
    declareHost()
  }
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
    // of it stays on screen. The margin change is animated, so the reveal reads
    // as a slide rather than a pop; parking animates the same way for symmetry.
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

    Behavior on margins.bottom { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    Behavior on margins.left { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    Behavior on margins.right { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

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
            if (root.selectedIndex >= 0 && root.selectedIndex < root.groups.length)
              root.restoreGroup(root.groups[root.selectedIndex], event.modifiers & Qt.ShiftModifier)
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
        model: root.groups
        currentIndex: root.selectedIndex

        delegate: TaskButton {
          required property var modelData
          required property int index
          entry: modelData
          selected: index === root.selectedIndex
          horizontal: root.vertical
          length: root.buttonLength
          thickness: root.panelSize - 10
          onActivated: function(original) { root.restoreGroup(modelData, original) }
          onHovered: root.selectedIndex = index
        }
      }
    }
  }

  // -------------------------------------------------------------- flyout

  // The per-window list a grouped button expands into. A separate popup so it
  // can grow past the strip's edge instead of being clipped by it; mouse-only,
  // so it never competes with the panel's keyboard focus.
  PopupWindow {
    id: flyoutWindow
    visible: root.flyoutGroup !== null && root.flyoutGroup.members && root.flyoutGroup.members.length > 1
    color: "transparent"

    implicitWidth: 260
    implicitHeight: flyoutColumn.implicitHeight

    // The anchor is a 1x1 point placed next to the hovered button in the
    // panel's own coordinates, then handed to the popup machinery (which keeps
    // it on screen). Side is chosen by position: above for a bottom strip,
    // outside the edge for a side strip.
    anchor {
      id: flyoutAnchor
      window: panel
      edges: Edges.Top | Edges.Left
      gravity: Edges.Top | Edges.Left
      adjustment: PopupAdjustment.Slide
      rect.width: 1
      rect.height: 1
      onAnchoring: {
        if (!root.flyoutButton) return
        var b = root.flyoutButton
        var lx = 0
        var ly = 0
        if (root.panelPosition === "bottom") {
          lx = 0
          ly = -flyoutWindow.implicitHeight - 8
        } else if (root.panelPosition === "left") {
          lx = b.width + 8
          ly = (b.height - flyoutWindow.implicitHeight) / 2
        } else {
          lx = -flyoutWindow.implicitWidth - 8
          ly = (b.height - flyoutWindow.implicitHeight) / 2
        }
        var p = panel.contentItem.mapFromItem(b, lx, ly)
        flyoutAnchor.rect.x = Math.round(p.x)
        flyoutAnchor.rect.y = Math.round(p.y)
      }
    }

    Rectangle {
      id: flyoutSurface
      anchors.fill: parent
      radius: root.radius
      color: root.background
      border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.16)
      border.width: 1

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onEntered: { flyoutHideDelay.stop(); root.flyoutHovered = true }
        onExited: { root.flyoutHovered = false; root.flyoutMaybeClose() }
      }

      Column {
        id: flyoutColumn
        width: 260
        padding: 6
        spacing: 2

        Repeater {
          model: root.flyoutGroup ? root.flyoutGroup.members : []
          delegate: FlyoutRow {
            required property var modelData
            required property int index
            entry: modelData
          }
        }
      }
    }
  }

  // ------------------------------------------------------------ components

  // A taskbar button: a rounded app tile carrying the class initial, an
  // elided single-line title, a focused-window indicator and a flash for
  // urgent or failed members. Left click restores the newest member here,
  // right click to the original workspace.
  component TaskButton: Rectangle {
    id: btn
    property var entry: null
    property bool selected: false
    property bool horizontal: false
    property real length: 184
    property real thickness: 36

    signal activated(bool original)
    signal hovered()

    readonly property var members: btn.entry ? (btn.entry.members || []) : []
    readonly property var first: btn.members.length ? btn.members[0] : null
    readonly property int memberCount: btn.members.length
    readonly property bool grouped: btn.memberCount > 1

    readonly property bool failed: {
      for (var i = 0; i < btn.members.length; i++)
        if (btn.members[i].status === "failed") return true
      return false
    }
    readonly property bool urgent: {
      for (var i = 0; i < btn.members.length; i++)
        if (btn.members[i].urgent) return true
      return false
    }
    readonly property bool attention: btn.urgent || btn.failed

    // Grouped buttons name the app; a lone window keeps its own title so the
    // button still says something useful before the flyout exists.
    readonly property string title: {
      if (btn.first === null) return "Window"
      if (btn.grouped) {
        var c = String(btn.first.class || "")
        return c ? c : String(btn.first.label || btn.first.title || "Window")
      }
      return String(btn.first.label || btn.first.title || btn.first.class || "Window")
    }
    readonly property string badge: {
      var c = btn.first ? String(btn.first.class || btn.first.title || "?") : "?"
      return c.length ? c.charAt(0).toUpperCase() : "?"
    }
    // Resolved app icon for this button's representative window — the group's
    // first member, so a grouped button shows one icon exactly like a grouped
    // Windows taskbar button (the count chip still rides the corner). "" when
    // icons are disabled or nothing resolves -> the letter tile shows instead.
    readonly property string iconSource: root.panelIcons
      ? root.resolveIcon(btn.first ? String(btn.first.class || "") : "")
      : ""

    width: btn.horizontal ? btn.length : (btn.parent ? btn.parent.width : 0)
    height: btn.horizontal ? (btn.parent ? btn.parent.height : 0) : btn.thickness
    radius: root.radius
    color: btn.selected ? root.activeFill : (btnArea.containsMouse ? root.hoverFill : "transparent")

    Behavior on color { ColorAnimation { duration: 110 } }

    // Urgent and failed members flash the button fill so attention cannot be
    // missed even when the pointer is elsewhere.
    Rectangle {
      id: flash
      anchors.fill: parent
      radius: btn.radius
      color: Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.20)
      visible: btn.attention
      opacity: 0
      SequentialAnimation on opacity {
        running: btn.attention
        loops: Animation.Infinite
        NumberAnimation { to: 1; duration: 420 }
        NumberAnimation { to: 0.15; duration: 420 }
      }
    }

    MouseArea {
      id: btnArea
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onEntered: { btn.hovered(); if (btn.grouped) root.flyoutOpen(btn.entry, btn) }
      onExited: { if (btn.grouped) root.flyoutMaybeClose() }
      onClicked: function(m) { btn.activated(m.button === Qt.RightButton) }
    }

    Row {
      anchors.fill: parent
      anchors.leftMargin: 6
      anchors.rightMargin: 8
      spacing: 8

      // App tile: the app's real icon (Windows-taskbar style), with the
      // class-initial letter as the fallback when no icon resolves. A second
      // sliver peeks out behind it and a count chip rides its corner when the
      // button is a group.
      Item {
        id: tileBox
        anchors.verticalCenter: parent.verticalCenter
        width: 26
        height: 26

        Rectangle {
          id: tile
          anchors.fill: parent
          radius: 7
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.16)
          Image {
            id: tileIcon
            anchors.centerIn: parent
            width: root.iconSize
            height: root.iconSize
            sourceSize.width: Math.round(root.iconSize * root.iconDpr)
            sourceSize.height: Math.round(root.iconSize * root.iconDpr)
            fillMode: Image.PreserveAspectFit
            smooth: true
            visible: btn.iconSource !== ""
            source: btn.iconSource
          }
          Text {
            anchors.centerIn: parent
            visible: btn.iconSource === ""
            text: btn.badge
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: 12
            font.weight: Font.DemiBold
          }
        }

        // A second tile peeking out behind the app tile is the "stacked
        // papers" cue Windows draws for a grouped button. Explicit geometry
        // (no anchors) so it can overhang the tile without fighting it.
        Rectangle {
          visible: btn.grouped
          x: -3
          y: -3
          z: -1
          width: 22
          height: 22
          radius: 7
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
        }

        Rectangle {
          visible: btn.grouped
          anchors.right: tile.right
          anchors.bottom: tile.bottom
          anchors.rightMargin: -4
          anchors.bottomMargin: -4
          width: 15
          height: 15
          radius: 7
          color: root.background
          border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.30)
          border.width: 1
          Text {
            anchors.centerIn: parent
            text: String(btn.memberCount)
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: 9
          }
        }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - tileBox.width - 6 - 8 - 8
        text: btn.title
        elide: Text.ElideRight
        color: btn.failed ? root.urgent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: 12
      }
    }

    // Focused-window indicator: a short rounded bar that lengthens and
    // brightens when this button is selected, like the running-app marker
    // under a Windows taskbar icon. Selection (hover or keyboard) is the
    // closest thing to focus a minimized-only list has.
    Rectangle {
      id: indicator
      radius: 2
      // Horizontal strip: a bar under the tile; vertical strip: a bar along
      // the leading (inner) edge. Size and anchoring follow the orientation
      // with plain bindings so nothing can fall out of sync at runtime.
      width: btn.horizontal ? (btn.selected ? 18 : 10) : 3
      height: btn.horizontal ? 3 : (btn.selected ? 18 : 10)
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, btn.selected ? 0.95 : 0.45)

      anchors.horizontalCenter: btn.horizontal ? tileBox.horizontalCenter : undefined
      anchors.bottom: btn.horizontal ? parent.bottom : undefined
      anchors.bottomMargin: btn.horizontal ? 2 : undefined
      anchors.verticalCenter: btn.horizontal ? undefined : tileBox.verticalCenter
      anchors.left: btn.horizontal ? undefined : parent.left
      anchors.leftMargin: btn.horizontal ? undefined : 2

      Behavior on color { ColorAnimation { duration: 110 } }
      Behavior on width { NumberAnimation { duration: 110 } }
      Behavior on height { NumberAnimation { duration: 110 } }
    }
  }

  // One row in the group flyout: the window's own title plus its origin, so
  // the detail the collapsed button dropped is still one click away.
  component FlyoutRow: Rectangle {
    id: frow
    required property var modelData
    required property int index
    property var entry: modelData
    readonly property bool failed: frow.entry ? frow.entry.status === "failed" : false
    readonly property string badge: {
      var c = frow.entry ? String(frow.entry.class || frow.entry.title || "?") : "?"
      return c.length ? c.charAt(0).toUpperCase() : "?"
    }
    // Same resolve-and-cache ladder as the button; "" -> the letter tile.
    readonly property string iconSource: root.panelIcons
      ? root.resolveIcon(frow.entry ? String(frow.entry.class || "") : "")
      : ""

    width: 248
    height: 40
    radius: root.radius
    color: frowArea.containsMouse ? root.hoverFill : "transparent"
    Behavior on color { ColorAnimation { duration: 90 } }

    // 16px app icon for the window, letter tile as fallback.
    Item {
      id: rowIconBox
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: parent.left
      anchors.leftMargin: 10
      width: 16
      height: 16
      Image {
        id: rowIcon
        anchors.fill: parent
        sourceSize.width: Math.round(root.flyoutIconSize * root.iconDpr)
        sourceSize.height: Math.round(root.flyoutIconSize * root.iconDpr)
        fillMode: Image.PreserveAspectFit
        smooth: true
        visible: frow.iconSource !== ""
        source: frow.iconSource
      }
      Rectangle {
        anchors.fill: parent
        radius: 4
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.16)
        visible: frow.iconSource === ""
        Text {
          anchors.centerIn: parent
          text: frow.badge
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: 9
          font.weight: Font.DemiBold
        }
      }
    }

    Column {
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: rowIconBox.right
      anchors.right: parent.right
      anchors.leftMargin: 8
      anchors.rightMargin: 10
      spacing: 1

      Text {
        width: parent.width
        text: frow.entry ? String(frow.entry.label || frow.entry.title || frow.entry.class || "Window") : ""
        elide: Text.ElideRight
        color: frow.failed ? root.urgent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: 12
      }
      Text {
        width: parent.width
        visible: text !== ""
        text: frow.failed ? "Could not restore — click to retry" : (frow.entry ? String(frow.entry.origin || "") : "")
        elide: Text.ElideRight
        color: frow.failed ? root.urgent : root.muted
        font.family: root.fontFamily
        font.pixelSize: 10
      }
    }

    MouseArea {
      id: frowArea
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: function(m) {
        root.restoreRow(frow.entry, m.button === Qt.RightButton)
        root.flyoutGroup = null
        root.flyoutButton = null
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
