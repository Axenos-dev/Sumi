import AppKit
import SwiftMath

/// A formula drawn by SwiftMath. It sits on the baseline of the text, and shrinks when
/// it's wider than the line.
final class MathAttachment: NSTextAttachment, CopyableAttachment {
  let copiedText: String

  /// Where the baseline of the formula is, from the bottom of the image.
  private let baseline: CGFloat

  /// The height of small letters in Latin Modern Math, the SwiftMath font, as a share of
  /// the font size.
  private static let mathXHeight: CGFloat = 0.431

  /// Fails when SwiftMath can't read the LaTeX.
  init?(latex: String, font: NSFont, isDisplay: Bool, copiedText: String) {
    // Latin Modern has smaller small letters than most text fonts, so at the text size a
    // formula looks small. KaTeX scales it up for the same reason.
    let fontSize = font.xHeight > 0 ? font.xHeight / Self.mathXHeight : font.pointSize

    // The image draws each time it shows, so the label color follows light and dark mode.
    var math = MathImage(
      latex: latex,
      fontSize: fontSize,
      textColor: .labelColor,
      labelMode: isDisplay ? .display : .text,
      textAlignment: .left
    )
    let (error, image, layout) = math.asImage()
    guard error == nil, let image, let layout else { return nil }

    // SwiftMath centers the formula in the image, and a short formula gets at least half
    // the font size as height.
    let height = max(layout.ascent + layout.descent, fontSize / 2)
    self.baseline = (image.size.height - height) / 2 + layout.descent
    self.copiedText = copiedText

    super.init(data: nil, ofType: nil)
    self.image = image
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
    let size = image?.size ?? .zero
    let isTooWide = size.width > lineFragment.width && size.width > 0
    let scale = isTooWide ? lineFragment.width / size.width : 1

    return CGRect(
      x: 0,
      y: -baseline * scale,
      width: size.width * scale,
      height: size.height * scale
    )
  }
}
