#!/bin/bash
set -euo pipefail

fail() {
  echo "$*" >&2
  exit 1
}

line_count() {
  awk 'NF { count += 1 } END { print count + 0 }' <<< "$1"
}

test "$#" -eq 2 || test "$#" -eq 3 \
  || fail 'usage: audit-realtime-linkage.sh DERIVED_DATA_ROOT CONFIGURATION [SDK]'

root="$1"
configuration="$2"
sdk="${3:-iphoneos}"
case "$configuration" in
  Debug|Release) ;;
  *) fail "unsupported configuration: $configuration" ;;
esac
case "$sdk" in
  iphoneos|iphonesimulator) ;;
  *) fail "unsupported SDK product directory: $sdk" ;;
esac

test -d "$root/Build/Products" \
  || fail "missing build products: $root/Build/Products"
audio_objects="$(find "$root/Build/Products" \
  -path "*/${configuration}-${sdk}/AudioEngine.o" -print)"
if test "$(line_count "$audio_objects")" -ne 1; then
  fail "merged AudioEngine.o must resolve exactly once (found $(line_count "$audio_objects"))"
fi

audio_object="$audio_objects"
symbol_line="$(nm -m "$audio_object" \
  | awk '$NF == "_rt_spectrum_mailbox_submit" { print }')"
if test "$(line_count "$symbol_line")" -ne 1; then
  fail "merged AudioEngine.o must define rt_spectrum_mailbox_submit exactly once (found $(line_count "$symbol_line"))"
fi
if ! rg -q \
  '\) external( \[no dead strip\])? _rt_spectrum_mailbox_submit$' \
  <<< "$symbol_line"; then
  printf '%s\n' "$symbol_line" >&2
  fail 'rt_spectrum_mailbox_submit must remain externally linkable after the package merge'
fi

echo "realtime package linkage audit ($configuration): PASS"
