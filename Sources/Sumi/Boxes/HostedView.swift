import AppKit
import SwiftUI

/// A SwiftUI view in a box, like the app's own view for a code block.
///
/// SwiftUI has to lay out the view to know its height, so this costs more than the AppKit
/// boxes. One hosting controller stays for the life of the box, so a streaming block
/// updates its view instead of making a new one.
struct HostedContent: BoxContent {
  let view: AnyView
  let copiedText: String

  private var host = Host()
  private let version: Int

  @MainActor private static var lastVersion = 0

  init(view: AnyView, copiedText: String) {
    self.view = view
    self.copiedText = copiedText
    Self.lastVersion += 1
    version = Self.lastVersion
  }

  mutating func keepWork(from previous: any BoxContent) {
    if let previous = previous as? HostedContent {
      host = previous.host
    }
  }

  func makeView() -> NSView {
    host.show(view, version: version)
    return host.controller.view
  }

  func update(_ view: NSView) {
    host.show(self.view, version: version)
  }

  func size(forWidth width: CGFloat) -> CGSize {
    host.show(view, version: version)
    return CGSize(width: width, height: host.height(forWidth: width))
  }
}

/// The hosting controller of one box. It stays when the content changes.
@MainActor
private final class Host {
  let controller = NSHostingController(rootView: AnyView(EmptyView()))

  private var shownVersion = 0
  private var measured: (width: CGFloat, height: CGFloat)?
  private var isResizeScheduled = false

  init() {
    // The text view sets the frame. The view shouldn't size itself.
    controller.sizingOptions = []
  }

  func show(_ view: AnyView, version: Int) {
    guard version != shownVersion else { return }

    shownVersion = version
    measured = nil
    controller.rootView = AnyView(
      view.onGeometryChange(for: CGFloat.self, of: \.size.height) { [weak self] _ in
        self?.scheduleResize()
      }
    )
    // SwiftUI takes a new root view lazily. Without this, the next measurement gets the
    // old content.
    controller.view.layoutSubtreeIfNeeded()
  }

  func height(forWidth width: CGFloat) -> CGFloat {
    if let measured, measured.width == width {
      return measured.height
    }

    let proposal = CGSize(width: width, height: .greatestFiniteMagnitude)
    let height = ceil(controller.sizeThatFits(in: proposal).height)
    measured = (width, height)
    return height
  }

  /// The view can change its height on its own, like a diagram that finishes drawing.
  /// Then the text lays out again around it.
  private func scheduleResize() {
    guard !isResizeScheduled else { return }
    isResizeScheduled = true

    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      isResizeScheduled = false

      guard let old = measured else { return }
      measured = nil
      guard height(forWidth: old.width) != old.height else { return }

      let view = controller.view
      (view.superview as? BlockTextView)?.boxViewDidChangeSize(view)
    }
  }
}
