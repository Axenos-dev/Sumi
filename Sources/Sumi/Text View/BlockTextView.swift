import AppKit

/// The text view behind `MarkdownText`. It uses TextKit 1.
///
/// On each update it replaces only the text from the first changed block to the end.
final class BlockTextView: NSTextView {
  /// The id and length of each block in the storage, in order.
  private var storedBlocks: [(id: Int, length: Int)] = []

  /// The boxes in the text and where they are, by box id.
  private var boxes: [[Int]: (attachment: BoxAttachment, location: Int)] = [:]

  private var measuredHeight: (width: CGFloat, height: CGFloat)?

  // For the extensions in the other files.
  var boxViews: [ObjectIdentifier: NSView] = [:]
  var boxViewArea: CGRect = .null
  var scrollObservers: [NSObjectProtocol] = []
  var hoveredLinkRange: NSRange?

  isolated deinit {
    scrollObservers.forEach(NotificationCenter.default.removeObserver)
  }

  /// Replaces the text from the first changed block to the end. The blocks before it keep
  /// their text, layout, and views.
  func show(_ blocks: [TextBlock]) {
    let keptCount = zip(blocks, storedBlocks).prefix { $0.id == $1.id }.count
    let isUnchanged = keptCount == blocks.count && keptCount == storedBlocks.count
    guard !isUnchanged, let textStorage else { return }

    let location = storedBlocks.prefix(keptCount).reduce(0) { $0 + $1.length }
    let replacement = NSMutableAttributedString()
    for block in blocks.dropFirst(keptCount) {
      replacement.append(block.text)
    }
    keepBoxes(in: replacement)

    showHoveredLink(at: nil)
    textStorage.beginEditing()
    textStorage.replaceCharacters(
      in: NSRange(location: location, length: textStorage.length - location),
      with: replacement
    )
    textStorage.endEditing()

    storedBlocks = blocks.map { ($0.id, $0.text.length) }
    indexBoxes(from: location)
    textDidChangeLayout()
  }

  /// Swaps new boxes for the ones already in the text, so each box keeps its view.
  private func keepBoxes(in text: NSMutableAttributedString) {
    text.enumerateAttribute(.attachment, in: text.fullRange) { value, range, _ in
      guard let box = value as? BoxAttachment else { return }
      guard let oldBox = boxes[box.id]?.attachment, oldBox !== box else { return }

      oldBox.updateContent(from: box)
      text.addAttribute(.attachment, value: oldBox, range: range)
    }
  }

  private func indexBoxes(from location: Int) {
    guard let textStorage else { return }

    boxes = boxes.filter { $0.value.location < location }

    let range = NSRange(location: location, length: textStorage.length - location)
    textStorage.enumerateAttribute(.attachment, in: range) { value, range, _ in
      if let box = value as? BoxAttachment {
        boxes[box.id] = (box, range.location)
      }
    }
  }

  /// Lays out the text again around an attachment that changed size, like a loaded image.
  func attachmentDidChangeSize(_ attachment: NSTextAttachment) {
    guard let textStorage, let layoutManager else { return }

    let wholeText = textStorage.fullRange
    textStorage.enumerateAttribute(.attachment, in: wholeText) { value, range, stop in
      guard value as? NSTextAttachment === attachment else { return }

      layoutManager.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
      layoutManager.invalidateDisplay(forCharacterRange: range)
      stop.pointee = true
    }
    textDidChangeLayout()
  }

  /// Lays out the text again around a box whose view changed its height on its own.
  func boxViewDidChangeSize(_ view: NSView) {
    let box = boxes.values.first { $0.attachment.madeView === view }
    if let box {
      attachmentDidChangeSize(box.attachment)
    }
  }

  private func textDidChangeLayout() {
    measuredHeight = nil
    invalidateIntrinsicContentSize()
    needsLayout = true
    setNeedsDisplay(bounds)
  }

  // MARK: Size

  override var intrinsicContentSize: CGSize {
    CGSize(width: NSView.noIntrinsicMetric, height: height(forWidth: bounds.width))
  }

  private func height(forWidth width: CGFloat) -> CGFloat {
    if let measuredHeight, measuredHeight.width == width {
      return measuredHeight.height
    }

    guard let layoutManager, let textContainer else { return bounds.height }

    layoutManager.ensureLayout(for: textContainer)
    let usedRect = layoutManager.usedRect(for: textContainer)
    let height = ceil(usedRect.maxY + textContainerOrigin.y)

    measuredHeight = (width, height)
    return height
  }

  override func layout() {
    super.layout()

    // A new width means a new height.
    if let measuredHeight, measuredHeight.width != bounds.width {
      self.measuredHeight = nil
      invalidateIntrinsicContentSize()
    }

    placeBoxViews()
  }

  // MARK: Copy

  /// Copy and "Search with Google" get attachments as text. Lookup, Translate, and Share
  /// don't come through here.
  override func attributedSubstring(
    forProposedRange range: NSRange,
    actualRange: NSRangePointer?
  ) -> NSAttributedString? {
    let text = super.attributedSubstring(
      forProposedRange: range,
      actualRange: actualRange
    )
    return text?.replacingCopyableAttachments()
  }
}
