import AppKit
import SwiftUI

/// The style with AppKit fonts and colors, for the converter.
///
/// Two resolved styles are equal when they come from the same settings. AppKit colors
/// made from SwiftUI colors don't always compare equal, and a style that never compares
/// equal would convert every block again on every update.
struct ResolvedStyle: Equatable {
  let bodyFont: NSFont
  let headingFonts: [NSFont]
  let codeFont: NSFont
  let tableFont: NSFont
  let tableHeaderFont: NSFont
  let quoteFont: NSFont

  let textColor: NSColor
  let linkColor: NSColor
  let inlineCodeColor: NSColor
  let inlineCodeBackground: NSColor
  let codeBackground: NSColor
  let quoteBarColor: NSColor

  let codeTheme: CodeTheme
  let lineSpacing: CGFloat
  let blockSpacing: CGFloat
  let listIndent: CGFloat
  let underlinesLinks: Bool
  let showsTableRowLines: Bool
  let rendersMath: Bool
  let baseURL: URL?

  let linkStyle: LinkStyleFunction?
  let codeBlockViews: [String: CodeBlockViewFunction]

  /// For custom views, so they look the same before and after they join the window. A
  /// view inside the window inherits it, and one that is only measured doesn't.
  let environment: EnvironmentValues

  private let source: Source

  private struct Source: Equatable {
    var style: MarkdownStyle
    var environmentFont: Font?
    var hasLinkStyle: Bool
    var codeBlockLanguages: Set<String>
  }

  @MainActor
  init(_ environment: EnvironmentValues) {
    let style = environment.markdownStyle
    let linkStyle = environment.markdownLinkStyle
    let codeBlockViews = environment.markdownCodeBlockViews
    let context = environment.fontResolutionContext

    func resolve(_ font: Font?) -> NSFont? {
      font.map { $0.resolve(in: context).ctFont as NSFont }
    }

    let environmentBody = resolve(environment.font) ?? .preferredFont(forTextStyle: .body)
    let body = resolve(style.font) ?? environmentBody
    let size = body.pointSize
    bodyFont = body

    // Headings without a font of their own: the body font, bigger and semibold.
    let h = style.headings
    let scales: [CGFloat] = [1.6, 1.35, 1.15, 1, 1, 0.9]
    headingFonts = [h.h1, h.h2, h.h3, h.h4, h.h5, h.h6].enumerated().map { level, font in
      resolve(font) ?? body.with(size: size * scales[level], weight: .semibold)
    }

    let monospaced = NSFont.monospacedSystemFont(ofSize: size * 0.9, weight: .regular)
    let semibold = body.with(size: size, weight: .semibold)
    codeFont = resolve(style.codeBlock.font) ?? monospaced
    tableFont = resolve(style.table.font) ?? body
    tableHeaderFont = resolve(style.table.headerFont) ?? semibold
    quoteFont = resolve(style.quote.font) ?? body

    textColor = NSColor(style.textColor)
    linkColor = NSColor(style.link.color)
    inlineCodeColor = NSColor(style.inlineCode.color)
    inlineCodeBackground = NSColor(style.inlineCode.background)
    codeBackground = NSColor(style.codeBlock.background)
    quoteBarColor = NSColor(style.quote.barColor)

    codeTheme = style.codeBlock.theme
    lineSpacing = style.lineSpacing
    blockSpacing = style.blockSpacing
    listIndent = style.list.indent
    underlinesLinks = style.link.isUnderlined
    showsTableRowLines = style.table.showsRowLines
    rendersMath = style.math.isEnabled
    baseURL = style.baseURL

    self.linkStyle = linkStyle
    self.codeBlockViews = codeBlockViews
    self.environment = environment

    source = Source(
      style: style,
      environmentFont: environment.font,
      hasLinkStyle: linkStyle != nil,
      codeBlockLanguages: Set(codeBlockViews.keys)
    )
  }

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.source == rhs.source
  }

  func url(for destination: String) -> URL? {
    URL(string: destination, relativeTo: baseURL)
  }
}
