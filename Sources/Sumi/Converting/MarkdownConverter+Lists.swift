import AppKit
import Markdown

/// Every item starts on a new line. The first paragraph goes right after the marker, and
/// the rest of the item goes below it, lined up with the text.
extension MarkdownConverter {
  func appendList(_ list: any ListItemContainer, to text: NSMutableAttributedString) {
    let depth = nestingDepth(of: list)

    for (index, item) in list.listItems.enumerated() {
      if index > 0 {
        text.append(NSAttributedString(string: "\n"))
      }
      appendListItem(item, at: index, depth: depth, to: text)
    }
  }

  private func appendListItem(
    _ item: ListItem,
    at index: Int,
    depth: Int,
    to text: NSMutableAttributedString
  ) {
    let markerIndent = CGFloat(depth + 1) * style.listIndent
    let textIndent = markerIndent + style.listIndent

    let children = Array(item.children)
    let firstParagraph = children.first as? Paragraph
    let otherBlocks = firstParagraph == nil ? children : Array(children.dropFirst())
    let endsList = endsOutermostList(item)

    // The marker line.
    let paragraphStyle = listParagraphStyle(
      firstLineIndent: markerIndent,
      indent: textIndent,
      endsList: endsList && otherBlocks.isEmpty
    )
    let attributes = bodyAttributes(paragraphStyle)

    text.append(marker(for: item, at: index, attributes: attributes))
    text.append(NSAttributedString(string: " ", attributes: attributes))
    if let firstParagraph {
      appendInlines(firstParagraph.children, to: text, attributes: attributes)
    }

    // The rest of the item.
    guard !otherBlocks.isEmpty else { return }
    text.append(NSAttributedString(string: "\n", attributes: attributes))

    for (blockIndex, block) in otherBlocks.enumerated() {
      if blockIndex > 0 {
        text.append(NSAttributedString(string: "\n"))
      }

      guard let paragraph = block as? Paragraph else {
        appendBlock(block, to: text)
        continue
      }

      let isLast = blockIndex == otherBlocks.count - 1
      let paragraphStyle = listParagraphStyle(
        firstLineIndent: textIndent,
        indent: textIndent,
        endsList: endsList && isLast
      )
      let attributes = bodyAttributes(paragraphStyle)
      appendInlines(paragraph.children, to: text, attributes: attributes)
    }
  }

  /// A bullet, a number, or a task box. Bullets are monospaced, so nested items line up.
  private func marker(
    for item: ListItem,
    at index: Int,
    attributes: TextAttributes
  ) -> NSAttributedString {
    let body = style.bodyFont

    if let checkbox = item.checkbox {
      let isChecked = checkbox == .checked
      let box = SymbolAttachment(
        symbol: isChecked ? "checkmark.square" : "square",
        color: isChecked ? style.linkColor : .secondaryLabelColor,
        font: body,
        copiedText: isChecked ? "[x]" : "[ ]"
      )
      return attachmentText(box, attributes: attributes)
    }

    if let list = item.parent as? OrderedList {
      let number = Int(list.startIndex) + index
      return NSAttributedString(string: "\(number).", attributes: attributes)
    }

    var bulletAttributes = attributes
    bulletAttributes[.font] = body.adding(.monoSpace)
    return NSAttributedString(string: "•", attributes: bulletAttributes)
  }

  /// How many lists contain `list`.
  private func nestingDepth(of list: any ListItemContainer) -> Int {
    var depth = 0
    var ancestor = list.parent
    while let markup = ancestor {
      if markup is ListItemContainer {
        depth += 1
      }
      ancestor = markup.parent
    }
    return depth
  }
}
