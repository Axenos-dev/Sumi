// swift-tools-version: 6.3

import PackageDescription

let package = Package(
  name: "Sumi",
  platforms: [
    .macOS(.v26)
  ],
  products: [
    .library(name: "Sumi", targets: ["Sumi"])
  ],
  dependencies: [
    .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.8.0"),
    .package(url: "https://github.com/raspu/Highlightr.git", from: "2.3.0"),
    .package(url: "https://github.com/mgriebling/SwiftMath.git", from: "1.7.3"),
  ],
  targets: [
    .target(
      name: "Sumi",
      dependencies: [
        .product(name: "Markdown", package: "swift-markdown"),
        .product(name: "Highlightr", package: "Highlightr"),
        .product(name: "SwiftMath", package: "SwiftMath"),
      ]
    ),
    .testTarget(
      name: "SumiTests",
      dependencies: ["Sumi"]
    ),
  ]
)
