import SwiftUI

/// Markdown as selectable text, made for text that streams in, like a model's answer.
///
/// Code blocks, tables, and quotes get their own AppKit views inside the text. Each
/// update parses only the last blocks again, converts only what changed, and replaces
/// only the text from the first changed block on.
public struct MarkdownText: View {
  private let text: String
  @State private var cache = MarkdownTextCache()

  @Environment(\.self) private var environment

  public init(_ text: String) {
    self.text = text
  }

  public var body: some View {
    let style = ResolvedStyle(environment)

    MarkdownTextView(
      blocks: cache.textBlocks(for: text, style: style),
    )
  }
}

#Preview {
  MarkdownText(
    """
    # MarkdownText

    Text with **bold**, *italic*, `inline code`, a [link](https://example.com),
    and $e^{i\\pi} + 1 = 0$.

    - [x] A finished task
    - [ ] A task

    > A quote.

    ```swift
    MarkdownText("Hello **World**")
    ```

    | Name | Value |
    | --- | --- |
    | One | 1 |
    """
  )
  .padding()
}
