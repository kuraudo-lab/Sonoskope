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
    .binaryTarget(name: "Sparkle",
      url: "https://github.com/sparkle-project/Sparkle/releases/download/2.10.1/Sparkle-for-Swift-Package-Manager.zip",
      checksum: "4c2e48a3e50ebcc2c88a58a4c7264a1a99c3c31857ce754357afb9cdb323022a"),
    .target(name: "SonoskopeCore", resources: [.process("Resources")]),
    .executableTarget(name: "Sonoskope", dependencies: [
      "SonoskopeCore", "Sparkle"
    ], linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
    .testTarget(name: "SonoskopeCoreTests", dependencies: ["SonoskopeCore"]),
    .testTarget(name: "SonoskopeTests", dependencies: ["Sonoskope", "SonoskopeCore"],
      linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@loader_path/../../.."])]),
  ]
)
