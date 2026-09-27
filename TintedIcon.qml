import QtQuick
import QtQuick.Effects

// App-icon artwork, optionally colorized to a single ink colour.
//
// Adapted from Davedes83/animated-dock TintedIcon.qml (MIT): MultiEffect
// colorization maps luminance onto the theme ink so shape survives. The
// untinted path is a plain Image.
Item {
  id: art

  property alias source: img.source
  property int sourceOversample: 96
  property bool tinted: false
  property color ink: "white"

  Image {
    id: img
    anchors.fill: parent
    visible: !art.tinted
    sourceSize.width: art.sourceOversample
    sourceSize.height: art.sourceOversample
    fillMode: Image.PreserveAspectFit
    smooth: true
    asynchronous: true
    mipmap: true
  }

  MultiEffect {
    anchors.fill: parent
    visible: art.tinted
    source: img
    colorization: 1.0
    colorizationColor: art.ink
    Behavior on colorizationColor { ColorAnimation { duration: 120 } }
  }
}
