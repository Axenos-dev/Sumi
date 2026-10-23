import AppKit

/// An SF Symbol at the size of the text, like a link icon or a task box. It has 3 points
/// of space after it.
final class SymbolAttachment: NSTextAttachment, CopyableAttachment {
  let copiedText: String

  private static let spacing: CGFloat = 3

  init(symbol: String, color: NSColor, font: NSFont, copiedText: String = "") {
    self.copiedText = copiedText
    super.init(data: nil, ofType: nil)

    let configuration = NSImage.SymbolConfiguration(
      pointSize: font.pointSize * 0.8,
      weight: .medium
    )
    .applying(NSImage.SymbolConfiguration(paletteColors: [color]))

    let symbolImage = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
      .withSymbolConfiguration(configuration)
    let symbolSize = symbolImage?.size ?? .zero
    let size = CGSize(width: symbolSize.width + Self.spacing, height: symbolSize.height)

    image = NSImage(size: size, flipped: false) { _ in
      symbolImage?.draw(in: CGRect(origin: .zero, size: symbolSize))
      return true
    }

    // Center the symbol on the capital letters.
    let y = (font.capHeight - size.height) / 2
    bounds = CGRect(origin: CGPoint(x: 0, y: y), size: size)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}
