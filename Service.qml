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
  property bool running: false
  property bool busy: hostProcess.running
  property bool listen: false
  property string lastError: ""
  property string actionStatus: ""
  property string targetName: ""
  property string targetLabel: ""
  property string previousDefaultName: ""
  property var sources: []

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
    var nodes = Pipewire.nodes && Pipewire.nodes.values ? Pipewire.nodes.values : []
    var list = []
    for (var i = 0; i < nodes.length; i++) {
      var node = nodes[i]
      if (!node || node.isSink || node.isStream) continue
      var name = String(node.name || "")
      if (!Model.isCaptureSourceName(name) && !Model.isOmavoiceName(name)) continue
      list.push({
        name: name,
        description: String(node.description || node.nickname || name),
        id: node.id
      })
    }
    return list
  }

  function omavoiceNode() {
    var nodes = Pipewire.nodes && Pipewire.nodes.values ? Pipewire.nodes.values : []
    for (var i = 0; i < nodes.length; i++) {
      var node = nodes[i]
      if (node && !node.isSink && String(node.name || "") === Model.NODE_NAME) return node
    }
    return null
  }

  function refreshSources() {
    sources = snapshotSources()
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
    var cmd = [scriptPath("omavoice-run"), "--preset", preset, "--target", targetName, "--dir", pluginDir]
    var same = hostProcess.running && hostProcess.command && hostProcess.command.join("\0") === cmd.join("\0")
    if (same) return
    if (hostProcess.running) {
      hostProcess.running = false
    }
    lastError = ""
    hostProcess.command = cmd
    hostProcess.running = true
  }

  function stopHost() {
    if (listen) setListen(false)
    if (hostProcess.running) hostProcess.running = false
    running = false
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
    running: root.active && hostProcess.running && root.setDefaultSource
    repeat: true
    onTriggered: {
      if (root.omavoiceNode()) {
        running = true
        root.promoteDefault()
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
      if (running) return
      root.running = false
    }
  }

  Process {
    id: listenProcess
    onRunningChanged: if (!running && root.listen) root.listen = false
  }
}
