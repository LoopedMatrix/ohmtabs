import QtQuick

// Independent Matrix digital-rain backdrop for Super Menu.
// Inspired by Omarchy's TTFX "matrix" screensaver look — not a copy of ttfx.
Item {
  id: rain

  property bool running: true
  property color ink: "#00ff41"
  property int fontPx: 16
  property int fps: 18
  property real trail: 0.22

  readonly property string glyphs: "アイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホ0123456789ABCDEF<>*+-=|"

  Canvas {
    id: canvas
    anchors.fill: parent
    renderTarget: Canvas.FramebufferObject
    renderStrategy: Canvas.Cooperative

    property var drops: []

    function rebuild() {
      if (!available) return
      var cell = Math.max(10, rain.fontPx)
      var cols = Math.max(1, Math.floor(width / cell))
      var next = []
      for (var i = 0; i < cols; i++)
        next.push({ y: Math.random() * -30, speed: 0.35 + Math.random() * 1.1 })
      drops = next
      var ctx = getContext("2d")
      if (ctx) {
        ctx.fillStyle = "#000000"
        ctx.fillRect(0, 0, width, height)
      }
    }

    onAvailableChanged: if (available) rebuild()
    onWidthChanged: rebuild()
    onHeightChanged: rebuild()
    Component.onCompleted: rebuild()

    onPaint: {
      var ctx = getContext("2d")
      if (!ctx || width < 1 || height < 1) return
      var cell = Math.max(10, rain.fontPx)
      ctx.fillStyle = Qt.rgba(0, 0, 0, rain.trail)
      ctx.fillRect(0, 0, width, height)
      ctx.font = cell + "px monospace"
      var list = drops
      var n = list.length
      var g = rain.glyphs
      var glen = g.length
      var ir = rain.ink.r, ig = rain.ink.g, ib = rain.ink.b
      for (var i = 0; i < n; i++) {
        var d = list[i]
        var ch = g.charAt(Math.floor(Math.random() * glen))
        var x = i * cell
        var y = d.y * cell
        ctx.fillStyle = Qt.rgba(ir, ig, ib, 1)
        ctx.fillText(ch, x, y)
        ctx.fillStyle = Qt.rgba(ir, ig, ib, 0.35)
        ctx.fillText(g.charAt(Math.floor(Math.random() * glen)), x, y - cell)
        d.y += d.speed
        if (y > height && Math.random() > 0.97) {
          d.y = -Math.random() * 18
          d.speed = 0.35 + Math.random() * 1.1
        }
      }
    }
  }

  Timer {
    interval: Math.max(40, Math.round(1000 / Math.max(8, rain.fps)))
    running: rain.running && rain.visible && rain.width > 8 && rain.height > 8
    repeat: true
    onTriggered: canvas.requestPaint()
  }
}
