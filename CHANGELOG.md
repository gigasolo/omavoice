# Changelog

All notable changes to Omavoice are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[0.1.1]: https://github.com/gigasolo/omavoice/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/gigasolo/omavoice/releases/tag/v0.1.0
