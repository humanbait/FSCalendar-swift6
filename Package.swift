// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FSCalendar",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "FSCalendarCore", targets: ["FSCalendarCore"]),
        .library(name: "FSCalendar", targets: ["FSCalendar"])
    ],
    targets: [
        .target(name: "FSCalendarCore"),
        .target(name: "FSCalendar", dependencies: ["FSCalendarCore"]),
        .testTarget(name: "FSCalendarCoreTests", dependencies: ["FSCalendarCore"]),
        .testTarget(name: "FSCalendarTests", dependencies: ["FSCalendar", "FSCalendarCore"])
    ],
    swiftLanguageModes: [.v6]
)
