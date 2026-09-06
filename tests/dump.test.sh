#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
run="$root/scripts/omavoice-run"
target="alsa_input.usb-TEST_MIC-00.analog-stereo"
live="${XDG_RUNTIME_DIR:-/tmp}/omavoice/host.conf"

dump() {
  "$run" --dump --preset "$1" --target "$target" --dir "$root" "${@:2}"
}

fail() { echo "dump.test: $*" >&2; exit 1; }

mkdir -p "$(dirname "$live")"
backup=""
if [[ -f $live ]]; then
  backup=$(mktemp)
  cp "$live" "$backup"
fi
printf 'SENTINEL_LIVE_CONF\n' > "$live"
dump meeting >/dev/null
grep -qx 'SENTINEL_LIVE_CONF' "$live" || fail "--dump must not overwrite the live host conf"
if [[ -n $backup ]]; then
  mv "$backup" "$live"
else
  rm -f "$live"
fi

meeting="$(dump meeting)"
meeting_good="$(dump meeting --quality good)"
meeting_best="$(dump meeting --quality best)"
podcast="$(dump podcast)"
podcast_good="$(dump podcast --quality good)"
podcast_best="$(dump podcast --quality best)"
clean="$(dump clean)"

echo "$meeting" | grep -q 'audio.aec' || fail "meeting must map audio.aec spa lib"
echo "$meeting" | grep -q 'monitor.mode = true' || fail "meeting AEC must use monitor.mode"
echo "$meeting" | grep -q 'webrtc.gain_control = false' || fail "meeting must disable webrtc AGC"
echo "$meeting" | grep -q 'webrtc.noise_suppression = false' || fail "meeting must not stack WebRTC NS"
echo "$meeting" | grep -q 'media.class = Audio/Sink' && fail "meeting must not invent an AEC sink"
echo "$meeting" | grep -A8 'node.name = "omavoice.aec"' | grep -q 'Stream/Output/Audio/Internal' \
  || fail "AEC source must be internal, not a second microphone"
echo "$meeting" | grep -q 'noise_suppressor_mono' || fail "meeting must use RNNoise mono"
echo "$meeting" | grep -q '"VAD Threshold (%)" = 80.0' || fail "meeting better VAD must be 80"
echo "$meeting" | grep -q '"VAD Grace Period (ms)" = 400' || fail "meeting better grace must be 400"
echo "$meeting_good" | grep -q '"VAD Threshold (%)" = 70.0' || fail "meeting good VAD must be 70"
echo "$meeting_good" | grep -q '"VAD Grace Period (ms)" = 500' || fail "meeting good grace must be 500"
echo "$meeting_best" | grep -q '"VAD Threshold (%)" = 85.0' || fail "meeting best VAD must be 85"
echo "$meeting_best" | grep -q '"VAD Grace Period (ms)" = 250' || fail "meeting best grace must be 250"
echo "$meeting" | grep -A10 'node.name = "omavoice.capture"' | grep -q 'node.dont-fallback = true' \
  || fail "omavoice.capture must not fall back to another mic"
echo "$meeting" | grep -A12 'node.name = "omavoice.capture"' | grep -q 'stream.dont-remix = true' \
  || fail "omavoice.capture must not remix"
echo "$meeting" | grep -A16 'media.class = Audio/Source' | grep -q 'node.virtual = true' \
  || fail "omavoice source must be node.virtual"
echo "$meeting" | grep -A16 'media.class = Audio/Source' | grep -q 'media.role = Communication' \
  || fail "omavoice source must be Communication"
echo "$meeting" | grep -A16 'media.class = Audio/Source' | grep -q 'session.suspend-timeout-seconds = 3' \
  || fail "omavoice source must suspend after 3s idle"
echo "$meeting" | grep -A16 'media.class = Audio/Source' | grep -q 'stream.dont-remix = true' \
  || fail "omavoice source must not remix"
echo "$meeting" | grep -q 'audio.position = \[ MONO \]' || fail "meeting must be mono"
echo "$meeting" | grep -q 'node.latency = 256/48000' || fail "meeting must pin 256/48000"
echo "$meeting" | grep -q 'lsp-plug.in/plugins/lv2/compressor_mono' || fail "meeting needs compressor_mono"
echo "$meeting" | grep -q 'lsp-plug.in/plugins/lv2/limiter_mono' || fail "meeting needs limiter_mono"
echo "$meeting" | grep -q 'noise_suppressor_stereo' && fail "meeting must not use stereo RNNoise"
echo "$meeting" | grep -q 'deep_filter' && fail "auto meeting must not stack DFN"

echo "$podcast" | grep -q 'bq_highpass' || fail "podcast must high-pass before NS"
echo "$podcast" | grep -q 'monitor.mode' && fail "podcast must not enable AEC this release"
echo "$podcast" | grep -q 'audio.position = \[ MONO \]' || fail "podcast must be mono"
echo "$podcast" | grep -q 'node.latency = 256/48000' || fail "podcast must pin 256/48000"
if grep -q libdeep_filter_ladspa.so <<<"$podcast"; then
  echo "$podcast" | grep -q 'deep_filter_mono' || fail "podcast must use DFN mono when present"
  echo "$podcast" | grep -q '"Attenuation Limit (dB)" = 70' || fail "podcast better DFN cap must be 70 dB"
  echo "$podcast_good" | grep -q '"Attenuation Limit (dB)" = 50' || fail "podcast good DFN cap must be 50 dB"
  echo "$podcast_best" | grep -q '"Attenuation Limit (dB)" = 85' || fail "podcast best DFN cap must be 85 dB"
  echo "$podcast" | grep -q 'deep_filter_stereo' && fail "podcast must not use stereo DFN"
  echo "$podcast" | grep -q 'noise_suppressor' && fail "podcast DFN must not stack RNNoise"
else
  echo "$podcast" | grep -q 'noise_suppressor_mono' || fail "podcast RNNoise fallback must be mono"
  echo "$podcast" | grep -q '"VAD Threshold (%)" = 85.0' || fail "podcast better VAD must be 85"
  echo "$podcast" | grep -q '"VAD Grace Period (ms)" = 200' || fail "podcast better grace must be 200"
  echo "$podcast_good" | grep -q '"VAD Threshold (%)" = 75.0' || fail "podcast good VAD must be 75"
  echo "$podcast_best" | grep -q '"VAD Threshold (%)" = 90.0' || fail "podcast best VAD must be 90"
fi

echo "$clean" | grep -q 'bq_highpass' || fail "clean must high-pass"
echo "$clean" | grep -q 'audio.position = \[ MONO \]' || fail "clean must be mono"
echo "$clean" | grep -q 'node.latency = 256/48000' || fail "clean must pin 256/48000"
echo "$clean" | grep -q 'noise_suppressor' && fail "clean must not denoise"
echo "$clean" | grep -q 'monitor.mode' && fail "clean must not enable AEC"

meeting_dfn="$(dump meeting --engine deepfilter)"
echo "$meeting_dfn" | grep -q 'monitor.mode = true' || fail "meeting DFN must keep AEC"
echo "$meeting_dfn" | grep -q 'webrtc.noise_suppression = false' || fail "meeting DFN must not stack WebRTC NS"
echo "$meeting_dfn" | grep -q 'bq_highpass' || fail "meeting DFN must high-pass before NS"
echo "$meeting_dfn" | grep -q 'deep_filter_mono' || fail "meeting --engine deepfilter must use DFN"
echo "$meeting_dfn" | grep -q 'noise_suppressor' && fail "meeting DFN must not stack RNNoise"

podcast_rn="$(dump podcast --engine rnnoise)"
echo "$podcast_rn" | grep -q 'noise_suppressor_mono' || fail "podcast --engine rnnoise must use RNNoise"
echo "$podcast_rn" | grep -q 'bq_highpass' || fail "podcast RNNoise must high-pass"
echo "$podcast_rn" | grep -q 'monitor.mode' && fail "podcast RNNoise must not enable AEC"
echo "$podcast_rn" | grep -q 'deep_filter' && fail "podcast RNNoise must not stack DFN"

echo "$meeting" | grep -q 'noise_suppressor_mono' || fail "auto meeting must still use RNNoise"

clean_forced="$(dump clean --engine deepfilter)"
echo "$clean_forced" | grep -q 'bq_highpass' || fail "clean stays high-pass when engine is forced"
echo "$clean_forced" | grep -q 'noise_suppressor' && fail "clean must not denoise when engine is forced"
echo "$clean_forced" | grep -q 'deep_filter' && fail "clean must not run DFN when engine is forced"

for kind in meeting podcast clean; do
  conf=""
  case $kind in
    meeting) conf=$meeting ;;
    podcast) conf=$podcast ;;
    clean) conf=$clean ;;
  esac
  echo "$conf" | grep -q 'name = preamp' || fail "$kind must emit a named preamp node"
  echo "$conf" | grep -q 'name = outgain' || fail "$kind must emit a named outgain node"
  echo "$conf" | grep -A2 'name = preamp' | grep -q 'label = mixer' || fail "$kind preamp must be mixer"
  echo "$conf" | grep -A2 'name = outgain' | grep -q 'label = mixer' || fail "$kind outgain must be mixer"
  echo "$conf" | grep -A3 'name = preamp' | grep -q '"Gain 1"' || fail "$kind preamp must expose Gain 1"
  echo "$conf" | grep -A3 'name = outgain' | grep -q '"Gain 1"' || fail "$kind outgain must expose Gain 1"
  echo "$conf" | grep -q 'inputs = \[ "preamp:In 1" \]' || fail "$kind must enter at preamp"
  echo "$conf" | grep -q 'outputs = \[ "outgain:Out" \]' || fail "$kind must exit at outgain"
done

gained="$(dump meeting --capture-gain-db 6 --output-gain-db -6)"
echo "$gained" | grep -A3 'name = preamp' | grep -q '"Gain 1" = 1.99526231' \
  || fail "capture +6 dB must bake linear ~2 on preamp"
echo "$gained" | grep -A3 'name = outgain' | grep -q '"Gain 1" = 0.50118723' \
  || fail "output -6 dB must bake linear ~0.5 on outgain"

meeting_clean="$(dump meeting --engine clean)"
echo "$meeting_clean" | grep -q 'noise_suppressor' && fail "meeting --engine clean must not denoise"
echo "$meeting_clean" | grep -q 'deep_filter' && fail "meeting --engine clean must not run DFN"
echo "$meeting_clean" | grep -q 'bq_highpass' || fail "meeting --engine clean still high-passes"

meeting_dfn_good="$(dump meeting --engine deepfilter --quality good)"
echo "$meeting_dfn_good" | grep -q '"Attenuation Limit (dB)" = 50' \
  || fail "meeting DFN good cap must be 50 dB"

echo "dump.test: ok"
