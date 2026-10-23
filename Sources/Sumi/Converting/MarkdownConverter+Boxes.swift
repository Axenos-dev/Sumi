import AppKit
import Markdown
import SwiftUI

extension MarkdownConverter {
  /// The box for a code block, a table, or a quote.
  func box(for markup: any Markup) -> BoxAttachment? {
    let id = boxID(for: markup)

    switch markup {
    case let codeBlock as CodeBlock:
      let code = codeBlock.code.trimmingCharacters(in: .newlines)
      if let view = customView(for: codeBlock, code: code) {
        return BoxAttachment(id: id, content: view)
      }

      let content = CodeBlockContent(
        code: code,
        language: codeBlock.language,
        font: style.codeFont,
        background: style.codeBackground,
        theme: style.codeTheme
      )
      return BoxAttachment(id: id, content: content)

    case let table as Markdown.Table:
      return BoxAttachment(id: id, content: tableContent(table))

    case let quote as BlockQuote:
      let content = QuoteContent(text: quoteText(quote), barColor: style.quoteBarColor)
      return BoxAttachment(id: id, content: content)

    default:
      return nil
    }
  }

  /// The app's own view for code blocks in this language, if it has one.
  private func customView(for codeBlock: CodeBlock, code: String) -> HostedContent? {
    guard let language = codeBlock.language?.lowercased() else { return nil }
    guard let function = style.codeBlockViews[language] else { return nil }

    let view = function.makeView(code)
      .frame(maxWidth: .infinity, alignment: .leading)
      .environment(\.self, style.environment)
    return HostedContent(view: AnyView(view), copiedText: code)
  }

  /// The position of the block in the document, then the path to `markup` inside it.
  private func boxID(for markup: any Markup) -> [Int] {
    var path: [Int] = []
    var node = markup
    while let parent = node.parent, !(parent is Markdown.Document) {
      path.append(node.indexInParent)
      node = parent
    }
    return [blockIndex] + path.reversed()
  }

  // MARK: Tables

  private func tableContent(_ table: Markdown.Table) -> TableContent {
    let alignments = table.columnAlignments.map(textAlignment)

    func cells(_ row: some TableCellContainer, font: NSFont) -> [NSAttributedString] {
      row.cells.enumerated().map { column, cell in
        let alignment = column < alignments.count ? alignments[column] : .natural
        return cellText(cell, font: font, alignment: alignment)
      }
    }

    let header = cells(table.head, font: style.tableHeaderFont)
    let body = table.body.rows.map { cells($0, font: style.tableFont) }
    return TableContent(rows: [header] + body, showsRowLines: style.showsTableRowLines)
  }

  private func textAlignment(
    _ alignment: Markdown.Table.ColumnAlignment?
  ) -> NSTextAlignment {
    switch alignment {
    case .center: .center
    case .right: .right
    case .left, nil: .natural
    }
  }

  /// An empty cell gets a space, so its row is still one line high.
  private func cellText(
    _ cell: Markdown.Table.Cell,
    font: NSFont,
    alignment: NSTextAlignment
  ) -> NSAttributedString {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.alignment = alignment
    paragraphStyle.lineSpacing = style.lineSpacing

    let attributes: TextAttributes = [
      .font: font,
      .foregroundColor: style.textColor,
      .paragraphStyle: paragraphStyle,
    ]

    let text = NSMutableAttributedString()
    appendInlines(cell.children, to: text, attributes: attributes)
    if text.length == 0 {
      text.append(NSAttributedString(string: " ", attributes: attributes))
    }
    return text
  }
}
