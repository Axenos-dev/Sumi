import AppKit

/// A thin line across the text, for `---`.
final class RuleAttachment: NSTextAttachment, CopyableAttachment {
  let copiedText = "---"

  /// How far above the baseline the line goes: the middle of the lowercase letters.
  private let lineY: CGFloat

  init(font: NSFont) {
    lineY = font.xHeight / 2
    super.init(data: nil, ofType: nil)

    // One point of color, stretched across the line.
    image = NSImage(size: CGSize(width: 1, height: 1), flipped: false) { rect in
      NSColor.separatorColor.setFill()
      rect.fill()
      return true
    }
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func attachmentBounds(
    for textContainer: NSTextContainer?,
    proposedLineFragment lineFragment: CGRect,
    glyphPosition position: CGPoint,
    characterIndex: Int
  ) -> CGRect {
    CGRect(x: 0, y: lineY, width: lineFragment.width, height: 1)
  }
}
