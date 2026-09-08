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

echo "$meeting" | grep -A2 'name = libpipewire-module-filter-chain' | grep -q nofail \
  && fail "filter-chain must not nofail or an empty host stays up without omavoice"
echo "$meeting" | grep -q 'audio.aec' || fail "meeting must map audio.aec spa lib"
echo "$meeting" | grep -q 'monitor.mode = true' || fail "meeting AEC must use monitor.mode"
echo "$meeting" | grep -q 'node.name = "omavoice.aec.sink"' || fail "meeting AEC sink must be named so it can suspend"
echo "$meeting" | grep -A4 'node.name = "omavoice.aec.sink"' | grep -q 'node.passive = true' \
  || fail "meeting AEC sink must be node.passive"
echo "$meeting" | grep -q 'node.suspend-on-idle = true' || fail "meeting AEC playback must suspend on idle"
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
echo "$meeting" | grep -A16 'node.name = "omavoice.capture"' | grep -q 'node.dont-fallback = true' \
  || fail "meeting capture must not fall back onto bluetooth"
echo "$meeting" | grep -A16 'node.name = "omavoice.capture"' | grep -q 'node.linger = true' \
  || fail "meeting capture must linger so dont-fallback does not destroy omavoice"
echo "$meeting" | grep -A16 'node.name = "omavoice.capture"' | grep -q 'node.dont-move = true' \
  || fail "meeting capture must not be dragged onto bluetooth"
echo "$meeting" | grep -A16 'node.name = "omavoice.capture"' | grep -q 'Stream/Input/Audio/Internal' \
  && fail "meeting capture Internal hides omavoice from the session"
echo "$podcast" | grep -A16 'node.name = "omavoice.capture"' | grep -q 'node.dont-fallback' \
  && fail "podcast capture dont-fallback destroys omavoice when the mic is not visible yet"
echo "$clean" | grep -A16 'node.name = "omavoice.capture"' | grep -q 'node.dont-fallback' \
  && fail "clean capture dont-fallback destroys omavoice when the mic is not visible yet"
echo "$meeting" | grep -A12 'node.name = "omavoice.aec.capture"' | grep -q 'node.linger = true' \
  || fail "AEC capture must linger on the named mic"
echo "$meeting" | grep -A12 'node.name = "omavoice.aec.capture"' | grep -q 'node.dont-move = true' \
  || fail "AEC capture must not be dragged onto bluetooth"
echo "$meeting" | grep -A16 'node.name = "omavoice.capture"' | grep -q 'stream.dont-remix = true' \
  || fail "omavoice.capture must not remix"
echo "$meeting" | grep -A16 'media.class = Audio/Source' | grep -q 'node.virtual = true' \
  || fail "omavoice source must be node.virtual"
echo "$meeting" | grep -A16 'media.class = Audio/Source' | grep -q 'media.role = Communication' \
  || fail "omavoice source must be Communication"
echo "$meeting" | grep -A16 'media.class = Audio/Source' | grep -q 'session.suspend-timeout-seconds = 0' \
  || fail "omavoice source must not idle-destroy after 3s"
echo "$meeting" | grep -A16 'media.class = Audio/Source' | grep -q 'node.always-process' \
  && fail "always-process makes capture fail target-not-found and destroys After"
echo "$meeting" | grep -A16 'media.class = Audio/Source' | grep -q 'stream.dont-remix = true' \
  || fail "omavoice source must not remix"
echo "$meeting" | grep -q 'audio.position = \[ MONO \]' || fail "meeting must be mono"
echo "$meeting" | grep -q 'node.latency = 256/48000' || fail "meeting must pin 256/48000"
echo "$meeting" | grep -q 'lsp-plug.in/plugins/lv2/compressor_mono' || fail "meeting needs compressor_mono"
echo "$meeting" | grep -q 'lsp-plug.in/plugins/lv2/limiter_mono' || fail "meeting needs limiter_mono"
echo "$meeting" | grep -q 'noise_suppressor_stereo' && fail "meeting must not use stereo RNNoise"
echo "$meeting" | grep -q 'deep_filter' && fail "auto meeting must not stack DFN"
echo "$meeting" | grep -q 'bq_highpass' || fail "meeting must high-pass in 0.3"
echo "$meeting" | grep -q 'name = eq_body' || fail "meeting must emit eq_body"
echo "$meeting" | grep -q 'name = eq_pres' || fail "meeting must emit eq_pres"
echo "$meeting" | grep -q 'name = eq_air' || fail "meeting must emit eq_air"
echo "$meeting" | grep -q 'bq_peaking' || fail "meeting voice EQ uses peaking bands"
echo "$meeting" | grep -q 'bq_highshelf' || fail "meeting air band must be highshelf"
echo "$meeting" | grep -A5 'name = eq_body' | grep -q '"Freq" = 250' || fail "eq_body must peak at 250 Hz"
echo "$meeting" | grep -A5 'name = eq_body' | grep -q '"Q" = 0.9' || fail "eq_body Q must be 0.9"
echo "$meeting" | grep -A5 'name = eq_pres' | grep -q '"Freq" = 3000' || fail "eq_pres must peak at 3000 Hz"
echo "$meeting" | grep -A5 'name = eq_pres' | grep -q '"Q" = 1.0' || fail "eq_pres Q must be 1.0"
echo "$meeting" | grep -A5 'name = eq_air' | grep -q '"Freq" = 8000' || fail "eq_air must shelf at 8000 Hz"
echo "$meeting" | grep -A5 'name = eq_air' | grep -q '"Q" = 0.707' || fail "eq_air Q must be 0.707"
echo "$meeting" | grep -A5 'name = eq_body' | grep -q '"Gain" = 2.0' || fail "meeting Warm body must be +2.0"
echo "$meeting" | grep -A5 'name = eq_pres' | grep -q '"Gain" = -1.5' || fail "meeting Warm presence must be -1.5"
echo "$podcast" | grep -q 'name = eq_body' || fail "podcast must emit voice EQ"
echo "$podcast" | grep -A5 'name = eq_body' | grep -q '"Gain" = -2.5' || fail "podcast Clear body must be -2.5"
echo "$podcast" | grep -A5 'name = eq_pres' | grep -q '"Gain" = 2.0' || fail "podcast Clear mid must be +2.0"
echo "$clean" | grep -q 'name = eq_body' && fail "clean must not emit voice EQ"
echo "$clean" | grep -q 'name = eq_pres' && fail "clean must not emit eq_pres"
echo "$clean" | grep -q 'name = eq_air' && fail "clean must not emit eq_air"
echo "$clean" | grep -q 'bq_peaking' && fail "clean must not emit peaking EQ"
echo "$clean" | grep -q 'bq_highshelf' && fail "clean must not emit highshelf EQ"
meeting_neutral="$(dump meeting --eq neutral)"
echo "$meeting_neutral" | grep -A4 'name = hp' | grep -q '"Freq" = 80.0' || fail "Neutral look must high-pass at 80 Hz"
echo "$meeting_neutral" | grep -q 'name = eq_body' || fail "Neutral must keep eq_body for live Gain"
echo "$meeting_neutral" | grep -q 'name = eq_pres' || fail "Neutral must keep eq_pres for live Gain"
echo "$meeting_neutral" | grep -q 'name = eq_air' || fail "Neutral must keep eq_air for live Gain"
echo "$meeting_neutral" | grep -A5 'name = eq_body' | grep -q '"Gain" = 0.0' || fail "Neutral body must be 0 dB"
echo "$meeting_neutral" | grep -A5 'name = eq_pres' | grep -q '"Gain" = 0.0' || fail "Neutral presence must be 0 dB"
echo "$meeting_neutral" | grep -A5 'name = eq_air' | grep -q '"Gain" = 0.0' || fail "Neutral air must be 0 dB"
meeting_bright="$(dump meeting --eq bright)"
echo "$meeting_bright" | grep -A4 'name = hp' | grep -q '"Freq" = 100.0' || fail "Bright look must raise HPF to 100 Hz"
echo "$meeting_bright" | grep -A5 'name = eq_air' | grep -q '"Gain" = 2.5' || fail "Bright look air gain must be +2.5"
meeting_air_alias="$(dump meeting --eq air)"
echo "$meeting_air_alias" | grep -A5 'name = eq_air' | grep -q '"Gain" = 2.5' || fail "old --eq air must map to Bright"
meeting_presence_alias="$(dump meeting --eq presence)"
echo "$meeting_presence_alias" | grep -A5 'name = eq_body' | grep -q '"Gain" = -2.5' || fail "old --eq presence must map to Clear"
echo "$meeting_presence_alias" | grep -A5 'name = eq_pres' | grep -q '"Gain" = 2.0' || fail "old --eq presence must map to Clear"
meeting_body_trim="$(dump meeting --eq warm --eq-body-db 1)"
echo "$meeting_body_trim" | grep -A5 'name = eq_body' | grep -q '"Gain" = 3.0' || fail "Warm --eq-body-db 1 must bake +3.0"
meeting_body_clamp="$(dump meeting --eq warm --eq-body-db 12)"
echo "$meeting_body_clamp" | grep -A5 'name = eq_body' | grep -q '"Gain" = 8.0' || fail "Warm --eq-body-db 12 must clamp trim to +8.0"

echo "$podcast" | grep -q 'bq_highpass' || fail "podcast must high-pass before NS"
echo "$podcast" | grep -q 'monitor.mode' && fail "podcast must not enable AEC this release"
echo "$podcast" | grep -q 'audio.position = \[ MONO \]' || fail "podcast must be mono"
echo "$podcast" | grep -q 'node.latency = 256/48000' || fail "podcast must pin 256/48000"
if grep -q libdeep_filter_ladspa.so <<<"$podcast"; then
  echo "$podcast" | grep -q 'deep_filter_mono' || fail "podcast must use DFN mono when present"
  echo "$podcast" | grep -q 'denoise:Audio In' || fail "DFN ports are Audio In / Audio Out"
  echo "$podcast" | grep -q 'denoise:Input' && fail "DFN must not use RNNoise Input/Output port names"
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
echo "$meeting_dfn" | grep -q 'denoise:Audio In' || fail "meeting DFN must link Audio In"
echo "$meeting_dfn" | grep -q 'noise_suppressor' && fail "meeting DFN must not stack RNNoise"
echo "$meeting" | grep -q 'denoise:Input' || fail "meeting RNNoise ports are Input/Output"

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

set +e
"$run" --dump --preset meeting --target 'foo"bar' --dir "$root" >/dev/null 2>&1
evil=$?
set -e
[[ $evil -eq 2 ]] || fail "quoted --target must be rejected, got $evil"

echo "dump.test: ok"
