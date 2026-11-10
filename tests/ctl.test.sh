#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ctl="$root/scripts/omavoice-ctl"
fail() { echo "ctl.test: $*" >&2; exit 1; }

tmpdir=$(mktemp -d)
trap 'rm -rf -- "$tmpdir"' EXIT
log="$tmpdir/pw-cli.log"

cat >"$tmpdir/pw-cli" <<EOF
#!/usr/bin/env bash
if [[ \${1:-} == ls && \${2:-} == Node ]]; then
  cat <<'NODES'
	id 10, type PipeWire:Interface:Node/3
		node.name = "omavoice"
	id 11, type PipeWire:Interface:Node/3
		node.name = "omavoice.capture"
NODES
  exit 0
fi
printf '%s\n' "\$@" >> "$log"
EOF
chmod +x "$tmpdir/pw-cli"

linklog="$tmpdir/links.log"
cat >"$tmpdir/pw-link" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" >> "$linklog"
EOF
chmod +x "$tmpdir/pw-link"

export PATH="$tmpdir:$PATH"

set +e
"$ctl" set "preamp:Gain 1" >/dev/null 2>&1
odd=$?
set -e
[[ $odd -eq 2 ]] || fail "odd argc must exit 2, got $odd"

"$ctl" set "preamp:Gain 1" 2.0 "denoise:VAD Threshold (%)" 80
[[ -f $log ]] || fail "pw-cli was not invoked"
mapfile -t args < "$log"
[[ ${args[0]} == s ]] || fail "pw-cli must set-param, got ${args[0]:-}"
[[ ${args[1]} == 11 ]] || fail "must target omavoice.capture id 11, got ${args[1]:-}"
[[ ${args[2]} == Props ]] || fail "must write Props, got ${args[2]:-}"
[[ ${args[3]} == *'"preamp:Gain 1"'* ]] || fail "must quote preamp:Gain 1: ${args[3]:-}"
[[ ${args[3]} == *'"denoise:VAD Threshold (%)"'* ]] || fail "must quote VAD key: ${args[3]:-}"
[[ ${args[3]} != *' id 10 '* && ${args[1]} != 10 ]] || fail "must not target published omavoice"

rm -f -- "$log"
"$ctl" set --id 99 "preamp:Gain 1" 2.0
mapfile -t args < "$log"
[[ ${args[1]} == 99 ]] || fail "--id must skip ls, got ${args[1]:-}"

set +e
"$ctl" set --id 11 "preamp:Gain 1" '1.0}' >/dev/null 2>&1
bad_val=$?
"$ctl" set --id 11 "nope" 1 >/dev/null 2>&1
bad_key=$?
set -e
[[ $bad_val -eq 2 ]] || fail "non-numeric value must exit 2, got $bad_val"
[[ $bad_key -eq 2 ]] || fail "unknown key must exit 2, got $bad_key"

cat >"$tmpdir/pw-dump" <<'EOF'
#!/usr/bin/env bash
cat <<'JSON'
[{"type":"PipeWire:Interface:Link","id":"0; touch /tmp/omavoice-pwned","info":{"props":{"link.output.node":3,"link.input.node":2}}},
 {"type":"PipeWire:Interface:Node","id":1,"info":{"props":{"node.name":"omavoice"}}},
 {"type":"PipeWire:Interface:Node","id":2,"info":{"props":{"node.name":"omavoice.aec.sink"}}},
 {"type":"PipeWire:Interface:Node","id":3,"info":{"props":{"node.name":"alsa_output.pci-Speaker"}}}]
JSON
EOF
chmod +x "$tmpdir/pw-dump"

rm -f -- "$log" "$linklog" /tmp/omavoice-pwned
release=$("$ctl" aec-sync)
[[ $release == release ]] || fail "idle graph must print release, got ${release:-empty}"
[[ -f /tmp/omavoice-pwned ]] && fail "dirty pw-dump id must not reach the shell"
[[ -f $log ]] && fail "release must not call pw-cli destroy"
[[ -s $linklog ]] && fail "release must not pw-link"

cat >"$tmpdir/pw-dump" <<'EOF'
#!/usr/bin/env bash
cat <<'JSON'
[{"type":"PipeWire:Interface:Link","id":7,"info":{"props":{"link.output.node":1,"link.input.node":4}}},
 {"type":"PipeWire:Interface:Node","id":1,"info":{"props":{"node.name":"omavoice"}}},
 {"type":"PipeWire:Interface:Node","id":2,"info":{"props":{"node.name":"omavoice.aec.sink"}}},
 {"type":"PipeWire:Interface:Node","id":4,"info":{"props":{"node.name":"zoom"}}}]
JSON
EOF
chmod +x "$tmpdir/pw-dump"
rm -f -- "$log" "$linklog"
hold=$("$ctl" aec-sync)
[[ $hold == hold ]] || fail "a real capture client must print hold, got ${hold:-empty}"
[[ -f $log ]] && fail "hold without a default sink must not call pw-cli"
[[ -s $linklog ]] && fail "hold without a default sink must not pw-link"

cat >"$tmpdir/pw-dump" <<'EOF'
#!/usr/bin/env bash
cat <<'JSON'
[{"type":"PipeWire:Interface:Link","id":7,"info":{"props":{"link.output.node":1,"link.input.node":4}}},
 {"type":"PipeWire:Interface:Node","id":1,"info":{"props":{"node.name":"omavoice"}}},
 {"type":"PipeWire:Interface:Node","id":4,"info":{"props":{"node.name":"omavoice.meter.hold"}}}]
JSON
EOF
chmod +x "$tmpdir/pw-dump"
meter=$("$ctl" aec-sync)
[[ $meter == release ]] || fail "panel meter must print release, got ${meter:-empty}"

cat >"$tmpdir/pw-dump" <<'EOF'
#!/usr/bin/env bash
cat <<'JSON'
[{"type":"PipeWire:Interface:Link","id":7,"info":{"props":{"link.output.node":1,"link.input.node":4}}},
 {"type":"PipeWire:Interface:Node","id":1,"info":{"props":{"node.name":"omavoice"}}},
 {"type":"PipeWire:Interface:Node","id":4,"info":{"props":{"node.name":"quickshell"}}}]
JSON
EOF
chmod +x "$tmpdir/pw-dump"
shell=$("$ctl" aec-sync)
[[ $shell == release ]] || fail "quickshell must print release, got ${shell:-empty}"

cat >"$tmpdir/pw-dump" <<'EOF'
#!/usr/bin/env bash
cat <<'JSON'
[{"id":8,"type":"PipeWire:Interface:Link","info":{"props":{"link.output.node":3,"link.input.node":2}}},
 {"id":1,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"omavoice"}}},
 {"id":2,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"omavoice.aec.sink"}}},
 {"id":3,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"alsa_output.pci-Speaker"}}}]
JSON
EOF
chmod +x "$tmpdir/pw-dump"
rm -f -- "$log" "$linklog"
release=$("$ctl" aec-sync)
[[ $release == release ]] || fail "idle graph with a real link id must print release, got ${release:-empty}"
[[ -f $log ]] && fail "release must not pw-cli destroy, got $(cat "$log")"
[[ -s $linklog ]] && fail "release must not pw-link"

cat >"$tmpdir/pw-dump" <<'EOF'
#!/usr/bin/env bash
cat <<'JSON'
[{"id":30,"type":"PipeWire:Interface:Metadata","props":{"metadata.name":"default"},"metadata":[
   {"key":"default.audio.sink","type":"Spa:String:JSON","value":{"name":"alsa_output.pci-Speaker"}}]},
 {"id":5,"type":"PipeWire:Interface:Client","info":{"props":{"node.name":"alsa_output.pci-Speaker"}}},
 {"id":1,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"omavoice"}}},
 {"id":2,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"omavoice.aec.sink"}}},
 {"id":3,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"alsa_output.pci-Speaker"}}},
 {"id":4,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"zoom"}}},
 {"id":7,"type":"PipeWire:Interface:Link","info":{"props":{"link.output.node":1,"link.input.node":4}}},
 {"id":10,"type":"PipeWire:Interface:Port","info":{"direction":"output","props":{"node.id":3,"port.name":"monitor_FL","port.direction":"out"}}},
 {"id":11,"type":"PipeWire:Interface:Port","info":{"direction":"output","props":{"node.id":3,"port.name":"monitor_FR","port.direction":"out"}}},
 {"id":12,"type":"PipeWire:Interface:Port","info":{"direction":"input","props":{"node.id":3,"port.name":"playback_FL","port.direction":"in"}}},
 {"id":13,"type":"PipeWire:Interface:Port","info":{"direction":"input","props":{"node.id":3,"port.name":"playback_FR","port.direction":"in"}}},
 {"id":20,"type":"PipeWire:Interface:Port","info":{"direction":"input","props":{"node.id":2,"port.name":"input_FL","port.direction":"in"}}},
 {"id":21,"type":"PipeWire:Interface:Port","info":{"direction":"input","props":{"node.id":2,"port.name":"input_FR","port.direction":"in"}}}]
JSON
EOF
chmod +x "$tmpdir/pw-dump"
rm -f -- "$log" "$linklog" /tmp/omavoice-pwned
hold=$("$ctl" aec-sync)
[[ $hold == hold ]] || fail "held call must print hold, got ${hold:-empty}"
[[ -f $log ]] && fail "a missing reference must not pw-cli destroy"
[[ -f $linklog ]] || fail "held call must link the default sink monitors"
mapfile -t args < "$linklog"
[[ ${#args[@]} -eq 4 ]] || fail "monitor link argc, got ${args[*]:-empty}"
[[ ${args[0]} == 10 ]] || fail "must link monitor_FL port 10, got ${args[0]:-}"
[[ ${args[1]} == 20 ]] || fail "monitor_FL must feed input_FL port 20, got ${args[1]:-}"
[[ ${args[2]} == 11 ]] || fail "must link monitor_FR port 11, got ${args[2]:-}"
[[ ${args[3]} == 21 ]] || fail "monitor_FR must feed input_FR port 21, got ${args[3]:-}"
for a in "${args[@]}"; do
  [[ $a == *:* || $a == *monitor_* || $a == *playback* || $a == *alsa_* || $a == *omavoice* ]] \
    && fail "pw-link must take port ids, not a node or port name: $a"
done

cat >"$tmpdir/pw-dump" <<'EOF'
#!/usr/bin/env bash
cat <<'JSON'
[{"id":30,"type":"PipeWire:Interface:Metadata","props":{"metadata.name":"default"},"metadata":[
   {"key":"default.audio.sink","type":"Spa:String:JSON","value":{"name":"alsa_output.pci-Speaker"}}]},
 {"id":1,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"omavoice"}}},
 {"id":2,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"omavoice.aec.sink"}}},
 {"id":3,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"alsa_output.pci-Speaker"}}},
 {"id":4,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"zoom"}}},
 {"id":7,"type":"PipeWire:Interface:Link","info":{"props":{"link.output.node":1,"link.input.node":4}}},
 {"id":40,"type":"PipeWire:Interface:Link","info":{"props":{"link.output.node":3,"link.output.port":10,"link.input.node":2,"link.input.port":20}}},
 {"id":41,"type":"PipeWire:Interface:Link","info":{"props":{"link.output.node":3,"link.output.port":11,"link.input.node":2,"link.input.port":21}}},
 {"id":10,"type":"PipeWire:Interface:Port","info":{"direction":"output","props":{"node.id":3,"port.name":"monitor_FL"}}},
 {"id":11,"type":"PipeWire:Interface:Port","info":{"direction":"output","props":{"node.id":3,"port.name":"monitor_FR"}}},
 {"id":12,"type":"PipeWire:Interface:Port","info":{"direction":"input","props":{"node.id":3,"port.name":"playback_FL"}}},
 {"id":20,"type":"PipeWire:Interface:Port","info":{"direction":"input","props":{"node.id":2,"port.name":"input_FL"}}},
 {"id":21,"type":"PipeWire:Interface:Port","info":{"direction":"input","props":{"node.id":2,"port.name":"input_FR"}}}]
JSON
EOF
chmod +x "$tmpdir/pw-dump"
rm -f -- "$log" "$linklog"
hold=$("$ctl" aec-sync)
[[ $hold == hold ]] || fail "already-linked call must print hold, got ${hold:-empty}"
[[ -f $log ]] && fail "monitor links already in place must not be destroyed"
[[ -s $linklog ]] && fail "monitor links already in place must not be linked again"

cat >"$tmpdir/pw-dump" <<'EOF'
#!/usr/bin/env bash
cat <<'JSON'
[{"id":30,"type":"PipeWire:Interface:Metadata","props":{"metadata.name":"default"},"metadata":[
   {"key":"default.audio.sink","type":"Spa:String:JSON","value":{"name":"omavoice.speakers"}}]},
 {"id":1,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"omavoice"}}},
 {"id":2,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"omavoice.aec.sink"}}},
 {"id":3,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"omavoice.speakers"}}},
 {"id":4,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"zoom"}}},
 {"id":7,"type":"PipeWire:Interface:Link","info":{"props":{"link.output.node":1,"link.input.node":4}}},
 {"id":10,"type":"PipeWire:Interface:Port","info":{"props":{"node.id":3,"port.name":"monitor_FL"}}},
 {"id":11,"type":"PipeWire:Interface:Port","info":{"props":{"node.id":3,"port.name":"monitor_FR"}}},
 {"id":20,"type":"PipeWire:Interface:Port","info":{"props":{"node.id":2,"port.name":"input_FL"}}},
 {"id":21,"type":"PipeWire:Interface:Port","info":{"props":{"node.id":2,"port.name":"input_FR"}}}]
JSON
EOF
chmod +x "$tmpdir/pw-dump"
rm -f -- "$log" "$linklog"
hold=$("$ctl" aec-sync)
[[ $hold == hold ]] || fail "omavoice default sink must still print hold, got ${hold:-empty}"
[[ -f $log ]] && fail "omavoice default sink must not destroy links"
[[ -s $linklog ]] && fail "omavoice default sink must not be linked into omavoice.aec.sink"

cat >"$tmpdir/pw-dump" <<'EOF'
#!/usr/bin/env bash
cat <<'JSON'
[{"id":30,"type":"PipeWire:Interface:Metadata","props":{"metadata.name":"default"},"metadata":[
   {"key":"default.audio.sink","type":"Spa:String:JSON","value":{"name":"bad;sink"}}]},
 {"id":1,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"omavoice"}}},
 {"id":2,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"omavoice.aec.sink"}}},
 {"id":3,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"bad;sink"}}},
 {"id":4,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"zoom"}}},
 {"id":7,"type":"PipeWire:Interface:Link","info":{"props":{"link.output.node":1,"link.input.node":4}}},
 {"id":10,"type":"PipeWire:Interface:Port","info":{"props":{"node.id":3,"port.name":"monitor_FL"}}},
 {"id":20,"type":"PipeWire:Interface:Port","info":{"props":{"node.id":2,"port.name":"input_FL"}}}]
JSON
EOF
chmod +x "$tmpdir/pw-dump"
rm -f -- "$log" "$linklog" /tmp/omavoice-pwned
hold=$("$ctl" aec-sync)
[[ $hold == hold ]] || fail "unsafe sink name must still print hold, got ${hold:-empty}"
[[ -f /tmp/omavoice-pwned ]] && fail "unsafe sink name must not reach the shell"
[[ -s $linklog ]] && fail "unsafe sink name must not be passed to pw-link"

cat >"$tmpdir/pw-dump" <<'EOF'
#!/usr/bin/env bash
cat <<'JSON'
[{"id":30,"type":"PipeWire:Interface:Metadata","props":{"metadata.name":"default"},"metadata":[
   {"key":"default.audio.sink","type":"Spa:String:JSON","value":"{\"name\":\"alsa_output.pci-Speaker\"}"}]},
 {"id":1,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"omavoice"}}},
 {"id":2,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"omavoice.aec.sink"}}},
 {"id":3,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"alsa_output.pci-Speaker"}}},
 {"id":4,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"zoom"}}},
 {"id":7,"type":"PipeWire:Interface:Link","info":{"props":{"link.output.node":1,"link.input.node":4}}},
 {"id":10,"type":"PipeWire:Interface:Port","info":{"props":{"node.id":3,"port.name":"monitor_MONO"}}},
 {"id":20,"type":"PipeWire:Interface:Port","info":{"props":{"node.id":2,"port.name":"input_FL"}}}]
JSON
EOF
chmod +x "$tmpdir/pw-dump"
rm -f -- "$log" "$linklog"
hold=$("$ctl" aec-sync)
[[ $hold == hold ]] || fail "mono reference must print hold, got ${hold:-empty}"
[[ -f $linklog ]] || fail "one monitor and one input must be linked"
mapfile -t args < "$linklog"
[[ ${#args[@]} -eq 2 ]] || fail "mono link argc, got ${args[*]:-empty}"
[[ ${args[0]} == 10 ]] || fail "must link the only monitor port, got ${args[0]:-}"
[[ ${args[1]} == 20 ]] || fail "must link the only input port, got ${args[1]:-}"

cat >"$tmpdir/pw-dump" <<'EOF'
#!/usr/bin/env bash
cat <<'JSON'
[{"id":30,"type":"PipeWire:Interface:Metadata","props":{"metadata.name":"default"},"metadata":[
   {"key":"default.audio.sink","type":"Spa:String:JSON","value":{"name":"alsa_output.pci-Speaker"}}]},
 {"id":1,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"omavoice"}}},
 {"id":2,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"omavoice.aec.sink"}}},
 {"id":3,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"alsa_output.pci-Speaker"}}},
 {"id":4,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"zoom"}}},
 {"id":8,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"omavoice.aec.playback"}}},
 {"id":7,"type":"PipeWire:Interface:Link","info":{"props":{"link.output.node":1,"link.input.node":4}}},
 {"id":"0; touch /tmp/omavoice-pwned","type":"PipeWire:Interface:Link","info":{"props":{"link.output.node":8,"link.input.node":2}}},
 {"id":9,"type":"PipeWire:Interface:Link","info":{"props":{"link.output.node":8,"link.output.port":50,"link.input.node":2,"link.input.port":20}}},
 {"id":10,"type":"PipeWire:Interface:Port","info":{"props":{"node.id":3,"port.name":"monitor_FL"}}},
 {"id":11,"type":"PipeWire:Interface:Port","info":{"props":{"node.id":3,"port.name":"monitor_FR"}}},
 {"id":12,"type":"PipeWire:Interface:Port","info":{"props":{"node.id":3,"port.name":"playback_FL"}}},
 {"id":50,"type":"PipeWire:Interface:Port","info":{"props":{"node.id":8,"port.name":"monitor_FL"}}},
 {"id":20,"type":"PipeWire:Interface:Port","info":{"props":{"node.id":2,"port.name":"input_FL"}}},
 {"id":21,"type":"PipeWire:Interface:Port","info":{"props":{"node.id":2,"port.name":"input_FR"}}}]
JSON
EOF
chmod +x "$tmpdir/pw-dump"
rm -f -- "$log" "$linklog" /tmp/omavoice-pwned
hold=$("$ctl" aec-sync)
[[ $hold == hold ]] || fail "foreign reference must print hold, got ${hold:-empty}"
[[ -f /tmp/omavoice-pwned ]] && fail "dirty link id must not reach the shell"
[[ -f $log ]] || fail "a link from another node must be destroyed"
mapfile -t args < "$log"
[[ ${#args[@]} -eq 2 ]] || fail "only the integer foreign link is destroyed, got ${args[*]:-empty}"
[[ ${args[0]} == destroy ]] || fail "foreign link must be pw-cli destroy, got ${args[0]:-}"
[[ ${args[1]} == 9 ]] || fail "must destroy link 9, got ${args[1]:-}"
[[ -f $linklog ]] || fail "foreign reference must be replaced with monitor ports"
mapfile -t args < "$linklog"
[[ ${#args[@]} -eq 4 ]] || fail "replacement link argc, got ${args[*]:-empty}"
[[ ${args[0]} == 10 && ${args[1]} == 20 && ${args[2]} == 11 && ${args[3]} == 21 ]] \
  || fail "replacement must be port ids 10 20 11 21, got ${args[*]:-empty}"
for a in "${args[@]}"; do
  [[ $a =~ ^[0-9]+$ ]] || fail "pw-link must take port ids, got $a"
done

cat >"$tmpdir/pw-dump" <<'EOF'
#!/usr/bin/env bash
cat <<'JSON'
[{"id":30,"type":"PipeWire:Interface:Metadata","props":{"metadata.name":"default"},"metadata":[
   {"key":"default.audio.sink","type":"Spa:String:JSON","value":{"name":"alsa_output.pci-Speaker"}}]},
 {"id":1,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"omavoice"}}},
 {"id":2,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"omavoice.aec.sink"}}},
 {"id":3,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"alsa_output.pci-Speaker"}}},
 {"id":4,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"zoom"}}},
 {"id":7,"type":"PipeWire:Interface:Link","info":{"props":{"link.output.node":1,"link.input.node":4}}},
 {"id":10,"type":"PipeWire:Interface:Port","info":{"props":{"node.id":3,"port.name":"monitor_MONO"}}},
 {"id":20,"type":"PipeWire:Interface:Port","info":{"props":{"node.id":2,"port.name":"input_FL"}}},
 {"id":21,"type":"PipeWire:Interface:Port","info":{"props":{"node.id":2,"port.name":"input_FR"}}}]
JSON
EOF
chmod +x "$tmpdir/pw-dump"
rm -f -- "$log" "$linklog"
hold=$("$ctl" aec-sync)
[[ $hold == hold ]] || fail "mono fan-out must print hold, got ${hold:-empty}"
[[ -f $log ]] && fail "mono fan-out must not destroy links"
[[ -f $linklog ]] || fail "one monitor must feed every echo-cancel input"
mapfile -t args < "$linklog"
[[ ${#args[@]} -eq 4 ]] || fail "fan-out argc, got ${args[*]:-empty}"
[[ ${args[0]} == 10 && ${args[1]} == 20 && ${args[2]} == 10 && ${args[3]} == 21 ]] \
  || fail "monitor_MONO must feed input_FL and input_FR, got ${args[*]:-empty}"
for a in "${args[@]}"; do
  [[ $a == *:* ]] && fail "fan-out must not pass a bare node or node:port: $a"
done

cat >"$tmpdir/pw-dump" <<'EOF'
#!/usr/bin/env bash
cat <<'JSON'
[{"id":30,"type":"PipeWire:Interface:Metadata","props":{"metadata.name":"default"},"metadata":[
   {"key":"default.audio.sink","type":"Spa:String:JSON","value":{"name":"alsa_output.pci-Speaker"}}]},
 {"id":1,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"omavoice"}}},
 {"id":2,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"omavoice.aec.sink"}}},
 {"id":3,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"alsa_output.pci-Speaker"}}},
 {"id":4,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"zoom"}}},
 {"id":8,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"other_sink"}}},
 {"id":7,"type":"PipeWire:Interface:Link","info":{"props":{"link.output.node":1,"link.input.node":4}}},
 {"id":9,"type":"PipeWire:Interface:Link","info":{"props":{"link.output.node":8,"link.output.port":50,"link.input.node":2,"link.input.port":21}}},
 {"id":12,"type":"PipeWire:Interface:Port","info":{"props":{"node.id":3,"port.name":"playback_FL"}}},
 {"id":50,"type":"PipeWire:Interface:Port","info":{"props":{"node.id":8,"port.name":"monitor_FL"}}},
 {"id":21,"type":"PipeWire:Interface:Port","info":{"props":{"node.id":2,"port.name":"input_FR"}}}]
JSON
EOF
chmod +x "$tmpdir/pw-dump"
rm -f -- "$log" "$linklog"
hold=$("$ctl" aec-sync)
[[ $hold == hold ]] || fail "no-monitor hold must print hold, got ${hold:-empty}"
[[ -f $log ]] && fail "no monitors must not destroy a foreign link, got $(cat "$log" 2>/dev/null)"
[[ -s $linklog ]] && fail "no monitors must not pw-link"

cat >"$tmpdir/pw-dump" <<'EOF'
#!/usr/bin/env bash
cat <<'JSON'
[{"id":30,"type":"PipeWire:Interface:Metadata","props":{"metadata.name":"default"},"metadata":[
   {"key":"default.audio.sink","type":"Spa:String:JSON","value":{"name":"alsa_output.pci-Speaker"}}]},
 {"id":1,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"omavoice"}}},
 {"id":2,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"omavoice.aec.sink"}}},
 {"id":3,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"alsa_output.pci-Speaker"}}},
 {"id":4,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"zoom"}}},
 {"id":8,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"other_sink"}}},
 {"id":7,"type":"PipeWire:Interface:Link","info":{"props":{"link.output.node":1,"link.input.node":4}}},
 {"id":9,"type":"PipeWire:Interface:Link","info":{"props":{"link.output.node":8,"link.output.port":50,"link.input.node":2,"link.input.port":22}}},
 {"id":10,"type":"PipeWire:Interface:Port","info":{"props":{"node.id":3,"port.name":"monitor_FL"}}},
 {"id":11,"type":"PipeWire:Interface:Port","info":{"props":{"node.id":3,"port.name":"monitor_FR"}}},
 {"id":20,"type":"PipeWire:Interface:Port","info":{"props":{"node.id":2,"port.name":"input_FL"}}},
 {"id":21,"type":"PipeWire:Interface:Port","info":{"props":{"node.id":2,"port.name":"input_FR"}}},
 {"id":22,"type":"PipeWire:Interface:Port","info":{"props":{"node.id":2,"port.name":"input_MONO"}}},
 {"id":50,"type":"PipeWire:Interface:Port","info":{"props":{"node.id":8,"port.name":"monitor_FL"}}}]
JSON
EOF
chmod +x "$tmpdir/pw-dump"
rm -f -- "$log" "$linklog"
hold=$("$ctl" aec-sync)
[[ $hold == hold ]] || fail "unpaired input must print hold, got ${hold:-empty}"
[[ -f $log ]] && fail "FL/FR must not destroy a link into input_MONO, got $(cat "$log" 2>/dev/null)"
mapfile -t args < "$linklog"
[[ ${args[0]} == 10 && ${args[1]} == 20 && ${args[2]} == 11 && ${args[3]} == 21 ]] \
  || fail "two monitors must not cross channels, got ${args[*]:-empty}"

cat >"$tmpdir/pw-dump" <<'EOF'
#!/usr/bin/env bash
cat <<'JSON'
[{"id":30,"type":"PipeWire:Interface:Metadata","props":{"metadata.name":"default"},"metadata":[
   {"key":"default.audio.sink","type":"Spa:String:JSON","value":{"name":"150"}}]},
 {"id":1,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"omavoice"}}},
 {"id":2,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"omavoice.aec.sink"}}},
 {"id":3,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"150"}}},
 {"id":8,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"omavoice.aec"}}},
 {"id":4,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"zoom"}}},
 {"id":7,"type":"PipeWire:Interface:Link","info":{"props":{"link.output.node":1,"link.input.node":4}}},
 {"id":10,"type":"PipeWire:Interface:Port","info":{"props":{"node.id":3,"port.name":"monitor_FL"}}},
 {"id":150,"type":"PipeWire:Interface:Port","info":{"props":{"node.id":8,"port.name":"output_FL"}}},
 {"id":20,"type":"PipeWire:Interface:Port","info":{"props":{"node.id":2,"port.name":"input_FL"}}},
 {"id":21,"type":"PipeWire:Interface:Port","info":{"props":{"node.id":2,"port.name":"input_FR"}}}]
JSON
EOF
chmod +x "$tmpdir/pw-dump"
rm -f -- "$log" "$linklog"
hold=$("$ctl" aec-sync)
[[ $hold == hold ]] || fail "digit sink name must still print hold, got ${hold:-empty}"
[[ -s $linklog ]] && fail "digit sink name must not pw-link, got $(cat "$linklog" 2>/dev/null)"

cat >"$tmpdir/pw-dump" <<'EOF'
#!/usr/bin/env bash
cat <<'JSON'
[{"id":30,"type":"PipeWire:Interface:Metadata","props":{"metadata.name":"default"},"metadata":[
   {"key":"default.audio.sink","type":"Spa:String:JSON","value":{"name":"alsa_output.pci-Speaker"}}]},
 {"id":1,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"omavoice"}}},
 {"id":2,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"omavoice.aec.sink"}}},
 {"id":3,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"alsa_output.pci-Speaker"}}},
 {"id":80,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":10}}},
 {"id":4,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"zoom"}}},
 {"id":7,"type":"PipeWire:Interface:Link","info":{"props":{"link.output.node":1,"link.input.node":4}}},
 {"id":9,"type":"PipeWire:Interface:Link","info":{"props":{"link.output.node":80,"link.output.port":50,"link.input.node":2,"link.input.port":20}}},
 {"id":10,"type":"PipeWire:Interface:Port","info":{"props":{"node.id":3,"port.name":"monitor_FL"}}},
 {"id":11,"type":"PipeWire:Interface:Port","info":{"props":{"node.id":3,"port.name":"monitor_FR"}}},
 {"id":20,"type":"PipeWire:Interface:Port","info":{"props":{"node.id":2,"port.name":"input_FL"}}},
 {"id":21,"type":"PipeWire:Interface:Port","info":{"props":{"node.id":2,"port.name":"input_FR"}}}]
JSON
EOF
chmod +x "$tmpdir/pw-dump"
rm -f -- "$log" "$linklog"
hold=$("$ctl" aec-sync)
[[ $hold == hold ]] || fail "numeric node.name must still print hold, got ${hold:-empty}"
[[ -f $log ]] && fail "numeric node.name must not destroy the blocked input's link, got $(cat "$log" 2>/dev/null)"
[[ -f $linklog ]] || fail "the other channel must still be linked"
mapfile -t args < "$linklog"
[[ ${#args[@]} -eq 2 ]] || fail "a numeric node.name 10 must block that port id, got ${args[*]:-empty}"
[[ ${args[0]} == 11 && ${args[1]} == 21 ]] || fail "must link only FR port ids, got ${args[*]:-empty}"

cat >"$tmpdir/pw-dump" <<'EOF'
#!/usr/bin/env bash
cat <<'JSON'
[{"id":30,"type":"PipeWire:Interface:Metadata","props":{"metadata.name":"default"},"metadata":[
   {"key":"default.audio.sink","type":"Spa:String:JSON","value":{"name":"alsa_output.pci-Speaker"}}]},
 {"id":1,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"omavoice"}}},
 {"id":2,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"omavoice.aec.sink"}}},
 {"id":3,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"alsa_output.pci-Speaker"}}},
 {"id":80,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"numeric_path","object.path":10}}},
 {"id":4,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"zoom"}}},
 {"id":7,"type":"PipeWire:Interface:Link","info":{"props":{"link.output.node":1,"link.input.node":4}}},
 {"id":9,"type":"PipeWire:Interface:Link","info":{"props":{"link.output.node":80,"link.output.port":50,"link.input.node":2,"link.input.port":20}}},
 {"id":10,"type":"PipeWire:Interface:Port","info":{"props":{"node.id":3,"port.name":"monitor_FL"}}},
 {"id":11,"type":"PipeWire:Interface:Port","info":{"props":{"node.id":3,"port.name":"monitor_FR"}}},
 {"id":20,"type":"PipeWire:Interface:Port","info":{"props":{"node.id":2,"port.name":"input_FL"}}},
 {"id":21,"type":"PipeWire:Interface:Port","info":{"props":{"node.id":2,"port.name":"input_FR"}}}]
JSON
EOF
chmod +x "$tmpdir/pw-dump"
rm -f -- "$log" "$linklog"
hold=$("$ctl" aec-sync)
[[ $hold == hold ]] || fail "numeric object.path must still print hold, got ${hold:-empty}"
[[ -f $log ]] && fail "numeric object.path must not destroy the blocked input's link, got $(cat "$log" 2>/dev/null)"
[[ -f $linklog ]] || fail "the other channel must still be linked"
mapfile -t args < "$linklog"
[[ ${#args[@]} -eq 2 ]] || fail "a numeric object.path 10 must block that port id, got ${args[*]:-empty}"
[[ ${args[0]} == 11 && ${args[1]} == 21 ]] || fail "must link only FR port ids, got ${args[*]:-empty}"

cat >"$tmpdir/pw-dump" <<'EOF'
#!/usr/bin/env bash
cat <<'JSON'
[{"id":30,"type":"PipeWire:Interface:Metadata","props":{"metadata.name":"default"},"metadata":[
   {"key":"default.audio.sink","type":"Spa:String:JSON","value":{"name":"alsa_output.pci-Speaker"}}]},
 {"id":1,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"omavoice"}}},
 {"id":2,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"omavoice.aec.sink"}}},
 {"id":3,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"alsa_output.pci-Speaker"}}},
 {"id":4,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"zoom"}}},
 {"id":8,"type":"PipeWire:Interface:Node","info":{"props":{"node.name":"other_sink"}}},
 {"id":7,"type":"PipeWire:Interface:Link","info":{"props":{"link.output.node":1,"link.input.node":4}}},
 {"id":9,"type":"PipeWire:Interface:Link","info":{"props":{"link.output.node":8,"link.output.port":50,"link.input.node":2,"link.input.port":21}}},
 {"id":10,"type":"PipeWire:Interface:Port","info":{"props":{"node.id":3,"port.name":"monitor_FL"}}},
 {"id":20,"type":"PipeWire:Interface:Port","info":{"props":{"node.id":2,"port.name":"input_FL"}}},
 {"id":21,"type":"PipeWire:Interface:Port","info":{"props":{"node.id":2,"port.name":"input_FR"}}},
 {"id":50,"type":"PipeWire:Interface:Port","info":{"props":{"node.id":8,"port.name":"output_FL"}}}]
JSON
EOF
chmod +x "$tmpdir/pw-dump"
rm -f -- "$log" "$linklog"
hold=$("$ctl" aec-sync)
[[ $hold == hold ]] || fail "single monitor fan-out must print hold, got ${hold:-empty}"
[[ -f $log ]] || fail "a foreign link on a channel the monitor will feed must be replaced"
mapfile -t destroyed < "$log"
[[ ${destroyed[0]} == destroy && ${destroyed[1]} == 9 ]] || fail "must destroy only link 9, got ${destroyed[*]:-empty}"
mapfile -t args < "$linklog"
[[ ${args[0]} == 10 && ${args[1]} == 20 && ${args[2]} == 10 && ${args[3]} == 21 ]] \
  || fail "one monitor_FL must feed input_FL and input_FR, got ${args[*]:-empty}"

echo "ctl.test: ok"
