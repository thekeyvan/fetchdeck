// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "FetchDeck",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .executable(
      name: "FetchDeckApp",
      targets: ["FetchDeckApp"]
    )
  ],
  targets: [
    .executableTarget(
      name: "FetchDeckApp"
    ),
    .testTarget(
      name: "FetchDeckAppTests",
      dependencies: ["FetchDeckApp"]
    ),
  ],
  swiftLanguageVersions: [.v5]
)
