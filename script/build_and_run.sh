#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-run}"
BUILD_DIR="$ROOT_DIR/artifacts/mac-run"
APP="$BUILD_DIR/Build/Products/Debug/CalendarShowcaseMac.app"
pkill -x CalendarShowcaseMac 2>/dev/null || true
mkdir -p "$BUILD_DIR"
xcodebuild -project "$ROOT_DIR/Example/CalendarShowcase.xcodeproj" -scheme CalendarShowcaseMac -destination 'platform=macOS,arch=arm64' -derivedDataPath "$BUILD_DIR" build > "$BUILD_DIR/build.log" 2>&1 || { tail -80 "$BUILD_DIR/build.log"; exit 1; }
case "$MODE" in
  run) open -n "$APP" ;;
  --verify|verify) open -n "$APP"; python3 -c 'import subprocess,time; end=time.monotonic()+10
while time.monotonic()<end:
 if subprocess.run(["pgrep","-x","CalendarShowcaseMac"],stdout=subprocess.DEVNULL).returncode==0: break
else: raise SystemExit("Mac application did not launch")' ;;
  --debug|debug) lldb -- "$APP/Contents/MacOS/CalendarShowcaseMac" ;;
  --logs|logs) open -n "$APP"; /usr/bin/log stream --info --style compact --predicate 'process == "CalendarShowcaseMac"' ;;
  --telemetry|telemetry) open -n "$APP"; /usr/bin/log stream --info --style compact --predicate 'subsystem == "com.spbgfs.fscalendar.calendarshowcasemac"' ;;
  *) echo "usage: $0 [--verify|--debug|--logs|--telemetry]" >&2; exit 2 ;;
esac
