// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LessonPlanner",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "LessonPlanner", targets: ["LessonPlanner"])],
    targets: [
        .executableTarget(name: "LessonPlanner"),
        .testTarget(name: "LessonPlannerTests", dependencies: ["LessonPlanner"])
    ]
)
