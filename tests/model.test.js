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

const bluez = {
  name: "bluez_input.A0:0C:E2:D0:C3:81",
  description: "OpenFit Pro by Shokz"
}

test("pickFallbackName ignores omavoice and keeps a remembered capture", () => {
  assert.equal(Model.pickFallbackName(builtin.name, bluez.name), builtin.name)
  assert.equal(Model.pickFallbackName("omavoice", bluez.name), bluez.name)
  assert.equal(Model.pickFallbackName("omavoice", "omavoice"), "")
  assert.equal(Model.pickFallbackName("", ""), "")
})

test("pickSource uses a remembered BT headset when default is already omavoice", () => {
  const fallback = Model.pickFallbackName("omavoice", bluez.name)
  const picked = Model.pickSource([builtin, bluez], "", fallback)
  assert.equal(picked.name, bluez.name)
})

test("restoreCaptureName prefers the pin over a remembered bluetooth source", () => {
  assert.equal(Model.restoreCaptureName(builtin.name, bluez.name, [builtin, bluez]), builtin.name)
  assert.equal(Model.restoreCaptureName("", bluez.name, [builtin, bluez]), bluez.name)
  assert.equal(Model.restoreCaptureName("omavoice", bluez.name, [builtin, bluez]), bluez.name)
  assert.equal(Model.restoreCaptureName("", "omavoice", [builtin, bluez]), "")
  assert.equal(Model.restoreCaptureName("alsa_input.usb-gone", "", [builtin, bluez]), "")
})

test("pickSource prefers builtin over unpinned bluetooth", () => {
  const fallback = Model.pickFallbackName("omavoice", "")
  const picked = Model.pickSource([builtin, bluez], "", fallback)
  assert.equal(picked.name, builtin.name)
})

test("bluetoothAddress normalizes colon and underscore MACs", () => {
  assert.equal(Model.bluetoothAddress("bluez_input.A0:0C:E2:D0:C3:81"), "A0:0C:E2:D0:C3:81")
  assert.equal(Model.bluetoothAddress("bluez_input.A0_0C_E2_D0_C3_81.0"), "A0:0C:E2:D0:C3:81")
  assert.equal(Model.bluetoothAddress(builtin.name), "")
})

test("dedupeCaptureSources keeps one bluez row per address", () => {
  const twin = { name: "bluez_input.A0_0C_E2_D0_C3_81.headset-head-unit", description: bluez.description }
  const rows = Model.dedupeCaptureSources([builtin, bluez, twin], "")
  assert.equal(rows.length, 2)
  assert.equal(rows[0].name, builtin.name)
  assert.equal(rows[1].name, bluez.name)
  const preferred = Model.dedupeCaptureSources([bluez, twin], twin.name)
  assert.equal(preferred.length, 1)
  assert.equal(preferred[0].name, twin.name)
})

test("eqCurveParams matches the 0.3 voice table", () => {
  assert.deepEqual(Model.eqCurveParams("neutral"), { hpHz: 80, body: 0, pres: 0, air: 0 })
  assert.deepEqual(Model.eqCurveParams("warm"), { hpHz: 80, body: 2.0, pres: -1.5, air: 0 })
  assert.deepEqual(Model.eqCurveParams("clear"), { hpHz: 80, body: -2.5, pres: 2.0, air: 0 })
  assert.deepEqual(Model.eqCurveParams("bright"), { hpHz: 100, body: 0, pres: 1.0, air: 2.5 })
  assert.equal(Model.eqCurveParams("nope").hpHz, 80)
})

test("eqCurveForPreset maps old Presence/Air looks and defaults Clear on Podcast", () => {
  assert.equal(Model.normalizeEqCurve("presence"), "clear")
  assert.equal(Model.normalizeEqCurve("air"), "bright")
  assert.equal(Model.eqCurveForPreset("meeting", {}), "warm")
  assert.equal(Model.eqCurveForPreset("podcast", {}), "clear")
  assert.equal(Model.eqCurveForPreset("clean", { meetingEq: "bright" }), "")
  assert.equal(Model.eqCurveForPreset("meeting", { meetingEq: "air" }), "bright")
  assert.equal(Model.eqCurveForPreset("podcast", { podcastEq: "presence" }), "clear")
})

test("eqBandGains adds trim and clamps to 12 dB", () => {
  const clear = Model.eqBandGains("clear", { body: 1 })
  assert.equal(clear.body, -1.5)
  assert.equal(clear.pres, 2.0)
  assert.equal(Model.eqBandGains("warm", { body: 12 }).body, 8)
  assert.equal(Model.eqBandGains("bright", { air: -6 }).air, -3.5)
  assert.equal(Model.snapEqTrimDb(0.3), 0)
  assert.equal(Model.snapEqTrimDb(1.24), 1)
  assert.equal(Model.clampEqTrimDb(9), 6)
})

test("Clean ignores voice EQ trim", () => {
  const trim = Model.eqTrimForPreset("clean", { meetingEqBodyDb: 4, podcastEqBodyDb: 3 })
  assert.deepEqual(trim, { body: 0, pres: 0, air: 0 })
})

test("eqTrimForPreset reads only the active preset schema keys", () => {
  assert.deepEqual(
    Model.eqTrimForPreset("meeting", { meetingEqBodyDb: 4, podcastEqBodyDb: 3, podcastEqPresenceDb: 2 }),
    { body: 4, pres: 0, air: 0 }
  )
  assert.deepEqual(
    Model.eqTrimForPreset("podcast", { meetingEqBodyDb: 4, podcastEqPresenceDb: 2, podcastEqAirDb: -1 }),
    { body: 0, pres: 2, air: -1 }
  )
  assert.equal(Model.eqTrimForPreset("meeting", { meetingEqBodyDb: 9 }).body, 6)
  assert.equal(Model.eqTrimForPreset("meeting", { meetingEqPresenceDb: "nope" }).pres, 0)
})

test("eqBandRange is the look ±6 clamp for Voice writes", () => {
  assert.deepEqual(Model.eqBandRange("neutral", "body"), { min: -6, max: 6 })
  assert.deepEqual(Model.eqBandRange("warm", "body"), { min: -4, max: 8 })
  assert.deepEqual(Model.eqBandRange("clear", "body"), { min: -8.5, max: 3.5 })
  assert.deepEqual(Model.eqBandRange("bright", "air"), { min: -3.5, max: 8.5 })
  assert.equal(Model.snapEqBandDb("warm", "body", 12), 8)
  assert.equal(Model.snapEqBandDb("warm", "body", -12), -4)
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

test("resolveEngine honors an explicit picker and keeps Clean HPF-only", () => {
  assert.equal(Model.normalizeEngine(""), "auto")
  assert.equal(Model.normalizeEngine("DEEPFILTER"), "deepfilter")
  assert.equal(Model.resolveEngine("meeting", "auto", true, true), "rnnoise")
  assert.equal(Model.resolveEngine("podcast", "auto", true, true), "deepfilter")
  assert.equal(Model.resolveEngine("meeting", "deepfilter", true, true), "deepfilter")
  assert.equal(Model.resolveEngine("podcast", "rnnoise", true, true), "rnnoise")
  assert.equal(Model.resolveEngine("meeting", "deepfilter", true, false), "deepfilter")
  assert.equal(Model.resolveEngine("clean", "deepfilter", true, true), "clean")
  assert.equal(Model.resolveEngine("clean", "auto", true, true), "clean")
})

test("engine copy names the picker tips", () => {
  assert.match(Model.engineChoiceHint("auto"), /Meeting/)
  assert.match(Model.engineChoiceHint("rnnoise"), /Never stacked/)
  assert.match(Model.engineChoiceHint("deepfilter"), /Heavier/)
})

test("clampGainDb and gainDbToLinear convert output trim", () => {
  assert.equal(Model.clampGainDb(0), 0)
  assert.equal(Model.clampGainDb(-20), -12)
  assert.equal(Model.clampGainDb(20), 12)
  assert.equal(Model.clampGainDb("nope"), 0)
  assert.equal(Model.clampGainDb(undefined), 0)
  assert.equal(Model.gainDbToLinear(0), 1)
  assert.ok(Math.abs(Model.gainDbToLinear(6) - 2) < 0.01)
  assert.ok(Math.abs(Model.gainDbToLinear(-6) - 0.5) < 0.01)
  assert.equal(Model.snapGainDb(0.2), 0)
  assert.equal(Model.snapGainDb(-0.4), 0)
  assert.equal(Model.snapGainDb(0.5), 0.5)
  assert.equal(Model.snapGainDb(0.76), 1)
  assert.equal(Model.snapGainDb(-1.24), -1)
  assert.equal(Model.snapGainDb(20), 12)
  const all = {
    meetingOutputGainDb: 1,
    podcastOutputGainDb: 2,
    cleanOutputGainDb: 3,
    meetingCaptureGainDb: 4,
    podcastCaptureGainDb: 5,
    cleanCaptureGainDb: 6
  }
  assert.equal(Model.outputGainDbForPreset("meeting", all), 1)
  assert.equal(Model.outputGainDbForPreset("podcast", all), 2)
  assert.equal(Model.outputGainDbForPreset("clean", all), 3)
  assert.equal(Model.captureGainDbForPreset("meeting", all), 4)
  assert.equal(Model.outputGainDbForPreset("podcast", { outputGainDb: 7, ...all }), 7)
  assert.equal(Model.captureGainDbForPreset("clean", { captureGainDb: -1, ...all }), -1)
  assert.equal(Model.outputGainDbForPreset("meeting", { outputGainDb: 2 }), 2)
  assert.equal(Model.outputGainDbForPreset("podcast", { outputGainDb: 2 }), 2)
  assert.equal(Model.outputGainDbForPreset("clean", { outputGainDb: 2 }), 2)
  assert.equal(Model.outputGainDbForPreset("clean", {}), 0)
  assert.deepEqual(Model.sharedGainPatch("output", 2), {
    outputGainDb: 2,
    meetingOutputGainDb: 2,
    podcastOutputGainDb: 2,
    cleanOutputGainDb: 2
  })
  assert.equal(Model.sharedGainPatch("capture", 1.24).meetingCaptureGainDb, 1)
})

test("qualityParams matches the dump VAD / DFN tables", () => {
  assert.deepEqual(Model.qualityParams("meeting", "better"), { vad: 80.0, grace: 400, dfn: 70 })
  assert.deepEqual(Model.qualityParams("meeting", "good"), { vad: 70.0, grace: 500, dfn: 50 })
  assert.deepEqual(Model.qualityParams("meeting", "best"), { vad: 85.0, grace: 250, dfn: 85 })
  assert.deepEqual(Model.qualityParams("podcast", "better"), { vad: 85.0, grace: 200, dfn: 70 })
  assert.deepEqual(Model.qualityParams("podcast", "good"), { vad: 75.0, grace: 400, dfn: 50 })
  assert.deepEqual(Model.qualityParams("podcast", "best"), { vad: 90.0, grace: 150, dfn: 85 })
})

test("setupGuide asks for the chosen engine when the plugin is missing", () => {
  const missingRn = Model.setupGuide("auto", false, false, "meeting")
  assert.equal(missingRn.needed, true)
  assert.match(missingRn.command, /noise-suppression-for-voice/)
  assert.equal(Model.setupGuide("auto", true, false, "meeting").needed, false)
  assert.equal(Model.setupGuide("auto", false, false, "clean").needed, false)
  assert.equal(Model.setupGuide("auto", false, true, "podcast").needed, false)
  const missingDfn = Model.setupGuide("deepfilter", true, false, "meeting")
  assert.equal(missingDfn.needed, true)
  assert.match(missingDfn.command, /libdeep_filter_ladspa-bin/)
  const missingForcedRn = Model.setupGuide("rnnoise", false, true, "podcast")
  assert.equal(missingForcedRn.needed, true)
  assert.match(missingForcedRn.command, /noise-suppression-for-voice/)
  assert.equal(Model.setupGuide("rnnoise", false, false, "clean").needed, false)
  assert.equal(Model.setupGuide("deepfilter", false, false, "clean").needed, false)
})

test("hostErrorText is one short sentence", () => {
  assert.equal(Model.hostErrorText("bind"), "Could not start the microphone.")
  assert.equal(Model.hostErrorText("probe"), "Could not check audio plugins.")
  assert.equal(Model.hostErrorText("host", "omavoice-run: session PipeWire did not answer"), "PipeWire did not answer.")
  assert.equal(Model.hostErrorText("host", "can't load config /run/user/1000/omavoice/host.1.conf"), "Could not start the microphone.")
})

test("statusText does not repeat lastError", () => {
  const text = Model.statusText({
    enabled: true,
    running: false,
    lastError: "Could not start the microphone.",
    targetName: usb.name
  })
  assert.equal(text, "Idle")
  assert.equal(text.includes("Could not start"), false)
})

test("statusText does not report a missing engine on Clean", () => {
  const text = Model.statusText({
    enabled: true,
    running: true,
    setupNeeded: true,
    setupHero: "Install RNNoise",
    preset: "clean",
    targetName: usb.name,
    targetLabel: usb.description
  })
  assert.match(text, /Clean/)
  assert.equal(text.includes("Install RNNoise"), false)
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

test("statusText names the preset while the host is starting", () => {
  const text = Model.statusText({
    enabled: true,
    running: false,
    busy: true,
    preset: "podcast",
    targetName: usb.name
  })
  assert.equal(text, "Starting Podcast…")
})

test("statusText names the duck: engine, mic, reload", () => {
  assert.equal(Model.busyStatusText("engine", "meeting", "deepfilter"), "Starting DeepFilterNet…")
  assert.equal(Model.busyStatusText("target", "meeting", "auto"), "Switching microphone…")
  assert.equal(Model.busyStatusText("reload", "meeting", "auto"), "Reloading…")
  assert.equal(Model.statusText({
    enabled: true,
    running: true,
    busyReason: "preset",
    preset: "clean",
    targetName: usb.name
  }), "Starting Clean…")
})

test("hostSwitchReason prefers preset over engine", () => {
  const prev = "meeting\0rnnoise\0mic\0/dir"
  const next = "podcast\0deepfilter\0mic\0/dir"
  assert.equal(Model.hostSwitchReason(prev, next, false), "preset")
  assert.equal(Model.hostSwitchReason(prev, "meeting\0deepfilter\0mic\0/dir", false), "engine")
  assert.equal(Model.hostSwitchReason(prev, "meeting\0rnnoise\0usb\0/dir", false), "target")
  assert.equal(Model.hostSwitchReason(prev, next, true), "reload")
  assert.equal(Model.hostSwitchReason("", next, false), "start")
})
