var NODE_NAME = "omavoice"
var NODE_DESCRIPTION = "Omavoice"
var PRESETS = ["meeting", "podcast", "clean"]

function normalizePreset(value) {
  var preset = String(value || "").toLowerCase()
  if (PRESETS.indexOf(preset) >= 0) return preset
  return "meeting"
}

function isOmavoiceName(name) {
  var value = String(name || "")
  return value === NODE_NAME
    || value.indexOf("omavoice.") === 0
    || value.indexOf("capture.omavoice") === 0
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
    if (isCaptureSourceName(list[k].name)) return list[k]
  }
  return null
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

function engineForPreset(preset, haveRnnoise, haveDeepfilter) {
  var value = normalizePreset(preset)
  if (value === "clean") return "clean"
  if (value === "podcast" && haveDeepfilter) return "deepfilter"
  if (haveRnnoise) return "rnnoise"
  return "clean"
}

function setupGuide(haveRnnoise) {
  if (haveRnnoise) {
    return { needed: false, hero: "", command: "", body: "" }
  }
  return {
    needed: true,
    hero: "Install RNNoise",
    command: "omarchy pkg add noise-suppression-for-voice",
    body: "Meeting and Podcast presets need the RNNoise LADSPA plugin. Clean still works without it."
  }
}

function statusText(state) {
  state = state || {}
  if (state.lastError) return String(state.lastError)
  if (!state.enabled) return "Off"
  if (state.setupNeeded) return "RNNoise not installed"
  if (!state.targetName) return "No microphone"
  if (state.running) return presetLabel(state.preset) + " · " + friendlyDeviceLabel(state.targetLabel || state.targetName)
  if (state.busy) return "Starting…"
  return "Idle"
}

if (typeof module !== "undefined") {
  module.exports = {
    NODE_NAME: NODE_NAME,
    NODE_DESCRIPTION: NODE_DESCRIPTION,
    PRESETS: PRESETS,
    normalizePreset: normalizePreset,
    isOmavoiceName: isOmavoiceName,
    isUsbSourceName: isUsbSourceName,
    isCaptureSourceName: isCaptureSourceName,
    sourceKind: sourceKind,
    friendlyDeviceLabel: friendlyDeviceLabel,
    pickSource: pickSource,
    presetLabel: presetLabel,
    presetHint: presetHint,
    engineForPreset: engineForPreset,
    setupGuide: setupGuide,
    statusText: statusText
  }
}
