// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FSCalendar",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "FSCalendarCore", targets: ["FSCalendarCore"]),
        .library(name: "FSCalendar", targets: ["FSCalendar"]),
        .library(name: "FSCalendarAppKit", targets: ["FSCalendarAppKit"])
    ],
    targets: [
        .target(name: "FSCalendarCore"),
        .target(name: "CalendarContractSupport", dependencies: ["FSCalendarCore"], path: "Development/ContractSupport"),
        .target(name: "CalendarDemoSupport", dependencies: ["FSCalendarCore"], path: "Development/DemoSupport"),
        .target(name: "FSCalendarAppKit", dependencies: ["FSCalendarCore"]),
        .testTarget(name: "FSCalendarAppKitTests", dependencies: ["FSCalendarAppKit", "FSCalendarCore", "CalendarContractSupport"]),
        .target(name: "FSCalendar", dependencies: ["FSCalendarCore"]),
        .testTarget(name: "FSCalendarCoreTests", dependencies: ["FSCalendarCore"]),
        .testTarget(name: "FSCalendarTests", dependencies: ["FSCalendar", "FSCalendarCore", "CalendarContractSupport"])
    ],
    swiftLanguageModes: [.v6]
)
