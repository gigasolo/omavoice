#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
run="$root/scripts/omavoice-run"
target="alsa_input.usb-TEST_MIC-00.analog-stereo"

dump() {
  "$run" --dump --preset "$1" --target "$target" --dir "$root"
}

fail() { echo "dump.test: $*" >&2; exit 1; }

meeting="$(dump meeting)"
podcast="$(dump podcast)"
clean="$(dump clean)"

echo "$meeting" | grep -q 'audio.aec' || fail "meeting must map audio.aec spa lib"
echo "$meeting" | grep -q 'monitor.mode = true' || fail "meeting AEC must use monitor.mode"
echo "$meeting" | grep -q 'webrtc.gain_control = false' || fail "meeting must disable webrtc AGC"
echo "$meeting" | grep -q 'webrtc.noise_suppression = false' || fail "meeting must not stack WebRTC NS"
echo "$meeting" | grep -q 'media.class = Audio/Sink' && fail "meeting must not invent an AEC sink"
echo "$meeting" | grep -A8 'node.name = "omavoice.aec"' | grep -q 'Stream/Output/Audio/Internal' \
  || fail "AEC source must be internal, not a second microphone"
echo "$meeting" | grep -q 'noise_suppressor_mono' || fail "meeting must use RNNoise mono"
echo "$meeting" | grep -q '"VAD Threshold (%)" = 85.0' || fail "meeting VAD must be 85"
echo "$meeting" | grep -q '"VAD Grace Period (ms)" = 200' || fail "meeting grace must be 200"
echo "$meeting" | grep -q 'audio.position = \[ MONO \]' || fail "meeting must be mono"
echo "$meeting" | grep -q 'node.latency = 256/48000' || fail "meeting must pin 256/48000"
echo "$meeting" | grep -q 'lsp-plug.in/plugins/lv2/compressor_mono' || fail "meeting needs compressor_mono"
echo "$meeting" | grep -q 'lsp-plug.in/plugins/lv2/limiter_mono' || fail "meeting needs limiter_mono"
echo "$meeting" | grep -q 'noise_suppressor_stereo' && fail "meeting must not use stereo RNNoise"

echo "$podcast" | grep -q 'bq_highpass' || fail "podcast must high-pass before NS"
echo "$podcast" | grep -q 'monitor.mode' && fail "podcast must not enable AEC this release"
echo "$podcast" | grep -q 'audio.position = \[ MONO \]' || fail "podcast must be mono"
echo "$podcast" | grep -q 'node.latency = 256/48000' || fail "podcast must pin 256/48000"
if grep -q libdeep_filter_ladspa.so <<<"$podcast"; then
  echo "$podcast" | grep -q 'deep_filter_mono' || fail "podcast must use DFN mono when present"
  echo "$podcast" | grep -q '"Attenuation Limit (dB)" = 70' || fail "podcast DFN cap must be 70 dB"
  echo "$podcast" | grep -q 'deep_filter_stereo' && fail "podcast must not use stereo DFN"
else
  echo "$podcast" | grep -q 'noise_suppressor_mono' || fail "podcast RNNoise fallback must be mono"
  echo "$podcast" | grep -q '"VAD Threshold (%)" = 85.0' || fail "podcast VAD must be 85"
  echo "$podcast" | grep -q '"VAD Grace Period (ms)" = 200' || fail "podcast grace must be 200"
fi

echo "$clean" | grep -q 'bq_highpass' || fail "clean must high-pass"
echo "$clean" | grep -q 'audio.position = \[ MONO \]' || fail "clean must be mono"
echo "$clean" | grep -q 'node.latency = 256/48000' || fail "clean must pin 256/48000"
echo "$clean" | grep -q 'noise_suppressor' && fail "clean must not denoise"
echo "$clean" | grep -q 'monitor.mode' && fail "clean must not enable AEC"

echo "dump.test: ok"
