import Markdown

/// The top-level blocks of a Markdown text.
///
/// When the text only grows at the end, just the last few blocks parse again. New text
/// can change the last block, and any block right before it with no blank line in
/// between. A line of dashes, for one, turns the paragraph above it into a heading.
struct MarkdownDocument {
  struct Block {
    var markup: any Markup

    /// The Markdown of the block, or `nil` when the parser didn't say where the block is.
    var source: String?

    /// Where the block is in the text, in UTF-8 bytes.
    var range: Range<Int>

    /// Where the line of the block starts, in UTF-8 bytes. Parsing again starts there,
    /// because the spaces before a block can matter, like for the code in a fence.
    var lineStart: Int
  }

  private(set) var text = ""
  private(set) var blocks: [Block] = []

  /// Whether the text may have a link reference, like `[docs]: https://example.com`. One
  /// reference changes links everywhere, even above it, so the same Markdown can show
  /// different text.
  private(set) var hasLinkReferences = false

  private static let newline = UInt8(ascii: "\n")

  mutating func update(_ newText: String) {
    guard newText != text else { return }

    hasLinkReferences = Self.mayContainLinkReference(newText)
    let isAppended = newText.utf8.starts(with: text.utf8)
    let firstParsed = isAppended && !hasLinkReferences ? firstChangeableBlock : 0

    let tailStart = firstParsed < blocks.count ? blocks[firstParsed].lineStart : 0
    let tail = String(decoding: newText.utf8.dropFirst(tailStart), as: UTF8.self)

    blocks.removeSubrange(firstParsed...)
    blocks += Self.parse(tail, at: tailStart)
    text = newText
  }

  /// The last block, or an earlier one when no blank line separates them.
  private var firstChangeableBlock: Int {
    guard var index = blocks.indices.last else { return 0 }

    while index > 0 {
      let gap = blocks[index - 1].range.upperBound..<blocks[index].range.lowerBound
      let gapBytes = text.utf8.dropFirst(gap.lowerBound).prefix(gap.count)
      if gapBytes.count(where: { $0 == Self.newline }) >= 2 {
        break
      }
      index -= 1
    }
    return index
  }

  /// Parses `text`, which starts `offset` bytes into the whole text.
  private static func parse(_ text: String, at offset: Int) -> [Block] {
    let lineStarts = lineStarts(of: text)
    let byteCount = text.utf8.count

    // The parser counts lines and columns from 1, and columns in UTF-8 bytes.
    func byteOffset(of location: SourceLocation) -> Int? {
      guard lineStarts.indices.contains(location.line - 1) else { return nil }
      return min(lineStarts[location.line - 1] + location.column - 1, byteCount)
    }

    return Document(parsing: text).children.map { child in
      let start = child.range.flatMap { byteOffset(of: $0.lowerBound) }
      let end = child.range.flatMap { byteOffset(of: $0.upperBound) }
      guard let range = child.range, let start, let end else {
        let nowhere = offset..<offset
        return Block(markup: child, source: nil, range: nowhere, lineStart: offset)
      }

      let source = text.utf8.dropFirst(start).prefix(end - start)
      return Block(
        markup: child,
        source: String(decoding: source, as: UTF8.self),
        range: offset + start..<offset + end,
        lineStart: offset + lineStarts[range.lowerBound.line - 1]
      )
    }
  }

  private static func lineStarts(of text: String) -> [Int] {
    var starts = [0]
    for (index, byte) in text.utf8.enumerated() where byte == newline {
      starts.append(index + 1)
    }
    return starts
  }

  /// Whether some line starts with a link label and a colon, like `[docs]: `.
  private static func mayContainLinkReference(_ text: String) -> Bool {
    var isAtLineStart = true
    var indentation = 0
    var isInLabel = false
    var previousByte: UInt8 = 0

    for byte in text.utf8 {
      switch byte {
      case newline:
        isAtLineStart = true
        indentation = 0
        isInLabel = false

      case UInt8(ascii: " ") where isAtLineStart && indentation < 3:
        indentation += 1

      case UInt8(ascii: "[") where isAtLineStart:
        isAtLineStart = false
        isInLabel = true

      case UInt8(ascii: ":") where isInLabel && previousByte == UInt8(ascii: "]"):
        return true

      default:
        isAtLineStart = false
      }
      previousByte = byte
    }
    return false
  }
}
