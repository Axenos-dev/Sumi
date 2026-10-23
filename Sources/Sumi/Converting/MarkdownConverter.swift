import AppKit
import Markdown

/// Turns one top-level Markdown block into text, in one walk over its tree.
///
/// Paragraphs, headings, and lists become styled text. Code blocks, tables, and quotes
/// become boxes with their own AppKit views. Formulas, images, link icons, task boxes,
/// and rules become attachments that TextKit draws.
@MainActor
struct MarkdownConverter {
  typealias Formula = MathExtraction.Formula

  let style: ResolvedStyle
  let formulas: [Formula]

  /// Where the block is in the document. Box ids start with it.
  let blockIndex: Int

  /// The text of `block`. After other text, it starts with a line break that ends the
  /// paragraph before it.
  func text(for block: any Markup, afterText: Bool) -> NSAttributedString {
    let text = NSMutableAttributedString()
    appendBlock(block, to: text)

    if afterText, text.length > 0 {
      text.insert(NSAttributedString(string: "\n"), at: 0)
    }
    addMissingAttributes(to: text)
    return text
  }

  func appendBlock(_ block: any Markup, to text: NSMutableAttributedString) {
    switch block {
    case let paragraph as Paragraph:
      if let formula = displayFormula(in: paragraph) {
        text.append(displayFormulaText(formula))
      } else {
        appendInlines(paragraph.children, to: text, attributes: blockAttributes)
      }

    case let heading as Heading:
      let attributes = headingAttributes(for: heading)
      appendInlines(heading.children, to: text, attributes: attributes)

    case let list as any ListItemContainer:
      appendList(list, to: text)

    case is ThematicBreak:
      let rule = RuleAttachment(font: style.bodyFont)
      text.append(attachmentText(rule, attributes: blockAttributes))

    case let html as HTMLBlock:
      let source = html.rawHTML.trimmingCharacters(in: .newlines)
      text.append(NSAttributedString(string: source, attributes: blockAttributes))

    default:
      if let box = box(for: block) {
        text.append(attachmentText(box, attributes: blockAttributes))
      }
    }
  }

  /// The body font and the spacing of a block.
  private var blockAttributes: TextAttributes {
    bodyAttributes(blockParagraphStyle)
  }

  func bodyAttributes(_ paragraphStyle: NSParagraphStyle) -> TextAttributes {
    [.font: style.bodyFont, .paragraphStyle: paragraphStyle]
  }

  /// One attachment character with `attributes`.
  func attachmentText(
    _ attachment: NSTextAttachment,
    attributes: TextAttributes
  ) -> NSAttributedString {
    var attributes = attributes
    attributes[.attachment] = attachment
    return NSAttributedString(string: "\u{FFFC}", attributes: attributes)
  }

  /// Fills in the font, paragraph style, and color where they're missing, like on the
  /// line breaks between blocks.
  private func addMissingAttributes(to text: NSMutableAttributedString) {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineSpacing = style.lineSpacing
    let defaults: TextAttributes = [
      .font: style.bodyFont,
      .paragraphStyle: paragraphStyle,
      .foregroundColor: style.textColor,
    ]

    var missing: [(NSRange, TextAttributes)] = []
    text.enumerateAttributes(in: text.fullRange) { attributes, range, _ in
      let added = defaults.filter { attributes[$0.key] == nil }
      if !added.isEmpty {
        missing.append((range, added))
      }
    }

    for (range, attributes) in missing {
      text.addAttributes(attributes, range: range)
    }
  }

  // MARK: Headings

  private func headingAttributes(for heading: Heading) -> TextAttributes {
    let level = min(max(heading.level, 1), 6)

    // The heading level for accessibility, the way AppKit converts it from Swift
    // attributes. A top-level heading counts from the start of the text, not from where
    // parsing started.
    let identity = heading.parent is Document ? blockIndex : heading.indexInParent
    let intent = AttributeContainer()
      .presentationIntent(PresentationIntent(.header(level: level), identity: identity))
      .accessibilityHeadingLevel(.init(rawValue: level) ?? .unspecified)
    let converted = try? NSAttributedString(
      AttributedString(" ", attributes: intent),
      including: \.appKit
    )

    var attributes = converted?.attributes(at: 0, effectiveRange: nil) ?? [:]
    attributes[.font] = style.headingFonts[level - 1]
    attributes[.paragraphStyle] = headingParagraphStyle
    return attributes
  }

  // MARK: Display formulas

  /// The formula of a paragraph that's nothing but a `$$` or `\[` formula.
  private func displayFormula(in paragraph: Paragraph) -> Formula? {
    guard paragraph.childCount == 1 else { return nil }
    guard let text = paragraph.child(at: 0) as? Markdown.Text else { return nil }

    let string = text.string.trimmingCharacters(in: .whitespaces)
    let pieces = MathExtraction.pieces(of: string)
    guard pieces.count == 1, case .formula(let number) = pieces[0] else { return nil }
    guard formulas.indices.contains(number) else { return nil }

    let formula = formulas[number]
    return formula.isDisplay ? formula : nil
  }

  /// A formula centered on its own line.
  private func displayFormulaText(_ formula: Formula) -> NSAttributedString {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.setParagraphStyle(blockParagraphStyle)
    paragraphStyle.alignment = .center

    let attributes = bodyAttributes(paragraphStyle)
    return formulaText(formula, font: style.bodyFont, attributes: attributes)
  }
}
