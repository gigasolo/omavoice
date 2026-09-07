# Omavoice 0.2 implementation audit

**When:** 2026-09-06, this laptop, `feat/0.2-live-level-engine` @ `84b1399`.  
**What ran:** Meeting host `pipewire -c /run/user/1000/omavoice/host.12365.conf` (pid 12365, age ~13 min). Panel closed. No `pw-cat`. Plugin left enabled; Podcast/Clean and plugin-off were **not** switched, so those CPUs are not in this file.

**Method:** process RSS/CPU over 8s, `pw-dump` links and node state, generated conf, then a pass over `Service.qml`, `Panel.qml`, `scripts/omavoice-*`, and `tests/*`. No behavior changes.

---

## Verdict

The plugin is not a memory hog and it is not talking to the network. It **is** an idle CPU hog on Meeting: about **16% CPU** with no call and the panel shut, versus **~3.5%** for Omarchy speaker-tuning. `session.suspend-timeout-seconds = 3` does not save you, because Meeting AEC `monitor.mode` stays linked to the laptop speaker. That is the one finding that fails the “not a resource hog” bar.

Security is local-session, not remote. The real holes are **world-readable host confs** (SECURITY.md is wrong) and **unescaped PipeWire names** interpolated into SPA JSON. Maintainability debt is concentrated in host start/recovery and grep-only tests — the same class that shipped the empty-host remount bug.

---

## Live snapshot (panel closed)

| Process | RSS | Threads | FDs | CPU / 8s |
| --- | --- | --- | --- | --- |
| session `pipewire` | 42 MB | 3 | 111 | 3.6% |
| `pipewire -c omarchy-speaker-tuning.conf` | 43 MB | 4 | 35 | 3.5% |
| `pipewire -c …/omavoice/host.12365.conf` | 40 MB | 4 | 58 | **16.0%** |
| `pw-cat` | — | — | — | not running |

Graph: `omavoice` is the default **and** live `Audio/Source`. All of `omavoice`, `omavoice.capture`, `omavoice.aec`, `omavoice.aec.capture` were **running**. Links:

- builtin laptop mic → `omavoice.aec.capture`
- `omavoice.aec` → `omavoice.capture`
- laptop **Speaker** sink → `echo-cancel-sink` (AEC monitor)

AEC target in the live conf is the ALSA builtin mic, not the Shokz BT headset. Runtime dir had **nine** leftover `host.<pid>.conf` files, mode **0644**.

Not measured here: panel-open `pw-cat`, plugin disabled, Podcast/Clean CPU.

---

## Findings

### P-1 — Meeting AEC keeps the whole chain running with no call

| | |
| --- | --- |
| **Severity** | **High** |
| **Evidence** | Host CPU 16% vs speaker-tuning 3.5% (8s sample). `pw-dump`: AEC nodes `running`; Speaker → `echo-cancel-sink`. Conf: `monitor.mode = true`, `session.suspend-timeout-seconds = 3` only on the published source. README already warns; the 3s suspend does not fire. |
| **Cost** | A long Omarchy session with Meeting on pays RNNoise + WebRTC AEC + LSP compressor/limiter the whole time speakers (or the monitor path) are alive, including no Zoom/Meet. |
| **Fix shape** | Keep AEC off until something records `omavoice`, or drop `monitor.mode` and take echo from the call’s playback, or move AEC behind a “call” gate. Smallest: make AEC playback/capture actually `node.passive` **and** verify they go idle when `omavoice` has no listeners. Measure Podcast/Clean the same way before claiming they are cheap. |

### P-2 — Auto-picked capture is the laptop mic while a BT headset is present

| | |
| --- | --- |
| **Severity** | **High** (wrong mic **and** wasted AEC) |
| **Evidence** | Live `target.object` = `alsa_input.pci-…HiFi__Mic__source`. `bluez_input.A0:0C:E2:D0:C3:81` exists. Default source is already `omavoice`, so `pickSource` cannot use it as fallback (`isCaptureSourceName` excludes omavoice) and walks the list — builtin wins over BT unless pinned. AEC monitor is the **Speaker** sink, not the BT headphones. |
| **Cost** | Meeting denoises the laptop mic and watches the laptop speaker while the user talks and listens on Shokz. CPU spent on the wrong devices; calls hear the wrong capsule. |
| **Fix shape** | When default is `omavoice`, pick from `previousDefaultName` or prefer `bluez_input` over builtin if that was the live default before promote. Pin is already the escape hatch — make Auto match what the OS was using. |

### P-3 — `onNodesChanged` always arms `startDebounce`

| | |
| --- | --- |
| **Severity** | Low |
| **Evidence** | `Service.qml` `onNodesChanged: refreshSources()` → `syncHost()` always `startDebounce.restart()` when enabled and `targetName` is set. `startHostNow` then no-ops if `hostKey` matches. Every WirePlumber/BT flicker is a 150ms timer. |
| **Cost** | QML timer churn, not a second host. Fine on this 19-node session; noisy if the graph flaps. |
| **Fix shape** | Call `syncHost()` only when pick, enabled, preset, engine, or target actually change. |

### P-4 — Fader preview shells out `pw-cli ls` every 80ms

| | |
| --- | --- |
| **Severity** | Low |
| **Evidence** | `previewGains` → `applyLiveControls` → `liveDebounce` 80ms → `omavoice-ctl` → `pw-cli ls Node` then `pw-cli s`. Keys/values are internal numbers today. |
| **Cost** | A long drag is a `pw-cli` process storm. Session is local; still sloppy. |
| **Fix shape** | Cache the capture node id when `afterNodeId` lands; persist-on-release already exists — use it for ctl too, or keep preview but skip `ls`. |

### R-1 — Stale `host.<pid>.conf` files accumulate, mode 0644

| | |
| --- | --- |
| **Severity** | **Medium** (perms) / Low (disk) |
| **Evidence** | `/run/user/1000/omavoice/` listed nine confs after a few remounts. `ls -l` → `-rw-r--r--`. `SECURITY.md` says `$XDG_RUNTIME_DIR` and implies a private runtime file; it does not match. umask 022. Unique pid conf (good) never unlinks the previous file. |
| **Cost** | Anyone on the machine can read which mic you chained and the full graph. Directory grows across plugin updates until logout. |
| **Fix shape** | `umask 077` (or `chmod 600`) after create; after `drop_leftover_host`, `rm -f` `host.conf` and `host.*.conf` except the file we are about to exec. |

### R-2 — `busy` can never be true

| | |
| --- | --- |
| **Severity** | Low |
| **Evidence** | `busy: hostProcess.running && !running` and `running: hostProcess.running`. Panel: `busy: service.busy && !service.running`. The starting spinner is dead. |
| **Cost** | Reload/start looks idle while bind-watch is retrying. |
| **Fix shape** | `busy: enabled && hostProcess.running && !afterNodeName` (or `hostAttempts > 0 && !afterNodeName`). |

### R-3 — Disable may restore default `omavoice`

| | |
| --- | --- |
| **Severity** | Medium |
| **Evidence** | `promoteDefault` sets `previousDefaultName` from `defaultSourceName` if empty. After a reboot, configured default is already `omavoice`, so previous becomes `omavoice`. `restoreDefault` then writes that back. Not exercised live (plugin left on). |
| **Cost** | Toggle off / plugin remove can leave every app aimed at a missing source. |
| **Fix shape** | Never store `omavoice` as previous. Persist the pre-promote name in settings. On stop, if previous is empty, restore the first non-omavoice `Audio/Source`. |

### R-4 — Panel hold is bounded (pass)

| | |
| --- | --- |
| **Severity** | — |
| **Evidence** | No `pw-cat` with the panel closed. `setMeterHold(false)` on panel close and destruction. `omavoice.meter.hold` not in the graph. |
| **Cost** | None while closed. Open cost not measured this pass. |
| **Fix shape** | None now. Re-measure with the panel open before calling After meters free. |

### R-5 — Host bind-watch is capped (pass)

| | |
| --- | --- |
| **Severity** | — |
| **Evidence** | `hostAttempts >= 8` stops `startHostNow` and `hostBindWatch`. Watcher is idle while `afterNodeName` is set (live). Kill path is `pgrep -x pipewire` + cmdline `/omavoice/host`, not speaker-tuning. |
| **Cost** | Eight restarts then a sticky error. Acceptable. |
| **Fix shape** | Keep the cap. Do not add another uncapped `onRunningChanged` loop. |

### M-1 — Tests would not have caught the empty-host remount

| | |
| --- | --- |
| **Severity** | **High** (process) |
| **Evidence** | `./tests/run` = Model unit tests + conf string greps + mocked `pw-cli` + `omarchy plugin validate`. `dump.test.sh` never runs `pipewire -c`. `qml.test.sh` greps for the last incident. Conf truncation, D-Bus-only host, and ctl injection all pass today’s suite. |
| **Cost** | The next lifecycle bug ships the same way. |
| **Fix shape** | One smoke: `omavoice-run --dump` → `timeout 2 pipewire -c` with a dummy name prefix, assert the process becomes a session client (or exits non-zero without `nofail`). Do not require a real mic. |

### M-2 — Host start is four overlapping machines

| | |
| --- | --- |
| **Severity** | Medium |
| **Evidence** | Path: `syncHost` → 150ms debounce → `startHostNow` → `onRunningChanged` retry → 1s `hostBindWatch` → `onAfterNodeIdChanged` start. Needed for remount; hard to see which path owns a given pid. |
| **Cost** | Next empty-host bug will be patched into a fifth timer. |
| **Fix shape** | One function `ensureHost()`: not enabled → stop; no node after grace → kill+start; else leave it. Keep the 8-cap. |

### M-3 — Two persist writers; pin writes twice

| | |
| --- | --- |
| **Severity** | Low |
| **Evidence** | `Panel.persistSettings` and `Service.persist` both `updateEntryInline`. `chooseSource` calls both `persistSettings({ pinnedSource })` and `service.pinSource`. |
| **Cost** | Duplicate settings writes; possible flicker if they diverge later. |
| **Fix shape** | Panel writes settings; Service only reads. Drop `pinSource` persist or drop the Panel copy. |

### M-4 — `--dir` is required and unused

| | |
| --- | --- |
| **Severity** | Low |
| **Evidence** | `omavoice-run` parses `--dir` into `plugin_dir`, requires it, never reads it again. `hostKey` includes `pluginDir`, so a path-only remount still restarts the host (that part is useful). |
| **Cost** | Confusion only. |
| **Fix shape** | Use it for nothing, or drop the requirement and stop putting it in `hostKey` if the binary path is already the Process command. |

### M-5 — File size is not the problem

| | |
| --- | --- |
| **Severity** | — |
| **Evidence** | Panel 1130, Service 532, run 465, Model 322. Split only helps if `ensureHost` moves out of Panel chrome. `docs/logos/` is 476K **untracked**, not in the plugin checkout. |
| **Cost** | None for ship weight. |
| **Fix shape** | Do not split files as a chore. Extract host ensure if M-2 is done. |

### S-1 — Host conf interpolates `node.name` into SPA JSON

| | |
| --- | --- |
| **Severity** | Medium |
| **Evidence** | `scripts/omavoice-run`: `target.object = "$target"` (and `$capture_target`) inside a double-quoted heredoc. `target` is the PipeWire name from QML. A name containing `"`, newline, or `}` breaks or extends the conf. Live names on this machine are `alsa_input.*` / `bluez_input.*` (safe charset). Other session clients can register a node. |
| **Cost** | Local confused deputy: a malicious or buggy client chooses the Omavoice capture target or injects modules. No network. |
| **Fix shape** | Allow `^[A-Za-z0-9._:-]+$` only; reject otherwise. Do not shell-quote into JSON — validate then substitute. |

### S-2 — `omavoice-ctl` concatenates Props JSON

| | |
| --- | --- |
| **Severity** | Low (today) / Medium if keys ever become external |
| **Evidence** | `params+=" \"$1\" $2"`. Values are linear gains / VAD numbers from `Model.js`. Keys are fixed. `ctl.test.sh` does not feed a quote. Demo: value `1.0 } } ; /bin/true` is inserted raw. `pw-cli` is still argv (`exec pw-cli s …`), so this is SPA parse injection, not shell. |
| **Cost** | Low while callers stay numeric. One bad QML string becomes a Props blob. |
| **Fix shape** | Only allow `[0-9.+-eE]+` for values; keys from a whitelist. Or `pw-cli` set-param without a hand-built dict. |

### S-3 — SECURITY.md is incomplete and wrong on file mode

| | |
| --- | --- |
| **Severity** | Medium (docs vs reality) |
| **Evidence** | Says unsandboxed, `pipewire -c`, `pw-cat`, default-source helper, no network, no root. Does not mention AEC speaker monitor, default-source hijack restore, 0644 confs, or name interpolation. Live confs are 0644. |
| **Cost** | Reviewers trust a file that does not describe the surface. |
| **Fix shape** | Rewrite after P-1/R-1/S-1 fixes, to match the code. |

### S-4 — Default input hijack is the product (pass, with residual)

| | |
| --- | --- |
| **Severity** | Residual, documented |
| **Evidence** | `default.audio.source` = `omavoice`. `omarchy-audio-input-set-default` gets a numeric id from Quickshell. `pw-cat` hold uses argv `--target` + bound name. Probe only `stat`s well-known LADSPA/SPA paths. No root. Leftover kill cannot match speaker-tuning (`pgrep -x pipewire` + `/omavoice/host`). |
| **Cost** | Every app hears the processed chain while enabled. AEC monitor hears the speaker. That is the feature; R-3 is the off-path bug. |
| **Fix shape** | Keep argv `execDetached`. Fix R-3. |

---

## Wakeup inventory

| Source | When it runs | Stops when |
| --- | --- | --- |
| Host `pipewire -c` | Plugin enabled | Disable / destroy / bind-watch replace |
| Meeting AEC + RNNoise + LSP | As long as the host is up **and** AEC monitor is linked | Not when the panel closes (P-1) |
| `pw-cat` hold | Panel open | Panel close / destroy (R-4) |
| `PwObjectTracker` on all non-sink non-stream nodes | Always | — (small graph here) |
| `onNodesChanged` → `syncHost` | Any node list change | — (P-3) |
| Timer 750ms unbound rescan | `hasUnboundNodes` | Names bound |
| Timer 400ms promote default | Host running and not yet promoted | `promoted` |
| Timer 1000ms `hostBindWatch` | Enabled and no `omavoice` node | Node appears or 8 attempts |
| Timer 800ms meter hold | Wanted hold and `pw-cat` down | Hold off or process up |
| Timer 2800ms hero phrase | Panel open, not tune page | Close |
| `PwNodePeakMonitor` per row + After | Panel open | Close |
| `omavoice-ctl` | Gain/quality change, 80ms debounce | — (P-4) |
| Probe process | Start / reload | Once |

---

## Host state machine (as it is)

```
enabled/target/preset/engine change
        → syncHost (debounce 150ms)
            → startHostNow (cap 8)
                → omavoice-run (unique conf, wait session, kill leftover pipewire)
                    → pipewire -c
onRunningChanged (died, still want host, no node) → debounce again
hostBindWatch (1s, no node, grace 2.5s) → kill Process, startHostNow
onAfterNodeIdChanged (node exists, Process not running) → startHostNow
```

The cap and unique conf are the right shape after the remount bug. The overlap is why M-2 exists.

---

## Recommended fix order (later cut, not this audit)

1. **P-1** — Meeting must go idle when nothing records `omavoice`. Re-measure CPU vs speaker-tuning.  
2. **P-2** — Auto capture must follow the real mic (BT vs builtin), not “first alsa after omavoice is default”.  
3. **R-1 / S-3** — `0600` confs, unlink leftovers, honest SECURITY.md.  
4. **S-1 / S-2** — Validate names and ctl values.  
5. **R-3** — Restore a real previous source.  
6. **M-1** — One `pipewire -c` smoke so empty-host cannot regress silently.  
7. **M-2 / P-3 / R-2 / M-3 / M-4** — Ensure-host, debounce, busy, persist, `--dir`.

Do not split Panel/Service, do not rewrite tests wholesale, do not touch Notes/EQ/NVIDIA in that cut.

---

## What this pass could not verify

- CPU with the **panel open** (`pw-cat` + peak monitors).  
- CPU on **Podcast** and **Clean**.  
- CPU with the plugin **disabled** (would stop the live host).  
- `restoreDefault` after a reboot where default is already `omavoice`.  
- QML binding counts inside Quickshell (no inspector attached).
