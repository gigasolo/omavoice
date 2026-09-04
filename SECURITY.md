# Security

Omavoice runs unsandboxed inside `omarchy-shell`, like every Omarchy plugin.

It:

- Starts a user `pipewire -c` client with a generated config under `$XDG_RUNTIME_DIR/omavoice/`
- While the panel is open, starts a silent `pw-cat` capture of Omavoice so the After meter can move
- Calls `omarchy-audio-input-set-default` to make the virtual source the default mic
- Reads PipeWire node names already visible to the session
- Does not use the network
- Does not run as root

Review `Service.qml` and `scripts/omavoice-run` before enabling it.
