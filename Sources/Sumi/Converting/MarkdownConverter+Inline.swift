import AppKit
import Markdown

extension MarkdownConverter {
  /// Appends inline markup: text, emphasis, links, inline code, and so on.
  func appendInlines(
    _ markups: some Sequence<any Markup>,
    to text: NSMutableAttributedString,
    attributes: TextAttributes
  ) {
    for markup in markups {
      var attributes = attributes

      switch markup {
      case let plainText as Markdown.Text:
        appendText(plainText.string, to: text, attributes: attributes)

      case is SoftBreak:
        text.append(NSAttributedString(string: " ", attributes: attributes))

      case is Markdown.LineBreak:
        text.append(NSAttributedString(string: "\n", attributes: attributes))

      case let inlineCode as InlineCode:
        text.append(inlineCodeText(inlineCode.code, attributes: attributes))

      case let strong as Strong:
        attributes[.font] = (attributes[.font] as? NSFont)?.adding(.bold)
        appendInlines(strong.children, to: text, attributes: attributes)

      case let emphasis as Emphasis:
        attributes[.font] = (attributes[.font] as? NSFont)?.adding(.italic)
        appendInlines(emphasis.children, to: text, attributes: attributes)

      case let strikethrough as Strikethrough:
        attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        appendInlines(strikethrough.children, to: text, attributes: attributes)

      case let link as Markdown.Link:
        appendLink(link, to: text, attributes: attributes)

      case let image as Markdown.Image:
        text.append(imageText(image, attributes: attributes))

      case let html as InlineHTML:
        let isLineBreak = ["<br>", "<br/>", "<br />"].contains(html.rawHTML.lowercased())
        let string = isLineBreak ? "\n" : html.rawHTML
        text.append(NSAttributedString(string: string, attributes: attributes))

      default:
        appendInlines(markup.children, to: text, attributes: attributes)
      }
    }
  }

  // MARK: Text and formulas

  /// Appends text, with a formula wherever there's a formula token.
  private func appendText(
    _ string: String,
    to text: NSMutableAttributedString,
    attributes: TextAttributes
  ) {
    guard !formulas.isEmpty else {
      text.append(NSAttributedString(string: string, attributes: attributes))
      return
    }

    for piece in MathExtraction.pieces(of: string) {
      switch piece {
      case .text(let part):
        text.append(NSAttributedString(string: String(part), attributes: attributes))

      case .formula(let number):
        guard formulas.indices.contains(number) else { continue }
        // The size of the text around it, so formulas in headings are bigger.
        let font = attributes[.font] as? NSFont ?? style.bodyFont
        text.append(formulaText(formulas[number], font: font, attributes: attributes))
      }
    }
  }

  /// A formula, or its LaTeX if SwiftMath can't read it.
  func formulaText(
    _ formula: Formula,
    font: NSFont,
    attributes: TextAttributes
  ) -> NSAttributedString {
    let source = formula.isDisplay ? "$$\(formula.latex)$$" : "$\(formula.latex)$"
    let attachment = MathAttachment(
      latex: formula.latex,
      font: font,
      isDisplay: formula.isDisplay,
      copiedText: source
    )

    guard let attachment else {
      return NSAttributedString(string: source, attributes: attributes)
    }
    return attachmentText(attachment, attributes: attributes)
  }

  // MARK: Inline code

  /// Monospaced code on a gray pill. The padding inside the pill is kerning on a word
  /// joiner before the code and on its last character, so it stays with the code when
  /// lines wrap.
  func inlineCodeText(_ code: String, attributes: TextAttributes) -> NSAttributedString {
    let font = attributes[.font] as? NSFont ?? style.bodyFont

    // Bold text around the code makes bold code. The text storage does that anyway.
    let codeSize = font.pointSize * 0.9
    var codeFont = NSFont.monospacedSystemFont(ofSize: codeSize, weight: .regular)
    if font.fontDescriptor.symbolicTraits.contains(.bold) {
      codeFont = codeFont.adding(.bold)
    }

    var codeAttributes = attributes
    codeAttributes[.font] = codeFont
    codeAttributes[.backgroundColor] = style.inlineCodeBackground
    // Code inside a link keeps the link color.
    if attributes[.link] == nil {
      codeAttributes[.foregroundColor] = style.inlineCodeColor
    }

    let padding: CGFloat = 5
    let codeText = NSMutableAttributedString(
      string: wordJoiner + code,
      attributes: codeAttributes
    )
    let string = codeText.string as NSString
    let lastCharacter = string.rangeOfComposedCharacterSequence(at: string.length - 1)
    codeText.addAttribute(.kern, value: padding, range: NSRange(location: 0, length: 1))
    codeText.addAttribute(.kern, value: padding, range: lastCharacter)

    // A zero-width space lets the line break right before the code.
    let text = NSMutableAttributedString(string: zeroWidthSpace, attributes: attributes)
    text.append(codeText)
    return text
  }

  // MARK: Links and images

  private func appendLink(
    _ link: Markdown.Link,
    to text: NSMutableAttributedString,
    attributes: TextAttributes
  ) {
    guard let url = link.destination.flatMap(style.url(for:)) else {
      appendInlines(link.children, to: text, attributes: attributes)
      return
    }

    var attributes = attributes
    attributes[.link] = url
    attributes[.foregroundColor] = style.linkColor
    if let icon = linkIcon(for: link, url: url, attributes: attributes) {
      text.append(icon)
    }

    if style.underlinesLinks {
      attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
    }
    appendInlines(link.children, to: text, attributes: attributes)
  }

  /// The icon before a link, if the link style gives it one. A word joiner keeps the icon
  /// on the line of the first word.
  private func linkIcon(
    for link: Markdown.Link,
    url: URL,
    attributes: TextAttributes
  ) -> NSAttributedString? {
    guard let linkStyle = style.linkStyle else { return nil }

    let markdownLink = MarkdownLink(url: url, label: link.plainText)
    guard case .symbol(let symbol) = linkStyle.style(markdownLink) else { return nil }

    let icon = SymbolAttachment(
      symbol: symbol,
      color: attributes[.foregroundColor] as? NSColor ?? style.linkColor,
      font: attributes[.font] as? NSFont ?? style.bodyFont
    )

    let text = NSMutableAttributedString()
    text.append(attachmentText(icon, attributes: attributes))
    text.append(NSAttributedString(string: wordJoiner, attributes: attributes))
    return text
  }

  /// An image, or its alt text when the source isn't a valid URL.
  private func imageText(
    _ image: Markdown.Image,
    attributes: TextAttributes
  ) -> NSAttributedString {
    guard let url = image.source.flatMap(style.url(for:)) else {
      return NSAttributedString(string: image.plainText, attributes: attributes)
    }

    let attachment = ImageAttachment(url: url, alternativeText: image.plainText)
    return attachmentText(attachment, attributes: attributes)
  }
}
