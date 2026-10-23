import AppKit
import SwiftUI
import Testing

@testable import Sumi

/// Links in text, in link icons, and in tables, which draw their own text.
@MainActor
struct LinkTests {
  let markdown = """
    Open [switch.go](file:///demo/switch.go) or [the note](myapp://notes/42) in `Switch`.

    | File |
    | --- |
    | [delete.go](file:///demo/delete.go) |
    """

  @Test func copyLeavesOutIconsAndCodePadding() throws {
    let host = Host()
    host.show(markdown)
    let textView = try #require(host.textView)

    let wholeText = NSRange(location: 0, length: textView.string.utf16.count)
    let copied = textView.attributedSubstring(
      forProposedRange: wholeText,
      actualRange: nil
    )

    #expect(copied?.string == "Open switch.go or the note in Switch.\nFile\ndelete.go")
  }

  @Test func pointerUnderlinesOnlyTheTextOfALink() throws {
    let host = Host()
    host.show(markdown)
    let textView = try #require(host.textView)

    let linkText = (textView.string as NSString).range(of: "switch.go")
    let point = center(of: linkText, in: textView)
    textView.mouseMoved(with: moveEvent(to: point, in: textView))

    func isUnderlined(_ index: Int) -> Bool {
      let underline = textView.layoutManager?.temporaryAttribute(
        .underlineStyle,
        atCharacterIndex: index,
        effectiveRange: nil
      )
      return underline != nil
    }
    #expect(isUnderlined(linkText.location))
    #expect(!isUnderlined(linkText.location - 2), "the icon in front isn't underlined")
  }

  @Test func clicksGoToTheOpenURLAction() throws {
    var openedURLs: [String] = []
    let openURL = OpenURLAction { url in
      openedURLs.append(url.absoluteString)
      return .handled
    }

    let host = Host()
    host.show(markdown, openURL: openURL)
    let textView = try #require(host.textView)
    let table = try #require(textView.firstSubview(of: TableView.self))

    // AppKit handles clicks on links in the text, so the delegate gets them directly.
    let wholeText = NSRange(location: 0, length: textView.string.utf16.count)
    textView.textStorage?.enumerateAttribute(.link, in: wholeText) { value, range, _ in
      if let value {
        textView.clicked(onLink: value, at: range.location)
      }
    }

    // A table finds the link under the pointer itself. Its link starts the last row.
    table.click(at: CGPoint(x: 30, y: table.bounds.height - 8))

    let expected = [
      "file:///demo/switch.go",
      "myapp://notes/42",
      "file:///demo/delete.go",
    ]
    #expect(openedURLs == expected)
  }

  private func center(of range: NSRange, in textView: NSTextView) -> CGPoint {
    let screenRect = textView.firstRect(forCharacterRange: range, actualRange: nil)
    let windowRect = textView.window?.convertFromScreen(screenRect) ?? .zero
    let rect = textView.convert(windowRect, from: nil)
    return CGPoint(x: rect.midX, y: rect.midY)
  }

  private func moveEvent(to point: CGPoint, in view: NSView) -> NSEvent {
    NSEvent.mouseEvent(
      with: .mouseMoved,
      location: view.convert(point, to: nil),
      modifierFlags: [],
      timestamp: ProcessInfo.processInfo.systemUptime,
      windowNumber: view.window?.windowNumber ?? 0,
      context: nil,
      eventNumber: 0,
      clickCount: 0,
      pressure: 0
    )!
  }
}
