#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
run="$root/scripts/omavoice-run"
fail() { echo "control.test: $*" >&2; exit 1; }

skip() {
  echo "control.test: skip ($1)"
  exit 0
}

if ! command -v pw-cli >/dev/null 2>&1; then
  skip "no pw-cli"
fi

if ! pw-cli info 0 >/dev/null 2>&1; then
  skip "no pipewire"
fi

omavoice_id() {
  pw-cli ls Node 2>/dev/null | awk '
    /^[[:space:]]*id [0-9]+,/ { id=$2; gsub(/,/, "", id) }
    /node.name = "omavoice"/ { print id; exit }
  '
}

target=""
while IFS= read -r line; do
  if [[ $line =~ node.name\ =\ \"([^\"]+)\" ]]; then
    name="${BASH_REMATCH[1]}"
    case "$name" in
      omavoice*|alsa_output*|bluez*|midi*) continue ;;
      alsa_input*|*_input_*|*.monitor) continue ;;
    esac
  fi
done < /dev/null

# Prefer a real capture source; fall back to any Audio/Source that is not omavoice.
target=$(pw-cli ls Node 2>/dev/null | awk '
  /^[[:space:]]*id [0-9]+,/ { name="" }
  /node.name = "/ {
    gsub(/.*node.name = "/, "")
    gsub(/".*/, "")
    name=$0
  }
  /media.class = "Audio\/Source"/ {
    if (name != "" && name !~ /^omavoice/) { print name; exit }
  }
')

if [[ -z $target ]]; then
  skip "no capture source"
fi

host_pid=""
cleanup() {
  if [[ -n ${host_pid:-} ]] && kill -0 "$host_pid" 2>/dev/null; then
    kill "$host_pid" 2>/dev/null || true
    wait "$host_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT

"$run" --preset clean --target "$target" --dir "$root" >/dev/null 2>&1 &
host_pid=$!

id1=""
for _ in $(seq 1 30); do
  id1=$(omavoice_id || true)
  if [[ -n $id1 ]]; then
    break
  fi
  sleep 0.1
done

[[ -n $id1 ]] || fail "omavoice node did not appear"

pw-cli set-param "$id1" Props '{ params = [ "filter.graph:outgain:Gain" 1.5 ] }' >/dev/null
sleep 0.2

id2=$(omavoice_id || true)
[[ -n $id2 ]] || fail "omavoice node disappeared after control write"
[[ $id1 == "$id2" ]] || fail "control write restarted omavoice node"

echo "control.test: ok"
