import AppKit
import Foundation
import Testing

/// Not a check: draws a Markdown file to a PNG next to it, for screenshots or a quick
/// look.
///
///     SNAPSHOT=notes.md swift test --filter snapshot
@Test(.enabled(if: ProcessInfo.processInfo.environment["SNAPSHOT"] != nil))
@MainActor
func snapshot() async throws {
  let path = try #require(ProcessInfo.processInfo.environment["SNAPSHOT"])
  let markdown = try String(contentsOfFile: path, encoding: .utf8)

  let host = Host()
  host.show(markdown)

  // Images load in the background, and need the main actor to finish.
  try await Task.sleep(for: .seconds(1))
  host.hostingView.layoutSubtreeIfNeeded()

  let textView = try #require(host.textView)
  let bitmap = try #require(textView.bitmapImageRepForCachingDisplay(in: textView.bounds))
  textView.cacheDisplay(in: textView.bounds, to: bitmap)

  let png = try #require(bitmap.representation(using: .png, properties: [:]))
  try png.write(to: URL(fileURLWithPath: path + ".png"))
}
