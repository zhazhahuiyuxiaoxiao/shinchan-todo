// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShinchanTodo",
    platforms: [.macOS(.v14)],
    products: [.library(name: "TodoCore", targets: ["TodoCore"]), .executable(name: "ShinchanTodo", targets: ["ShinchanTodo"])],
    targets: [
        .target(name: "TodoCore"),
        .target(name: "TodoSystem", dependencies: ["TodoCore"]),
        .executableTarget(name: "ShinchanTodo", dependencies: ["TodoCore", "TodoSystem"], resources: [.process("Resources")]),
        .executableTarget(name: "CoreChecks", dependencies: ["TodoCore", "TodoSystem"], path: "Tests/TodoCoreTests")
    ],
    swiftLanguageModes: [.v5]
)
