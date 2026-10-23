import AppKit

/// A view that draws its own text, with working links: a click opens them, the pointer
/// turns into a hand over them, and the one under the pointer gets an underline.
class DrawnTextView: NSView {
  /// A link in one of the drawn strings: which string, and the range of its text.
  private struct LinkSpot: Equatable {
    var index: Int
    var range: NSRange
  }

  private var pressedLink: URL?
  private var hoveredLink: LinkSpot?

  /// What the view draws, and where. Subclasses fill this in.
  var drawnTexts: [(string: NSAttributedString, rect: CGRect)] { [] }

  override var isFlipped: Bool { true }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)

    addTrackingArea(.hover(owner: self))
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  /// Call this when the text changes, so the hand cursor moves to the new links.
  func textDidChange() {
    hoveredLink = nil
    window?.invalidateCursorRects(for: self)
    needsDisplay = true
  }

  /// Draws the strings in `dirtyRect`, with the hovered link underlined.
  func drawTexts(in dirtyRect: CGRect) {
    for (index, text) in drawnTexts.enumerated() where text.rect.intersects(dirtyRect) {
      guard let hoveredLink, hoveredLink.index == index else {
        text.string.drawText(in: text.rect)
        continue
      }

      let underlined = NSMutableAttributedString(attributedString: text.string)
      underlined.addAttribute(
        .underlineStyle,
        value: NSUnderlineStyle.single.rawValue,
        range: hoveredLink.range
      )
      underlined.drawText(in: text.rect)
    }
  }

  override func resetCursorRects() {
    for (string, rect) in drawnTexts {
      for linkRect in string.linkRects(drawnIn: rect) {
        addCursorRect(linkRect, cursor: .pointingHand)
      }
    }
  }

  // MARK: Mouse

  override func mouseMoved(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)

    var link: LinkSpot?
    for (index, (string, rect)) in drawnTexts.enumerated() {
      if let found = string.link(at: point, drawnIn: rect) {
        link = LinkSpot(index: index, range: string.textRange(ofLinkAt: found.range))
        break
      }
    }
    guard link != hoveredLink else { return }

    hoveredLink = link
    needsDisplay = true
  }

  override func mouseExited(with event: NSEvent) {
    guard hoveredLink != nil else { return }

    hoveredLink = nil
    needsDisplay = true
  }

  override func mouseDown(with event: NSEvent) {
    pressedLink = link(at: event)
    if pressedLink == nil {
      super.mouseDown(with: event)
    }
  }

  override func mouseUp(with event: NSEvent) {
    guard let pressedLink else {
      super.mouseUp(with: event)
      return
    }

    self.pressedLink = nil
    if link(at: event) == pressedLink {
      open(pressedLink)
    }
  }

  /// Opens the link through the text view around this view, so its delegate handles the
  /// click like any other link.
  private func open(_ url: URL) {
    var view = superview
    while let current = view, !(current is NSTextView) {
      view = current.superview
    }

    if let textView = view as? NSTextView {
      textView.clicked(onLink: url, at: 0)
    } else {
      NSWorkspace.shared.open(url)
    }
  }

  private func link(at event: NSEvent) -> URL? {
    let point = convert(event.locationInWindow, from: nil)
    for (string, rect) in drawnTexts {
      if let link = string.link(at: point, drawnIn: rect) {
        return link.url
      }
    }
    return nil
  }
}
