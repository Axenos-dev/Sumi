import AppKit

/// Draws text backgrounds, like inline code, as rounded pills. The default layout manager
/// fills the whole line, line spacing included. The horizontal padding comes from kerns
/// in the text, so a pill is as wide as its text.
final class RoundedBackgroundLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
  private static let verticalPadding: CGFloat = 3.5
  private static let cornerRadius: CGFloat = 5

  /// Where the text container is in the view that draws right now.
  private var drawingOrigin: CGPoint = .zero

  override init() {
    super.init()
    delegate = self
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    delegate = self
  }

  /// Moves inline code to the next line in one piece when it fits there. Otherwise a path
  /// like `internal/volume/create.go` breaks after a slash.
  func layoutManager(
    _ layoutManager: NSLayoutManager,
    shouldBreakLineByWordBeforeCharacterAt index: Int
  ) -> Bool {
    guard index > 0 else { return true }

    let background: NSColor? = attribute(.backgroundColor, at: index)
    let backgroundBefore: NSColor? = attribute(.backgroundColor, at: index - 1)
    return background == nil || backgroundBefore == nil
  }

  override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
    drawingOrigin = origin
    super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
  }

  override func fillBackgroundRectArray(
    _ rectArray: UnsafePointer<NSRect>,
    count rectCount: Int,
    forCharacterRange charRange: NSRange,
    color: NSColor
  ) {
    // The selection comes through here too, in its own color. It draws as usual.
    let background: NSColor? = attribute(.backgroundColor, at: charRange.location)
    let font: NSFont? = attribute(.font, at: charRange.location)
    guard background == color, let font, let textContainer = textContainers.first else {
      super.fillBackgroundRectArray(
        rectArray,
        count: rectCount,
        forCharacterRange: charRange,
        color: color
      )
      return
    }

    let radius = Self.cornerRadius
    let path = NSBezierPath()
    for rect in UnsafeBufferPointer(start: rectArray, count: rectCount) {
      let pill = pillRect(around: rect, font: font, in: textContainer)
      path.append(NSBezierPath(roundedRect: pill, xRadius: radius, yRadius: radius))
    }

    color.setFill()
    path.fill()
  }

  /// A pill from a bit above the capital letters to a bit below the baseline.
  private func pillRect(
    around rect: CGRect,
    font: NSFont,
    in textContainer: NSTextContainer
  ) -> CGRect {
    let origin = drawingOrigin
    let point = CGPoint(x: rect.midX - origin.x, y: rect.midY - origin.y)
    let glyph = glyphIndex(for: point, in: textContainer)
    let line = lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
    let baseline = origin.y + line.minY + location(forGlyphAt: glyph).y

    // When code wraps, `rect` goes to the end of the line. The pill stops at the text.
    let usedLine = lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
    let maxX = min(rect.maxX, origin.x + usedLine.maxX)

    return CGRect(
      x: rect.minX,
      y: baseline - font.capHeight - Self.verticalPadding,
      width: maxX - rect.minX,
      height: font.capHeight + Self.verticalPadding * 2
    )
  }

  private func attribute<Value>(_ key: NSAttributedString.Key, at index: Int) -> Value? {
    guard let textStorage, index < textStorage.length else { return nil }
    return textStorage.attribute(key, at: index, effectiveRange: nil) as? Value
  }
}
