var NODE_NAME = "omavoice"
var CAPTURE_NAME = "omavoice.capture"
var NODE_DESCRIPTION = "Omavoice"
var PRESETS = ["meeting", "podcast", "clean"]
var QUALITIES = ["good", "better", "best"]
var ENGINES = ["auto", "rnnoise", "deepfilter"]
var EQ_CURVES = ["neutral", "warm", "clear", "bright"]

function normalizePreset(value) {
  var preset = String(value || "").toLowerCase()
  if (PRESETS.indexOf(preset) >= 0) return preset
  return "meeting"
}

function normalizeQuality(value) {
  var quality = String(value || "").toLowerCase()
  if (QUALITIES.indexOf(quality) >= 0) return quality
  return "better"
}

function qualityIndex(value) {
  return QUALITIES.indexOf(normalizeQuality(value))
}

function qualityFromIndex(index) {
  var i = Math.round(Number(index))
  if (!isFinite(i) || i < 0) i = 1
  if (i > 2) i = 2
  return QUALITIES[i]
}

function qualityLabel(value) {
  var quality = normalizeQuality(value)
  if (quality === "good") return "Softer"
  if (quality === "best") return "Stronger"
  return "Balanced"
}

function qualityHint(preset, quality) {
  var kind = normalizePreset(preset)
  var level = normalizeQuality(quality)
  if (kind === "podcast") {
    if (level === "good") return "Light denoise. More of the room stays."
    if (level === "best") return "Heavier denoise. Less air, less noise."
    return "Speech that sounds finished."
  }
  if (level === "good") return "More of your voice. Some room stays."
  if (level === "best") return "Quieter room. May clip a word ending."
  return "Echo and noise cut for calls."
}

function isOmavoiceName(name) {
  var value = String(name || "")
  return value === NODE_NAME
    || value.indexOf("omavoice.") === 0
    || value.indexOf("capture.omavoice") === 0
}

function isOmavoiceNode(node) {
  if (!node) return false
  var name = String(node.name || "")
  if (name === NODE_NAME) return true
  if (name) return false
  return String(node.description || node.nickname || "") === NODE_DESCRIPTION
}

function isUsbSourceName(name) {
  return String(name || "").indexOf("alsa_input.usb-") === 0
}

function isCaptureSourceName(name) {
  var value = String(name || "")
  if (!value || isOmavoiceName(value)) return false
  if (value.indexOf("alsa_input.") === 0) return true
  if (value.indexOf("bluez_input.") === 0) return true
  if (value.indexOf("bluez_capture") === 0) return false
  return false
}

function sourceKind(name) {
  var value = String(name || "")
  if (isOmavoiceName(value)) return "omavoice"
  if (isUsbSourceName(value)) return "usb"
  if (value.indexOf("bluez_input.") === 0) return "bluetooth"
  if (value.indexOf("alsa_input.") === 0) return "builtin"
  return "other"
}

function bluetoothAddress(name) {
  var value = String(name || "")
  if (value.indexOf("bluez_input.") !== 0) return ""
  var rest = value.slice("bluez_input.".length)
  var match = rest.match(/^([0-9A-Fa-f]{2}[:_]){5}[0-9A-Fa-f]{2}/)
  if (!match) return ""
  return match[0].toUpperCase().replace(/_/g, ":")
}

function dedupeCaptureSources(list, preferName) {
  var rows = Array.isArray(list) ? list : []
  var prefer = String(preferName || "")
  var out = []
  var slot = {}
  for (var i = 0; i < rows.length; i++) {
    var row = rows[i]
    var addr = bluetoothAddress(row && row.name)
    if (!addr) {
      out.push(row)
      continue
    }
    if (slot[addr] === undefined) {
      slot[addr] = out.length
      out.push(row)
      continue
    }
    if (String(row.name || "") === prefer) out[slot[addr]] = row
  }
  return out
}

function friendlyDeviceLabel(text) {
  var label = String(text || "").trim()
  label = label.replace(/^sof-soundwire\s+/i, "")
  label = label.replace(/^built-?in audio\s+/i, "")
  label = label.replace(/\s+Analog Stereo$/i, "")
  label = label.replace(/\s+Mono$/i, "")
  label = label.replace(/\s+Input$/i, "")
  label = label.replace(/\s+Microphone[s]?$/i, "")
  label = label.replace(/^alsa_input\./, "")
  label = label.replace(/^usb-/, "")
  label = label.replace(/_/g, " ")
  return label || "Microphone"
}

function sourceSignature(list) {
  var parts = []
  var rows = Array.isArray(list) ? list : []
  for (var i = 0; i < rows.length; i++) {
    parts.push(String(rows[i].name || "") + "\t" + String(rows[i].description || ""))
  }
  return parts.join("\n")
}

function sourcesUnchanged(before, after) {
  return sourceSignature(before) === sourceSignature(after)
}

// Quickshell unbinds PwNode.name when the registry churns (host restart).
// An empty snapshot is a flicker, not "no microphones".
function shouldDeferSourcePick(currentName, hasUnboundNodes) {
  return !!String(currentName || "") && hasUnboundNodes === true
}

function pickFallbackName(defaultName, rememberedName) {
  if (isCaptureSourceName(defaultName)) return String(defaultName)
  if (isCaptureSourceName(rememberedName)) return String(rememberedName)
  return ""
}

function pickSource(sources, pinnedName, defaultName) {
  var list = Array.isArray(sources) ? sources : []
  function findName(name) {
    var want = String(name || "")
    if (!want) return null
    for (var i = 0; i < list.length; i++) {
      if (String(list[i].name || "") === want) return list[i]
    }
    return null
  }

  var pinned = findName(pinnedName)
  if (pinned && isCaptureSourceName(pinned.name)) return pinned

  var usb = []
  for (var j = 0; j < list.length; j++) {
    if (isUsbSourceName(list[j].name)) usb.push(list[j])
  }
  var fallback = findName(defaultName)
  if (fallback && isUsbSourceName(fallback.name)) return fallback
  if (usb.length === 1) return usb[0]
  if (usb.length > 1 && fallback && isUsbSourceName(fallback.name)) return fallback
  if (usb.length > 0) return usb[0]
  if (fallback && isCaptureSourceName(fallback.name)) return fallback
  for (var k = 0; k < list.length; k++) {
    if (sourceKind(list[k].name) === "builtin") return list[k]
  }
  var bluetooth = []
  for (var b = 0; b < list.length; b++) {
    if (sourceKind(list[b].name) === "bluetooth") bluetooth.push(list[b])
  }
  if (bluetooth.length > 0) return bluetooth[0]
  for (var n = 0; n < list.length; n++) {
    if (isCaptureSourceName(list[n].name)) return list[n]
  }
  return null
}

function restoreCaptureName(pinnedName, previousName, sources) {
  var list = Array.isArray(sources) ? sources : []
  function present(name) {
    var want = String(name || "")
    if (!want || !isCaptureSourceName(want) || isOmavoiceName(want)) return ""
    for (var i = 0; i < list.length; i++) {
      if (String(list[i].name || "") === want) return want
    }
    return ""
  }
  return present(pinnedName) || present(previousName)
}

function presetLabel(preset) {
  var value = normalizePreset(preset)
  if (value === "podcast") return "Podcast"
  if (value === "clean") return "Clean"
  return "Meeting"
}

function presetHint(preset) {
  var value = normalizePreset(preset)
  if (value === "podcast") return "Denoise, gate-like VAD, speech presence"
  if (value === "clean") return "High-pass only — keeps music and program"
  return "Echo cancel and RNNoise for calls"
}

function normalizeEngine(value) {
  var engine = String(value || "").toLowerCase()
  if (ENGINES.indexOf(engine) >= 0) return engine
  return "auto"
}

function engineForPreset(preset, haveRnnoise, haveDeepfilter) {
  var value = normalizePreset(preset)
  if (value === "clean") return "clean"
  if (value === "podcast" && haveDeepfilter) return "deepfilter"
  if (haveRnnoise) return "rnnoise"
  return "clean"
}

function resolveEngine(preset, engineSetting, haveRnnoise, haveDeepfilter) {
  var kind = normalizePreset(preset)
  if (kind === "clean") return "clean"
  var want = normalizeEngine(engineSetting)
  if (want === "rnnoise" || want === "deepfilter") return want
  return engineForPreset(kind, haveRnnoise, haveDeepfilter)
}

function engineChoiceHint(value) {
  var want = normalizeEngine(value)
  if (want === "rnnoise") return "Neural denoise. Never stacked with DeepFilterNet."
  if (want === "deepfilter") return "Heavier denoise. Never stacked with RNNoise."
  return "Meeting: RNNoise. Podcast: DeepFilterNet if installed, else RNNoise. Clean: none."
}

function engineLabel(engine) {
  var want = String(engine || "")
  if (want === "deepfilter") return "DeepFilterNet"
  if (want === "rnnoise") return "RNNoise"
  if (want === "clean") return "Clean"
  return "Auto"
}

function hostSwitchReason(prevKey, nextKey, reloading) {
  if (reloading) return "reload"
  var old = String(prevKey || "").split("\0")
  var neu = String(nextKey || "").split("\0")
  if (!old[0] || old.length < 4) return "start"
  if (old[0] !== neu[0]) return "preset"
  if (old[1] !== neu[1]) return "engine"
  if (old[2] !== neu[2]) return "target"
  return "start"
}

function busyStatusText(reason, preset, engineSetting) {
  if (reason === "engine") return "Starting " + engineLabel(engineSetting) + "…"
  if (reason === "target") return "Switching microphone…"
  if (reason === "reload") return "Reloading…"
  return "Starting " + presetLabel(preset) + "…"
}

function clampGainDb(value) {
  var n = Number(value)
  if (!isFinite(n)) return 0
  if (n < -12) return -12
  if (n > 12) return 12
  return n
}

function clampEqTrimDb(value) {
  var n = Number(value)
  if (!isFinite(n)) return 0
  if (n < -6) return -6
  if (n > 6) return 6
  return n
}

function snapEqTrimDb(value) {
  var n = clampEqTrimDb(value)
  if (Math.abs(n) <= 0.4) return 0
  return Math.round(n * 2) / 2
}

function clampEqBandDb(value) {
  var n = Number(value)
  if (!isFinite(n)) return 0
  if (n < -12) return -12
  if (n > 12) return 12
  return n
}

function aliasEqCurve(value) {
  var curve = String(value || "").toLowerCase()
  if (curve === "presence") return "clear"
  if (curve === "air") return "bright"
  return curve
}

function normalizeEqCurve(value, fallback) {
  var curve = aliasEqCurve(value)
  if (EQ_CURVES.indexOf(curve) >= 0) return curve
  var def = aliasEqCurve(fallback || "neutral")
  if (EQ_CURVES.indexOf(def) >= 0) return def
  return "neutral"
}

function eqCurveParams(curve) {
  var c = normalizeEqCurve(curve, "neutral")
  if (c === "warm") return { hpHz: 80, body: 2.0, pres: -1.5, air: 0 }
  if (c === "clear") return { hpHz: 80, body: -2.5, pres: 2.0, air: 0 }
  if (c === "bright") return { hpHz: 100, body: 0, pres: 1.0, air: 2.5 }
  return { hpHz: 80, body: 0, pres: 0, air: 0 }
}

function eqCurveForPreset(preset, values) {
  if (normalizePreset(preset) === "clean") return ""
  var src = values || {}
  if (normalizePreset(preset) === "podcast") return normalizeEqCurve(src.podcastEq, "clear")
  return normalizeEqCurve(src.meetingEq, "warm")
}

function eqTrimForPreset(preset, values) {
  var src = values || {}
  var kind = normalizePreset(preset)
  if (kind === "clean") return { body: 0, pres: 0, air: 0 }
  if (kind === "podcast") {
    return {
      body: clampEqTrimDb(src.podcastEqBodyDb),
      pres: clampEqTrimDb(src.podcastEqPresenceDb),
      air: clampEqTrimDb(src.podcastEqAirDb)
    }
  }
  return {
    body: clampEqTrimDb(src.meetingEqBodyDb),
    pres: clampEqTrimDb(src.meetingEqPresenceDb),
    air: clampEqTrimDb(src.meetingEqAirDb)
  }
}

function eqBandGains(curve, trim) {
  var c = eqCurveParams(curve)
  var t = trim || {}
  return {
    hpHz: c.hpHz,
    body: clampEqBandDb(c.body + clampEqTrimDb(t.body)),
    pres: clampEqBandDb(c.pres + clampEqTrimDb(t.pres)),
    air: clampEqBandDb(c.air + clampEqTrimDb(t.air))
  }
}

function eqBandBase(curve, band) {
  var c = eqCurveParams(curve)
  if (band === "pres") return c.pres
  if (band === "air") return c.air
  return c.body
}

function eqBandRange(curve, band) {
  var base = eqBandBase(curve, band)
  return {
    min: clampEqBandDb(base - 6),
    max: clampEqBandDb(base + 6)
  }
}

function snapEqBandDb(curve, band, value) {
  var r = eqBandRange(curve, band)
  var n = Number(value)
  if (!isFinite(n)) n = eqBandBase(curve, band)
  if (n < r.min) n = r.min
  if (n > r.max) n = r.max
  if (Math.abs(n) <= 0.4) n = 0
  n = Math.round(n * 2) / 2
  if (n < r.min) n = r.min
  if (n > r.max) n = r.max
  return n
}

function eqCurveHint(value) {
  var c = normalizeEqCurve(value, "neutral")
  if (c === "warm") return "A little low end. Less edge."
  if (c === "clear") return "Cut the box. Speech a bit forward."
  if (c === "bright") return "Higher high-pass and a gentle top."
  return "High-pass only. No color."
}

function snapGainDb(value) {
  var n = clampGainDb(value)
  if (Math.abs(n) <= 0.4) return 0
  return Math.round(n * 2) / 2
}

function gainDbToLinear(db) {
  return Math.pow(10, clampGainDb(db) / 20)
}

function hasGain(src, key) {
  return src && src[key] !== undefined && src[key] !== null && src[key] !== ""
}

function gainDbFromKeys(src, keys) {
  for (var i = 0; i < keys.length; i++) {
    if (hasGain(src, keys[i])) return clampGainDb(src[keys[i]])
  }
  return 0
}

function outputGainDbForPreset(preset, values) {
  var kind = normalizePreset(preset)
  var first = "meetingOutputGainDb"
  if (kind === "podcast") first = "podcastOutputGainDb"
  else if (kind === "clean") first = "cleanOutputGainDb"
  return gainDbFromKeys(values || {}, ["outputGainDb", first, "meetingOutputGainDb", "podcastOutputGainDb", "cleanOutputGainDb"])
}

function captureGainDbForPreset(preset, values) {
  var kind = normalizePreset(preset)
  var first = "meetingCaptureGainDb"
  if (kind === "podcast") first = "podcastCaptureGainDb"
  else if (kind === "clean") first = "cleanCaptureGainDb"
  return gainDbFromKeys(values || {}, ["captureGainDb", first, "meetingCaptureGainDb", "podcastCaptureGainDb", "cleanCaptureGainDb"])
}

function sharedGainPatch(kind, db) {
  var n = snapGainDb(db)
  if (kind === "capture") {
    return {
      captureGainDb: n,
      meetingCaptureGainDb: n,
      podcastCaptureGainDb: n,
      cleanCaptureGainDb: n
    }
  }
  return {
    outputGainDb: n,
    meetingOutputGainDb: n,
    podcastOutputGainDb: n,
    cleanOutputGainDb: n
  }
}

function qualityParams(preset, quality) {
  var kind = normalizePreset(preset)
  var level = normalizeQuality(quality)
  if (kind === "podcast") {
    if (level === "good") return { vad: 75.0, grace: 400, dfn: 50 }
    if (level === "best") return { vad: 90.0, grace: 150, dfn: 85 }
    return { vad: 85.0, grace: 200, dfn: 70 }
  }
  if (level === "good") return { vad: 70.0, grace: 500, dfn: 50 }
  if (level === "best") return { vad: 85.0, grace: 250, dfn: 85 }
  return { vad: 80.0, grace: 400, dfn: 70 }
}

function setupGuide(engine, haveRnnoise, haveDeepfilter, preset) {
  var kind = normalizePreset(preset)
  var want = normalizeEngine(engine)
  var none = { needed: false, hero: "", command: "", body: "" }

  function rnnoiseRow() {
    return {
      needed: true,
      hero: "Install RNNoise",
      command: "omarchy pkg add noise-suppression-for-voice",
      body: "This engine needs the RNNoise LADSPA plugin. Clean still works without it."
    }
  }

  function dfnRow() {
    return {
      needed: true,
      hero: "Install DeepFilterNet",
      command: "omarchy pkg aur add libdeep_filter_ladspa-bin",
      body: "DeepFilterNet is not installed. Reload after installing it."
    }
  }

  if (kind === "clean") return none
  if (want === "rnnoise") return haveRnnoise ? none : rnnoiseRow()
  if (want === "deepfilter") return haveDeepfilter ? none : dfnRow()
  if (kind === "podcast" && haveDeepfilter) return none
  if (haveRnnoise) return none
  return rnnoiseRow()
}

function hostErrorText(kind, raw) {
  var t = String(raw || "")
  if (kind === "probe") return "Could not check audio plugins."
  if (t.indexOf("session PipeWire did not answer") >= 0) return "PipeWire did not answer."
  return "Could not start the microphone."
}

function statusText(state) {
  state = state || {}
  if (!state.enabled) return "Off"
  if (state.setupNeeded && normalizePreset(state.preset) !== "clean") {
    return String(state.setupHero || "Plugin not installed")
  }
  if (!state.targetName) return "No microphone"
  if (state.busyReason) return busyStatusText(state.busyReason, state.preset, state.engineSetting)
  if (state.running) return presetLabel(state.preset) + " · " + friendlyDeviceLabel(state.targetLabel || state.targetName)
  if (state.busy) return busyStatusText("start", state.preset, state.engineSetting)
  return "Idle"
}

if (typeof module !== "undefined") {
  module.exports = {
    NODE_NAME: NODE_NAME,
    CAPTURE_NAME: CAPTURE_NAME,
    NODE_DESCRIPTION: NODE_DESCRIPTION,
    PRESETS: PRESETS,
    QUALITIES: QUALITIES,
    ENGINES: ENGINES,
    EQ_CURVES: EQ_CURVES,
    normalizePreset: normalizePreset,
    normalizeQuality: normalizeQuality,
    qualityIndex: qualityIndex,
    qualityFromIndex: qualityFromIndex,
    qualityLabel: qualityLabel,
    qualityHint: qualityHint,
    isOmavoiceName: isOmavoiceName,
    isOmavoiceNode: isOmavoiceNode,
    isUsbSourceName: isUsbSourceName,
    isCaptureSourceName: isCaptureSourceName,
    sourceKind: sourceKind,
    bluetoothAddress: bluetoothAddress,
    dedupeCaptureSources: dedupeCaptureSources,
    friendlyDeviceLabel: friendlyDeviceLabel,
    sourceSignature: sourceSignature,
    sourcesUnchanged: sourcesUnchanged,
    shouldDeferSourcePick: shouldDeferSourcePick,
    pickFallbackName: pickFallbackName,
    pickSource: pickSource,
    restoreCaptureName: restoreCaptureName,
    presetLabel: presetLabel,
    presetHint: presetHint,
    normalizeEngine: normalizeEngine,
    engineForPreset: engineForPreset,
    resolveEngine: resolveEngine,
    engineChoiceHint: engineChoiceHint,
    engineLabel: engineLabel,
    hostSwitchReason: hostSwitchReason,
    busyStatusText: busyStatusText,
    clampGainDb: clampGainDb,
    clampEqTrimDb: clampEqTrimDb,
    snapEqTrimDb: snapEqTrimDb,
    clampEqBandDb: clampEqBandDb,
    normalizeEqCurve: normalizeEqCurve,
    eqCurveParams: eqCurveParams,
    eqCurveForPreset: eqCurveForPreset,
    eqTrimForPreset: eqTrimForPreset,
    eqBandGains: eqBandGains,
    eqBandBase: eqBandBase,
    eqBandRange: eqBandRange,
    snapEqBandDb: snapEqBandDb,
    eqCurveHint: eqCurveHint,
    snapGainDb: snapGainDb,
    gainDbToLinear: gainDbToLinear,
    outputGainDbForPreset: outputGainDbForPreset,
    captureGainDbForPreset: captureGainDbForPreset,
    sharedGainPatch: sharedGainPatch,
    qualityParams: qualityParams,
    setupGuide: setupGuide,
    hostErrorText: hostErrorText,
    statusText: statusText
  }
}
