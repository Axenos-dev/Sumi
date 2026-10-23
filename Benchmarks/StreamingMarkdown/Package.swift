// swift-tools-version: 6.3

import PackageDescription

// Microsoft's SwiftStreamingMarkdown pins an older swift-markdown than Sumi, so it
// gets a package of its own.
let package = Package(
  name: "Bench",
  platforms: [.macOS(.v26)],
  dependencies: [
    .package(
      url: "https://github.com/microsoft/SwiftStreamingMarkdown",
      revision: "95bb755a9b23a1aea8682b9ebc912cb72b176c95"
    )
  ],
  targets: [
    .executableTarget(
      name: "Bench",
      dependencies: [
        .product(name: "SwiftStreamingMarkdown", package: "SwiftStreamingMarkdown")
      ],
      swiftSettings: [.swiftLanguageMode(.v5)]
    )
  ]
)
