import AppKit
import Markdown

/// Vertical spacing. Lines in a paragraph get the line spacing, and blocks get the
/// component spacing. List items and the text under a heading get half of it, so they
/// stay together. A heading also gets half above it, on top of the usual block spacing.
///
/// TextKit puts the line spacing between every two lines, also between blocks. So the gap
/// between two blocks is the component spacing plus the line spacing.
extension MarkdownConverter {
  /// For paragraphs, and for boxes like code blocks.
  var blockParagraphStyle: NSParagraphStyle {
    paragraphStyle(spacingAfter: style.blockSpacing)
  }

  var headingParagraphStyle: NSParagraphStyle {
    let half = style.blockSpacing / 2
    return paragraphStyle(spacingBefore: half, spacingAfter: half)
  }

  /// For a paragraph in a list item. The last one gets full block spacing below.
  func listParagraphStyle(
    firstLineIndent: CGFloat,
    indent: CGFloat,
    endsList: Bool
  ) -> NSParagraphStyle {
    let spacing = endsList ? style.blockSpacing : style.blockSpacing / 2

    let listStyle = paragraphStyle(spacingAfter: spacing)
    listStyle.firstLineHeadIndent = firstLineIndent
    listStyle.headIndent = indent
    return listStyle
  }

  /// Whether the item is the last one in its list, and in every list around it. Its last
  /// paragraph is then the last paragraph of the whole list.
  func endsOutermostList(_ item: ListItem) -> Bool {
    guard let list = item.parent else { return false }
    guard item.indexInParent == list.childCount - 1 else { return false }
    guard let parentItem = list.parent as? ListItem else { return true }

    let isLastInParent = list.indexInParent == parentItem.childCount - 1
    return isLastInParent && endsOutermostList(parentItem)
  }

  private func paragraphStyle(
    spacingBefore: CGFloat = 0,
    spacingAfter: CGFloat
  ) -> NSMutableParagraphStyle {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineSpacing = style.lineSpacing
    paragraphStyle.paragraphSpacingBefore = spacingBefore
    paragraphStyle.paragraphSpacing = spacingAfter
    return paragraphStyle
  }
}
