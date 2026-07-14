#!/bin/zsh
# Native end-to-end smoke test. Requires Accessibility permission for the
# invoking terminal/Codex process; the app itself uses an in-memory fixture.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d)"
DERIVED="$WORK/DerivedData"
LOG="$WORK/build.log"
SCREENSHOT="${MAC4DSTEM_UI_SMOKE_SCREENSHOT:-/tmp/mac4dstem-ui-smoke.png}"
: "${DEVELOPER_DIR:=/Applications/Xcode-beta.app/Contents/Developer}"
export DEVELOPER_DIR

cleanup() {
  local exit_code=$?
  if (( exit_code != 0 )); then
    screencapture -x /tmp/mac4dstem-ui-smoke-failure.png 2>/dev/null || true
    screencapture -x -D 2 /tmp/mac4dstem-ui-smoke-failure-display2.png 2>/dev/null || true
    cp "$LOG" /tmp/mac4dstem-ui-smoke-build.log 2>/dev/null || true
    cp "$WORK/calibration.log" /tmp/mac4dstem-ui-smoke-calibration.log 2>/dev/null || true
    cp "$WORK/app.log" /tmp/mac4dstem-ui-smoke-app.log 2>/dev/null || true
    echo "Failure artifacts: /tmp/mac4dstem-ui-smoke-{failure.png,build.log,app.log}" >&2
  fi
  if [[ -n "${APP_PID:-}" ]]; then kill "$APP_PID" 2>/dev/null || true; fi
  rm -rf "$WORK"
  return $exit_code
}
trap cleanup EXIT

xcodebuild -project "$ROOT/mac4DSTEM.xcodeproj" -scheme mac4DSTEM \
  -configuration Debug -derivedDataPath "$DERIVED" \
  PRODUCT_BUNDLE_IDENTIFIER=com.paullobpreis.mac4DSTEM.UISmoke \
  CODE_SIGNING_ALLOWED=NO build >"$LOG"
APP="$DERIVED/Build/Products/Debug/mac4DSTEM.app"
codesign --force --deep --sign - "$APP" 2>/dev/null

# Window frames are persisted by bundle identifier. A smoke run must not inherit
# a frame on a detached display from an earlier interactive session.
defaults delete com.paullobpreis.mac4DSTEM.UISmoke \
  "NSWindow Frame dataset-AppWindow-1" 2>/dev/null || true

launch_demo() {
  local log_name="$1"
  shift
  LLVM_PROFILE_FILE="$WORK/default-%p.profraw" \
    "$APP/Contents/MacOS/mac4DSTEM" --demo-fixture "$@" >"$WORK/$log_name" 2>&1 &
  APP_PID=$!
  sleep 1
  if ! kill -0 "$APP_PID" 2>/dev/null; then
    echo "Demo app exited before automation started" >&2
    exit 1
  fi
}

launch_demo calibration.log --demo-uncalibrated
CALIBRATION_RESULT="$(osascript "$ROOT/tools/ui-smoke-test/calibration.applescript" "$APP_PID")"
echo "$CALIBRATION_RESULT"
kill "$APP_PID" 2>/dev/null || true
wait "$APP_PID" 2>/dev/null || true
unset APP_PID

launch_demo app.log
WORKFLOW_RESULT="$(osascript "$ROOT/tools/ui-smoke-test/smoke.applescript" "$APP_PID")"
echo "$WORKFLOW_RESULT"
SESSION_STARTED=$(date +%s)
osascript "$ROOT/tools/ui-smoke-test/session-save.applescript" "$APP_PID" "$WORK"
SESSION_SECONDS=$(($(date +%s) - SESSION_STARTED))
SESSION_SIDECAR=("$WORK"/*.mac4dstem.h5(N))
if (( ${#SESSION_SIDECAR[@]} != 1 )) || [[ ! -s "$SESSION_SIDECAR[1]" ]]; then
  echo "UI smoke did not publish one non-empty session sidecar" >&2
  exit 1
fi
printf '{"calibration":"%s","workflows":"%s","session_save_seconds":%d}\n' \
  "$CALIBRATION_RESULT" "$WORKFLOW_RESULT" "$SESSION_SECONDS" \
  > /tmp/mac4dstem-ui-smoke-timings.json
sleep 1
screencapture -x "$SCREENSHOT"
echo "Screenshot: $SCREENSHOT"
echo "Timings: /tmp/mac4dstem-ui-smoke-timings.json"
