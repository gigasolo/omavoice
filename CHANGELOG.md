# Changelog

All notable changes to Omavoice are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.16] — 2026-09-04

### Changed

- Bar, panel, and README use the original microphone mark again.

## [0.1.15] — 2026-09-04

### Changed

- Bar, panel, and README use the rendered wave orb (`4.jpg`) as a PNG, so
  the mark matches the image instead of a traced SVG.

## [0.1.14] — 2026-09-04

### Changed

- Preset tuning lives on PRESET: a wrench flips to Softer / Balanced /
  Stronger for Meeting and Podcast.
- Auto-select sits on the MICROPHONE header, next to the device list.
- The hero is on/off only. Each control sits in the section it belongs to.

## [0.1.13] — 2026-09-04

### Changed

- Wave mark is a close-cropped orb with four long arcs, matching the
  reference image — not a small circle with short ticks.

## [0.1.12] — 2026-09-04

### Changed

- Processing stops are **Softer**, **Balanced**, and **Stronger**, with a
  line of copy that says what each does for Meeting and Podcast.
- Mark is the long-wave orb as SVG, used in the bar, the panel, and the
  README.

## [0.1.11] — 2026-09-04

### Added

- Settings has a three-stop slider for **Meeting** and **Podcast**: Good,
  Better, Best. Default is Better (today’s tune). Good is gentler; Best
  is tighter. Clean is unchanged.

## [0.1.10] — 2026-09-04

### Changed

- On/off is the original pill toggle again. Settings is a matching bordered
  button, same height, centered with it.
- Mark is a square **O** with the mic capsule cut out, so it no longer
  squashes a portrait silhouette into a square.

## [0.1.9] — 2026-09-04

### Changed

- Header matches HEY: a larger microphone, with settings and power as the
  same icon buttons, vertically centered.

## [0.1.8] — 2026-09-04

### Changed

- Meeting VAD is 80% with a 400 ms grace so word endings are not clipped.
- README banner uses the same microphone as the bar, with the line **Your
  voice, better heard.** The lead no longer talks about a record button.

### Added

- A settings page, flipped like HEY: cog on the hero, back arrow to return.
  One control — **Default microphone** — so apps pick Omavoice automatically.

## [0.1.7] — 2026-09-04

### Fixed

- Preset and on/off switches no longer drop the selected mic while PipeWire
  rebinds node names, which was restarting the host extra times and making
  the call stutter.
- After meters wait for the new Omavoice node before `pw-cat` holds the
  graph, and they refuse to fall back to another source. Peak monitors are
  rebound after each graph generation so Before/After stay honest without
  closing the panel.

## [0.1.6] — 2026-09-04

### Changed

- Peak meters sit on the microphone rows. Each row shows that device’s live
  level; the selected row adds a hairline **After** for Omavoice. The silent
  `pw-cat` hold still runs while the panel is open so After moves without a
  call.

### Removed

- Listen (headphones), including the panel toggle, middle-click, and `l`.
  The chain is what Zoom hears; a speaker monitor was a feedback trap.

## [0.1.5] — 2026-09-04

### Added

- Open panel shows Before and After peak meters (raw mic vs Omavoice), using
  the same PipeWire peak monitor as the Omarchy audio panel. A silent
  `pw-cat` hold keeps the filter-chain flowing so After moves without a
  call. Meters and the hold stop when the panel closes.

## [0.1.4] — 2026-09-04

### Changed

- Bar mark is a microphone, tinted like HEY’s SVG icon, with a tooltip for
  off / preset / error.

## [0.1.3] — 2026-09-04

### Fixed

- Meeting no longer registers **Omavoice echo cancel** as a second microphone.
  That node is the AEC stage feeding Omavoice; it is now
  `Stream/Output/Audio/Internal` so pickers only show **Omavoice**.

## [0.1.2] — 2026-09-04

### Fixed

- Meeting echo cancel now uses `monitor.mode = true` so WebRTC AEC reads the
  default sink’s monitor instead of a virtual sink Zoom/Meet never play into.
  The isolated client maps `audio.aec` to `libspa-aec-webrtc`; without that
  the module was skipped. Do not force MONO/`node.latency` on the AEC module
  itself — that SIGFPE’d against a stereo speaker monitor.
- Disabled `webrtc.gain_control`; PipeWire’s WebRTC backend documents that AGC
  wrecks delay-agnostic AEC, especially on speech.

### Changed

- Denoisers run **mono** (`noise_suppressor_mono` / `deep_filter_mono`) at
  48 kHz with `node.latency = 256/48000`.
- Meeting RNNoise VAD is 85% with a 200 ms grace; Podcast grace matches.
- DeepFilterNet attenuation cap is 70 dB (was unlimited 100 dB).
- Meeting and Podcast add a light LSP compressor + limiter after denoise so
  speech does not come out thin.
- Bluetooth sources show a narrow-band warning in the panel.

## [0.1.1] — 2026-09-03

### Fixed

- Panel no longer sticks on **Starting…** after the PipeWire host is already
  running. Quickshell leaves `PwNode.name` empty until a `PwObjectTracker`
  binds the node (the same contract `omarchy.audio` uses). Omavoice now binds
  non-stream nodes, treats the host process as running, and only uses the
  bound source to promote the default input.
- Clicking a microphone in the panel now selects it. The live source list was
  rebuilt on every PipeWire poll, which destroyed the row under the pointer
  before `onClicked` fired. The open panel now snapshots the list, source
  snapshots are reused when names have not changed, and the active mic uses
  CursorSurface `current` so the selection is visible.

## [0.1.0] — 2026-09-03

### Added

- Omarchy 4 plugin (`gigasolo.omavoice`) that publishes a virtual PipeWire
  source named **Omavoice** for Zoom, Meet, OBS, and browsers.
- Three presets: **Meeting** (WebRTC echo cancel + RNNoise), **Podcast**
  (DeepFilterNet3 when installed, otherwise RNNoise), **Clean** (high-pass
  only).
- USB capture preferred automatically when it appears; laptop and Bluetooth
  mics stay in the picker.
- Isolated `pipewire -c` host, same pattern as Omarchy speaker tuning.
- Bar widget with on/off, presets, listen (headphones), and RNNoise setup
  guidance.
- MIT license (GigaSolo LLC).

[0.1.16]: https://github.com/gigasolo/omavoice/compare/v0.1.15...v0.1.16
[0.1.15]: https://github.com/gigasolo/omavoice/compare/v0.1.14...v0.1.15
[0.1.14]: https://github.com/gigasolo/omavoice/compare/v0.1.13...v0.1.14
[0.1.13]: https://github.com/gigasolo/omavoice/compare/v0.1.12...v0.1.13
[0.1.12]: https://github.com/gigasolo/omavoice/compare/v0.1.11...v0.1.12
[0.1.11]: https://github.com/gigasolo/omavoice/compare/v0.1.10...v0.1.11
[0.1.10]: https://github.com/gigasolo/omavoice/compare/v0.1.9...v0.1.10
[0.1.9]: https://github.com/gigasolo/omavoice/compare/v0.1.8...v0.1.9
[0.1.8]: https://github.com/gigasolo/omavoice/compare/v0.1.7...v0.1.8
[0.1.7]: https://github.com/gigasolo/omavoice/compare/v0.1.6...v0.1.7
[0.1.6]: https://github.com/gigasolo/omavoice/compare/v0.1.5...v0.1.6
[0.1.5]: https://github.com/gigasolo/omavoice/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/gigasolo/omavoice/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/gigasolo/omavoice/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/gigasolo/omavoice/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/gigasolo/omavoice/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/gigasolo/omavoice/releases/tag/v0.1.0
