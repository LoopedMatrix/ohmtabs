pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import "OhmTabsModel.js" as Model

// Optional Super Menu widgets. All network work is opt-in via settings
// (default off). No qs.Commons — probe-safe.
Column {
  id: root
  spacing: 8

  property var settings: ({})
  property var shell: null
  property color fg: "#c0caf5"
  property color muted: Qt.rgba(0.75, 0.79, 0.96, 0.55)
  property color hoverFill: Qt.rgba(0.75, 0.79, 0.96, 0.14)
  property color accent: "#7aa2f7"
  property string fontFamily: "sans-serif"
  property bool active: false

  readonly property bool showWeather: !!(settings && settings.superMenuWeather)
  readonly property bool showCalendar: !!(settings && settings.superMenuCalendar)
  readonly property bool showRss: !!(settings && settings.superMenuRss)
  readonly property bool showNews: !!(settings && settings.superMenuNews)
  readonly property bool showCrypto: !!(settings && settings.superMenuCrypto)
  readonly property bool showAlerts: !!(settings && settings.superMenuAlerts)
  readonly property bool showClocks: !!(settings && settings.superMenuWorldClock)
  readonly property bool anyOn: showWeather || showCalendar || showRss || showNews || showCrypto || showAlerts || showClocks

  width: parent ? parent.width : 256
  visible: root.anyOn

  property string weatherText: "Weather…"
  property var cryptoRows: []
  property var rssRows: []
  property var newsRows: []
  property var alertRows: []
  property string clockLocal: ""
  property string clockUtc: ""
  property var calCells: []
  property var calHeaders: ["S", "M", "T", "W", "T", "F", "S"]
  property string calTitle: ""
  property var appointments: []
  property var icsEvents: []
  property string selectedDate: ""
  property string draftTitle: ""
  property string draftStart: ""
  property var clockRows: []
  signal saveAppointments(var list)

  readonly property var shownAppointments: Model.mergeAppointments(root.appointments, root.icsEvents)
  readonly property var dayEvents: Model.appointmentsOnDate(root.shownAppointments, root.selectedDate)
  readonly property bool flipClock: !(settings && settings.superMenuFlipClock === false)

  function getUrl(url, cb) {
    var u = String(url || "")
    if (u.indexOf("https://") !== 0 && u.indexOf("http://") !== 0) return
    var xhr = new XMLHttpRequest()
    xhr.onreadystatechange = function() {
      if (xhr.readyState === 4) cb(xhr.status, xhr.responseText)
    }
    try { xhr.open("GET", u); xhr.send() } catch (e) { cb(0, "") }
  }

  function refreshClocks() {
    var zones = (root.settings && root.settings.superMenuTimeZones) ? root.settings.superMenuTimeZones : ["Local"]
    var cycle = root.settings ? root.settings.superMenuHourCycle : "24"
    var order = root.settings ? root.settings.superMenuDateOrder : "dmy"
    var now = Date.now()
    var rows = []
    for (var i = 0; i < zones.length; i++) rows.push(Model.clockRow(now, zones[i], cycle, order))
    root.clockRows = rows
  }

  function refreshCalendar() {
    var week = root.settings && root.settings.superMenuWeekStart ? root.settings.superMenuWeekStart : "sunday"
    var cal = Model.calendarMonth(Date.now(), week, root.shownAppointments)
    root.calTitle = cal.title
    root.calCells = cal.cells
    root.calHeaders = cal.headers
  }

  function refreshIcs() {
    var url = root.settings && root.settings.superMenuCalIcsUrl ? String(root.settings.superMenuCalIcsUrl) : ""
    if (!url) { root.icsEvents = []; return }
    root.getUrl(url, function(st, body) {
      root.icsEvents = st === 200 ? Model.parseIcsEvents(body, 80) : []
      if (root.showCalendar) root.refreshCalendar()
    })
  }

  function addDayEvent() {
    var next = Model.upsertAppointment(root.appointments, {
      title: root.draftTitle,
      date: root.selectedDate,
      start: root.draftStart,
      id: "a" + Date.now()
    })
    root.saveAppointments(next)
    root.draftTitle = ""
    root.draftStart = ""
  }

  function dropDayEvent(id) {
    root.saveAppointments(Model.removeAppointment(root.appointments, id))
  }

  function openGoogleDay() {
    var d = String(root.selectedDate || "")
    var url = "https://calendar.google.com"
    if (d.length === 10)
      url = "https://calendar.google.com/calendar/r/day/" + d.slice(0, 4) + "/" + d.slice(5, 7) + "/" + d.slice(8, 10)
    try { Quickshell.execDetached(["xdg-open", url]) } catch (e) {}
  }

  function refreshWeather() {
    if (!root.showWeather) return
    root.getUrl("https://ipwho.is/", function(st, body) {
      var lat = -33.87
      var lon = 151.21
      var city = ""
      if (st === 200) {
        try {
          var j = JSON.parse(body)
          if (j && j.latitude) { lat = Number(j.latitude); lon = Number(j.longitude); city = String(j.city || "") }
        } catch (e) {}
      }
      var url = "https://api.open-meteo.com/v1/forecast?latitude=" + lat + "&longitude=" + lon + "&current=temperature_2m,weather_code&timezone=auto"
      root.getUrl(url, function(st2, body2) {
        if (st2 !== 200) { root.weatherText = "Weather unavailable"; return }
        try {
          var w = JSON.parse(body2)
          var cur = w && w.current ? w.current : {}
          var t = cur.temperature_2m
          var label = Model.weatherLabel(cur.weather_code)
          var where = city ? city : ""
          root.weatherText = (where ? where + " · " : "") + (t !== undefined ? Math.round(t) + "° · " : "") + label
        } catch (e2) { root.weatherText = "Weather unavailable" }
      })
    })
  }

  function refreshCrypto() {
    if (!root.showCrypto) return
    var ids = (root.settings && root.settings.superMenuCryptoIds) ? String(root.settings.superMenuCryptoIds) : "bitcoin,ethereum,solana"
    var vs = Model.sanitizeCurrency(root.settings && root.settings.superMenuCurrency)
    var prefix = Model.currencyPrefix(vs)
    var url = "https://api.coingecko.com/api/v3/simple/price?ids=" + ids + "&vs_currencies=" + vs + "&include_24hr_change=true"
    root.getUrl(url, function(st, body) {
      if (st !== 200) { root.cryptoRows = []; return }
      try {
        var j = JSON.parse(body)
        var out = []
        var keys = ids.split(",")
        for (var i = 0; i < keys.length; i++) {
          var id = keys[i]
          var row = j[id]
          if (!row) continue
          var price = Number(row[vs])
          var ch = Number(row[vs + "_24h_change"] || 0)
          out.push({
            name: id,
            price: prefix + price.toLocaleString(undefined, { maximumFractionDigits: price >= 100 ? 0 : 2 }),
            change: (ch >= 0 ? "+" : "") + ch.toFixed(1) + "%",
            up: ch >= 0
          })
        }
        root.cryptoRows = out
      } catch (e) { root.cryptoRows = [] }
    })
  }

  function refreshFeed(kind) {
    var feeds = []
    if (kind === "rss") {
      if (!root.showRss) return
      feeds = (root.settings && root.settings.superMenuRssFeeds) ? root.settings.superMenuRssFeeds : []
      if ((!feeds || !feeds.length) && root.settings && root.settings.superMenuRssUrl) feeds = [root.settings.superMenuRssUrl]
    } else {
      if (!root.showNews) return
      feeds = (root.settings && root.settings.superMenuNewsFeeds) ? root.settings.superMenuNewsFeeds : []
      if ((!feeds || !feeds.length) && root.settings && root.settings.superMenuNewsUrl) feeds = [root.settings.superMenuNewsUrl]
    }
    if (!feeds || !feeds.length) {
      if (kind === "rss") root.rssRows = []
      else root.newsRows = []
      return
    }
    var pending = feeds.length
    var acc = []
    var i
    for (i = 0; i < feeds.length; i++) {
      root.getUrl(String(feeds[i]), function(st, body) {
        if (st === 200) acc = acc.concat(Model.parseRssItems(body, 4))
        pending -= 1
        if (pending <= 0) {
          if (acc.length > 6) acc = acc.slice(0, 6)
          if (kind === "rss") root.rssRows = acc
          else root.newsRows = acc
        }
      })
    }
  }

  function refreshAlerts() {
    if (!root.showAlerts) return
    var svc = (root.shell && typeof root.shell.serviceFor === "function") ? root.shell.serviceFor("omarchy.notifications") : null
    var m = svc && svc.popupModel ? svc.popupModel : null
    var out = []
    if (m) {
      try {
        var n = Math.min(4, m.count)
        for (var i = 0; i < n; i++) {
          var it = m.get(i)
          var title = String((it && (it.summary || it.appName || it.app)) || "Notification")
          if (title.length > 42) title = title.slice(0, 39) + "..."
          out.push({ title: title })
        }
      } catch (e) {}
    }
    root.alertRows = out
  }

  function refreshAll() {
    if (!root.active || !root.anyOn) return
    root.refreshClocks()
    root.refreshCalendar()
    root.refreshIcs()
    root.refreshWeather()
    root.refreshCrypto()
    root.refreshFeed("rss")
    root.refreshFeed("news")
    root.refreshAlerts()
  }

  onActiveChanged: if (root.active) root.refreshAll()
  onSettingsChanged: if (root.active) root.refreshAll()
  Component.onCompleted: if (root.active) root.refreshAll()

  Timer {
    interval: 30000
    running: root.active && root.anyOn
    repeat: true
    onTriggered: {
      root.refreshClocks()
      root.refreshAlerts()
    }
  }
  Timer {
    interval: 60000
    running: root.active && root.showCrypto
    repeat: true
    onTriggered: root.refreshCrypto()
  }
  Timer {
    interval: 900000
    running: root.active && (root.showWeather || root.showRss || root.showNews)
    repeat: true
    onTriggered: {
      root.refreshWeather()
      root.refreshFeed("rss")
      root.refreshFeed("news")
    }
  }

  Text {
    visible: root.showClocks
    text: "Clocks"
    color: root.fg
    font.family: root.fontFamily
    font.pixelSize: 11
    font.weight: Font.DemiBold
  }
  Repeater {
    model: root.showClocks ? root.clockRows : []
    delegate: Column {
      required property var modelData
      width: root.width
      spacing: 2
      Text {
        text: modelData.label + "  " + modelData.date
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: 10
      }
      FlipClock {
        visible: root.flipClock
        digits: modelData.digits
        ap: modelData.ap
        tile: 24
      }
      Text {
        visible: !root.flipClock
        text: modelData.hh + ":" + modelData.mm + (modelData.ap ? (" " + modelData.ap) : "")
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: 16
        font.weight: Font.DemiBold
      }
    }
  }

  Text {
    visible: root.showWeather
    text: "Weather"
    color: root.fg
    font.family: root.fontFamily
    font.pixelSize: 11
    font.weight: Font.DemiBold
  }
  Text {
    visible: root.showWeather
    width: root.width
    text: root.weatherText
    elide: Text.ElideRight
    color: root.fg
    font.family: root.fontFamily
    font.pixelSize: 13
  }

  Text {
    visible: root.showCalendar
    text: root.calTitle || "Calendar"
    color: root.fg
    font.family: root.fontFamily
    font.pixelSize: 11
    font.weight: Font.DemiBold
  }
  Grid {
    visible: root.showCalendar
    columns: 7
    rowSpacing: 2
    columnSpacing: 2
    width: root.width
    Repeater {
      model: root.calHeaders
      Text {
        required property string modelData
        width: Math.floor(root.width / 7)
        height: 14
        text: modelData
        color: root.muted
        font.pixelSize: 9
        horizontalAlignment: Text.AlignHCenter
      }
    }
    Repeater {
      model: root.calCells
      Rectangle {
        required property var modelData
        width: Math.floor(root.width / 7)
        height: 20
        radius: 4
        color: {
          if (modelData.date && modelData.date === root.selectedDate) return Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.55)
          if (modelData.on) return Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.28)
          return "transparent"
        }
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          y: 1
          text: parent.modelData.d
          color: root.fg
          font.pixelSize: 9
        }
        Rectangle {
          visible: parent.modelData.has === true
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: 2
          width: 4
          height: 4
          radius: 2
          color: root.accent
        }
        MouseArea {
          anchors.fill: parent
          enabled: parent.modelData.date !== ""
          onClicked: root.selectedDate = (root.selectedDate === parent.modelData.date) ? "" : parent.modelData.date
        }
      }
    }
  }
  Item {
    visible: root.showCalendar && root.selectedDate !== ""
    width: root.width
    height: 22
    Text {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: root.selectedDate
      color: root.muted
      font.family: root.fontFamily
      font.pixelSize: 10
    }
    Rectangle {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: 22
      height: 22
      radius: 11
      color: calClose.containsMouse ? root.hoverFill : "transparent"
      Text { anchors.centerIn: parent; text: "✕"; color: root.fg; font.pixelSize: 11 }
      MouseArea {
        id: calClose
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.selectedDate = ""
      }
    }
  }
  Repeater {
    model: (root.showCalendar && root.selectedDate !== "") ? root.dayEvents : []
    delegate: Row {
      required property var modelData
      width: root.width
      spacing: 6
      Text {
        width: root.width - 28
        text: (modelData.start ? (modelData.start + "  ") : "") + modelData.title
        elide: Text.ElideRight
        color: root.fg
        font.pixelSize: 11
      }
      Rectangle {
        visible: modelData.source !== "ics"
        width: 18
        height: 18
        radius: 9
        color: dropAp.containsMouse ? root.hoverFill : "transparent"
        Text { anchors.centerIn: parent; text: "−"; color: root.fg; font.pixelSize: 12 }
        MouseArea { id: dropAp; anchors.fill: parent; hoverEnabled: true; onClicked: root.dropDayEvent(modelData.id) }
      }
    }
  }
  Text {
    visible: root.showCalendar && root.dayEvents.length === 0 && root.selectedDate !== ""
    text: "No appointments"
    color: root.muted
    font.pixelSize: 10
  }
  Row {
    visible: root.showCalendar && root.selectedDate !== ""
    spacing: 6
    width: root.width
    Rectangle {
      width: parent.width - 50
      height: 26
      radius: 6
      color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06)
      TextInput {
        id: titleInput
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        verticalAlignment: Text.AlignVCenter
        color: root.fg
        font.pixelSize: 11
        text: root.draftTitle
        onTextChanged: root.draftTitle = text
        Keys.onReturnPressed: root.addDayEvent()
      }
      Text {
        visible: titleInput.text.length === 0
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: 8
        text: "Add appointment"
        color: root.muted
        font.pixelSize: 11
      }
    }
    Rectangle {
      width: 44
      height: 26
      radius: 6
      color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.35)
      Text { anchors.centerIn: parent; text: "Add"; color: root.fg; font.pixelSize: 11 }
      MouseArea { anchors.fill: parent; onClicked: root.addDayEvent() }
    }
  }
  Row {
    visible: root.showCalendar && root.selectedDate !== ""
    spacing: 6
    Rectangle {
      width: 72
      height: 24
      radius: 6
      color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06)
      TextInput {
        id: timeInput
        anchors.fill: parent
        anchors.margins: 4
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: Text.AlignHCenter
        color: root.fg
        font.pixelSize: 11
        text: root.draftStart
        onTextChanged: root.draftStart = text
        Keys.onReturnPressed: root.addDayEvent()
      }
      Text {
        visible: timeInput.text.length === 0
        anchors.centerIn: parent
        text: "HH:MM"
        color: root.muted
        font.pixelSize: 10
      }
    }
    Rectangle {
      height: 24
      width: gcalLab.implicitWidth + 12
      radius: 6
      color: "transparent"
      border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.25)
      border.width: 1
      Text { id: gcalLab; anchors.centerIn: parent; text: "Google Calendar"; color: root.fg; font.pixelSize: 10 }
      MouseArea { anchors.fill: parent; onClicked: root.openGoogleDay() }
    }
  }

  Text {
    visible: root.showCrypto
    text: "Crypto"
    color: root.fg
    font.family: root.fontFamily
    font.pixelSize: 11
    font.weight: Font.DemiBold
  }
  Repeater {
    model: root.showCrypto ? root.cryptoRows : []
    delegate: Row {
      required property var modelData
      width: root.width
      spacing: 6
      Text { text: modelData.name; color: root.fg; font.pixelSize: 11; width: 78; elide: Text.ElideRight }
      Text { text: modelData.price; color: root.fg; font.pixelSize: 11 }
      Text { text: modelData.change; color: modelData.up ? "#9ece6a" : "#f7768e"; font.pixelSize: 11 }
    }
  }

  Text {
    visible: root.showRss
    text: "RSS"
    color: root.fg
    font.family: root.fontFamily
    font.pixelSize: 11
    font.weight: Font.DemiBold
  }
  Repeater {
    model: root.showRss ? root.rssRows : []
    delegate: Text {
      required property var modelData
      width: root.width
      text: modelData.title
      elide: Text.ElideRight
      color: root.fg
      font.pixelSize: 11
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          if (modelData.link) {
            try { Quickshell.execDetached(["xdg-open", modelData.link]) } catch (e) {}
          }
        }
      }
    }
  }

  Text {
    visible: root.showNews
    text: "News"
    color: root.fg
    font.family: root.fontFamily
    font.pixelSize: 11
    font.weight: Font.DemiBold
  }
  Repeater {
    model: root.showNews ? root.newsRows : []
    delegate: Text {
      required property var modelData
      width: root.width
      text: modelData.title
      elide: Text.ElideRight
      color: root.fg
      font.pixelSize: 11
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          if (modelData.link) {
            try { Quickshell.execDetached(["xdg-open", modelData.link]) } catch (e) {}
          }
        }
      }
    }
  }

  Text {
    visible: root.showAlerts
    text: "Alerts"
    color: root.fg
    font.family: root.fontFamily
    font.pixelSize: 11
    font.weight: Font.DemiBold
  }
  Text {
    visible: root.showAlerts && root.alertRows.length === 0
    text: "No notifications"
    color: root.muted
    font.pixelSize: 11
  }
  Repeater {
    model: root.showAlerts ? root.alertRows : []
    delegate: Text {
      required property var modelData
      width: root.width
      text: modelData.title
      elide: Text.ElideRight
      color: root.fg
      font.pixelSize: 11
    }
  }
}
