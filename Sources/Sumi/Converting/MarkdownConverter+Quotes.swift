import AppKit
import Markdown

/// The text inside a quote, which the quote view draws itself. Each block after the first
/// gets space above it, and lists and nested quotes are indented.
extension MarkdownConverter {
  func quoteText(_ quote: BlockQuote) -> NSAttributedString {
    let text = NSMutableAttributedString()
    appendQuoteBlocks(quote.children, to: text, font: style.quoteFont, indent: 0)
    return text
  }

  private func appendQuoteBlocks(
    _ blocks: some Sequence<any Markup>,
    to text: NSMutableAttributedString,
    font: NSFont,
    indent: CGFloat
  ) {
    // Most blocks are one paragraph at this indent.
    func appendParagraph(_ inlines: [any Markup], font paragraphFont: NSFont? = nil) {
      appendQuoteParagraph(inlines, to: text, font: paragraphFont ?? font, indent: indent)
    }

    for block in blocks {
      switch block {
      case let paragraph as Paragraph:
        appendParagraph(Array(paragraph.children))

      case let heading as Heading:
        appendParagraph(Array(heading.children), font: font.adding(.bold))

      case let list as any ListItemContainer:
        appendQuoteList(list, to: text, font: font, indent: indent)

      case let codeBlock as CodeBlock:
        let code = codeBlock.code.trimmingCharacters(in: .newlines)
        appendParagraph([Markdown.Text(code)], font: style.codeFont)

      case let quote as BlockQuote:
        appendQuoteBlocks(quote.children, to: text, font: font, indent: indent + 16)

      case is ThematicBreak:
        continue

      default:
        let source = block.format().trimmingCharacters(in: .whitespacesAndNewlines)
        appendParagraph([Markdown.Text(source)])
      }
    }
  }

  private func appendQuoteList(
    _ list: any ListItemContainer,
    to text: NSMutableAttributedString,
    font: NSFont,
    indent: CGFloat
  ) {
    let start = Int((list as? OrderedList)?.startIndex ?? 1)

    for (index, item) in list.listItems.enumerated() {
      let marker: String
      if let checkbox = item.checkbox {
        marker = checkbox == .checked ? "☑︎" : "☐"
      } else {
        marker = list is OrderedList ? "\(start + index)." : "•"
      }
      appendQuoteListItem(item, marker: marker, to: text, font: font, indent: indent)
    }
  }

  /// The marker hangs in front of the text, and a tab lines the text up after it.
  private func appendQuoteListItem(
    _ item: ListItem,
    marker: String,
    to text: NSMutableAttributedString,
    font: NSFont,
    indent: CGFloat
  ) {
    let markerWidth: CGFloat = 20
    let children = Array(item.children)
    let firstParagraph = children.first as? Paragraph
    let firstInlines = firstParagraph.map { Array($0.children) } ?? []

    appendQuoteParagraph(
      [Markdown.Text(marker + "\t")] + firstInlines,
      to: text,
      font: font,
      indent: indent,
      hangingIndent: markerWidth
    )

    let rest = firstParagraph == nil ? children : Array(children.dropFirst())
    appendQuoteBlocks(rest, to: text, font: font, indent: indent + markerWidth)
  }

  private func appendQuoteParagraph(
    _ inlines: [any Markup],
    to text: NSMutableAttributedString,
    font: NSFont,
    indent: CGFloat,
    hangingIndent: CGFloat = 0
  ) {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineSpacing = style.lineSpacing
    paragraphStyle.firstLineHeadIndent = indent
    paragraphStyle.headIndent = indent + hangingIndent
    paragraphStyle.tabStops = []
    if hangingIndent > 0 {
      let textStart = indent + hangingIndent
      paragraphStyle.tabStops = [NSTextTab(textAlignment: .natural, location: textStart)]
    }

    // Space goes above each paragraph, so the last one leaves no gap at the bottom.
    paragraphStyle.paragraphSpacingBefore = text.length > 0 ? style.blockSpacing : 0

    let attributes: TextAttributes = [
      .font: font,
      .foregroundColor: style.textColor,
      .paragraphStyle: paragraphStyle,
    ]

    // The line break belongs to the paragraph before it, so it gets that style.
    if text.length > 0 {
      let keys: Set<NSAttributedString.Key> = [.font, .paragraphStyle, .foregroundColor]
      let previous = text.attributes(at: text.length - 1, effectiveRange: nil)
      let lineBreakAttributes = previous.filter { keys.contains($0.key) }
      text.append(NSAttributedString(string: "\n", attributes: lineBreakAttributes))
    }

    appendInlines(inlines, to: text, attributes: attributes)
  }
}
