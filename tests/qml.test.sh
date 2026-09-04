#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { echo "qml.test: $*" >&2; exit 1; }

grep -q 'id: afterPeakMonitor' "$root/Panel.qml" || fail "Panel needs afterPeakMonitor"
grep -q 'id: rowPeak' "$root/Panel.qml" || fail "each mic row needs a peak monitor"
grep -q 'PwNodePeakMonitor' "$root/Panel.qml" || fail "Panel must use PwNodePeakMonitor"
grep -q 'afterPeakMonitor.peak' "$root/Panel.qml" || fail "selected row must show After"
grep -q 'enabled: root.opened && !!node' "$root/Panel.qml" || fail "row meters must run only while the panel is open"
grep -q 'Util.alpha' "$root/Panel.qml" || fail "meters must use Omarchy audio chrome"
grep -q 'setMeterHold' "$root/Service.qml" || fail "Service must expose setMeterHold"
grep -q 'pw-cat' "$root/Service.qml" || fail "Service must hold the graph with pw-cat"
grep -q '"--target", Model.NODE_NAME' "$root/Service.qml" || fail "pw-cat must target omavoice"
grep -q '/dev/null' "$root/Service.qml" || fail "meter hold must discard audio"
grep -q 'afterNode' "$root/Service.qml" || fail "Service must expose afterNode"
grep -q 'nodeNamed' "$root/Service.qml" || fail "Service must look up capture nodes by name"
grep -q '"version": "0.1.6"' "$root/manifest.json" || fail "manifest must be 0.1.6"

grep -q 'setListen' "$root/Service.qml" && fail "Listen must be gone from Service"
grep -q 'listenProcess' "$root/Service.qml" && fail "Listen process must be gone"
grep -q 'pw-loopback' "$root/Service.qml" && fail "pw-loopback must be gone"
grep -q 'toggleListen' "$root/Panel.qml" && fail "Listen must be gone from Panel"
grep -q 'Listen (use headphones)' "$root/Panel.qml" && fail "Listen row must be gone"
grep -q 'id: beforePeakMonitor' "$root/Panel.qml" && fail "hero Before/After meters must be gone"
grep -q 'label: "Before"' "$root/Panel.qml" && fail "hero Before bar must be gone"

echo "qml.test: ok"
