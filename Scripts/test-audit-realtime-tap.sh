#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AUDIT="$ROOT/Scripts/audit-realtime-tap.sh"

expect_failure() {
  local fixture="$1"
  local expected="$2"
  local output

  if output="$("$AUDIT" --fixture "$fixture" 2>&1)"; then
    echo "fixture unexpectedly passed: $fixture" >&2
    exit 1
  fi
  if ! rg -F -q "$expected" <<< "$output"; then
    echo "fixture failed through the wrong classifier: $fixture" >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi
  echo "PASS (rejected): $fixture"
}

expect_failure old-swift-thunk \
  'Swift AVAudioPCMBuffer tap thunk is still present'
expect_failure bridge-ownership \
  'forbidden ownership traffic'
expect_failure submit-allocation \
  'forbidden allocation/free traffic'
expect_failure submit-lock \
  'forbidden lock/semaphore traffic'
expect_failure submit-dispatch \
  'forbidden dispatch/task/wakeup/blocking traffic'
expect_failure submit-unexpected-call \
  'unexpected branch target'
expect_failure missing-symbol \
  'must resolve exactly once (found 0)'
expect_failure ambiguous-symbol \
  'must resolve exactly once (found 2)'

"$AUDIT" --fixture allowed-chain
echo 'PASS (accepted): allowed-chain'
echo 'audit callback-chain self-tests: PASS'
