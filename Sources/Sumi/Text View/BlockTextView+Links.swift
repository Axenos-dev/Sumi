import AppKit

/// Underlines the link under the pointer. It's a temporary attribute, so only the drawing
/// changes and the text doesn't lay out again.
extension BlockTextView {
  override func mouseMoved(with event: NSEvent) {
    // The tracking area also gets moves over views on top of the text, like a copy
    // button. Those views set their own cursor.
    let viewUnderPointer = window?.contentView?.hitTest(event.locationInWindow)
    if let viewUnderPointer, !viewUnderPointer.isDescendant(of: self) {
      viewUnderPointer.cursorUpdate(with: event)
      showHoveredLink(at: nil)
      return
    }

    super.mouseMoved(with: event)
    showHoveredLink(at: convert(event.locationInWindow, from: nil))
  }

  override func mouseExited(with event: NSEvent) {
    super.mouseExited(with: event)
    showHoveredLink(at: nil)
  }

  /// Underlines the link at `point`, and removes the underline from the last one.
  func showHoveredLink(at point: CGPoint?) {
    guard let layoutManager else { return }

    let linkRange = point.flatMap(linkRange(at:))
    guard linkRange != hoveredLinkRange else { return }

    if let hoveredLinkRange {
      layoutManager.removeTemporaryAttribute(
        .underlineStyle,
        forCharacterRange: hoveredLinkRange
      )
    }
    if let linkRange {
      layoutManager.addTemporaryAttribute(
        .underlineStyle,
        value: NSUnderlineStyle.single.rawValue,
        forCharacterRange: linkRange
      )
    }
    hoveredLinkRange = linkRange
  }

  /// The text of the link at `point`, without its icon.
  private func linkRange(at point: CGPoint) -> NSRange? {
    guard let layoutManager, let textContainer, let textStorage else { return nil }

    let origin = textContainerOrigin
    let point = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
    let glyph = layoutManager.glyphIndex(for: point, in: textContainer)
    let glyphRect = layoutManager.boundingRect(
      forGlyphRange: NSRange(location: glyph, length: 1),
      in: textContainer
    )
    guard glyphRect.contains(point) else { return nil }

    var range = NSRange()
    let link = textStorage.attribute(
      .link,
      at: layoutManager.characterIndexForGlyph(at: glyph),
      longestEffectiveRange: &range,
      in: textStorage.fullRange
    )
    return link == nil ? nil : textStorage.textRange(ofLinkAt: range)
  }
}
