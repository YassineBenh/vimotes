// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "ViMotes",
  platforms: [.macOS(.v13)],
  products: [
    .library(name: "ViMotesCore", targets: ["ViMotesCore"]),
    .executable(name: "ViMotes", targets: ["ViMotes"]),
  ],
  dependencies: [
    .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6")
  ],
  targets: [
    .target(name: "ViMotesCore"),
    .executableTarget(
      name: "ViMotes",
      dependencies: [
        "ViMotesCore",
        .product(name: "Sparkle", package: "Sparkle"),
      ]
    ),
    .testTarget(
      name: "ViMotesCoreTests",
      dependencies: ["ViMotesCore"]
    ),
    .testTarget(
      name: "ViMotesTests",
      dependencies: ["ViMotes"]
    ),
  ]
)
