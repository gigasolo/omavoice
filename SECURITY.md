# Security

Omavoice runs unsandboxed inside `omarchy-shell`, like every Omarchy plugin.

It:

- Starts a user `pipewire -c` client from a **0600** config under `$XDG_RUNTIME_DIR/omavoice/host.<pid>.conf`. `--target` must be a PipeWire `node.name` matching `[A-Za-z0-9._:-]+`.
- Leftover `omavoice*` nodes are destroyed with `pw-cli` as a fixed argv
  and a non-negative integer id from `pw-dump`. IDs are not interpolated
  into a shell.
- Meeting echo cancel uses `monitor.mode`. Its reference is the default sink's monitor ports, linked by port id. It must not link the sink node, and it must not link any `omavoice*` node into `omavoice.aec.sink`.
- While the panel is open, starts a silent `pw-cat` capture of `omavoice` so the After meter can move. That hold is named `omavoice.meter.hold` and stops when the panel closes.
- Calls `omarchy-audio-input-set-default` to make `omavoice` the default mic, and restores the pinned capture (else `previousAudioSource`) when disabled. It never stores `omavoice` as that previous source.
- Reads PipeWire node names already visible to the session.
- Does not use the network.
- Does not run as root.

Review `Service.qml` and `scripts/omavoice-run` before enabling it.
