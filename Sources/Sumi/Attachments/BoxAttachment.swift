import AppKit

/// What a box shows: a code block, a table, or a quote, each with its own AppKit view.
///
/// TextKit asks for the size before any view exists, so the content has to know its size
/// on its own.
@MainActor
protocol BoxContent {
  /// What a copy puts in place of the box.
  var copiedText: String { get }

  func makeView() -> NSView

  /// Shows this content in a view that `makeView()` made for older content.
  func update(_ view: NSView)

  func size(forWidth width: CGFloat) -> CGSize

  /// Takes over work from the content this one replaces, like cell measurements.
  mutating func keepWork(from previous: any BoxContent)
}

extension BoxContent {
  mutating func keepWork(from previous: any BoxContent) {}
}

/// Keeps space in the text for a box. The text view puts the view of the box there when
/// the box gets near the screen.
final class BoxAttachment: NSTextAttachment, CopyableAttachment {
  /// Where the box is in the Markdown tree. A newer attachment with the same id hands its
  /// content over to this one, so the view stays.
  let id: [Int]
  private(set) var copiedText: String
  private(set) var content: any BoxContent
  /// The view, once the box has been near the screen.
  private(set) var madeView: NSView?

  @MainActor
  init(id: [Int], content: any BoxContent) {
    self.id = id
    self.content = content
    self.copiedText = content.copiedText
    super.init(data: nil, ofType: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  /// The view, made the first time the box gets near the screen.
  @MainActor
  var view: NSView {
    if let madeView {
      return madeView
    }

    let view = content.makeView()
    madeView = view
    return view
  }

  /// Takes the content of a newer attachment with the same id.
  @MainActor
  func updateContent(from attachment: BoxAttachment) {
    var content = attachment.content
    content.keepWork(from: self.content)

    self.content = content
    copiedText = content.copiedText
    if let madeView {
      content.update(madeView)
    }
  }

  /// No cell. TextKit 1 gives an attachment without contents a one-point cell, and then
  /// never asks `attachmentBounds` for the size.
  override var attachmentCell: (any NSTextAttachmentCellProtocol)? {
    get { nil }
    set {}
  }

  /// As wide as the line. The box sits a bit below the baseline, as far as the descender
  /// of the font goes, relative to its height.
  override func attachmentBounds(
    for textContainer: NSTextContainer?,
    proposedLineFragment lineFragment: CGRect,
    glyphPosition position: CGPoint,
    characterIndex: Int
  ) -> CGRect {
    var descentRatio: CGFloat = 0.2
    if let font = textContainer?.layoutManager?.textStorage?.font(at: characterIndex) {
      descentRatio = abs(font.descender) / (abs(font.ascender) + abs(font.descender))
    }

    let width = max(0, lineFragment.width)
    nonisolated(unsafe) let content = content
    let size = MainActor.assumeIsolated { content.size(forWidth: width) }

    return CGRect(origin: CGPoint(x: 0, y: -descentRatio * size.height), size: size)
  }

  /// Nothing to draw. The view of the box covers this spot.
  override func image(
    forBounds imageBounds: CGRect,
    textContainer: NSTextContainer?,
    characterIndex charIndex: Int
  ) -> NSImage? {
    nil
  }
}
