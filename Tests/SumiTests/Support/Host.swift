import AppKit
import SwiftUI

@testable import Sumi

/// An offscreen window that shows one message, like a chat app does.
@MainActor
final class Host {
  static let width: CGFloat = 720

  let window: NSWindow
  let hostingView = NSHostingView(rootView: AnyView(EmptyView()))

  init() {
    _ = NSApplication.shared

    hostingView.frame = NSRect(x: 0, y: 0, width: Self.width, height: 900)
    window = NSWindow(
      contentRect: hostingView.frame,
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    window.appearance = NSAppearance(named: .aqua)
    window.contentView = hostingView
  }

  /// Shows `text`, and waits until SwiftUI and AppKit are done with it.
  func show(_ text: String, openURL: OpenURLAction? = nil) {
    var view = AnyView(Self.message(text))
    if let openURL {
      view = AnyView(view.environment(\.openURL, openURL))
    }

    hostingView.rootView = view
    hostingView.layoutSubtreeIfNeeded()
    for _ in 0..<5 {
      CFRunLoopRunInMode(.defaultMode, 0, true)
    }
    hostingView.layoutSubtreeIfNeeded()
  }

  var textView: BlockTextView? {
    hostingView.firstSubview(of: BlockTextView.self)
  }

  /// A message as a chat app shows it, plus a custom view for `chart` code blocks.
  private static func message(_ text: String) -> some View {
    ScrollView {
      MarkdownText(text)
        .font(.system(size: 15))
        .markdownLinkStyle(linkStyle)
        .markdownCodeBlock("chart") { code in
          Text(code).padding().background(.yellow)
        }
        .frame(width: width)
    }
  }

  private static func linkStyle(_ link: MarkdownLink) -> MarkdownLinkStyle {
    guard link.url.isFileURL else { return .text }

    if link.url.hasDirectoryPath {
      return .symbol("folder")
    }
    return .symbol("chevron.left.forwardslash.chevron.right")
  }
}

extension NSView {
  func firstSubview<View: NSView>(of type: View.Type) -> View? {
    for subview in subviews {
      if let match = subview as? View ?? subview.firstSubview(of: type) {
        return match
      }
    }
    return nil
  }

  /// Sends a press and a release at `point`.
  func click(at point: CGPoint) {
    let location = convert(point, to: nil)
    func event(_ type: NSEvent.EventType) -> NSEvent {
      NSEvent.mouseEvent(
        with: type,
        location: location,
        modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: window?.windowNumber ?? 0,
        context: nil,
        eventNumber: 0,
        clickCount: 1,
        pressure: 1
      )!
    }

    mouseDown(with: event(.leftMouseDown))
    mouseUp(with: event(.leftMouseUp))
  }
}
