import AppKit

/// A quote: the text with a thin bar on the leading edge, and no background. Its height
/// comes from measuring the text.
struct QuoteContent: BoxContent {
  static let textIndent: CGFloat = 24
  static let verticalPadding: CGFloat = 4

  var text: NSAttributedString
  var barColor: NSColor

  var copiedText: String {
    text.replacingCopyableAttachments().string
  }

  func makeView() -> NSView {
    QuoteView(content: self)
  }

  func update(_ view: NSView) {
    (view as? QuoteView)?.show(self)
  }

  func size(forWidth width: CGFloat) -> CGSize {
    CGSize(width: width, height: textHeight(forWidth: width) + Self.verticalPadding * 2)
  }

  fileprivate func textHeight(forWidth width: CGFloat) -> CGFloat {
    let textWidth = max(1, width - Self.textIndent)
    return ceil(text.drawnSize(forWidth: textWidth).height)
  }
}

final class QuoteView: DrawnTextView {
  private static let barWidth: CGFloat = 4

  private var content: QuoteContent
  private var cachedTextHeight: (width: CGFloat, height: CGFloat)?

  init(content: QuoteContent) {
    self.content = content
    super.init(frame: .zero)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func show(_ content: QuoteContent) {
    let isSameText = content.text.isEqual(to: self.content.text)
    let isSameBar = content.barColor == self.content.barColor
    guard !(isSameText && isSameBar) else { return }

    self.content = content
    cachedTextHeight = nil
    textDidChange()
  }

  override var drawnTexts: [(string: NSAttributedString, rect: CGRect)] {
    let indent = QuoteContent.textIndent
    let rect = CGRect(
      x: indent,
      y: QuoteContent.verticalPadding,
      width: max(1, bounds.width - indent),
      height: textHeight
    )
    return [(content.text, rect)]
  }

  override func draw(_ dirtyRect: NSRect) {
    let bar = NSRect(x: 0, y: 0, width: Self.barWidth, height: bounds.height)
    let radius = Self.barWidth / 2
    content.barColor.setFill()
    NSBezierPath(roundedRect: bar, xRadius: radius, yRadius: radius).fill()

    drawTexts(in: dirtyRect)
  }

  private var textHeight: CGFloat {
    if let cachedTextHeight, cachedTextHeight.width == bounds.width {
      return cachedTextHeight.height
    }

    let height = content.textHeight(forWidth: bounds.width)
    cachedTextHeight = (bounds.width, height)
    return height
  }
}
