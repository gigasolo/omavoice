import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "gigasolo.omavoice"
  ipcTarget: "gigasolo.omavoice"
  manageIpc: false

  property string focusSection: "header"
  property int sourceIndex: 0
  property int presetIndex: 0
  property int engineIndex: 0
  property int eqIndex: 0
  property bool cursorActive: false
  property int phraseIndex: 0
  property bool tuneOpen: false
  property bool pendingTuneOpen: false
  property bool levelOpen: false

  readonly property var sharedService: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor(moduleName) : null
  readonly property var service: sharedService || localService

  function pushSettings() { if (service) service.settings = settings }
  function armMeterHold() {
    if (!opened || !service || typeof service.setMeterHold !== "function") return
    service.setMeterHold(true)
  }
  onSettingsChanged: pushSettings()
  onServiceChanged: {
    pushSettings()
    if (opened) displaySources = captureSources.slice()
    armMeterHold()
  }
  readonly property string afterHoldKey: (service.afterNodeName || "") + ":" + (service.afterNodeId || "")
  onAfterHoldKeyChanged: armMeterHold()
  Component.onCompleted: pushSettings()

  readonly property var presets: [
    { value: "meeting", label: "Meeting", hint: "Zoom, Meet, Teams" },
    { value: "podcast", label: "Podcast", hint: "OBS, record, interviews" },
    { value: "clean", label: "Clean", hint: "High-pass only" }
  ]
  readonly property var captureSources: {
    var list = []
    var all = service.sources || []
    for (var i = 0; i < all.length; i++) {
      if (Model.isCaptureSourceName(all[i].name)) list.push(all[i])
    }
    return list
  }
  // Snapshot the list while the panel is open. A live Repeater model that
  // is replaced on every PipeWire poll destroys the row mid-click.
  property var displaySources: []
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color iconColor: service.enabled && service.running ? foreground : dim
  readonly property color barIconColor: service.enabled && service.running ? barForeground : Qt.darker(barForeground, 1.55)
  readonly property bool headerHasCursor: cursorActive && focusSection === "header"
  readonly property string toggleHint: service.enabled ? "Turn Omavoice off" : "Turn Omavoice on"
  readonly property string barTooltip: {
    if (!service.enabled) return "Omavoice · off"
    if (service.lastError !== "") return "Omavoice · " + service.lastError
    if (!service.running) return "Omavoice · " + service.statusText
    return "Omavoice · " + Model.presetLabel(service.preset)
  }
  readonly property var activePhrases: [
    "Clearing the room",
    "Hushing the fans",
    "Catching the voice",
    "Cutting the echo"
  ]
  readonly property string heroPhraseText: {
    if (service.lastError !== "") return "Couldn't start"
    if (service.running) return activePhrases[phraseIndex % activePhrases.length]
    return service.statusText
  }
  readonly property var setup: service.setup || { needed: false }

  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    var keys = []
    try { if (values) keys = Object.keys(values) } catch (e) {}
    if (values && keys.length === 0) {
      for (var key in values) keys.push(key)
    }
    for (var i = 0; i < keys.length; i++) {
      var k = keys[i]
      if (values[k] === undefined) delete entry[k]
      else entry[k] = values[k]
    }
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function toggleEnabled() {
    persistSettings({ enabled: !service.enabled })
  }

  function choosePreset(value) {
    persistSettings({ preset: Model.normalizePreset(value) })
  }

  function chooseSource(name) {
    persistSettings({ pinnedSource: String(name || "") })
    if (service && typeof service.pinSource === "function") service.pinSource(name)
  }

  function setChipHover(section, on) {
    if (on) {
      cursorActive = true
      focusSection = section
      return
    }
    if (focusSection === section) cursorActive = false
  }

  function showTune(open) {
    var next = open === true
    if (tuneOpen === next || pageFlip.running) return
    pendingTuneOpen = next
    pageFlip.restart()
  }

  function toggleDefaultSource() {
    persistSettings({ setDefaultSource: !service.setDefaultSource })
  }

  function setMeetingQuality(value) {
    persistSettings({ meetingQuality: Model.normalizeQuality(value) })
  }

  function setPodcastQuality(value) {
    persistSettings({ podcastQuality: Model.normalizeQuality(value) })
  }

  function formatGainDb(db) {
    var n = Model.snapGainDb(db)
    return (n > 0 ? "+" : "") + n.toFixed(1)
  }

  function setOutputGainDb(value) {
    var db = Model.snapGainDb(value)
    persistSettings({
      outputGainDb: db,
      meetingOutputGainDb: db,
      podcastOutputGainDb: db,
      cleanOutputGainDb: db
    })
    if (service && typeof service.clearGainPreview === "function") service.clearGainPreview()
    if (service && typeof service.rebuildHost === "function") service.rebuildHost()
  }

  function setEngine(value) {
    persistSettings({ engine: Model.normalizeEngine(value) })
  }

  function setEqCurve(value) {
    if (service.preset === "clean") return
    var prefix = service.preset === "podcast" ? "podcastEq" : "meetingEq"
    var patch = {}
    patch[prefix] = Model.normalizeEqCurve(value, "neutral")
    patch[prefix + "BodyDb"] = 0
    patch[prefix + "PresenceDb"] = 0
    patch[prefix + "AirDb"] = 0
    persistSettings(patch)
    if (service && typeof service.clearEqPreview === "function") service.clearEqPreview()
    if (service && typeof service.applyLiveControls === "function") service.applyLiveControls()
  }

  function eqCurveBase(band) {
    return Model.eqBandBase(service.eqCurve || "neutral", band)
  }

  function setEqTrimDb(band, value) {
    if (service.preset === "clean") return
    var trim = Model.snapEqTrimDb(Model.snapEqBandDb(service.eqCurve || "neutral", band, value) - eqCurveBase(band))
    var prefix = service.preset === "podcast" ? "podcastEq" : "meetingEq"
    var key = prefix + "BodyDb"
    if (band === "pres") key = prefix + "PresenceDb"
    else if (band === "air") key = prefix + "AirDb"
    var patch = {}
    patch[key] = trim
    persistSettings(patch)
    if (service && typeof service.clearEqPreview === "function") service.clearEqPreview()
    if (service && typeof service.applyLiveControls === "function") service.applyLiveControls()
  }

  function previewEqBand(band, value) {
    if (!service || typeof service.previewEqGains !== "function") return
    var t = service.eqTrim || { body: 0, pres: 0, air: 0 }
    var next = { body: t.body, pres: t.pres, air: t.air }
    next[band] = Model.snapEqTrimDb(Model.snapEqBandDb(service.eqCurve || "neutral", band, value) - eqCurveBase(band))
    service.previewEqGains(next.body, next.pres, next.air)
  }

  function setCaptureGainDb(value) {
    var db = Model.snapGainDb(value)
    persistSettings({
      captureGainDb: db,
      meetingCaptureGainDb: db,
      podcastCaptureGainDb: db,
      cleanCaptureGainDb: db
    })
    if (service && typeof service.clearGainPreview === "function") service.clearGainPreview()
    if (service && typeof service.rebuildHost === "function") service.rebuildHost()
  }

  component QualitySlider: Column {
    required property string title
    required property string preset
    required property string quality
    signal chosen(string value)

    width: parent.width
    spacing: Style.space(8)

    Text {
      text: title
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.subtitle
      font.bold: true
    }

    Text {
      width: parent.width
      text: Model.qualityHint(preset, quality)
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }

    PanelSlider {
      bar: root.bar
      width: parent.width
      minimum: 0
      maximum: 2
      step: 1
      integer: true
      tickCount: 3
      value: Model.qualityIndex(quality)
      onMoved: function(v) { chosen(Model.qualityFromIndex(v)) }
      onReleased: function(v) { chosen(Model.qualityFromIndex(v)) }
    }

    Row {
      width: parent.width
      Repeater {
        model: ["Softer", "Balanced", "Stronger"]
        Text {
          required property string modelData
          required property int index
          width: parent.width / 3
          text: modelData
          color: Model.qualityIndex(quality) === index ? root.foreground : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: Model.qualityIndex(quality) === index
          horizontalAlignment: index === 0 ? Text.AlignLeft : (index === 2 ? Text.AlignRight : Text.AlignHCenter)
        }
      }
    }
  }

  component GainRow: RowLayout {
    required property string title
    required property real persisted
    property string hint: ""
    property real minimum: -12
    property real maximum: 12
    property real held: persisted
    property real lastSent: persisted
    signal moved(real value)
    signal released(real value)

    width: parent.width
    spacing: Style.space(8)

    // PanelSlider drops dragging before released(). Rebinding held then
    // would copy persisted back and persist the old +1.0 / +1.5.
    onPersistedChanged: {
      lastSent = persisted
      if (!gainSlider.dragging) held = persisted
    }

    function snapHeld(v) {
      var s = Model.snapGainDb(v)
      if (s < minimum) s = minimum
      if (s > maximum) s = maximum
      return s
    }

    function applyHeld(v) {
      var s = snapHeld(v)
      held = s
      lastSent = s
      return s
    }

    HoverHandler { id: gainHover }
    PanelToolTip {
      visible: hint !== "" && gainHover.hovered
      text: hint
      fontFamily: root.fontFamily
    }

    Text {
      text: title
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      Layout.preferredWidth: Style.space(56)
      Layout.alignment: Qt.AlignVCenter
    }

    PanelSlider {
      id: gainSlider
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignVCenter
      bar: root.bar
      minimum: parent.minimum
      maximum: parent.maximum
      step: 0.5
      value: held
      onMoved: function(v) { moved(applyHeld(v)) }
      onReleased: function(v) {
        var s = lastSent
        held = s
        released(s)
      }
    }

    Text {
      Layout.preferredWidth: Style.space(44)
      Layout.alignment: Qt.AlignVCenter
      horizontalAlignment: Text.AlignRight
      text: root.formatGainDb(held)
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  component VoiceRow: GainRow {
    required property string band
    // Fixed ±12 so changing a look moves the thumb. Writes still clamp to look ±6.
    function snapHeld(v) {
      var s = Model.snapEqBandDb(service.eqCurve || "neutral", band, v)
      if (s < minimum) s = minimum
      if (s > maximum) s = maximum
      return s
    }
  }

  function launchSetup() {
    if (!bar || !setup.command) return
    bar.run("omarchy-launch-floating-terminal-with-presentation " + Util.shellQuote(setup.command))
    close()
  }

  function ensureCursor() {
    if (focusSection === "presets") {
      for (var i = 0; i < presets.length; i++) {
        if (presets[i].value === service.preset) { presetIndex = i; break }
      }
    }
    if (displaySources.length === 0) {
      if (focusSection === "sources") focusSection = "presets"
      sourceIndex = 0
      return
    }
    if (sourceIndex >= displaySources.length) sourceIndex = displaySources.length - 1
    if (sourceIndex < 0) sourceIndex = 0
  }

  function setHeaderCursor() {
    cursorActive = true
    focusSection = "header"
    if (panelFlick) panelFlick.contentY = 0
  }

  function moveCursor(dx, dy) {
    if (tuneOpen) return
    cursorActive = true
    ensureCursor()
    if (dy === 0) return
    var sections = ["header", "presets", "sources"]
    if (setup.needed) sections.push("setup")
    var idx = sections.indexOf(focusSection)
    if (idx < 0) idx = 0
    if (focusSection === "presets" && dx !== 0) {
      presetIndex = Math.max(0, Math.min(presets.length - 1, presetIndex + dx))
      return
    }
    if (focusSection === "sources" && dy !== 0 && displaySources.length > 0) {
      var next = sourceIndex + dy
      if (next >= 0 && next < displaySources.length) {
        sourceIndex = next
        return
      }
    }
    var ni = Math.max(0, Math.min(sections.length - 1, idx + dy))
    focusSection = sections[ni]
    if (focusSection === "sources") sourceIndex = dy > 0 ? 0 : Math.max(0, displaySources.length - 1)
  }

  function activateCursor() {
    if (tuneOpen) return
    ensureCursor()
    if (focusSection === "header") toggleEnabled()
    else if (focusSection === "presets") choosePreset(presets[presetIndex].value)
    else if (focusSection === "sources" && displaySources[sourceIndex]) chooseSource(displaySources[sourceIndex].name)
    else if (focusSection === "setup") launchSetup()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: {
    if (!opened) {
      tuneOpen = false
      pendingTuneOpen = false
      levelOpen = false
      if (cardRotation) cardRotation.angle = 0
      if (typeof service.setMeterHold === "function") service.setMeterHold(false)
      return
    }
    cursorActive = false
    focusSection = "header"
    displaySources = captureSources.slice()
    ensureCursor()
    if (panelFlick) panelFlick.contentY = 0
    if (typeof service.setMeterHold === "function") service.setMeterHold(true)
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  readonly property real levelPreview: {
    if (!service || !service.gainPreview) return 1
    var po = Model.gainDbToLinear(service.previewOutputDb)
    var pc = Model.gainDbToLinear(service.previewCaptureDb)
    var o = Model.gainDbToLinear(service.outputGainDb)
    var c = Model.gainDbToLinear(service.captureGainDb)
    return (po / Math.max(o, 0.0001)) * (pc / Math.max(c, 0.0001))
  }

  readonly property string meterEpoch: {
    var name = service.afterNodeName || ""
    if (name) {
      var node = service.afterNode
      var id = node && node.id !== undefined ? String(node.id) : ""
      return name + ":" + id
    }
    return service.running ? "starting" : "off"
  }
  property bool metersArmed: true
  onMeterEpochChanged: {
    metersArmed = false
    Qt.callLater(function() { root.metersArmed = true })
  }

  PwNodePeakMonitor {
    id: afterPeakMonitor
    node: service.afterNode
    enabled: root.opened && root.metersArmed && !!service.afterNode
  }

  onCaptureSourcesChanged: if (opened) sourceRefreshTimer.restart()

  Timer {
    id: sourceRefreshTimer
    interval: 400
    onTriggered: if (root.opened) root.displaySources = root.captureSources.slice()
  }

  Service {
    id: localService
    active: root.sharedService === null
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function on(): string { root.persistSettings({ enabled: true }); return "ok" }
    function off(): string { root.persistSettings({ enabled: false }); return "ok" }
    function preset(name: string): string { root.choosePreset(name); return "ok" }
    function status(): string { return service.statusText }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    active: service.enabled && service.running
    tooltipText: root.barTooltip
    iconComponent: Component {
      Item {
        OmavoiceIcon {
          anchors.centerIn: parent
          iconSize: Style.space(12)
          color: root.barIconColor
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.toggleEnabled()
      else if (buttonCode === Qt.LeftButton) root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(
      root.tuneOpen ? tuneInner.implicitHeight + Style.space(24) : column.implicitHeight,
      Style.space(560)
    )

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (root.tuneOpen) return
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (!root.tuneOpen && root.cursorActive) root.activateCursor()
      onCloseRequested: {
        if (root.tuneOpen) root.showTune(false)
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (root.tuneOpen) return
        if (t === "m" || t === "M") root.choosePreset("meeting")
        else if (t === "p" || t === "P") root.choosePreset("podcast")
        else if (t === "c" || t === "C") root.choosePreset("clean")
        else if (t === "o" || t === "O") root.toggleEnabled()
        else if (t === "r" || t === "R") {
          if (typeof service.reload === "function") service.reload()
        }
      }

      transform: Rotation {
        id: cardRotation
        origin.x: keyCatcher.width / 2
        origin.y: keyCatcher.height / 2
        axis.x: 0
        axis.y: 1
        axis.z: 0
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        visible: !root.tuneOpen
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          Item {
            id: header
            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, reloadButton.implicitHeight, powerSwitch.implicitHeight)
            readonly property bool ringVisible: root.headerHasCursor
            function focusHero() { root.setHeaderCursor() }

            OmavoiceIcon {
              id: heroIcon
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              iconSize: Style.font.display
              color: root.iconColor
              opacity: service.enabled ? 1.0 : 0.5
            }

            Column {
              id: heroLabels
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(14)
              anchors.right: reloadButton.left
              anchors.rightMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(3)

              Text {
                text: "Omavoice"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
              }

              Text {
                width: parent.width
                visible: text !== ""
                text: root.heroPhraseText.toUpperCase()
                textFormat: Text.PlainText
                color: service.lastError !== "" ? root.urgent : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }
            }

            PanelActionButton {
              id: reloadButton
              anchors.right: powerSwitch.left
              anchors.rightMargin: Style.space(4)
              anchors.verticalCenter: parent.verticalCenter
              iconText: service.reloading ? "󰑓" : "󰑐"
              tooltipText: "Reload processing"
              foreground: root.foreground
              fontFamily: root.fontFamily
              enabled: !service.reloading
              onClicked: if (typeof service.reload === "function") service.reload()
            }

            ToggleSwitch {
              id: powerSwitch
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              checked: service.enabled
              busy: service.busy && !service.running
              hasCursor: header.ringVisible
              foreground: root.foreground
              onHovered: function(on) { if (on) header.focusHero() }
              onToggled: root.toggleEnabled()
              PanelToolTip {
                visible: powerSwitch.containsMouse
                text: root.toggleHint
                fontFamily: root.fontFamily
              }
            }
          }

          Text {
            visible: service.lastError !== ""
            width: parent.width
            text: service.lastError
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Column {
            visible: root.setup.needed
            width: parent.width
            spacing: Style.space(6)

            Text {
              width: parent.width
              text: root.setup.body
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            CursorSurface {
              width: parent.width
              implicitHeight: setupRow.implicitHeight + Style.spacing.rowPaddingX
              hasCursor: root.cursorActive && root.focusSection === "setup"
              foreground: root.foreground
              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: { root.cursorActive = true; root.focusSection = "setup" }
                onClicked: root.launchSetup()
              }
              RowLayout {
                id: setupRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                Text {
                  text: root.setup.command
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  Layout.fillWidth: true
                  wrapMode: Text.WordWrap
                }
              }
            }
          }

          PanelSeparator { foreground: root.foreground }

          Column {
            width: parent.width
            spacing: Style.space(8)

            Item {
              width: parent.width
              implicitHeight: Math.max(presetHeader.implicitHeight, presetTuneButton.implicitHeight)

              PanelSectionHeader {
                id: presetHeader
                anchors.left: parent.left
                anchors.right: presetTuneButton.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                text: "PRESET"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              PanelActionButton {
                id: presetTuneButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰒓"
                tooltipText: "Tune Meeting and Podcast"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.showTune(true)
              }
            }

            Row {
              id: presetRow
              width: parent.width
              spacing: Style.space(6)

              HoverHandler {
                onHoveredChanged: root.setChipHover("presets", hovered)
              }

              Repeater {
                model: root.presets
                CursorSurface {
                  required property var modelData
                  required property int index
                  width: Math.floor((parent.width - Style.space(6) * 2) / 3)
                  implicitHeight: Style.space(36)
                  hasCursor: root.cursorActive && root.focusSection === "presets" && root.presetIndex === index
                  foreground: root.foreground
                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: {
                      root.cursorActive = true
                      root.focusSection = "presets"
                      root.presetIndex = index
                    }
                    onClicked: root.choosePreset(modelData.value)
                  }
                  Rectangle {
                    anchors.fill: parent
                    radius: Style.cornerRadius
                    color: service.preset === modelData.value
                      ? (bar ? Style.selectedFillFor(bar.foreground, Color.accent) : Color.accent)
                      : "transparent"
                    border.width: 1
                    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
                  }
                  Text {
                    anchors.centerIn: parent
                    text: modelData.label
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: service.preset === modelData.value
                  }
                }
              }
            }

            Text {
              width: parent.width
              text: Model.presetHint(service.preset)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          PanelSeparator { foreground: root.foreground }

          Column {
            width: parent.width
            spacing: Style.space(8)

            Item {
              width: parent.width
              implicitHeight: Math.max(micHeader.implicitHeight, micAutoRow.implicitHeight)

              PanelSectionHeader {
                id: micHeader
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "MICROPHONE"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Row {
                id: micAutoRow
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(6)

                PanelSectionHeader {
                  id: micAutoLabel
                  text: "AUTOMATIC"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  anchors.verticalCenter: parent.verticalCenter
                }

                ToggleSwitch {
                  id: defaultMicSwitch
                  trackHeight: Math.round(micAutoLabel.font.pixelSize * 1.2)
                  cursorPad: Style.space(3)
                  anchors.verticalCenter: micAutoLabel.verticalCenter
                  anchors.verticalCenterOffset: Math.round(micAutoLabel.topPadding / 2)
                  checked: service.setDefaultSource
                  foreground: root.foreground
                  onToggled: root.toggleDefaultSource()
                  PanelToolTip {
                    visible: defaultMicSwitch.containsMouse
                    text: service.setDefaultSource
                      ? "Apps pick Omavoice automatically"
                      : "Pick Omavoice in each app"
                    fontFamily: root.fontFamily
                  }
                }
              }
            }

            Text {
              visible: Model.sourceKind(service.targetName) === "bluetooth"
              width: parent.width
              text: "Headset mics are narrow-band. USB is better for Omavoice."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Text {
              visible: displaySources.length === 0
              width: parent.width
              text: "No capture sources. Plug in a USB mic."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            Column {
              id: sourceList
              width: parent.width
              spacing: Style.space(4)

              HoverHandler {
                onHoveredChanged: root.setChipHover("sources", hovered)
              }

              Repeater {
                model: displaySources
                CursorSurface {
                  id: sourceRow
                  required property var modelData
                  required property int index
                  readonly property bool isActive: service.targetName === modelData.name
                  width: parent.width
                  implicitHeight: sourceInner.implicitHeight + Style.space(8)
                  hasCursor: root.cursorActive && root.focusSection === "sources" && root.sourceIndex === index
                  current: isActive
                  foreground: root.foreground
                  fill: root.bar ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "transparent"
                  currentFill: root.bar ? Style.selectedFillFor(root.bar.foreground, Color.accent) : "transparent"

                  Column {
                    id: sourceInner
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Style.space(8)
                    anchors.rightMargin: Style.space(8)
                    spacing: Style.space(6)

                    RowLayout {
                      id: sourceMeterRow
                      width: parent.width
                      spacing: Style.space(10)

                      Column {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 1
                        Text {
                          width: parent.width
                          text: Model.friendlyDeviceLabel(modelData.description || modelData.name)
                          color: root.foreground
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.body
                          font.bold: sourceRow.isActive
                          elide: Text.ElideRight
                        }
                        Text {
                          width: parent.width
                          text: Model.sourceKind(modelData.name) === "usb" ? "USB" : Model.sourceKind(modelData.name)
                          color: root.dim
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                        }
                      }

                      Item {
                        Layout.preferredWidth: Style.space(72)
                        Layout.preferredHeight: Style.space(8)
                        Layout.alignment: Qt.AlignVCenter

                        Rectangle {
                          anchors.fill: parent
                          color: Util.alpha(root.foreground, 0.18)
                          visible: sourceRow.isActive

                          Rectangle {
                            height: parent.height
                            width: parent.width * Math.max(0, Math.min(1, afterPeakMonitor.peak * root.levelPreview))
                            color: root.foreground
                            Behavior on width { NumberAnimation { duration: 70 } }
                          }
                        }
                      }

                      MouseArea {
                        id: levelHit
                        visible: sourceRow.isActive
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: Style.space(22)
                        implicitHeight: Style.space(22)
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.levelOpen = !root.levelOpen

                        Text {
                          anchors.centerIn: parent
                          // 󰅂 is right in this font (clock "next month"). Dropdown uses 󰅀 for down.
                          text: root.levelOpen ? "󰅀" : "󰅁"
                          color: root.dim
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.body
                        }

                        PanelToolTip {
                          visible: levelHit.containsMouse
                          text: "Level"
                          fontFamily: root.fontFamily
                        }
                      }
                    }

                    Item {
                      id: levelDrawer
                      width: parent.width
                      visible: sourceRow.isActive
                      height: sourceRow.isActive && root.levelOpen ? levelInner.implicitHeight : 0
                      clip: true
                      Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                      Column {
                        id: levelInner
                        width: parent.width
                        spacing: Style.space(8)

                        GainRow {
                          title: "Output"
                          persisted: service.outputGainDb
                          onMoved: function(v) {
                            if (service && typeof service.previewGains === "function")
                              service.previewGains(service.captureGainDb, v)
                          }
                          onReleased: function(v) { root.setOutputGainDb(v) }
                        }

                        GainRow {
                          title: "Input"
                          persisted: service.captureGainDb
                          hint: "Before noise suppression."
                          onMoved: function(v) {
                            if (service && typeof service.previewGains === "function")
                              service.previewGains(v, service.outputGainDb)
                          }
                          onReleased: function(v) { root.setCaptureGainDb(v) }
                        }
                      }
                    }
                  }

                  MouseArea {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.rightMargin: sourceRow.isActive ? Style.space(8) + Style.space(10) + Style.space(22) : 0
                    anchors.top: parent.top
                    height: sourceMeterRow.height + Style.space(8)
                    hoverEnabled: true
                    preventStealing: true
                    cursorShape: Qt.PointingHandCursor
                    onContainsMouseChanged: if (containsMouse) {
                      root.cursorActive = true
                      root.focusSection = "sources"
                      root.sourceIndex = index
                    }
                    onClicked: root.chooseSource(modelData.name)
                  }
                }
              }
            }
          }
        }
      }

      Flickable {
        id: tuneFlick
        anchors.fill: parent
        visible: root.tuneOpen
        contentWidth: width
        contentHeight: tuneInner.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: tuneInner
          width: parent.width
          spacing: Style.space(16)

          Item {
            width: parent.width
            implicitHeight: Math.max(tuneBackButton.implicitHeight, tuneLabels.implicitHeight)

            PanelActionButton {
              id: tuneBackButton
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰁍"
              tooltipText: "Back"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.showTune(false)
            }

            Column {
              id: tuneLabels
              anchors.left: tuneBackButton.right
              anchors.leftMargin: Style.space(10)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(3)
              Text {
                text: "PRESET"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
              }
            }
          }

          PanelSeparator { foreground: root.foreground }

          Column {
            width: parent.width
            spacing: Style.space(8)

            Text {
              text: "Engine"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }

            Row {
              id: engineRow
              width: parent.width
              spacing: Style.space(6)

              HoverHandler {
                onHoveredChanged: root.setChipHover("engine", hovered)
              }

              Repeater {
                model: [
                  { value: "auto", label: "Auto" },
                  { value: "rnnoise", label: "RNNoise" },
                  { value: "deepfilter", label: "DeepFilterNet" }
                ]
                CursorSurface {
                  required property var modelData
                  required property int index
                  width: Math.floor((parent.width - Style.space(6) * 2) / 3)
                  implicitHeight: Style.space(32)
                  hasCursor: root.cursorActive && root.focusSection === "engine" && root.engineIndex === index
                  foreground: root.foreground
                  MouseArea {
                    id: engineHit
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: {
                      root.cursorActive = true
                      root.focusSection = "engine"
                      root.engineIndex = index
                    }
                    onClicked: root.setEngine(modelData.value)
                  }
                  PanelToolTip {
                    visible: engineHit.containsMouse
                    text: Model.engineChoiceHint(modelData.value)
                    fontFamily: root.fontFamily
                  }
                  Rectangle {
                    anchors.fill: parent
                    radius: Style.cornerRadius
                    color: service.engineSetting === modelData.value
                      ? (bar ? Style.selectedFillFor(bar.foreground, Color.accent) : Color.accent)
                      : "transparent"
                    border.width: 1
                    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
                  }
                  Text {
                    anchors.centerIn: parent
                    text: modelData.label
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: service.engineSetting === modelData.value
                  }
                  Rectangle {
                    visible: service.engineSetting === "auto" && service.engine === modelData.value
                    width: Style.space(6)
                    height: Style.space(6)
                    radius: width / 2
                    color: root.foreground
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.topMargin: Style.space(6)
                    anchors.rightMargin: Style.space(6)
                  }
                }
              }
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(8)

            Item {
              width: parent.width
              implicitHeight: Math.max(voiceTitle.implicitHeight, voiceDisabled.implicitHeight)

              Text {
                id: voiceTitle
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Voice"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.subtitle
                font.bold: true
              }

              PanelSectionHeader {
                id: voiceDisabled
                visible: service.preset === "clean"
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "DISABLED"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }
            }

            Column {
              width: parent.width
              spacing: Style.space(8)
              enabled: service.preset !== "clean"
              opacity: enabled ? 1 : 0.5

              Row {
                id: voiceRow
                width: parent.width
                spacing: Style.space(6)

                HoverHandler {
                  onHoveredChanged: {
                    if (service.preset === "clean") return
                    root.setChipHover("voice", hovered)
                  }
                }

                Repeater {
                  model: [
                    { value: "neutral", label: "Neutral" },
                    { value: "warm", label: "Warm" },
                    { value: "clear", label: "Clear" },
                    { value: "bright", label: "Bright" }
                  ]
                  CursorSurface {
                    required property var modelData
                    required property int index
                    width: Math.floor((parent.width - Style.space(6) * 3) / 4)
                    implicitHeight: Style.space(32)
                    hasCursor: service.preset !== "clean" && root.cursorActive && root.focusSection === "voice" && root.eqIndex === index
                    foreground: root.foreground
                    MouseArea {
                      id: eqHit
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onEntered: {
                        if (service.preset === "clean") return
                        root.cursorActive = true
                        root.focusSection = "voice"
                        root.eqIndex = index
                      }
                      onClicked: root.setEqCurve(modelData.value)
                    }
                    PanelToolTip {
                      visible: eqHit.containsMouse
                      text: Model.eqCurveHint(modelData.value)
                      fontFamily: root.fontFamily
                    }
                    Rectangle {
                      anchors.fill: parent
                      radius: Style.cornerRadius
                      color: (service.eqCurve || "neutral") === modelData.value
                        ? (bar ? Style.selectedFillFor(bar.foreground, Color.accent) : Color.accent)
                        : "transparent"
                      border.width: 1
                      border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
                    }
                    Text {
                      anchors.centerIn: parent
                      text: modelData.label
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: (service.eqCurve || "neutral") === modelData.value
                    }
                  }
                }
              }

              VoiceRow {
                title: "Body"
                band: "body"
                persisted: service.eqBodyDb
                hint: "Named curve plus your trim."
                onMoved: function(v) { root.previewEqBand("body", v) }
                onReleased: function(v) { root.setEqTrimDb("body", v) }
              }

              VoiceRow {
                title: "Presence"
                band: "pres"
                persisted: service.eqPresDb
                hint: "Named curve plus your trim."
                onMoved: function(v) { root.previewEqBand("pres", v) }
                onReleased: function(v) { root.setEqTrimDb("pres", v) }
              }

              VoiceRow {
                title: "Air"
                band: "air"
                persisted: service.eqAirDb
                hint: "Named curve plus your trim."
                onMoved: function(v) { root.previewEqBand("air", v) }
                onReleased: function(v) { root.setEqTrimDb("air", v) }
              }
            }
          }

          QualitySlider {
            title: "Meeting"
            preset: "meeting"
            quality: service.meetingQuality
            onChosen: function(value) { root.setMeetingQuality(value) }
          }

          QualitySlider {
            title: "Podcast"
            preset: "podcast"
            quality: service.podcastQuality
            onChosen: function(value) { root.setPodcastQuality(value) }
          }
        }
      }
    }
  }

  SequentialAnimation {
    id: pageFlip
    NumberAnimation {
      target: cardRotation
      property: "angle"
      from: 0
      to: 90
      duration: 130
      easing.type: Easing.InQuad
    }
    ScriptAction {
      script: {
        root.tuneOpen = root.pendingTuneOpen
        cardRotation.angle = -90
        if (tuneFlick) tuneFlick.contentY = 0
      }
    }
    NumberAnimation {
      target: cardRotation
      property: "angle"
      from: -90
      to: 0
      duration: 170
      easing.type: Easing.OutQuad
    }
  }

  Timer {
    interval: 2800
    running: root.opened && service.running && !root.tuneOpen
    repeat: true
    onTriggered: root.phraseIndex = (root.phraseIndex + 1) % root.activePhrases.length
  }
}
