#!/usr/bin/env bash
# Load a dumped Clean conf under unique node names and require a session client.
# Does not touch the live omavoice host.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
run="$root/scripts/omavoice-run"
fail() { echo "host-smoke.test: $*" >&2; exit 1; }

tmp=$(mktemp --suffix=.conf)
pid=""
cleanup() {
  if [[ -n $pid ]] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
  rm -f -- "$tmp"
}
trap cleanup EXIT

target=$(pw-dump 2>/dev/null | python3 -c '
import json, sys
data = json.load(sys.stdin)
for o in data:
    if not str(o.get("type", "")).endswith("Node"):
        continue
    p = (o.get("info") or {}).get("props") or {}
    name = p.get("node.name") or ""
    if name.startswith("alsa_input.") or name.startswith("bluez_input."):
        print(name)
        break
')
[[ -n $target ]] || fail "need a session capture source to load the smoke graph"

"$run" --dump --preset clean --target "$target" --dir "$root" \
  | sed 's/"omavoice/"omavoice.audit/g' >"$tmp"
grep -q 'node.name = "omavoice.audit"' "$tmp" || fail "smoke conf must rename the published source"
grep -q "target.object = \"$target\"" "$tmp" || fail "smoke conf must capture a real session source"

/usr/bin/pipewire -c "$tmp" >/dev/null 2>&1 &
pid=$!
sleep 0.8
kill -0 "$pid" 2>/dev/null || fail "pipewire -c exited instead of joining the session"

pw-cli ls Node 2>/dev/null | grep -q 'node.name = "omavoice.audit"' \
  || fail "omavoice.audit must appear in the session graph"

pw-cli ls Client 2>/dev/null | grep -q "pipewire.sec.pid = \"$pid\"" \
  || fail "host must be a session Client (pid $pid), not a D-Bus-only leftover"

kill "$pid" 2>/dev/null || true
wait "$pid" 2>/dev/null || true
pid=""
for i in $(seq 1 20); do
  pw-cli ls Node 2>/dev/null | grep -q 'node.name = "omavoice.audit"' || break
  sleep 0.1
done
pw-cli ls Node 2>/dev/null | grep -q 'node.name = "omavoice.audit"' \
  && fail "omavoice.audit must leave the graph after the smoke host exits"

echo "host-smoke.test: ok"
