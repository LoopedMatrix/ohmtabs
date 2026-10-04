import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "ohmtabs.startmenu"

  implicitWidth: vertical ? barSize : 40
  implicitHeight: vertical ? 40 : barSize

  WidgetButton {
    bar: root.bar
    text: "S"
    fontSize: Style.font.body
    keepSpace: true
    anchors.fill: parent
    tooltipText: "Super Menu"
    onPressed: function(button) {
      if (button === Qt.LeftButton) {
        if (root.bar && root.bar.run) {
          root.bar.run("omarchy-shell tech.loopedmatrix.ohmtabs openSuperMenu")
        }
      }
    }
  }
}
