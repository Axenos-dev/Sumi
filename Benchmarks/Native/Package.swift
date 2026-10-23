// swift-tools-version: 6.3

import PackageDescription

// Sumi next to MarkdownUI, Textual, and a plain text view.
let package = Package(
  name: "Bench",
  platforms: [.macOS(.v26)],
  dependencies: [
    .package(path: "../.."),
    .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", exact: "2.4.1"),
    .package(url: "https://github.com/gonzalezreal/textual", exact: "0.5.0"),
  ],
  targets: [
    .executableTarget(
      name: "Bench",
      dependencies: [
        .product(name: "Sumi", package: "Sumi"),
        .product(name: "MarkdownUI", package: "swift-markdown-ui"),
        .product(name: "Textual", package: "textual"),
      ],
      swiftSettings: [.swiftLanguageMode(.v5)]
    )
  ]
)
