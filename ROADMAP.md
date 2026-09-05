# Omavoice roadmap

One virtual microphone. Three jobs. Isolated `pipewire -c` host.
This file is the ship plan for 0.2 and 0.3. Issues carry the work.

GitHub Projects needs the `project` scope on the connector. Until that is granted, track work with labels `0.2.0` / `0.3.0` and this file.

## Non-goals

- Listen / headphone monitor as a headline feature
- EasyEffects-style plugin rack or arbitrary LV2 inserts
- Stacking RNNoise + DeepFilterNet + NVIDIA
- Restarting the host on every fader tick
- Re-enabling `webrtc.gain_control` (it fights Meeting AEC)
- Making Clean a dumping ground for EQ and gain experiments

## 0.2.0 — Level, engine, Notes

Ship in this order. Each row is one PR.

| Bite | Issue | Why this size |
| --- | --- | --- |
| Live filter-chain controls | #2 | Unlock for every slider. Today `hostKey` restarts on preset + quality + target. |
| Output gain | #3 | What people mean by volume. After the limiter, never WebRTC AGC. |
| Capture preamp | #4 | Quiet USB vs hot condensers. Separate from output so NS sees a sane level. |
| Engine picker | #5 | Meeting can already run DFN; only policy blocks it. Never stack engines. |
| Engine setup rows | #6 | probe + reload copy when a chosen engine is missing. |
| Notes source | #1 | Second job: sink monitor + mic. AEC off. Not a Meeting variant. |

`auto` keeps today's behavior: Meeting = RNNoise, Podcast = DFN if present else RNNoise, Clean = none.

## 0.3.0 — Voice and NVIDIA

| Bite | Issue | Why this size |
| --- | --- | --- |
| Voice EQ curves | #7 | Neutral / Warm / Presence / Air via builtin biquads. No new package. Off on Clean. |
| Three-band trim | #8 | Body / Presence / Air on the existing tune page. Only after named curves. |
| NVIDIA engine | #9 | probe Tensor GPU + AFX or linux-broadcast, then `engine = nvidia`. Do not vendor NGC blobs. |
| Speex light engine | #10 | only if a filter-chain wrapper is cheap on Omarchy. After RNNoise/DFN picker. |

## Constraints that stay true

- Isolated host. Never write `pipewire.conf.d` or stock `filter-chain.conf.d`.
- Mono 48 kHz, `256/48000`. Do not force MONO on the AEC module.
- One published call source named **Omavoice**. Notes, if shipped, is a second source.
- After meters stay honest when gain or EQ moves.
