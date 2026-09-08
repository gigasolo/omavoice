# Omavoice roadmap

One virtual microphone. Three jobs. Isolated `pipewire -c` host.
Issues and this file carry the work. Version freeze, merge, and marketplace
are a separate ship decision — this file is the product order.

## Non-goals

- Listen / headphone monitor as a headline feature
- EasyEffects-style plugin rack or arbitrary LV2 inserts
- Stacking RNNoise + DeepFilterNet + NVIDIA
- Restarting the host on every fader tick
- Re-enabling `webrtc.gain_control` (it fights Meeting AEC)
- Making Clean a dumping ground for EQ and gain experiments
- A Custom Voice look (Meeting and Podcast already store look + trim)

## 0.2.0 — shipped 2026-09-06

Live level and engine picker. Notes is not in this release.

| Bite | Issue | Status |
| --- | --- | --- |
| Live filter-chain controls | #2 | Shipped |
| Output gain | #3 | Shipped |
| Capture preamp | #4 | Shipped |
| Engine picker | #5 | Shipped |
| Engine setup rows | #6 | Shipped |
| Notes source | #1 | **Not in 0.2.** Later. |

`auto`: Meeting = RNNoise, Podcast = DeepFilterNet if present else RNNoise, Clean = none.

## 0.3.0 — Voice, Bluetooth, Level (`feat/0.3-voice-eq`)

On the branch. Manifest still `0.2.0` until freeze.

| Bite | Issue | Status |
| --- | --- | --- |
| Voice looks Neutral / Warm / Clear / Bright | #7 | **This cut.** Builtin biquads. Meeting Warm, Podcast Clear. Clean: Voice visible and disabled. |
| Body / Presence / Air knobs | #8 | **This cut.** Fixed ±12 scale; writes clamp to look ±6. Live, no host restart. |
| One Input / Output for every preset | — | **This cut.** Shared faders. Release bakes gain into a host restart. One Omavoice meter, not Before/After. |
| Do not grab unselected Bluetooth | — | **This cut.** Capture pinned to the named target; meters only the selected row; unpinned BT does not beat the builtin mic. |
| Restore the pinned mic on disable | — | **This cut.** |
| Hover matches across Preset, mics, Engine, Voice | — | **This cut.** Highlight clears when the cursor leaves. |

NVIDIA, Speex, and Notes stay out of 0.3.

## 0.4.0 — later

| Bite | Issue | Why later |
| --- | --- | --- |
| Meeting idle CPU | — | AEC + RNNoise still run ~16% while Omavoice is the default source and nothing is in a call. Unlinking the speaker monitor was not enough. Needs a real idle path that does not kill After or AUTOMATIC. |
| Notes source | #1 | Second published source: sink monitor + mic, AEC off. Not a Meeting variant. |
| NVIDIA engine | #9 | Probe Tensor GPU + AFX or linux-broadcast, then `engine = nvidia`. Do not vendor NGC blobs. |
| Speex light engine | #10 | Only if a filter-chain wrapper is cheap on Omarchy. No LADSPA wrapper on Omarchy yet. |
| Per-mic Level | — | Two USBs with different trims. Today one pin, one Input, one Output. |
| Voice Reset on the heading | — | Today: click Warm (Meeting) or Clear (Podcast) to restore that look and zero trim. |

## Constraints that stay true

- Isolated host. Never write `pipewire.conf.d` or stock `filter-chain.conf.d`.
- Mono 48 kHz, `256/48000`. Do not force MONO on the AEC module.
- One published call source named **Omavoice**. Notes, if shipped, is a second source.
- The selected mic shows what Omavoice is sending. Input/Output bake on host start.
- Engines never stack.
