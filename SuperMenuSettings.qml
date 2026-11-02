import QtQuick
import QtQuick.Layouts
import qs.Commons
import "OhmTabsModel.js" as Model

// Super Menu settings — separate overlay from Dock Settings.
Item {
  id: ui

  property var service: null
  property var settings: ({})

  signal closeRequested()
  signal backRequested()

  readonly property color fg: Color.menu ? Color.menu.text : "#c0caf5"
  readonly property color muted: Qt.rgba(fg.r, fg.g, fg.b, 0.55)
  readonly property color card: Color.menu ? Color.menu.background : "#1a1b26"
  readonly property color stroke: Color.accent !== undefined ? Color.accent : "#7aa2f7"
  readonly property color groupFill: Qt.rgba(fg.r, fg.g, fg.b, 0.06)
  readonly property string fontFamily: Style.font.menuFamily
  readonly property int radius: Math.max(12, Style.cornerRadius)

  function save(patch) {
    if (ui.service && typeof ui.service.saveSettings === "function")
      ui.service.saveSettings(patch)
  }

  function layoutOf() {
    return Model.normalizeMenuLayout(ui.settings && ui.settings.superMenuLayout)
  }

  function moveToColumn(id, column) {
    var layout = ui.layoutOf()
    if (Model.menuSectionColumn(layout, id) === column) return
    var dest = layout[column] || []
    ui.save({ superMenuLayout: Model.moveMenuSection(layout, id, column, dest.length) })
  }

  function nudgeSection(id, dir) {
    var layout = ui.layoutOf()
    var col = Model.menuSectionColumn(layout, id)
    var list = layout[col] || []
    var index = list.indexOf(id)
    if (index < 0) return
    if (dir === "up" && index > 0)
      ui.save({ superMenuLayout: Model.moveMenuSection(layout, id, col, index - 1) })
    else if (dir === "down" && index < list.length - 1)
      ui.save({ superMenuLayout: Model.moveMenuSection(layout, id, col, index + 1) })
  }

  function feeds(kind) {
    var key = kind === "news" ? "superMenuNewsFeeds" : "superMenuRssFeeds"
    var list = ui.settings && ui.settings[key]
    return Object.prototype.toString.call(list) === "[object Array]" ? list : []
  }

  function addFeed(kind, raw) {
    var next = Model.sanitizeUrlList(ui.feeds(kind).concat([raw]), [], 8)
    if (kind === "news") ui.save({ superMenuNewsFeeds: next, superMenuNewsUrl: next[0] || "" })
    else ui.save({ superMenuRssFeeds: next, superMenuRssUrl: next[0] || "" })
  }

  function dropFeed(kind, url) {
    var next = Model.sanitizeUrlList(Model.listWithout(ui.feeds(kind), url), [], 8)
    if (kind === "news") ui.save({ superMenuNewsFeeds: next, superMenuNewsUrl: next[0] || "" })
    else ui.save({ superMenuRssFeeds: next, superMenuRssUrl: next[0] || "" })
  }

  function addCoin(raw) {
    var cur = ui.settings && ui.settings.superMenuCryptoIds ? String(ui.settings.superMenuCryptoIds) : ""
    ui.save({ superMenuCryptoIds: Model.csvAddId(cur, raw, 8) })
  }

  width: 400
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
    spacing: 10

    Item {
      width: parent.width
      height: 28
      Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: "Super Menu"
        color: ui.fg
        font.family: ui.fontFamily
        font.pixelSize: Style.font.body
        font.weight: Font.DemiBold
      }
      Rectangle {
        id: menuBack
        anchors.right: closeBtn.left
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        width: backLab.implicitWidth + 16
        height: 28
        radius: 14
        color: backArea.containsMouse ? Qt.rgba(ui.fg.r, ui.fg.g, ui.fg.b, 0.12) : "transparent"
        Text { id: backLab; anchors.centerIn: parent; text: "Menu"; color: ui.fg; font.pixelSize: 11; font.weight: Font.DemiBold }
        MouseArea { id: backArea; anchors.fill: parent; hoverEnabled: true; onClicked: ui.backRequested() }
      }
      Rectangle {
        id: closeBtn
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

    Text {
      width: parent.width
      text: "This panel is Super Menu only. Dock settings stay in the other menu. Arrange in the menu, or move a section here."
      wrapMode: Text.WordWrap
      color: ui.muted
      font.family: ui.fontFamily
      font.pixelSize: Style.font.caption
    }

    Text { text: "Layout"; color: ui.fg; font.family: ui.fontFamily; font.pixelSize: 12; font.weight: Font.DemiBold }
    Repeater {
      model: ["apps", "pinned", "agents", "clocks", "weather", "calendar", "files", "crypto", "rss", "news", "alerts"]
      delegate: Rectangle {
        id: layRow
        required property string modelData
        readonly property string sectionCol: Model.menuSectionColumn(ui.layoutOf(), modelData)
        width: col.width
        implicitHeight: layCol.implicitHeight + 12
        height: implicitHeight
        radius: 10
        color: ui.groupFill
        Column {
          id: layCol
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: 8
          spacing: 4
          Text {
            text: Model.menuSectionTitle(layRow.modelData)
            color: ui.fg
            font.family: ui.fontFamily
            font.pixelSize: 12
            font.weight: Font.DemiBold
          }
          Row {
            spacing: 4
            SmChip { label: "Left"; on: layRow.sectionCol === "left"; onPicked: ui.moveToColumn(layRow.modelData, "left") }
            SmChip { label: "Center"; on: layRow.sectionCol === "center"; onPicked: ui.moveToColumn(layRow.modelData, "center") }
            SmChip { label: "Right"; on: layRow.sectionCol === "right"; onPicked: ui.moveToColumn(layRow.modelData, "right") }
            SmChip { label: "Up"; on: false; onPicked: ui.nudgeSection(layRow.modelData, "up") }
            SmChip { label: "Down"; on: false; onPicked: ui.nudgeSection(layRow.modelData, "down") }
          }
        }
      }
    }
    SmChip { label: "Reset layout"; on: false; onPicked: ui.save({ superMenuLayout: Model.defaultMenuLayout() }) }

    SmToggle { title: "Recommended files"; hint: "Recent files. Move the section in Layout."; checked: ui.settings.superMenuRecommended !== false; onToggled: ui.save({ superMenuRecommended: ui.settings.superMenuRecommended === false }) }
    SmToggle { title: "Calendar"; hint: "Month grid for today."; checked: ui.settings.superMenuCalendar === true; onToggled: ui.save({ superMenuCalendar: !ui.settings.superMenuCalendar }) }
    SmToggle { title: "Weather"; hint: "Local temperature via Open-Meteo."; checked: ui.settings.superMenuWeather === true; onToggled: ui.save({ superMenuWeather: !ui.settings.superMenuWeather }) }
    SmToggle { title: "World clock"; hint: "Local time and UTC."; checked: ui.settings.superMenuWorldClock === true; onToggled: ui.save({ superMenuWorldClock: !ui.settings.superMenuWorldClock }) }
    SmToggle { title: "Crypto prices"; hint: "CoinGecko. Add CoinGecko ids below."; checked: ui.settings.superMenuCrypto === true; onToggled: ui.save({ superMenuCrypto: !ui.settings.superMenuCrypto }) }
    SmToggle { title: "RSS"; hint: "Headlines from the RSS list below."; checked: ui.settings.superMenuRss === true; onToggled: ui.save({ superMenuRss: !ui.settings.superMenuRss }) }
    SmToggle { title: "News"; hint: "Headlines from the news list below."; checked: ui.settings.superMenuNews === true; onToggled: ui.save({ superMenuNews: !ui.settings.superMenuNews }) }
    SmToggle { title: "Alerts"; hint: "Recent Omarchy notifications. No second server."; checked: ui.settings.superMenuAlerts === true; onToggled: ui.save({ superMenuAlerts: !ui.settings.superMenuAlerts }) }

    Text { text: "Calendar week starts"; color: ui.fg; font.family: ui.fontFamily; font.pixelSize: 12 }
    Row {
      spacing: 6
      SmChip { label: "Sunday"; on: (ui.settings.superMenuWeekStart || "sunday") !== "monday"; onPicked: ui.save({ superMenuWeekStart: "sunday" }) }
      SmChip { label: "Monday"; on: ui.settings.superMenuWeekStart === "monday"; onPicked: ui.save({ superMenuWeekStart: "monday" }) }
    }

    Text { text: "Clock"; color: ui.fg; font.family: ui.fontFamily; font.pixelSize: 12 }
    Row {
      spacing: 6
      SmChip { label: "24 hour"; on: (ui.settings.superMenuHourCycle || "24") !== "12"; onPicked: ui.save({ superMenuHourCycle: "24" }) }
      SmChip { label: "12 hour"; on: ui.settings.superMenuHourCycle === "12"; onPicked: ui.save({ superMenuHourCycle: "12" }) }
    }
    Row {
      spacing: 6
      SmChip { label: "DDMMYY"; on: (ui.settings.superMenuDateOrder || "dmy") !== "mdy"; onPicked: ui.save({ superMenuDateOrder: "dmy" }) }
      SmChip { label: "MMDDYY"; on: ui.settings.superMenuDateOrder === "mdy"; onPicked: ui.save({ superMenuDateOrder: "mdy" }) }
    }
    SmToggle { title: "Flip clock"; hint: "Split-flap digits instead of plain text."; checked: ui.settings.superMenuFlipClock !== false; onToggled: ui.save({ superMenuFlipClock: ui.settings.superMenuFlipClock === false }) }

    Text { text: "Time zones"; color: ui.fg; font.family: ui.fontFamily; font.pixelSize: 12 }
    Repeater {
      model: ui.settings.superMenuTimeZones || ["Local"]
      delegate: Row {
        required property string modelData
        width: col.width
        spacing: 8
        Text { text: modelData; color: ui.fg; font.pixelSize: 12; width: col.width - 40; elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter }
        Rectangle {
          width: 22; height: 22; radius: 11
          color: dropTz.containsMouse ? Qt.rgba(ui.fg.r, ui.fg.g, ui.fg.b, 0.14) : "transparent"
          Text { anchors.centerIn: parent; text: "−"; color: ui.fg; font.pixelSize: 14 }
          MouseArea { id: dropTz; anchors.fill: parent; hoverEnabled: true; onClicked: ui.save({ superMenuTimeZones: Model.sanitizeTimeZones(Model.listWithout(ui.settings.superMenuTimeZones || [], modelData)) }) }
        }
      }
    }
    SmAddRow {
      placeholder: "America/New_York"
      onSubmitted: function(t) {
        var cur = ui.settings.superMenuTimeZones || []
        ui.save({ superMenuTimeZones: Model.sanitizeTimeZones(cur.concat([t])) })
      }
    }

    Text { text: "Google Calendar ICS (read-only)"; color: ui.fg; font.family: ui.fontFamily; font.pixelSize: 12 }
    Text {
      width: parent.width
      text: "Paste a secret iCal URL from Google Calendar → Settings → Integrate calendar. Local add/edit still works. Two-way Google sync needs Hermes Google auth."
      wrapMode: Text.WordWrap
      color: ui.muted
      font.pixelSize: 11
    }
    SmAddRow {
      placeholder: "https://calendar.google.com/calendar/ical/…"
      onSubmitted: function(t) { ui.save({ superMenuCalIcsUrl: Model.sanitizeHttpUrl(t, "") }) }
    }
    Text {
      visible: !!(ui.settings.superMenuCalIcsUrl)
      width: parent.width
      text: String(ui.settings.superMenuCalIcsUrl || "")
      elide: Text.ElideMiddle
      color: ui.muted
      font.pixelSize: 10
    }

    Text { text: "Crypto currency"; color: ui.fg; font.family: ui.fontFamily; font.pixelSize: 12 }
    Row {
      spacing: 6
      SmChip { label: "USD"; on: (ui.settings.superMenuCurrency || "usd") === "usd"; onPicked: ui.save({ superMenuCurrency: "usd" }) }
      SmChip { label: "AUD"; on: ui.settings.superMenuCurrency === "aud"; onPicked: ui.save({ superMenuCurrency: "aud" }) }
      SmChip { label: "EUR"; on: ui.settings.superMenuCurrency === "eur"; onPicked: ui.save({ superMenuCurrency: "eur" }) }
      SmChip { label: "GBP"; on: ui.settings.superMenuCurrency === "gbp"; onPicked: ui.save({ superMenuCurrency: "gbp" }) }
    }

    Text { text: "Coins (CoinGecko id)"; color: ui.fg; font.family: ui.fontFamily; font.pixelSize: 12 }
    Repeater {
      model: String(ui.settings.superMenuCryptoIds || "").split(",").filter(function(x) { return x.length })
      delegate: Row {
        required property string modelData
        width: col.width
        spacing: 8
        Text { text: modelData; color: ui.fg; font.pixelSize: 12; width: col.width - 40; elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter }
        Rectangle {
          width: 22; height: 22; radius: 11
          color: dropCoin.containsMouse ? Qt.rgba(ui.fg.r, ui.fg.g, ui.fg.b, 0.14) : "transparent"
          Text { anchors.centerIn: parent; text: "−"; color: ui.fg; font.pixelSize: 14 }
          MouseArea { id: dropCoin; anchors.fill: parent; hoverEnabled: true; onClicked: ui.save({ superMenuCryptoIds: Model.csvToggleId(String(ui.settings.superMenuCryptoIds || ""), modelData, 8) }) }
        }
      }
    }
    SmAddRow {
      placeholder: "bitcoin"
      onSubmitted: function(t) { ui.addCoin(t) }
    }

    Text { text: "RSS feeds"; color: ui.fg; font.family: ui.fontFamily; font.pixelSize: 12 }
    Repeater {
      model: ui.feeds("rss")
      delegate: Row {
        required property string modelData
        width: col.width
        spacing: 8
        Text { text: modelData; color: ui.fg; font.pixelSize: 11; width: col.width - 40; elide: Text.ElideMiddle; anchors.verticalCenter: parent.verticalCenter }
        Rectangle {
          width: 22; height: 22; radius: 11
          color: dropRss.containsMouse ? Qt.rgba(ui.fg.r, ui.fg.g, ui.fg.b, 0.14) : "transparent"
          Text { anchors.centerIn: parent; text: "−"; color: ui.fg; font.pixelSize: 14 }
          MouseArea { id: dropRss; anchors.fill: parent; hoverEnabled: true; onClicked: ui.dropFeed("rss", modelData) }
        }
      }
    }
    SmAddRow {
      placeholder: "https://hnrss.org/frontpage"
      onSubmitted: function(t) { ui.addFeed("rss", t) }
    }

    Text { text: "News feeds"; color: ui.fg; font.family: ui.fontFamily; font.pixelSize: 12 }
    Repeater {
      model: ui.feeds("news")
      delegate: Row {
        required property string modelData
        width: col.width
        spacing: 8
        Text { text: modelData; color: ui.fg; font.pixelSize: 11; width: col.width - 40; elide: Text.ElideMiddle; anchors.verticalCenter: parent.verticalCenter }
        Rectangle {
          width: 22; height: 22; radius: 11
          color: dropNews.containsMouse ? Qt.rgba(ui.fg.r, ui.fg.g, ui.fg.b, 0.14) : "transparent"
          Text { anchors.centerIn: parent; text: "−"; color: ui.fg; font.pixelSize: 14 }
          MouseArea { id: dropNews; anchors.fill: parent; hoverEnabled: true; onClicked: ui.dropFeed("news", modelData) }
        }
      }
    }
    SmAddRow {
      placeholder: "https://feeds.bbci.co.uk/news/rss.xml"
      onSubmitted: function(t) { ui.addFeed("news", t) }
    }
  }

  component SmToggle: Rectangle {
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
      anchors.right: knob.left
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: 12
      anchors.rightMargin: 8
      spacing: 2
      Text { text: tog.title; color: ui.fg; font.family: ui.fontFamily; font.pixelSize: 13 }
      Text { id: hintLab; width: parent.width; text: tog.hint; wrapMode: Text.WordWrap; color: ui.muted; font.family: ui.fontFamily; font.pixelSize: 11 }
    }
    Rectangle {
      id: knob
      anchors.right: parent.right
      anchors.rightMargin: 12
      anchors.verticalCenter: parent.verticalCenter
      width: 36
      height: 20
      radius: 10
      color: tog.checked ? ui.stroke : Qt.rgba(ui.fg.r, ui.fg.g, ui.fg.b, 0.18)
      Rectangle {
        width: 16; height: 16; radius: 8
        x: tog.checked ? 18 : 2
        y: 2
        color: "#ffffff"
      }
    }
    MouseArea { anchors.fill: parent; onClicked: tog.toggled() }
  }

  component SmChip: Rectangle {
    id: chip
    property string label: ""
    property bool on: false
    signal picked()
    width: lab.implicitWidth + 16
    height: 26
    radius: 8
    color: chip.on ? Qt.rgba(ui.stroke.r, ui.stroke.g, ui.stroke.b, 0.28) : "transparent"
    border.color: chip.on ? ui.stroke : Qt.rgba(ui.fg.r, ui.fg.g, ui.fg.b, 0.25)
    border.width: 1
    Text { id: lab; anchors.centerIn: parent; text: chip.label; color: ui.fg; font.pixelSize: 11 }
    MouseArea { anchors.fill: parent; onClicked: chip.picked() }
  }

  component SmAddRow: Item {
    id: add
    property string placeholder: ""
    signal submitted(string text)
    width: col.width
    height: 32
    Rectangle {
      anchors.fill: parent
      radius: 8
      color: Qt.rgba(ui.fg.r, ui.fg.g, ui.fg.b, 0.06)
      border.color: Qt.rgba(ui.fg.r, ui.fg.g, ui.fg.b, 0.18)
      border.width: 1
    }
    TextInput {
      id: input
      anchors.left: parent.left
      anchors.right: addBtn.left
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: 10
      anchors.rightMargin: 8
      color: ui.fg
      font.pixelSize: 12
      clip: true
      Keys.onReturnPressed: {
        add.submitted(input.text)
        input.text = ""
      }
    }
    Text {
      visible: input.text.length === 0
      anchors.left: input.left
      anchors.verticalCenter: input.verticalCenter
      text: add.placeholder
      color: ui.muted
      font.pixelSize: 12
    }
    Rectangle {
      id: addBtn
      anchors.right: parent.right
      anchors.rightMargin: 4
      anchors.verticalCenter: parent.verticalCenter
      width: 44
      height: 24
      radius: 6
      color: Qt.rgba(ui.stroke.r, ui.stroke.g, ui.stroke.b, 0.35)
      Text { anchors.centerIn: parent; text: "Add"; color: ui.fg; font.pixelSize: 11 }
      MouseArea {
        anchors.fill: parent
        onClicked: {
          add.submitted(input.text)
          input.text = ""
        }
      }
    }
  }
}
