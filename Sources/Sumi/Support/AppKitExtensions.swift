import AppKit

typealias TextAttributes = [NSAttributedString.Key: Any]

extension NSAttributedString {
  var fullRange: NSRange {
    NSRange(location: 0, length: length)
  }

  func font(at index: Int) -> NSFont? {
    guard index < length else { return nil }
    return attribute(.font, at: index, effectiveRange: nil) as? NSFont
  }
}

extension NSFont {
  func adding(_ trait: NSFontDescriptor.SymbolicTraits) -> NSFont {
    let traits = fontDescriptor.symbolicTraits.union(trait)
    let descriptor = fontDescriptor.withSymbolicTraits(traits)
    return NSFont(descriptor: descriptor, size: pointSize) ?? self
  }

  /// The same family at another size and weight.
  func with(size: CGFloat, weight: NSFont.Weight) -> NSFont {
    let traits = [NSFontDescriptor.TraitKey.weight: weight]
    let descriptor = fontDescriptor.addingAttributes([.traits: traits])
    return NSFont(descriptor: descriptor, size: size) ?? self
  }
}

extension NSTrackingArea {
  /// Follows the pointer over the visible part of `owner`, for hover effects.
  static func hover(owner: NSView) -> NSTrackingArea {
    NSTrackingArea(
      rect: .zero,
      options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
      owner: owner
    )
  }
}

extension NSColor {
  /// The gray behind inline code and code blocks.
  static let markdownCodeBackground = NSColor(name: nil) { appearance in
    let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    return isDark ? NSColor(white: 1, alpha: 0.1) : NSColor(white: 0, alpha: 0.06)
  }
}
