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
printf '%s\n' "\$@" > "$log"
EOF
chmod +x "$tmpdir/pw-cli"

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

echo "ctl.test: ok"
