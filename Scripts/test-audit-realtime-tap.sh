#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AUDIT="$ROOT/Scripts/audit-realtime-tap.sh"
FIXTURE_DIR="$ROOT/Scripts/Fixtures/RealtimeTapAudit"
ASSEMBLY="$FIXTURE_DIR/RealtimeTapAuditFixture.S"
OLD_SWIFT_THUNK="$FIXTURE_DIR/OldSwiftThunk.swift"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/realtime-tap-audit.XXXXXX")"
SDKROOT="$(xcrun --sdk iphoneos --show-sdk-path)"
CLANG="$(xcrun --sdk iphoneos --find clang)"
SWIFTC="$(xcrun --sdk iphoneos --find swiftc)"
failures=0

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

fixture_objects() {
  local root="$1"

  printf '%s\n' \
    "$root/Build/Intermediates.noindex/AudioEngine.build/Release-iphoneos/AudioEngine.build/Objects-normal/arm64"
}

compile_assembly() {
  local output="$1"
  shift

  "$CLANG" \
    -target arm64-apple-ios17.0 \
    -isysroot "$SDKROOT" \
    -x assembler-with-cpp \
    "$@" \
    -c "$ASSEMBLY" \
    -o "$output"
}

build_root() {
  local name="$1"
  local mutation="${2:-}"
  local root="$TMP_ROOT/$name"
  local objects
  local bridge_flags=''
  local mailbox_flags=''

  objects="$(fixture_objects "$root")"
  mkdir -p "$objects"

  case "$mutation" in
    bridge-ownership) bridge_flags='-DBRIDGE_OWNERSHIP=1' ;;
    bridge-indirect) bridge_flags='-DBRIDGE_INDIRECT=1' ;;
    bridge-register-return) bridge_flags='-DBRIDGE_REGISTER_RETURN=1' ;;
    submit-allocation) mailbox_flags='-DSUBMIT_ALLOCATION=1' ;;
    submit-lock) mailbox_flags='-DSUBMIT_LOCK=1' ;;
    submit-dispatch) mailbox_flags='-DSUBMIT_DISPATCH=1' ;;
    submit-unexpected) mailbox_flags='-DSUBMIT_UNEXPECTED=1' ;;
    submit-local-call) mailbox_flags='-DSUBMIT_LOCAL_CALL=1' ;;
    missing-symbol) mailbox_flags='-DMISSING_C_ENTRY=1' ;;
    ambiguous-symbol) mailbox_flags='-DAMBIGUOUS_SUBMIT=1' ;;
    '' | old-swift-thunk | missing-object | ambiguous-object) ;;
    *) echo "unknown fixture mutation: $mutation" >&2; exit 1 ;;
  esac

  compile_assembly \
    "$objects/NoiseEngine.o" \
    -DOBJECT_NOISE_ENGINE=1
  compile_assembly \
    "$objects/RealtimeTapBridge.o" \
    -DOBJECT_REALTIME_TAP_BRIDGE=1 \
    $bridge_flags
  compile_assembly \
    "$objects/SpectrumAnalyzer.o" \
    -DOBJECT_SPECTRUM_ANALYZER=1
  compile_assembly \
    "$objects/SpectrumMailbox.o" \
    -DOBJECT_SPECTRUM_MAILBOX=1 \
    $mailbox_flags
  compile_assembly \
    "$objects/RealtimeAtomics.o" \
    -DOBJECT_REALTIME_ATOMICS=1

  if test "$mutation" = old-swift-thunk; then
    "$SWIFTC" \
      -target arm64-apple-ios17.0 \
      -sdk "$SDKROOT" \
      -parse-as-library \
      -module-name RealtimeTapFixture \
      -emit-object "$OLD_SWIFT_THUNK" \
      -o "$objects/NoiseEngine.o"
  fi
  if test "$mutation" = missing-object; then
    rm "$objects/SpectrumMailbox.o"
  fi
  if test "$mutation" = ambiguous-object; then
    duplicate="$(dirname "$(dirname "$(dirname "$objects")")")/Duplicate.build/Objects-normal/arm64"
    mkdir -p "$duplicate"
    cp "$objects/SpectrumMailbox.o" "$duplicate/SpectrumMailbox.o"
  fi

  printf '%s\n' "$root"
}

expect_success() {
  local name="$1"
  local root
  local output

  root="$(build_root "$name")"
  if ! output="$("$AUDIT" "$root" 2>&1)"; then
    echo "fixture failed unexpectedly: $name" >&2
    printf '%s\n' "$output" >&2
    failures=$((failures + 1))
    return
  fi
  echo "PASS (accepted): $name"
}

expect_failure() {
  local name="$1"
  local expected="$2"
  local root
  local output

  root="$(build_root "$name" "$name")"
  if output="$("$AUDIT" "$root" 2>&1)"; then
    echo "RED (unexpectedly accepted): $name" >&2
    failures=$((failures + 1))
    return
  fi
  if ! rg -F -q "$expected" <<< "$output"; then
    echo "RED (wrong rejection): $name" >&2
    printf '%s\n' "$output" >&2
    failures=$((failures + 1))
    return
  fi
  echo "PASS (rejected): $name"
}

expect_success valid-chain
expect_failure old-swift-thunk \
  'Swift AVAudioPCMBuffer or AVAudioTime callback thunk is still present'
expect_failure bridge-ownership \
  'forbidden ownership traffic'
expect_failure bridge-indirect \
  'forbidden indirect branch'
expect_failure bridge-register-return \
  'forbidden return register'
expect_failure submit-allocation \
  'forbidden allocation/free traffic'
expect_failure submit-lock \
  'forbidden lock/semaphore traffic'
expect_failure submit-dispatch \
  'forbidden dispatch/task/wakeup/blocking traffic'
expect_failure submit-unexpected \
  'unexpected branch target'
expect_failure submit-local-call \
  'unexpected local call'
expect_failure missing-object \
  'SpectrumMailbox.o must resolve exactly once (found 0)'
expect_failure ambiguous-object \
  'SpectrumMailbox.o must resolve exactly once (found 2)'
expect_failure missing-symbol \
  'fixed spectrum mailbox C entry must resolve exactly once (found 0)'
expect_failure ambiguous-symbol \
  'Release specialized SpectrumMailbox.submit must resolve exactly once (found 2)'

if test "$failures" -ne 0; then
  echo "audit Mach-O fixture self-tests: FAIL ($failures)" >&2
  exit 1
fi
echo 'audit Mach-O fixture self-tests: PASS'
