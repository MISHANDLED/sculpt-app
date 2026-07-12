#!/bin/bash
set -euo pipefail

ROOT="${1:?usage: audit-realtime-tap.sh DERIVED_DATA_ROOT}"
NOISE_OBJECT="$(find "$ROOT" -path '*Objects-normal/arm64/NoiseEngine.o' -print -quit)"
BRIDGE_OBJECT="$(find "$ROOT" -path '*Objects-normal/arm64/RealtimeTapBridge.o' -print -quit)"

test -n "$NOISE_OBJECT" || {
  echo 'NoiseEngine.o not found' >&2
  exit 1
}
test -n "$BRIDGE_OBJECT" || {
  echo 'RealtimeTapBridge.o not found' >&2
  exit 1
}

NOISE_SYMBOLS="$(nm -nm "$NOISE_OBJECT")"
if rg -q 'AVAudioPCMBuffer.*Ieggg_AbDIeyByy_TR' <<< "$NOISE_SYMBOLS"; then
  echo 'Swift AVAudioPCMBuffer tap thunk is still present' >&2
  exit 1
fi

BRIDGE_SYMBOLS="$(nm -nm "$BRIDGE_OBJECT")"
BLOCK_INVOKES="$(
  awk '$2 == "(__TEXT,__text)" && $NF ~ /^___rt_audio_node_install_spectrum_tap_block_invoke/ {print $NF}' \
    <<< "$BRIDGE_SYMBOLS"
)"
FORWARDERS="$(
  awk '$2 == "(__TEXT,__text)" && $NF == "_rt_spectrum_tap_forward" {print $NF}' \
    <<< "$BRIDGE_SYMBOLS"
)"
test -n "$BLOCK_INVOKES" || {
  echo 'spectrum tap block invoke not found' >&2
  exit 1
}
test -n "$FORWARDERS" || {
  echo 'spectrum tap forwarder not found' >&2
  exit 1
}

CALLBACKS="$BLOCK_INVOKES $FORWARDERS"
for symbol in $CALLBACKS; do
  DISASSEMBLY="$(
    xcrun llvm-objdump \
      --disassemble-symbols="$symbol" \
      --reloc \
      "$BRIDGE_OBJECT"
  )"
  if rg -q '(swift|objc)_[[:alnum:]_]*(retain|release|Retain|Release)|objc_storeStrong|_Block_object_(assign|dispose)' \
    <<< "$DISASSEMBLY"; then
    echo "ownership traffic in $symbol" >&2
    exit 1
  fi
done
