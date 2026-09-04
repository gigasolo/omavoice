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
  property bool cursorActive: false
  property int phraseIndex: 0
  property bool settingsOpen: false
  property bool pendingSettingsOpen: false

  readonly property var sharedService: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor(moduleName) : null
  readonly property var service: sharedService || localService

  function pushSettings() { if (service) service.settings = settings }
  onSettingsChanged: pushSettings()
  onServiceChanged: pushSettings()
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
  readonly property string heroPhraseText: service.running
    ? activePhrases[phraseIndex % activePhrases.length]
    : service.statusText
  readonly property var setup: service.setup || { needed: false }

  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) {
      if (values[key] === undefined) delete entry[key]
      else entry[key] = values[key]
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

  function showSettings(open) {
    var next = open === true
    if (settingsOpen === next || pageFlip.running) return
    pendingSettingsOpen = next
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
    if (settingsOpen) return
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
    if (settingsOpen) return
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
      settingsOpen = false
      pendingSettingsOpen = false
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

  readonly property string meterEpoch: {
    var node = service.afterNode
    if (node && node.id !== undefined) return String(node.id)
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
    enabled: root.opened && root.metersArmed && service.running && !!service.afterNode
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
      root.settingsOpen ? settingsInner.implicitHeight + Style.space(24) : column.implicitHeight,
      Style.space(560)
    )

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (root.settingsOpen) return
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (!root.settingsOpen && root.cursorActive) root.activateCursor()
      onCloseRequested: {
        if (root.settingsOpen) root.showSettings(false)
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (root.settingsOpen) return
        if (t === "m" || t === "M") root.choosePreset("meeting")
        else if (t === "p" || t === "P") root.choosePreset("podcast")
        else if (t === "c" || t === "C") root.choosePreset("clean")
        else if (t === "o" || t === "O") root.toggleEnabled()
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
        visible: !root.settingsOpen
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
            implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, headerActions.implicitHeight)
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
              anchors.right: headerActions.left
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

            Row {
              id: headerActions
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(8)

              PanelActionButton {
                id: settingsButton
                size: powerSwitch.trackHeight
                bordered: true
                iconText: "󰒓"
                tooltipText: "Settings"
                foreground: root.foreground
                fontFamily: root.fontFamily
                anchors.verticalCenter: parent.verticalCenter
                onClicked: root.showSettings(true)
              }

              ToggleSwitch {
                id: powerSwitch
                checked: service.enabled
                busy: service.busy && !service.running
                hasCursor: header.ringVisible
                foreground: root.foreground
                anchors.verticalCenter: parent.verticalCenter
                onHovered: function(on) { if (on) header.focusHero() }
                onToggled: root.toggleEnabled()
                PanelToolTip {
                  visible: powerSwitch.containsMouse
                  text: root.toggleHint
                  fontFamily: root.fontFamily
                }
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

            PanelSectionHeader {
              text: "PRESET"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Row {
              width: parent.width
              spacing: Style.space(6)

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

            PanelSectionHeader {
              text: "MICROPHONE"
              foreground: root.foreground
              fontFamily: root.fontFamily
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
              width: parent.width
              spacing: Style.space(4)
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

                  PwNodePeakMonitor {
                    id: rowPeak
                    node: {
                      var _ = service.nodes
                      return service.nodeNamed ? service.nodeNamed(modelData.name) : null
                    }
                    enabled: root.opened && root.metersArmed && !!node
                  }

                  RowLayout {
                    id: sourceInner
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Style.space(8)
                    anchors.rightMargin: Style.space(8)
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

                        Rectangle {
                          height: parent.height
                          width: parent.width * Math.max(0, Math.min(1, rowPeak.peak))
                          color: sourceRow.isActive
                            ? Util.alpha(root.foreground, 0.40)
                            : Util.alpha(root.foreground, 0.55)
                          Behavior on width { NumberAnimation { duration: 70 } }
                        }

                        Rectangle {
                          visible: sourceRow.isActive && service.running
                          height: Math.max(2, Math.ceil(parent.height * 0.4))
                          width: parent.width * Math.max(0, Math.min(1, afterPeakMonitor.peak))
                          anchors.verticalCenter: parent.verticalCenter
                          color: root.foreground
                          Behavior on width { NumberAnimation { duration: 70 } }
                        }
                      }
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
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

      Column {
        id: settingsPage
        anchors.fill: parent
        visible: root.settingsOpen
        spacing: Style.space(12)

        Column {
          id: settingsInner
          width: parent.width
          spacing: Style.space(12)

          Item {
            width: parent.width
            implicitHeight: Math.max(settingsBackButton.implicitHeight, settingsLabels.implicitHeight)

            PanelActionButton {
              id: settingsBackButton
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰁍"
              tooltipText: "Back"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.showSettings(false)
            }

            Column {
              id: settingsLabels
              anchors.left: settingsBackButton.right
              anchors.leftMargin: Style.space(10)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(3)
              Text {
                text: "SETTINGS"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
              }
            }
          }

          PanelSeparator { foreground: root.foreground }

          Toggle {
            width: parent.width
            label: "Default microphone"
            description: "Apps pick Omavoice automatically."
            checked: service.setDefaultSource
            foreground: root.foreground
            onClicked: root.toggleDefaultSource()
          }

          PanelSeparator { foreground: root.foreground }

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
        root.settingsOpen = root.pendingSettingsOpen
        cardRotation.angle = -90
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
    running: root.opened && service.running && !root.settingsOpen
    repeat: true
    onTriggered: root.phraseIndex = (root.phraseIndex + 1) % root.activePhrases.length
  }
}
