# Omavoice

<p align="center">
  <img src="docs/omavoice.svg" alt="Omavoice — your voice, below every app" width="720">
</p>

<p align="center">
  <strong>A virtual microphone for Zoom, Meet, and the record button.</strong><br>
  One source. Three presets. Noise and echo stay on this side of the call.
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-22c55e?style=flat-square" alt="License: MIT"></a>
  <img src="https://img.shields.io/badge/omarchy-4%20Quattro-0ea5e9?style=flat-square" alt="Omarchy 4 Quattro">
  <img src="https://img.shields.io/badge/pipewire-filter--chain-a3e635?style=flat-square" alt="PipeWire filter-chain">
  <img src="https://img.shields.io/badge/version-0.1.6-111827?style=flat-square" alt="Version 0.1.6">
</p>

Pick **Omavoice** in Zoom, Google Meet, OBS, or a browser. The plugin sits under those apps as a PipeWire source, so you do not configure each one. USB mics attach themselves when you plug them in.

An independent [MIT](LICENSE)-licensed plugin by [GigaSolo](https://github.com/gigasolo) for [Omarchy](https://omarchy.org/) 4 (Quattro). Not affiliated with or endorsed by 37signals.

---

## Presets

| | Meeting | Podcast | Clean |
| --- | --- | --- | --- |
| **For** | Zoom, Meet, Teams | OBS, interviews, local record | Program mixes, music beds |
| **Does** | Monitor-mode AEC + RNNoise mono + compressor | High-pass + DeepFilterNet3 (or RNNoise) + compressor | High-pass only |
| **Keeps** | Your voice on a laptop with speakers | Speech that sounds finished | Applause, keys, and music |

Right-click the mark to toggle. Open the panel to switch presets and pick a microphone. Each mic row shows a live level; the selected row adds a hairline of what Omavoice is sending.

In the app itself, choose **Omavoice** as the microphone and turn *its* noise cancellation off. Two denoisers stacked sound hollow.

## Install

```sh
omarchy pkg add noise-suppression-for-voice
omarchy plugin add https://github.com/gigasolo/omavoice.git --enable
```

Omarchy may ask which side of the bar to use. The default is the right.

> [!IMPORTANT]
> Plugins run as unsandboxed code inside `omarchy-shell`. Only add repos you trust, and [read the source](https://github.com/gigasolo/omavoice) before you enable one.

Without `--enable`, the plugin is cloned and left off so you can review it first:

```sh
omarchy plugin add https://github.com/gigasolo/omavoice.git
less ~/.config/omarchy/plugins/gigasolo.omavoice/README.md
omarchy plugin enable gigasolo.omavoice --section right
```

From a local checkout:

```sh
omarchy plugin add "$PWD" --enable
```

Do not symlink the checkout into `~/.config/omarchy/plugins` — Omarchy refuses plugins that contain symlinks.

### Optional Podcast engine

```sh
omarchy pkg aur add deepfilternet-ladspa
```

If that plugin is missing, Podcast uses RNNoise. Meeting still echo-cancels without RNNoise, but the neural denoise needs `noise-suppression-for-voice`.

## Use

| Action | How |
| --- | --- |
| Open or close the panel | Left-click the mark |
| Toggle Omavoice | Right-click, or `o` |
| Meeting / Podcast / Clean | `m` / `p` / `c` |
| Move | Arrow keys or `h` `j` `k` `l` |
| Activate | Enter |
| Close | Escape |

USB capture is preferred when it appears. Laptop mics and Bluetooth headsets stay in the picker. Pin one if you have several USB devices.

## How it sits in the graph

```
USB / laptop / BT mic
        │
        ▼
  Omavoice  (pipewire -c, its own client)
   Meeting · Podcast · Clean
        │
        ▼
  Zoom · Meet · OBS · browser
```

The host is a dedicated PipeWire client, the same isolation Omarchy uses for speaker tuning. It does not write into that tuning, and it does not load stock `filter-chain.conf.d`. Disable the plugin and the chain stops.

## Update and remove

```sh
omarchy plugin update gigasolo.omavoice
omarchy plugin remove gigasolo.omavoice
```

`omarchy plugin update` shows the diff and fast-forwards the git checkout. Removing the plugin does not change your other audio devices.

## If something is wrong

**The mark is missing.** Confirm it is enabled:

```sh
omarchy plugin list | grep omavoice
omarchy plugin enable gigasolo.omavoice --section right
```

**The panel asks for RNNoise.** Run `omarchy pkg add noise-suppression-for-voice`, or click the setup row.

**The app still hears the raw USB mic.** Select **Omavoice** inside Zoom / Meet / OBS, not the hardware device.

**The voice sounds hollow.** The call app is probably denoising too. Turn that off.

## Develop

```sh
git clone https://github.com/gigasolo/omavoice.git
cd omavoice
./tests/run
```

That runs the Model tests and `omarchy plugin validate .`, the same checks Omarchy uses before it will install a plugin.

## Sharing

Omarchy distributes third-party plugins as public git repos. Anyone can run `omarchy plugin add` against this URL.

To help people find it, list it at [omarchyplugins.com](https://omarchyplugins.com).

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

## License

[MIT](LICENSE). Copyright (c) 2026 GigaSolo LLC.

```
SPDX-License-Identifier: MIT
```

Omarchy is a trademark of its respective owners.
