const test = require("node:test")
const assert = require("node:assert/strict")
const Model = require("../Model.js")

const usb = {
  name: "alsa_input.usb-QUALCOMM_QCS_KALAMAP-HDK-00.analog-stereo",
  description: "QUALCOMM QCS KALAMAP Analog Stereo"
}
const usb2 = {
  name: "alsa_input.usb-DJI_OsmoAction6_SN-01.analog-stereo",
  description: "DJI Osmo Action 6"
}
const builtin = {
  name: "alsa_input.pci-0000_00_1f.3-platform-sof_sdw.HiFi__Mic__source",
  description: "Microphones"
}
const omavoice = {
  name: "omavoice",
  description: "Omavoice"
}

test("normalizePreset falls back to meeting", () => {
  assert.equal(Model.normalizePreset("podcast"), "podcast")
  assert.equal(Model.normalizePreset("CLEAN"), "clean")
  assert.equal(Model.normalizePreset("nope"), "meeting")
  assert.equal(Model.normalizePreset(""), "meeting")
})

test("isOmavoiceNode matches name or description when name is still unbound", () => {
  assert.equal(Model.isOmavoiceNode({ name: "omavoice" }), true)
  assert.equal(Model.isOmavoiceNode({ name: "omavoice.aec" }), false)
  assert.equal(Model.isOmavoiceNode({ name: "", description: "Omavoice" }), true)
  assert.equal(Model.isOmavoiceNode({ name: "", description: "Omavoice echo cancel" }), false)
  assert.equal(Model.isOmavoiceNode({ name: "", description: "Microphones" }), false)
  assert.equal(Model.isOmavoiceNode(null), false)
})

test("USB and omavoice name detection", () => {
  assert.equal(Model.isUsbSourceName(usb.name), true)
  assert.equal(Model.isUsbSourceName(builtin.name), false)
  assert.equal(Model.isOmavoiceName("omavoice"), true)
  assert.equal(Model.isOmavoiceName("omavoice.aec"), true)
  assert.equal(Model.isCaptureSourceName("omavoice"), false)
  assert.equal(Model.isCaptureSourceName(usb.name), true)
})

test("sourcesUnchanged ignores object identity and node ids", () => {
  const a = [{ name: usb.name, description: usb.description, id: 1 }]
  const b = [{ name: usb.name, description: usb.description, id: 99 }]
  assert.equal(Model.sourcesUnchanged(a, b), true)
  assert.equal(Model.sourcesUnchanged(a, [usb, builtin]), false)
})

test("pickSource prefers a pinned USB node", () => {
  const picked = Model.pickSource([builtin, usb, usb2], usb2.name, builtin.name)
  assert.equal(picked.name, usb2.name)
})

test("pickSource ignores a stale pin and prefers USB over the laptop mic", () => {
  const picked = Model.pickSource([builtin, usb], "alsa_input.usb-gone", builtin.name)
  assert.equal(picked.name, usb.name)
})

test("pickSource uses the default when it is the only USB match among several", () => {
  const picked = Model.pickSource([usb, usb2, builtin], "", usb.name)
  assert.equal(picked.name, usb.name)
})

test("pickSource falls back to the default builtin when no USB is present", () => {
  const picked = Model.pickSource([builtin, omavoice], "", builtin.name)
  assert.equal(picked.name, builtin.name)
})

test("normalizeQuality defaults to better", () => {
  assert.equal(Model.normalizeQuality("good"), "good")
  assert.equal(Model.normalizeQuality("BEST"), "best")
  assert.equal(Model.normalizeQuality(""), "better")
  assert.equal(Model.normalizeQuality("nope"), "better")
  assert.equal(Model.qualityIndex("better"), 1)
  assert.equal(Model.qualityFromIndex(0), "good")
  assert.equal(Model.qualityFromIndex(2), "best")
  assert.equal(Model.qualityFromIndex(99), "best")
  assert.equal(Model.qualityLabel("good"), "Softer")
  assert.equal(Model.qualityLabel("better"), "Balanced")
  assert.equal(Model.qualityLabel("best"), "Stronger")
  assert.match(Model.qualityHint("meeting", "good"), /voice/)
  assert.match(Model.qualityHint("meeting", "best"), /clip/)
  assert.match(Model.qualityHint("podcast", "best"), /Heavier/)
})

test("shouldDeferSourcePick keeps the mic while PipeWire names are unbound", () => {
  assert.equal(Model.shouldDeferSourcePick(usb.name, true), true)
  assert.equal(Model.shouldDeferSourcePick(usb.name, false), false)
  assert.equal(Model.shouldDeferSourcePick("", true), false)
  assert.equal(Model.shouldDeferSourcePick(null, true), false)
})

test("engineForPreset uses DeepFilterNet only for podcast when present", () => {
  assert.equal(Model.engineForPreset("clean", true, true), "clean")
  assert.equal(Model.engineForPreset("meeting", true, true), "rnnoise")
  assert.equal(Model.engineForPreset("podcast", true, true), "deepfilter")
  assert.equal(Model.engineForPreset("podcast", true, false), "rnnoise")
  assert.equal(Model.engineForPreset("meeting", false, false), "clean")
})

test("setupGuide asks for RNNoise when the LADSPA plugin is missing", () => {
  const missing = Model.setupGuide(false)
  assert.equal(missing.needed, true)
  assert.match(missing.command, /noise-suppression-for-voice/)
  assert.equal(Model.setupGuide(true).needed, false)
})

test("statusText reports the live preset and device", () => {
  const text = Model.statusText({
    enabled: true,
    running: true,
    preset: "meeting",
    targetName: usb.name,
    targetLabel: usb.description
  })
  assert.match(text, /Meeting/)
  assert.match(text, /QUALCOMM/)
})
