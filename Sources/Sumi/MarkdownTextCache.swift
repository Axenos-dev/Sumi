import AppKit

/// Remembers the last update of a `MarkdownText`, so the next one only parses the blocks
/// at the end and only converts the blocks that changed.
@MainActor
final class MarkdownTextCache {
  private var document = MarkdownDocument()
  private var text = ""
  private var style: ResolvedStyle?
  private var blocks: [Block] = []

  private struct Block {
    var source: String?
    var textBlock: TextBlock
  }

  func textBlocks(for text: String, style: ResolvedStyle) -> [TextBlock] {
    // SwiftUI runs the body again for any change of the environment.
    if text == self.text, style == self.style {
      return blocks.map(\.textBlock)
    }

    let math = MathExtraction(text, findsFormulas: style.rendersMath)
    document.update(math.text)

    let keptCount = unchangedBlockCount(style: style)
    var newBlocks = Array(blocks.prefix(keptCount))
    var hasText = newBlocks.contains { $0.textBlock.text.length > 0 }

    for (index, block) in document.blocks.enumerated().dropFirst(keptCount) {
      let converter = MarkdownConverter(
        style: style,
        formulas: math.formulas,
        blockIndex: index
      )
      let text = converter.text(for: block.markup, afterText: hasText)
      hasText = hasText || text.length > 0

      newBlocks.append(Block(source: block.source, textBlock: TextBlock(text: text)))
    }

    blocks = newBlocks
    self.text = text
    self.style = style
    return blocks.map(\.textBlock)
  }

  /// How many blocks at the start have the same Markdown as last time. A new style or a
  /// link reference can change any block, so then nothing counts as unchanged.
  private func unchangedBlockCount(style: ResolvedStyle) -> Int {
    guard style == self.style, !document.hasLinkReferences else { return 0 }

    var count = 0
    for (new, old) in zip(document.blocks, blocks) {
      guard let source = new.source, source == old.source else { break }
      count += 1
    }
    return count
  }
}
