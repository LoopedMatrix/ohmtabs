import QtQuick
import qs.Commons

// Dock-style settings card (layout from the macOS/animated dock settings UI).
// Colours follow the Omarchy menu palette so theme switches still apply.
Item {
  id: ui

  property var service: null
  property var settings: ({})
  property bool ohmtabsOn: true
  property int minimizedCount: 0
  property var excludedClasses: []

  signal closeRequested()
  signal restoreAll()
  signal openDrawer()
  signal setOhmTabsOn(bool on)
  signal removeExcluded(string cls)

  readonly property color fg: Color.menu.text
  readonly property color muted: Qt.rgba(fg.r, fg.g, fg.b, 0.55)
  readonly property color card: Color.menu.background
  readonly property color stroke: Color.accent
  readonly property color groupFill: Qt.rgba(fg.r, fg.g, fg.b, 0.06)
  readonly property string fontFamily: Style.font.menuFamily
  readonly property int radius: Math.max(12, Style.cornerRadius)

  function save(patch) {
    if (ui.service && typeof ui.service.saveSettings === "function")
      ui.service.saveSettings(patch)
  }

  width: 360
  implicitHeight: col.implicitHeight + 28

  Rectangle {
    anchors.fill: parent
    radius: ui.radius + 4
    color: Qt.rgba(ui.card.r, ui.card.g, ui.card.b, 0.94)
    border.color: ui.stroke
    border.width: 2
  }

  Column {
    id: col
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: 16
    spacing: 12

    Item {
      width: parent.width
      height: 28
      Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: "Dock Settings"
        color: ui.fg
        font.family: ui.fontFamily
        font.pixelSize: Style.font.body
        font.weight: Font.DemiBold
      }
      Rectangle {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 28
        height: 28
        radius: 14
        color: closeArea.containsMouse ? Qt.rgba(ui.fg.r, ui.fg.g, ui.fg.b, 0.12) : "transparent"
        Text { anchors.centerIn: parent; text: "✕"; color: ui.fg; font.pixelSize: 14 }
        MouseArea { id: closeArea; anchors.fill: parent; hoverEnabled: true; onClicked: ui.closeRequested() }
      }
    }

    DockSlider {
      label: "Icon Size"
      valueText: String(Math.round(liveValue)) + " px"
      from: 16
      to: 48
      value: Number(ui.settings.iconSize || 32)
      onReleased: function(v) { ui.save({ iconSize: Math.round(v) }) }
    }

    DockToggle {
      title: "Auto-hide"
      hint: "Slide the dock off-screen until the edge is brushed."
      checked: ui.settings.panelAutoHide === true
      onToggled: ui.save({ panelAutoHide: !ui.settings.panelAutoHide })
    }

    DockToggle {
      title: "Border"
      hint: "Outline around the dock card."
      checked: ui.settings.panelBorder !== false
      onToggled: ui.save({ panelBorder: ui.settings.panelBorder === false })
    }

    DockSlider {
      label: "Border opacity"
      valueText: String(Math.round((ui.settings.panelBorderOpacity !== undefined ? ui.settings.panelBorderOpacity : 0.95) * 100)) + "%"
      from: 0
      to: 1
      value: ui.settings.panelBorderOpacity !== undefined ? Number(ui.settings.panelBorderOpacity) : 0.95
      onReleased: function(v) { ui.save({ panelBorderOpacity: Math.round(v * 100) / 100 }) }
    }

    DockSlider {
      label: "Background opacity"
      valueText: String(Math.round((ui.settings.panelBgOpacity !== undefined ? ui.settings.panelBgOpacity : 0.78) * 100)) + "%"
      from: 0.15
      to: 1
      value: ui.settings.panelBgOpacity !== undefined ? Number(ui.settings.panelBgOpacity) : 0.78
      onReleased: function(v) { ui.save({ panelBgOpacity: Math.round(v * 100) / 100 }) }
    }

    Text {
      text: "Position"
      color: ui.fg
      font.family: ui.fontFamily
      font.pixelSize: Style.font.bodySmall || Style.font.caption
    }
    DockSegment {
      options: ["Bottom", "Top", "Left", "Right"]
      current: ui.settings.panelPosition === "top" ? 1 : (ui.settings.panelPosition === "left" ? 2 : (ui.settings.panelPosition === "right" ? 3 : 0))
      onChosen: function(i) {
        ui.save({ panelPosition: i === 1 ? "top" : (i === 2 ? "left" : (i === 3 ? "right" : "bottom")) })
      }
    }

    DockToggle {
      title: "Full length"
      hint: "Span the whole edge of the screen."
      checked: ui.settings.fullLength === true
      onToggled: ui.save({ fullLength: ui.settings.fullLength === false })
    }

    Text {
      text: "Corner Shape"
      color: ui.fg
      font.family: ui.fontFamily
      font.pixelSize: Style.font.bodySmall || Style.font.caption
    }
    DockSegment {
      options: ["Rounded", "Square", "Pill"]
      current: ui.settings.cornerShape === "square" ? 1 : (ui.settings.cornerShape === "rounded" ? 0 : 2)
      onChosen: function(i) {
        ui.save({ cornerShape: i === 1 ? "square" : (i === 2 ? "pill" : "rounded") })
      }
    }

    DockToggle {
      title: "Icon magnify"
      hint: "Grow icons under the pointer."
      checked: ui.settings.magnify !== false
      onToggled: ui.save({ magnify: ui.settings.magnify === false })
    }
    DockToggle {
      title: "Icon tint"
      hint: "Colorize app icons to the theme ink."
      checked: ui.settings.tintIcons === true
      onToggled: ui.save({ tintIcons: !ui.settings.tintIcons })
    }
    DockToggle {
      title: "Apps button"
      hint: "Grid icon that opens the Omarchy menu."
      checked: ui.settings.showAppsButton !== false
      onToggled: ui.save({ showAppsButton: ui.settings.showAppsButton === false })
    }
    DockToggle {
      title: "Running apps"
      hint: "Show open windows on the dock."
      checked: ui.settings.showRunning !== false
      onToggled: ui.save({ showRunning: ui.settings.showRunning === false })
    }
    DockToggle {
      title: "Workspaces"
      hint: "Pips for workspaces 1–N. Click or scroll to switch."
      checked: ui.settings.showWorkspaces === true
      onToggled: ui.save({ showWorkspaces: !ui.settings.showWorkspaces })
    }
    DockToggle {
      title: "Active window"
      hint: "Show the focused window title on the dock."
      checked: ui.settings.showActiveWindow !== false
      onToggled: ui.save({ showActiveWindow: ui.settings.showActiveWindow === false })
    }
    DockToggle {
      title: "Clock"
      hint: "Time on the dock."
      checked: ui.settings.showClock === true
      onToggled: ui.save({ showClock: !ui.settings.showClock })
    }
    DockToggle {
      title: "Status chips"
      hint: "Mute, Wi-Fi panel, Bluetooth panel."
      checked: ui.settings.showStatus === true
      onToggled: ui.save({ showStatus: !ui.settings.showStatus })
    }
    DockToggle {
      title: "Notifications"
      hint: "Bell on the dock. Opens OhmTabs drawer (uses Omarchy history)."
      checked: ui.settings.showNotifs === true
      onToggled: ui.save({ showNotifs: !ui.settings.showNotifs })
    }
    DockToggle {
      title: "Dashboard"
      hint: "Overview overlay of open windows."
      checked: ui.settings.showDashboard === true
      onToggled: ui.save({ showDashboard: !ui.settings.showDashboard })
    }
    DockToggle {
      title: "OSD"
      hint: "Volume/brightness pill above the dock when they change."
      checked: ui.settings.showOsd === true
      onToggled: ui.save({ showOsd: !ui.settings.showOsd })
    }
    DockToggle {
      title: "Hide when windows overlap"
      hint: "Park the dock if a window covers it. Off keeps the reserved strip."
      checked: ui.settings.dockDodge === true
      onToggled: ui.save({ dockDodge: !ui.settings.dockDodge })
    }
    DockToggle {
      title: "Icon name on hover"
      hint: "Glassy title card above a dock icon."
      checked: ui.settings.showIconName === true
      onToggled: ui.save({ showIconName: !ui.settings.showIconName })
    }

    Rectangle { width: parent.width; height: 1; color: Qt.rgba(ui.fg.r, ui.fg.g, ui.fg.b, 0.12) }

    DockToggle {
      title: "OhmTabs"
      hint: ui.ohmtabsOn ? "Off returns minimized windows, then drops the title strips." : "Off: no title strips, Minimize refused."
      checked: ui.ohmtabsOn
      onToggled: ui.setOhmTabsOn(!ui.ohmtabsOn)
    }
    DockToggle {
      title: "Omarchy bar controls"
      hint: "− □ × on the OhmTabs bar widget for the focused window."
      checked: ui.settings.barWindowControls !== false
      onToggled: ui.save({ barWindowControls: ui.settings.barWindowControls === false })
    }

    Row {
      spacing: 8
      Rectangle {
        width: restText.implicitWidth + 16
        height: 28
        radius: 8
        color: "transparent"
        border.color: ui.stroke
        border.width: 1
        visible: ui.minimizedCount > 0
        Text { id: restText; anchors.centerIn: parent; text: "Restore all (" + ui.minimizedCount + ")"; color: ui.fg; font.pixelSize: 12 }
        MouseArea { anchors.fill: parent; onClicked: ui.restoreAll() }
      }
      Rectangle {
        width: drawerText.implicitWidth + 16
        height: 28
        radius: 8
        color: "transparent"
        border.color: Qt.rgba(ui.fg.r, ui.fg.g, ui.fg.b, 0.25)
        border.width: 1
        Text { id: drawerText; anchors.centerIn: parent; text: "Minimized windows"; color: ui.fg; font.pixelSize: 12 }
        MouseArea { anchors.fill: parent; onClicked: ui.openDrawer() }
      }
    }
  }

  component DockToggle: Rectangle {
    id: tog
    property string title: ""
    property string hint: ""
    property bool checked: false
    signal toggled()
    width: col.width
    implicitHeight: hintLab.implicitHeight + 36
    radius: 12
    color: ui.groupFill
    border.color: Qt.rgba(ui.stroke.r, ui.stroke.g, ui.stroke.b, 0.35)
    border.width: 1
    Column {
      anchors.left: parent.left
      anchors.right: track.left
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: 12
      anchors.rightMargin: 10
      spacing: 2
      Text { text: tog.title; color: ui.fg; font.family: ui.fontFamily; font.pixelSize: Style.font.body }
      Text { id: hintLab; width: parent.width; text: tog.hint; wrapMode: Text.WordWrap; color: ui.muted; font.family: ui.fontFamily; font.pixelSize: Style.font.caption }
    }
    Rectangle {
      id: track
      anchors.right: parent.right
      anchors.rightMargin: 12
      anchors.verticalCenter: parent.verticalCenter
      width: 44
      height: 24
      radius: 12
      color: tog.checked ? ui.stroke : Qt.rgba(ui.fg.r, ui.fg.g, ui.fg.b, 0.18)
      Rectangle {
        width: 18
        height: 18
        radius: 9
        color: "white"
        anchors.verticalCenter: parent.verticalCenter
        x: tog.checked ? track.width - 21 : 3
        Behavior on x { NumberAnimation { duration: 120 } }
      }
    }
    MouseArea { anchors.fill: parent; onClicked: tog.toggled() }
  }

  component DockSlider: Column {
    id: sl
    property string label: ""
    property string valueText: ""
    property real from: 0
    property real to: 1
    property real value: 0
    property real liveValue: sl.value
    signal released(real v)
    width: col.width
    spacing: 6
    Row {
      width: parent.width
      Text { text: sl.label; color: ui.fg; font.family: ui.fontFamily; font.pixelSize: Style.font.body }
      Item { width: parent.width - labelW.width - valW.width; height: 1 }
      Text { id: valW; text: sl.valueText; color: ui.muted; font.family: ui.fontFamily; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
      Text { id: labelW; visible: false; text: sl.label }
    }
    Item {
      width: parent.width
      height: 22
      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 4
        radius: 2
        color: Qt.rgba(ui.fg.r, ui.fg.g, ui.fg.b, 0.15)
        Rectangle {
          height: parent.height
          radius: 2
          width: parent.width * Math.max(0, Math.min(1, (sl.liveValue - sl.from) / (sl.to - sl.from)))
          color: ui.stroke
        }
      }
      Rectangle {
        id: knob
        width: 16
        height: 16
        radius: 8
        color: ui.stroke
        anchors.verticalCenter: parent.verticalCenter
        x: Math.max(0, Math.min(parent.width - width, ((sl.liveValue - sl.from) / (sl.to - sl.from)) * (parent.width - width)))
      }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        function setFrom(mx) {
          var t = Math.max(0, Math.min(1, mx / width))
          sl.liveValue = sl.from + t * (sl.to - sl.from)
        }
        onPressed: function(m) { setFrom(m.x) }
        onPositionChanged: function(m) { if (pressed) setFrom(m.x) }
        onReleased: sl.released(sl.liveValue)
      }
    }
  }

  component DockSegment: Row {
    id: seg
    property var options: []
    property int current: 0
    signal chosen(int index)
    width: col.width
    spacing: 8
    Repeater {
      model: seg.options
      delegate: Rectangle {
        required property var modelData
        required property int index
        width: (seg.width - (seg.options.length - 1) * seg.spacing) / seg.options.length
        height: 34
        radius: 10
        color: index === seg.current ? Qt.rgba(ui.stroke.r, ui.stroke.g, ui.stroke.b, 0.22) : ui.groupFill
        border.color: index === seg.current ? ui.stroke : Qt.rgba(ui.fg.r, ui.fg.g, ui.fg.b, 0.2)
        border.width: 1
        Text {
          anchors.centerIn: parent
          text: modelData
          color: ui.fg
          font.family: ui.fontFamily
          font.pixelSize: Style.font.caption
          font.weight: index === seg.current ? Font.DemiBold : Font.Normal
        }
        MouseArea { anchors.fill: parent; onClicked: seg.chosen(index) }
      }
    }
  }
}
