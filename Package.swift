// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "CountdownScreenSaver",
  platforms: [.macOS(.v13)],
  products: [
    .library(name: "CountdownCore", targets: ["CountdownCore"]),
    .library(name: "CountdownUI", targets: ["CountdownUI"]),
    .executable(name: "CountdownPreview", targets: ["CountdownPreview"]),
  ],
  targets: [
    .target(name: "CountdownCore"),
    .target(name: "CountdownUI", dependencies: ["CountdownCore"]),
    .executableTarget(name: "CountdownPreview", dependencies: ["CountdownUI", "CountdownCore"]),
    .testTarget(
      name: "CountdownCoreTests", dependencies: ["CountdownCore"], resources: [.copy("Fixtures")]),
    .testTarget(name: "CountdownUITests", dependencies: ["CountdownUI", "CountdownCore"]),
  ]
)
