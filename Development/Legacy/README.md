# Development-only reference framework

This directory vendors FSCalendar 2.8.4 from the local `FSCalendar-master` source snapshot. The source checkout had no Git metadata; `SOURCE-HASHES.json` records SHA-256 hashes of the original framework files. The root MIT license retains the upstream attribution.

`FSCalendarLegacy.h` is the only added framework source file. It is an umbrella header for the development Xcode target. The original implementation files are unchanged. This target is never a dependency of the distributed Swift products.

The demo supplies accessibility identifiers and fixed fixture state through its adapter. Its legacy characterization tests intentionally retain the old programmatic-selection callback behavior, out-of-bounds exception, and aligned-month preceding placeholder week.
