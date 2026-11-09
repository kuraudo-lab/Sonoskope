// swift-tools-version: 5.10
import PackageDescription

let package = Package(
  name: "Sonoskope",
  defaultLocalization: "en",
  platforms: [.macOS("14.2")],
  products: [
    .executable(name: "Sonoskope", targets: ["Sonoskope"]),
    .library(name: "SonoskopeCore", targets: ["SonoskopeCore"]),
  ],
  targets: [
    .target(name: "SonoskopeCore", resources: [.process("Resources")]),
    .executableTarget(name: "Sonoskope", dependencies: ["SonoskopeCore"]),
    .testTarget(name: "SonoskopeCoreTests", dependencies: ["SonoskopeCore"]),
    .testTarget(name: "SonoskopeTests", dependencies: ["Sonoskope", "SonoskopeCore"]),
  ]
)
