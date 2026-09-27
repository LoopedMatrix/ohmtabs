import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Notification drawer. Reads Omarchy's notification service when present.
// Does not start a second NotificationServer. Not a copy of Caelestia.
Item {
  id: root
  property var notifService: null
  property color ink: Color.menu.text
  property color muted: Qt.rgba(ink.r, ink.g, ink.b, 0.55)
  property color fill: Color.menu.background
  property color line: Color.menu.border
  property color accent: Color.accent
  property string fontFamily: Style.font.menuFamily
  signal closeRequested()

  readonly property var popupModel: notifService && notifService.popupModel ? notifService.popupModel : null
  readonly property int count: popupModel ? popupModel.count : 0

  width: 360
  implicitHeight: Math.min(420, 56 + Math.max(1, count) * 56 + 52)

  function rowText(i) {
    if (!popupModel || i < 0 || i >= popupModel.count) return { summary: "", body: "" }
    var r = popupModel.get(i)
    return { summary: String(r.summary || r.appName || "Notification"), body: String(r.body || "") }
  }

  Column {
    anchors.fill: parent
    anchors.margins: 14
    spacing: 8

    Item {
      width: parent.width
      height: 28
      Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: root.count === 0 ? "No notifications" : (root.count + " notification" + (root.count === 1 ? "" : "s"))
        color: root.ink
        font.family: root.fontFamily
        font.pixelSize: 14
        font.weight: Font.Medium
      }
      Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6
        Rectangle {
          width: histText.implicitWidth + 14
          height: 24
          radius: 12
          color: "transparent"
          border.color: root.line
          border.width: 1
          Text { id: histText; anchors.centerIn: parent; text: "History"; color: root.ink; font.pixelSize: 11 }
          MouseArea {
            anchors.fill: parent
            onClicked: {
              try { Quickshell.execDetached(["omarchy-shell", "notifications", "showHistory"]) } catch (e) {}
            }
          }
        }
        Rectangle {
          width: clrText.implicitWidth + 14
          height: 24
          radius: 12
          color: "transparent"
          border.color: root.line
          border.width: 1
          Text { id: clrText; anchors.centerIn: parent; text: "Clear"; color: root.ink; font.pixelSize: 11 }
          MouseArea {
            anchors.fill: parent
            onClicked: {
              try { Quickshell.execDetached(["omarchy-shell", "notifications", "dismissAll"]) } catch (e) {}
            }
          }
        }
      }
    }

    ListView {
      width: parent.width
      height: parent.height - 40
      clip: true
      spacing: 6
      model: root.count
      delegate: Rectangle {
        required property int index
        width: ListView.view.width
        height: 50
        radius: 12
        color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.06)
        border.color: root.line
        border.width: 1
        Column {
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.margins: 10
          spacing: 2
          Text {
            width: parent.width
            text: root.rowText(index).summary
            elide: Text.ElideRight
            color: root.ink
            font.pixelSize: 13
          }
          Text {
            width: parent.width
            text: root.rowText(index).body
            elide: Text.ElideRight
            color: root.muted
            font.pixelSize: 11
          }
        }
      }
      Text {
        visible: root.count === 0
        anchors.centerIn: parent
        text: "Quiet. History still lives in Omarchy."
        color: root.muted
        font.pixelSize: 12
      }
    }
  }
}
