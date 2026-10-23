import AppKit

/// Text that a view draws itself, like a table cell, has no text view to find links or to
/// round the background of inline code. A throwaway layout of the same width does that.
extension NSAttributedString {
  /// The link at `point`, and the range of its characters, for text drawn in `rect`.
  func link(at point: CGPoint, drawnIn rect: CGRect) -> (url: URL, range: NSRange)? {
    guard rect.contains(point) else { return nil }

    let layout = TextLayout(self, width: rect.width)
    let point = CGPoint(x: point.x - rect.minX, y: point.y - rect.minY)
    guard let index = layout.characterIndex(at: point) else { return nil }

    var range = NSRange()
    let value = attribute(.link, at: index, longestEffectiveRange: &range, in: fullRange)

    switch value {
    case let url as URL:
      return (url, range)
    case let string as String:
      return URL(string: string).map { ($0, range) }
    default:
      return nil
    }
  }

  /// Where the links are, for text drawn in `rect`.
  func linkRects(drawnIn rect: CGRect) -> [CGRect] {
    var linkRanges: [NSRange] = []
    enumerateAttribute(.link, in: fullRange) { value, range, _ in
      if value != nil {
        linkRanges.append(range)
      }
    }
    guard !linkRanges.isEmpty else { return [] }

    let layout = TextLayout(self, width: rect.width)
    return linkRanges.flatMap { range in
      layout.rects(for: range).map { $0.offsetBy(dx: rect.minX, dy: rect.minY) }
    }
  }

  /// Draws the text in `rect`. Text with a background goes through the rounded layout
  /// manager, so inline code looks like it does in the text view.
  func drawText(in rect: CGRect) {
    guard hasBackgroundColor else {
      draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
      return
    }

    let layout = TextLayout(self, width: rect.width)
    let glyphs = layout.layoutManager.glyphRange(for: layout.textContainer)
    layout.layoutManager.drawBackground(forGlyphRange: glyphs, at: rect.origin)
    layout.layoutManager.drawGlyphs(forGlyphRange: glyphs, at: rect.origin)
  }

  /// The size of the text at `width`, as `drawText(in:)` draws it. Plain string drawing
  /// ignores the kern after the last character: the right padding of inline code.
  func drawnSize(forWidth width: CGFloat) -> CGSize {
    guard hasBackgroundColor else {
      let bounds = CGSize(width: width, height: .greatestFiniteMagnitude)
      let options: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
      return boundingRect(with: bounds, options: options).size
    }

    let layout = TextLayout(self, width: width)
    layout.layoutManager.ensureLayout(for: layout.textContainer)
    return layout.layoutManager.usedRect(for: layout.textContainer).size
  }

  private var hasBackgroundColor: Bool {
    var hasBackgroundColor = false
    enumerateAttribute(.backgroundColor, in: fullRange) { value, _, stop in
      if value != nil {
        hasBackgroundColor = true
        stop.pointee = true
      }
    }
    return hasBackgroundColor
  }
}

private struct TextLayout {
  let textStorage: NSTextStorage
  let layoutManager = RoundedBackgroundLayoutManager()
  let textContainer: NSTextContainer

  init(_ string: NSAttributedString, width: CGFloat) {
    textStorage = NSTextStorage(attributedString: string)
    let size = CGSize(width: width, height: .greatestFiniteMagnitude)
    textContainer = NSTextContainer(size: size)
    textContainer.lineFragmentPadding = 0

    layoutManager.addTextContainer(textContainer)
    textStorage.addLayoutManager(layoutManager)
  }

  /// The character under `point`, if there's one right there.
  func characterIndex(at point: CGPoint) -> Int? {
    let glyph = layoutManager.glyphIndex(for: point, in: textContainer)
    let glyphRect = layoutManager.boundingRect(
      forGlyphRange: NSRange(location: glyph, length: 1),
      in: textContainer
    )
    guard glyphRect.contains(point) else { return nil }

    return layoutManager.characterIndexForGlyph(at: glyph)
  }

  /// One rect per line that the characters in `range` cover.
  func rects(for range: NSRange) -> [CGRect] {
    let glyphs = layoutManager.glyphRange(
      forCharacterRange: range,
      actualCharacterRange: nil
    )

    var rects: [CGRect] = []
    layoutManager.enumerateEnclosingRects(
      forGlyphRange: glyphs,
      withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
      in: textContainer
    ) { rect, _ in
      rects.append(rect)
    }
    return rects
  }
}
