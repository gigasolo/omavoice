import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import "Model.js" as Model

Item {
  id: root

  property var shell: null
  property var settings: ({})
  property var manifest: null
  property bool active: true

  property bool probed: false
  property bool haveRnnoise: false
  property bool haveDeepfilter: false
  property bool haveWebrtc: false
  property bool listen: false
  property string lastError: ""
  property string actionStatus: ""
  property string targetName: ""
  property string targetLabel: ""
  property string previousDefaultName: ""
  property string hostKey: ""
  property var sources: []
  property bool promoted: false
  property bool meterHoldWanted: false

  // Quickshell leaves PwNode.name empty until the node is bound.
  readonly property var nodes: Pipewire.nodes ? Pipewire.nodes.values : []
  readonly property var trackedNodes: {
    var list = []
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (n && !n.isStream) list.push(n)
    }
    return list
  }
  PwObjectTracker { objects: root.trackedNodes }

  readonly property bool busy: hostProcess.running && !running
  readonly property bool running: hostProcess.running
  readonly property var beforeNode: {
    var _ = nodes
    return nodeNamed(targetName)
  }
  readonly property var afterNode: {
    var _ = nodes
    return omavoiceNode()
  }

  readonly property string pluginDir: manifest && manifest.__sourceDir ? String(manifest.__sourceDir) : Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, "")
  readonly property bool enabled: setting("enabled", true) !== false
  readonly property string preset: Model.normalizePreset(setting("preset", "meeting"))
  readonly property string pinnedSource: String(setting("pinnedSource", "") || "")
  readonly property bool setDefaultSource: setting("setDefaultSource", true) !== false
  readonly property var setup: Model.setupGuide(haveRnnoise)
  readonly property bool setupNeeded: setup.needed && preset !== "clean"
  readonly property string engine: Model.engineForPreset(preset, haveRnnoise, haveDeepfilter)
  readonly property string statusText: Model.statusText({
    enabled: enabled,
    running: running,
    busy: busy,
    setupNeeded: setupNeeded,
    preset: preset,
    targetName: targetName,
    targetLabel: targetLabel,
    lastError: lastError
  })

  readonly property var defaultSource: Pipewire.defaultAudioSource
  readonly property string defaultSourceName: defaultSource && defaultSource.name ? String(defaultSource.name) : ""

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function scriptPath(name) {
    return pluginDir + "/scripts/" + name
  }

  function snapshotSources() {
    var list = []
    for (var i = 0; i < nodes.length; i++) {
      var node = nodes[i]
      if (!node || node.isSink || node.isStream) continue
      var name = String(node.name || "")
      if (!Model.isCaptureSourceName(name)) continue
      list.push({
        name: name,
        description: String(node.description || node.nickname || name),
        id: node.id
      })
    }
    return list
  }

  function omavoiceNode() {
    for (var i = 0; i < nodes.length; i++) {
      var node = nodes[i]
      if (node && !node.isSink && !node.isStream && Model.isOmavoiceNode(node)) return node
    }
    return null
  }

  function nodeNamed(name) {
    var want = String(name || "")
    if (!want) return null
    for (var i = 0; i < nodes.length; i++) {
      var node = nodes[i]
      if (node && !node.isSink && !node.isStream && String(node.name || "") === want) return node
    }
    return null
  }

  function refreshSources() {
    var next = snapshotSources()
    if (!Model.sourcesUnchanged(sources, next)) sources = next
    var picked = Model.pickSource(sources, pinnedSource, defaultSourceName)
    var nextName = picked ? String(picked.name) : ""
    var nextLabel = picked ? String(picked.description || picked.name) : ""
    if (nextName !== targetName || nextLabel !== targetLabel) {
      targetName = nextName
      targetLabel = nextLabel
    }
    syncHost()
  }

  function syncHost() {
    if (!root.active || !enabled || !targetName) {
      stopHost()
      return
    }
    startHost()
  }

  function startHost() {
    var key = preset + "\0" + targetName + "\0" + pluginDir
    if (hostProcess.running && hostKey === key) return
    hostKey = key
    lastError = ""
    promoted = false
    hostProcess.running = false
    hostProcess.command = [scriptPath("omavoice-run"), "--preset", preset, "--target", targetName, "--dir", pluginDir]
    hostProcess.running = true
  }

  function stopHost() {
    if (listen) setListen(false)
    if (hostProcess.running) hostProcess.running = false
    hostKey = ""
    promoted = false
    if (!enabled) restoreDefault()
  }

  function setEnabled(on) {
    if (on === enabled) return
    persist({ enabled: on === true })
  }

  function setPreset(value) {
    persist({ preset: Model.normalizePreset(value) })
  }

  function pinSource(name) {
    persist({ pinnedSource: String(name || "") })
  }

  function persist(values) {
    if (!shell || typeof shell.updateEntryInline !== "function") {
      var next = {}
      for (var existing in settings) next[existing] = settings[existing]
      for (var key in values) next[key] = values[key]
      settings = next
      return
    }
    var entry = { id: "gigasolo.omavoice" }
    for (var k in settings) if (k !== "id") entry[k] = settings[k]
    for (var n in values) entry[n] = values[n]
    settings = entry
    shell.updateEntryInline("gigasolo.omavoice", entry)
  }

  function setListen(on) {
    listen = on === true
    if (!listen) {
      listenProcess.running = false
      return
    }
    listenProcess.command = [
      "pw-loopback",
      "--capture-props=target.object=omavoice node.passive=true node.name=omavoice.listen.capture",
      "--playback-props=node.passive=true node.name=omavoice.listen.playback"
    ]
    listenProcess.running = true
  }

  // Filter-chain sources are node.passive, so After peaks stay at 0 unless
  // something captures Omavoice. A silent pw-cat hold while the panel is
  // open pulls the graph without starting a call or Listen.
  function setMeterHold(on) {
    meterHoldWanted = on === true
    syncMeterHold()
  }

  function syncMeterHold() {
    var want = meterHoldWanted && running && enabled
    if (!want) {
      meterHoldRetry.stop()
      if (meterHoldProcess.running) meterHoldProcess.running = false
      return
    }
    if (meterHoldProcess.running) return
    meterHoldProcess.command = [
      "pw-cat",
      "-r",
      "-a",
      "--target", Model.NODE_NAME,
      "--rate", "48000",
      "--channels", "1",
      "-P", "{ node.name=omavoice.meter.hold }",
      "/dev/null"
    ]
    meterHoldProcess.running = true
  }

  function promoteDefault() {
    if (!setDefaultSource) return
    var node = omavoiceNode()
    if (!node || node.id === undefined) return
    if (defaultSourceName && !Model.isOmavoiceName(defaultSourceName) && previousDefaultName === "") {
      previousDefaultName = defaultSourceName
    }
    Quickshell.execDetached([
      "omarchy-audio-input-set-default",
      String(node.id),
      Model.NODE_NAME
    ])
  }

  function restoreDefault() {
    if (!previousDefaultName) return
    var nodes = Pipewire.nodes && Pipewire.nodes.values ? Pipewire.nodes.values : []
    for (var i = 0; i < nodes.length; i++) {
      var node = nodes[i]
      if (node && String(node.name || "") === previousDefaultName && node.id !== undefined) {
        Quickshell.execDetached([
          "omarchy-audio-input-set-default",
          String(node.id),
          previousDefaultName
        ])
        break
      }
    }
    previousDefaultName = ""
  }

  function probe() {
    probeProcess.command = [scriptPath("omavoice-probe")]
    probeProcess.running = true
  }

  onEnabledChanged: syncHost()
  onPresetChanged: syncHost()
  onPinnedSourceChanged: refreshSources()
  onTargetNameChanged: syncHost()
  onActiveChanged: {
    if (!active) stopHost()
    else {
      probe()
      refreshSources()
    }
  }

  Component.onCompleted: {
    probe()
    refreshSources()
  }

  Component.onDestruction: {
    restoreDefault()
    setMeterHold(false)
    stopHost()
  }

  Timer {
    interval: 750
    running: root.active
    repeat: true
    onTriggered: root.refreshSources()
  }

  Timer {
    interval: 400
    running: root.active && hostProcess.running && root.setDefaultSource && !root.promoted
    repeat: true
    onTriggered: {
      if (root.omavoiceNode()) {
        root.promoteDefault()
        root.promoted = true
      }
    }
  }

  Process {
    id: probeProcess
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var data = JSON.parse(text)
          haveRnnoise = data.rnnoise === true
          haveDeepfilter = data.deepfilter === true
          haveWebrtc = data.webrtc === true
          probed = true
          lastError = ""
        } catch (e) {
          lastError = "Could not probe audio plugins"
        }
      }
    }
  }

  Process {
    id: hostProcess
    stdout: StdioCollector {}
    stderr: StdioCollector {
      onStreamFinished: {
        var text = String(this.text || "").trim()
        if (text && !hostProcess.running) lastError = text.split("\n").slice(-1)[0]
      }
    }
    onRunningChanged: {
      if (!running) root.promoted = false
      root.syncMeterHold()
    }
  }

  Process {
    id: listenProcess
    onRunningChanged: if (!running && root.listen) root.listen = false
  }

  Process {
    id: meterHoldProcess
    onRunningChanged: {
      if (running) return
      if (root.meterHoldWanted && root.running) meterHoldRetry.restart()
    }
  }

  Timer {
    id: meterHoldRetry
    interval: 400
    repeat: false
    onTriggered: root.syncMeterHold()
  }
}
