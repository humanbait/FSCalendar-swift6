#!/bin/sh
# Separate test hosts avoid contaminating Swift memory figures with all earlier scenario allocations.
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DEVICE=${1:-00008030-000948522284802E}
"$SCRIPT_DIR/test-device.sh" "$DEVICE" performance-legacy \
  -only-test-configuration 'Legacy baseline' \
  -only-testing:CalendarShowcaseTests/LegacyDriverTests/testRepeatedNavigationPerformance \
  -collect-test-diagnostics never
"$SCRIPT_DIR/test-device.sh" "$DEVICE" performance-swift \
  -only-test-configuration 'Swift rewrite' \
  -only-testing:CalendarShowcaseTests/SharedDriverTests/testSwiftRepeatedNavigationPerformance \
  -collect-test-diagnostics never
