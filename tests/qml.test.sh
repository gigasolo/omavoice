#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { echo "qml.test: $*" >&2; exit 1; }

grep -q 'id: beforePeakMonitor' "$root/Panel.qml" || fail "Panel needs beforePeakMonitor"
grep -q 'id: afterPeakMonitor' "$root/Panel.qml" || fail "Panel needs afterPeakMonitor"
grep -q 'PwNodePeakMonitor' "$root/Panel.qml" || fail "Panel must use PwNodePeakMonitor"
grep -q 'enabled: root.opened && service.running' "$root/Panel.qml" || fail "meters must run only while the panel is open"
grep -q 'label: "Before"' "$root/Panel.qml" || fail "Panel needs a Before bar"
grep -q 'label: "After"' "$root/Panel.qml" || fail "Panel needs an After bar"
grep -q 'Util.alpha' "$root/Panel.qml" || fail "meters must use Omarchy audio chrome"
grep -q 'setMeterHold' "$root/Service.qml" || fail "Service must expose setMeterHold"
grep -q 'pw-cat' "$root/Service.qml" || fail "Service must hold the graph with pw-cat"
grep -q '"--target", Model.NODE_NAME' "$root/Service.qml" || fail "pw-cat must target omavoice"
grep -q '/dev/null' "$root/Service.qml" || fail "meter hold must discard audio"
grep -q 'beforeNode' "$root/Service.qml" || fail "Service must expose beforeNode"
grep -q 'afterNode' "$root/Service.qml" || fail "Service must expose afterNode"
grep -q '"version": "0.1.5"' "$root/manifest.json" || fail "manifest must be 0.1.5"

echo "qml.test: ok"
