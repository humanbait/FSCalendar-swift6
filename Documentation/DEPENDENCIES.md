# Dependency audit

Audited during legacy removal on 2026-09-19.

## Distributed libraries

There are no external Swift package, CocoaPods, Carthage, or vendored third-party dependencies in the current checkout. The Xcode project references only this repository's local Swift package.

| Module | Dependencies |
| --- | --- |
| FSCalendarCore | Apple Foundation |
| FSCalendar | FSCalendarCore, Apple UIKit |
| FSCalendarAppKit | FSCalendarCore, Apple AppKit |

Swift 6.2 or later in Swift 6 language mode, iOS 16+, and macOS 13+ remain required. Apple frameworks may expose additional system modules transitively.

## Development and tests

- CalendarDemoSupport uses Foundation only. Its unused FSCalendarCore dependency was removed from SwiftPM and the iOS showcase project generator. The obsolete `-ObjC` app linker flag was also removed.
- CalendarContractSupport uses FSCalendarCore and Foundation; it is used by renderer tests, not distributed calendar products.
- Showcase apps link the corresponding calendar modules and shared demo fixtures. Tests additionally use Apple XCTest.
- Building and testing require Xcode, SwiftPM, and Xcode command-line tools (including xcodebuild, simctl, devicectl, and xcresulttool as applicable).
- Project generation and evidence scripts use Python 3's standard library only. Shell scripts also use system utilities and Git. Physical-device testing requires development signing.

The Objective-C framework, adapter, and legacy-only tests were removed. The evidence summarizer still recognizes historical legacy results without depending on legacy code. The root MIT license and upstream attribution are retained.
