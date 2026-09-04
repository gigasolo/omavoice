import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
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

  function toggleListen() {
    service.setListen(!service.listen)
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
    cursorActive = true
    ensureCursor()
    if (dy === 0) return
    var sections = ["header", "presets", "sources"]
    if (setup.needed) sections.push("setup")
    sections.push("listen")
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
    ensureCursor()
    if (focusSection === "header") toggleEnabled()
    else if (focusSection === "presets") choosePreset(presets[presetIndex].value)
    else if (focusSection === "sources" && displaySources[sourceIndex]) chooseSource(displaySources[sourceIndex].name)
    else if (focusSection === "setup") launchSetup()
    else if (focusSection === "listen") toggleListen()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: {
    if (!opened) {
      if (service.listen) service.setListen(false)
      return
    }
    cursorActive = false
    focusSection = "header"
    displaySources = captureSources.slice()
    ensureCursor()
    if (panelFlick) panelFlick.contentY = 0
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
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
      else if (buttonCode === Qt.MiddleButton) root.toggleListen()
      else root.toggle()
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
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "m" || t === "M") root.choosePreset("meeting")
        else if (t === "p" || t === "P") root.choosePreset("podcast")
        else if (t === "c" || t === "C") root.choosePreset("clean")
        else if (t === "l" || t === "L") root.toggleListen()
        else if (t === "o" || t === "O") root.toggleEnabled()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
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
            implicitHeight: hero.implicitHeight
            readonly property bool ringVisible: root.headerHasCursor
            function focusHero() { root.setHeaderCursor() }

            PanelHero {
              id: hero
              width: parent.width
              title: "Omavoice"
              meta: root.heroPhraseText
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: service.enabled ? 1.0 : 0.5
              iconComponent: Component {
                OmavoiceIcon {
                  iconSize: Style.font.display
                  color: root.iconColor
                }
              }
              trailingControl: Component {
                ToggleSwitch {
                  id: powerSwitch
                  checked: service.enabled
                  busy: service.busy && !service.running
                  hasCursor: header.ringVisible
                  foreground: hero.foreground
                  onHovered: function(on) { if (on) header.focusHero() }
                  onToggled: root.toggleEnabled()
                  PanelToolTip {
                    visible: powerSwitch.containsMouse
                    text: root.toggleHint
                    fontFamily: hero.fontFamily
                  }
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
                  implicitHeight: sourceCol.implicitHeight + Style.space(8)
                  hasCursor: root.cursorActive && root.focusSection === "sources" && root.sourceIndex === index
                  current: isActive
                  foreground: root.foreground
                  fill: root.bar ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "transparent"
                  currentFill: root.bar ? Style.selectedFillFor(root.bar.foreground, Color.accent) : "transparent"

                  Column {
                    id: sourceCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Style.space(8)
                    anchors.rightMargin: Style.space(8)
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

          PanelSeparator { foreground: root.foreground }

          CursorSurface {
            width: parent.width
            implicitHeight: listenRow.implicitHeight + Style.space(8)
            hasCursor: root.cursorActive && root.focusSection === "listen"
            foreground: root.foreground
            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: { root.cursorActive = true; root.focusSection = "listen" }
              onClicked: root.toggleListen()
            }
            RowLayout {
              id: listenRow
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              Text {
                text: service.listen ? "Listening to Omavoice" : "Listen (use headphones)"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                Layout.fillWidth: true
              }
              ToggleSwitch {
                checked: service.listen
                foreground: root.foreground
                onToggled: root.toggleListen()
              }
            }
          }
        }
      }
    }
  }

  Timer {
    interval: 2800
    running: root.opened && service.running
    repeat: true
    onTriggered: root.phraseIndex = (root.phraseIndex + 1) % root.activePhrases.length
  }
}
