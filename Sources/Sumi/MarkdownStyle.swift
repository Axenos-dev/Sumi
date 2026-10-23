import SwiftUI

/// How `MarkdownText` looks. The defaults look like the Codex app, so most apps change
/// only a few values:
///
/// ```swift
/// MarkdownText(text)
///   .markdownStyle { style in
///     style.link.color = .blue
///     style.codeBlock.theme = CodeTheme(light: "github", dark: "github-dark")
///   }
/// ```
public struct MarkdownStyle: Equatable, Sendable {
  /// The body font. Without one, the text uses the font of the environment.
  public var font: Font?
  public var textColor: Color = .primary
  public var lineSpacing: CGFloat = 6

  /// The space between blocks: paragraphs, lists, code blocks, and so on.
  public var blockSpacing: CGFloat = 14

  /// Where relative links and images start from.
  public var baseURL: URL?

  public var headings = Headings()
  public var link = Link()
  public var inlineCode = InlineCode()
  public var codeBlock = CodeBlock()
  public var table = Table()
  public var quote = Quote()
  public var list = List()
  public var math = Math()

  public init() {}

  /// A level without a font gets the body font, bigger and semibold.
  public struct Headings: Equatable, Sendable {
    public var h1: Font?
    public var h2: Font?
    public var h3: Font?
    public var h4: Font?
    public var h5: Font?
    public var h6: Font?
  }

  public struct Link: Equatable, Sendable {
    public var color: Color = .accentColor

    /// Underlines every link. Otherwise only the link under the pointer gets one.
    public var isUnderlined = false
  }

  public struct InlineCode: Equatable, Sendable {
    public var color: Color = .primary
    public var background = Color(nsColor: .markdownCodeBackground)
  }

  public struct CodeBlock: Equatable, Sendable {
    /// Without one, code blocks use a monospaced font a bit smaller than the body.
    public var font: Font?
    public var background = Color(nsColor: .markdownCodeBackground)
    public var theme = CodeTheme.standard
  }

  public struct Table: Equatable, Sendable {
    /// Without one, cells use the body font.
    public var font: Font?

    /// Without one, the header uses the body font in semibold.
    public var headerFont: Font?

    /// Lines between rows. The line under the header is always there.
    public var showsRowLines = true
  }

  public struct Quote: Equatable, Sendable {
    /// Without one, quotes use the body font.
    public var font: Font?
    public var barColor = Color(nsColor: .quaternaryLabelColor)
  }

  public struct List: Equatable, Sendable {
    /// How far each level goes in.
    public var indent: CGFloat = 12
  }

  public struct Math: Equatable, Sendable {
    /// Draws LaTeX in `$`, `$$`, `\(`, and `\[` as formulas.
    public var isEnabled = true
  }
}

/// The colors of code, as highlight.js theme names, like "github" and "github-dark".
public struct CodeTheme: Equatable, Sendable {
  public var light: String
  public var dark: String

  public init(light: String, dark: String) {
    self.light = light
    self.dark = dark
  }

  public static let standard = CodeTheme(light: "xcode", dark: "xcode-dark")
}

extension EnvironmentValues {
  @Entry var markdownStyle = MarkdownStyle()
}
