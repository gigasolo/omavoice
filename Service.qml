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
  property string lastError: ""
  property string actionStatus: ""
  property string targetName: ""
  property string targetLabel: ""

  property string hostKey: ""
  property var sources: []
  property bool promoted: false
  property bool meterHoldWanted: false
  property string meterHoldTarget: ""
  property bool reloading: false

  // Quickshell leaves PwNode.name empty until the node is bound.
  readonly property var nodes: Pipewire.nodes ? Pipewire.nodes.values : []
  readonly property var trackedNodes: {
    var list = []
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (!n || n.isSink) continue
      var name = String(n.name || "")
      // PwNode.name is constant. Tracking while empty freezes After unbound.
      if (!name) continue
      if (n.isStream && name !== Model.NODE_NAME) continue
      list.push(n)
    }
    return list
  }
  PwObjectTracker { objects: root.trackedNodes }

  readonly property bool running: !!afterNodeName
  readonly property bool busy: enabled && !afterNodeName && (hostProcess.running || (hostAttempts > 0 && hostAttempts < 8))
  // After meters and the panel hold need the bound source. Matching the
  // unbound description fires onAfterNodeChanged too early, then the same
  // object later gets name "omavoice" with no second change — After stays
  // at Before until a preset toggle recreates the node.
  readonly property string afterNodeName: {
    if (defaultSourceName === Model.NODE_NAME) return Model.NODE_NAME
    for (var i = 0; i < trackedNodes.length; i++) {
      var n = trackedNodes[i]
      if (n && String(n.name || "") === Model.NODE_NAME) return Model.NODE_NAME
    }
    return ""
  }
  readonly property var afterNode: {
    if (defaultSourceName === Model.NODE_NAME && defaultSource) return defaultSource
    var name = afterNodeName
    if (!name) return null
    return nodeNamed(name)
  }
  readonly property string afterNodeId: {
    var node = afterNode
    return node && node.id !== undefined ? String(node.id) : ""
  }

  readonly property string pluginDir: manifest && manifest.__sourceDir ? String(manifest.__sourceDir) : Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, "")
  readonly property bool enabled: setting("enabled", true) !== false
  readonly property string preset: Model.normalizePreset(setting("preset", "meeting"))
  readonly property string meetingQuality: Model.normalizeQuality(setting("meetingQuality", "better"))
  readonly property string podcastQuality: Model.normalizeQuality(setting("podcastQuality", "better"))
  readonly property string quality: preset === "podcast" ? podcastQuality : meetingQuality
  readonly property string pinnedSource: String(setting("pinnedSource", "") || "")
  readonly property string previousAudioSource: String(setting("previousAudioSource", "") || "")
  readonly property bool setDefaultSource: setting("setDefaultSource", true) !== false
  readonly property string engineSetting: Model.normalizeEngine(setting("engine", "auto"))
  readonly property string engine: Model.resolveEngine(preset, engineSetting, haveRnnoise, haveDeepfilter)
  readonly property var setup: Model.setupGuide(engineSetting, haveRnnoise, haveDeepfilter, preset)
  readonly property bool setupNeeded: setup.needed
  readonly property real outputGainDb: Model.outputGainDbForPreset(preset, settings)
  readonly property real captureGainDb: Model.captureGainDbForPreset(preset, settings)
  readonly property string eqCurve: Model.eqCurveForPreset(preset, settings)
  readonly property var eqTrim: Model.eqTrimForPreset(preset, settings)
  readonly property var eqBands: Model.eqBandGains(eqCurve, eqPreview ? previewEqTrim : eqTrim)
  readonly property real eqBodyDb: eqBands.body
  readonly property real eqPresDb: eqBands.pres
  readonly property real eqAirDb: eqBands.air
  property bool gainPreview: false
  property real previewCaptureDb: 0
  property real previewOutputDb: 0
  property bool eqPreview: false
  property var previewEqTrim: ({ body: 0, pres: 0, air: 0 })
  property int hostAttempts: 0
  property double hostStartedAt: 0
  readonly property string statusText: Model.statusText({
    enabled: enabled,
    running: running,
    busy: busy,
    setupNeeded: setupNeeded,
    setupHero: setup.hero,
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

  readonly property bool hasUnboundNodes: {
    for (var i = 0; i < nodes.length; i++) {
      var node = nodes[i]
      if (node && !node.isSink && !node.isStream && !String(node.name || "")) return true
    }
    return false
  }

  function refreshSources() {
    var next = snapshotSources()
    if (Model.shouldDeferSourcePick(targetName, hasUnboundNodes)) {
      if (next.length > 0 && !Model.sourcesUnchanged(sources, next)) sources = next
      if (!hostProcess.running) syncHost()
      return
    }
    if (!Model.sourcesUnchanged(sources, next)) sources = next
    var fallback = Model.pickFallbackName(defaultSourceName, previousAudioSource)
    var picked = Model.pickSource(sources, pinnedSource, fallback)
    var nextName = picked ? String(picked.name) : ""
    var nextLabel = picked ? String(picked.description || picked.name) : ""
    var pickChanged = nextName !== targetName || nextLabel !== targetLabel
    if (pickChanged) {
      targetName = nextName
      targetLabel = nextLabel
    }
    if (pickChanged || !hostProcess.running) syncHost()
  }

  function syncHost() {
    if (!root.active || !enabled) {
      startDebounce.stop()
      stopHost()
      return
    }
    if (!targetName) {
      // After a plugin reload the registry is still binding; do not kill a
      // host we are about to start, and do not clear a pick that has not
      // landed yet.
      if (hasUnboundNodes || hostProcess.running) return
      startDebounce.stop()
      stopHost()
      return
    }
    startDebounce.restart()
  }

  function startHostNow() {
    if (!root.active || !enabled || !targetName) return
    if (!probed) return
    if (hostAttempts >= 8) {
      if (!lastError) lastError = Model.hostErrorText("bind")
      return
    }
    var key = preset + "\0" + engine + "\0" + targetName + "\0" + pluginDir
    if (hostProcess.running && hostKey === key) return
    if (meterHoldProcess.running) meterHoldProcess.running = false
    meterHoldTarget = ""
    hostAttempts += 1
    hostKey = key
    promoted = false
    hostStartedAt = Date.now()
    hostProcess.running = false
    var args = [scriptPath("omavoice-run"), "--preset", preset, "--quality", quality, "--engine", engine, "--capture-gain-db", String(captureGainDb), "--output-gain-db", String(outputGainDb), "--target", targetName, "--dir", pluginDir]
    if (eqCurve) {
      args.push("--eq", eqCurve)
      args.push("--eq-body-db", String(eqTrim.body))
      args.push("--eq-pres-db", String(eqTrim.pres))
      args.push("--eq-air-db", String(eqTrim.air))
    }
    hostProcess.command = args
    hostProcess.running = true
  }

  function applyLiveControls() {
    if (!root.active || !enabled || !hostProcess.running) return
    liveDebounce.restart()
  }

  function previewGains(captureDb, outputDb) {
    previewCaptureDb = Model.clampGainDb(captureDb)
    previewOutputDb = Model.clampGainDb(outputDb)
    gainPreview = true
    applyLiveControls()
  }

  function clearGainPreview() {
    gainPreview = false
  }

  function previewEqGains(bodyDb, presDb, airDb) {
    previewEqTrim = {
      body: Model.clampEqTrimDb(bodyDb),
      pres: Model.clampEqTrimDb(presDb),
      air: Model.clampEqTrimDb(airDb)
    }
    eqPreview = true
    applyLiveControls()
  }

  function clearEqPreview() {
    eqPreview = false
  }

  function writeLiveControls() {
    if (!root.active || !enabled || !hostProcess.running) return
    var cap = gainPreview ? previewCaptureDb : captureGainDb
    var out = gainPreview ? previewOutputDb : outputGainDb
    var args = [scriptPath("omavoice-ctl"), "set"]
    args.push("preamp:Gain 1", String(Model.gainDbToLinear(cap)))
    args.push("outgain:Gain 1", String(Model.gainDbToLinear(out)))
    var qp = Model.qualityParams(preset, quality)
    if (engine === "rnnoise") {
      args.push("denoise:VAD Threshold (%)", String(qp.vad))
      args.push("denoise:VAD Grace Period (ms)", String(qp.grace))
    } else if (engine === "deepfilter") {
      args.push("denoise:Attenuation Limit (dB)", String(qp.dfn))
    }
    if (eqCurve) {
      var bands = eqBands
      args.push("hp:Freq", String(bands.hpHz))
      args.push("eq_body:Gain", String(bands.body))
      args.push("eq_pres:Gain", String(bands.pres))
      args.push("eq_air:Gain", String(bands.air))
    }
    Quickshell.execDetached(args)
  }

  function stopHost() {
    startDebounce.stop()
    if (meterHoldProcess.running) meterHoldProcess.running = false
    meterHoldTarget = ""
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

  // Filter-chain sources are node.passive, so After peaks stay at 0 unless
  // something captures Omavoice. A silent pw-cat hold while the panel is
  // open pulls the graph without starting a call.
  function setMeterHold(on) {
    meterHoldWanted = on === true
    syncMeterHold()
  }

  function syncMeterHold() {
    var name = afterNodeName
    var id = afterNodeId
    var token = name && id ? name + ":" + id : ""
    // Meeting AEC keeps the chain running. Podcast/Clean stay silent
    // unless a hold is attached to this node id, not the previous omavoice.
    var want = meterHoldWanted && enabled && !!token
    if (!want) {
      meterHoldRetry.stop()
      if (meterHoldProcess.running) meterHoldProcess.running = false
      meterHoldTarget = ""
      return
    }
    if (meterHoldProcess.running && meterHoldTarget === token) return
    // Same-tick stop+start often does not relaunch Process. Stop, then retry.
    if (meterHoldProcess.running) {
      meterHoldProcess.running = false
      meterHoldRetry.restart()
      return
    }
    meterHoldTarget = token
    meterHoldProcess.command = [
      "pw-cat",
      "-r",
      "-a",
      "--target", name,
      "--rate", "48000",
      "--channels", "1",
      "--media-category", "Capture",
      "-P", "{ node.name=omavoice.meter.hold }",
      "/dev/null"
    ]
    meterHoldProcess.running = true
  }

  function promoteDefault() {
    if (!setDefaultSource) return
    if (Model.isOmavoiceName(defaultSourceName)) {
      promoted = true
      return
    }
    var node = omavoiceNode()
    if (!node || node.id === undefined) return
    if (defaultSourceName && Model.isCaptureSourceName(defaultSourceName) && defaultSourceName !== previousAudioSource)
      persist({ previousAudioSource: defaultSourceName })
    Quickshell.execDetached([
      "omarchy-audio-input-set-default",
      String(node.id),
      Model.NODE_NAME
    ])
  }

  function restoreDefault() {
    var want = previousAudioSource
    if (!want || Model.isOmavoiceName(want)) return
    var nodes = Pipewire.nodes && Pipewire.nodes.values ? Pipewire.nodes.values : []
    for (var i = 0; i < nodes.length; i++) {
      var node = nodes[i]
      if (node && String(node.name || "") === want && node.id !== undefined) {
        Quickshell.execDetached([
          "omarchy-audio-input-set-default",
          String(node.id),
          want
        ])
        break
      }
    }
  }

  function probe() {
    probeProcess.command = [scriptPath("omavoice-probe")]
    probeProcess.running = true
  }

  // Re-scan LADSPA plugins and rebuild the chain. Needed after installing
  // RNNoise or DeepFilterNet without restarting the shell.
  function reload() {
    reloading = true
    probed = false
    hostKey = ""
    hostAttempts = 0
    probe()
    if (!root.active || !enabled || !targetName) reloading = false
  }

  onEnabledChanged: { hostAttempts = 0; syncHost() }
  onPresetChanged: { hostAttempts = 0; syncHost() }
  onEngineChanged: { hostAttempts = 0; syncHost() }
  onQualityChanged: applyLiveControls()
  onOutputGainDbChanged: applyLiveControls()
  onCaptureGainDbChanged: applyLiveControls()
  onEqCurveChanged: applyLiveControls()
  onEqBodyDbChanged: applyLiveControls()
  onEqPresDbChanged: applyLiveControls()
  onEqAirDbChanged: applyLiveControls()
  onProbedChanged: if (probed) syncHost()
  onPinnedSourceChanged: refreshSources()
  onNodesChanged: refreshSources()
  onTargetNameChanged: { hostAttempts = 0; syncHost() }
  onAfterNodeChanged: syncMeterHold()
  onAfterNodeNameChanged: {
    syncMeterHold()
    if (afterNodeName) {
      lastError = ""
      hostAttempts = 0
    }
  }
  onAfterNodeIdChanged: {
    syncMeterHold()
    applyLiveControls()
    if (afterNodeName) hostAttempts = 0
    if (afterNodeName && !hostProcess.running && enabled && targetName && probed)
      startHostNow()
  }
  onSetDefaultSourceChanged: {
    if (setDefaultSource) {
      promoted = false
      return
    }
    restoreDefault()
    promoted = true
  }
  onActiveChanged: {
    if (!active) stopHost()
    else {
      hostAttempts = 0
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
    id: startDebounce
    interval: 150
    repeat: false
    onTriggered: root.startHostNow()
  }

  Timer {
    id: liveDebounce
    interval: 80
    repeat: false
    onTriggered: root.writeLiveControls()
  }

  Timer {
    interval: 750
    running: root.active && root.hasUnboundNodes
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
          lastError = ""
        } catch (e) {
          haveRnnoise = false
          haveDeepfilter = false
          haveWebrtc = false
          lastError = Model.hostErrorText("probe")
          root.reloading = false
        }
        probed = true
      }
    }
  }

  Process {
    id: hostProcess
    stdout: StdioCollector {}
    stderr: StdioCollector {
      onStreamFinished: {
        var text = String(this.text || "").trim()
        if (text && !hostProcess.running && root.hostAttempts >= 8)
          lastError = Model.hostErrorText("host", text)
      }
    }
    onRunningChanged: {
      if (running) {
        root.reloading = false
        return
      }
      root.promoted = false
      root.syncMeterHold()
    }
  }

  Timer {
    id: hostBindWatch
    interval: 1000
    running: root.active && root.enabled && !root.afterNodeName && root.hostAttempts < 8
    repeat: true
    onTriggered: {
      if (root.afterNodeName) return
      if (root.defaultSourceName === Model.NODE_NAME) return
      if (!root.probed || !root.targetName) return
      if (hostProcess.running) return
      root.startHostNow()
    }
  }

  Process {
    id: meterHoldProcess
    onRunningChanged: {
      if (running) return
      if (root.meterHoldWanted && root.afterNodeName) meterHoldRetry.restart()
    }
  }

  Timer {
    id: meterHoldRetry
    interval: 400
    repeat: false
    onTriggered: root.syncMeterHold()
  }

  Timer {
    id: meterHoldWatch
    interval: 800
    running: root.meterHoldWanted && root.enabled && !!root.afterNodeId && (!meterHoldProcess.running || root.meterHoldTarget !== root.afterNodeName + ":" + root.afterNodeId)
    repeat: true
    onTriggered: root.syncMeterHold()
  }
}
