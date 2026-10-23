import SwiftUI

/// A link, as the link style function sees it.
public struct MarkdownLink {
  /// Where the link goes. Relative links start from the base URL.
  public var url: URL

  /// The text of the link, without Markdown.
  public var label: String
}

public enum MarkdownLinkStyle {
  /// Just the text.
  case text

  /// An SF Symbol in the link color before the text. It stays on the line of the first
  /// word, and copies leave it out.
  case symbol(String)
}

extension View {
  /// Sets the whole style of `MarkdownText`.
  nonisolated public func markdownStyle(_ style: MarkdownStyle) -> some View {
    environment(\.markdownStyle, style)
  }

  /// Changes some values of the style, and keeps the rest.
  nonisolated public func markdownStyle(
    _ update: @escaping (inout MarkdownStyle) -> Void
  ) -> some View {
    transformEnvironment(\.markdownStyle, transform: update)
  }

  /// Picks how each link looks.
  ///
  /// The function runs for each link when its block converts, so a block that doesn't
  /// change keeps its link styles. Clicks go to the `openURL` action of the environment.
  ///
  /// ```swift
  /// MarkdownText(text)
  ///   .markdownLinkStyle { link in
  ///     link.url.isFileURL ? .symbol("doc") : .text
  ///   }
  /// ```
  nonisolated public func markdownLinkStyle(
    _ style: @escaping @MainActor (MarkdownLink) -> MarkdownLinkStyle
  ) -> some View {
    environment(\.markdownLinkStyle, LinkStyleFunction(style: style))
  }

  /// Shows code blocks in `language` with your own view, like a diagram for `mermaid`.
  /// The view gets the code, and grows with it while it streams.
  ///
  /// SwiftUI has to lay out the view to know its height, so these blocks cost more than
  /// the built-in ones. Other blocks stay as fast as before.
  ///
  /// ```swift
  /// MarkdownText(text)
  ///   .markdownCodeBlock("mermaid") { code in
  ///     MermaidView(source: code)
  ///   }
  /// ```
  nonisolated public func markdownCodeBlock<Content: View>(
    _ language: String,
    @ViewBuilder content: @escaping @MainActor (String) -> Content
  ) -> some View {
    let view = CodeBlockViewFunction { code in AnyView(content(code)) }
    return transformEnvironment(\.markdownCodeBlockViews) { views in
      views[language.lowercased()] = view
    }
  }
}

/// Closures can't be compared, so any two link styles count as equal.
struct LinkStyleFunction: Equatable, Sendable {
  let style: @MainActor (MarkdownLink) -> MarkdownLinkStyle

  static func == (lhs: Self, rhs: Self) -> Bool { true }
}

struct CodeBlockViewFunction: Sendable {
  let makeView: @MainActor (String) -> AnyView
}

extension EnvironmentValues {
  @Entry var markdownLinkStyle: LinkStyleFunction? = nil
  @Entry var markdownCodeBlockViews: [String: CodeBlockViewFunction] = [:]
}
