#!/bin/bash
# Full Sculptor test suite = 3 invocations because local-package schemes are
# invisible to -workspace. Counts are intentionally not hard-coded.
set -uo pipefail
cd "$(dirname "$0")/.."
SIM="${SIM:-$(xcrun simctl list devices available | grep -m1 -o 'iPhone [^(]*' | sed 's/ *$//')}"
DEST="platform=iOS Simulator,name=$SIM"
LOGDIR="${TMPDIR:-/tmp}"
FAIL=0
run() {  # run <label> <dir> <scheme> [extra xcodebuild args...]
  local label="$1" dir="$2" scheme="$3"; shift 3
  local log="$LOGDIR/sculptor-tests-$label.log"
  echo "== $label ($scheme) =="
  ( cd "$dir" && xcodebuild test -scheme "$scheme" "$@" -destination "$DEST" ) > "$log" 2>&1
  if grep -q "TEST SUCCEEDED" "$log"; then
    grep -Eo "Test run with [0-9]+ tests.*passed" "$log" | tail -1
  else
    echo "FAILED — see $log"; tail -5 "$log"; FAIL=1
  fi
}
run audioengine Packages/AudioEngine AudioEngine
run designsystem Packages/DesignSystem DesignSystem
run app . Sculptor-Workspace -workspace Sculptor.xcworkspace
exit $FAIL
