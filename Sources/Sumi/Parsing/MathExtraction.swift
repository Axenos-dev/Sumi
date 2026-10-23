import Foundation

/// Pulls the formulas out of a Markdown text before parsing.
///
/// Markdown mangles LaTeX: backslashes escape things, and underscores turn into emphasis.
/// So each formula becomes a token: its number between two Private Use Area characters,
/// which Markdown leaves alone. Code spans and code blocks keep their dollar signs.
struct MathExtraction {
  struct Formula: Equatable {
    var latex: String

    /// `$$` or `\[`, which goes on its own line.
    var isDisplay: Bool
  }

  enum Piece {
    case text(Substring)
    case formula(Int)
  }

  /// The text with tokens instead of formulas.
  let text: String
  let formulas: [Formula]

  init(_ markdown: String, findsFormulas: Bool = true) {
    guard findsFormulas else {
      text = markdown
      formulas = []
      return
    }

    var scanner = Scanner(bytes: Array(markdown.utf8))
    scanner.scan()

    text = String(decoding: scanner.output, as: UTF8.self)
    formulas = scanner.formulas
  }

  /// Splits `string` into plain text and formula numbers.
  static func pieces(of string: String) -> [Piece] {
    var pieces: [Piece] = []
    var rest = string[...]

    while let token = nextToken(in: rest) {
      if token.range.lowerBound > rest.startIndex {
        pieces.append(.text(rest[..<token.range.lowerBound]))
      }
      pieces.append(.formula(token.number))
      rest = rest[token.range.upperBound...]
    }

    if !rest.isEmpty {
      pieces.append(.text(rest))
    }
    return pieces
  }

  private static func nextToken(
    in text: Substring
  ) -> (range: Range<String.Index>, number: Int)? {
    guard let start = text.firstIndex(of: tokenStart) else { return nil }
    guard let end = text[start...].firstIndex(of: tokenEnd) else { return nil }
    guard let number = Int(text[text.index(after: start)..<end]) else { return nil }

    return (start..<text.index(after: end), number)
  }

  private static let tokenStart: Character = "\u{E000}"
  private static let tokenEnd: Character = "\u{E001}"
}

/// Walks the bytes once and copies them to `output`, with tokens in place of formulas.
private struct Scanner {
  let bytes: [UInt8]
  var output: [UInt8] = []
  var formulas: [MathExtraction.Formula] = []

  private var index = 0

  /// The fence of the code block we're in, if any.
  private var fence: (character: UInt8, length: Int)?

  init(bytes: [UInt8]) {
    self.bytes = bytes
    output.reserveCapacity(bytes.count)
  }

  mutating func scan() {
    var isAtLineStart = true

    while index < bytes.count {
      // Code blocks get copied line by line, untouched.
      if isAtLineStart {
        isAtLineStart = false
        if updateFence() || fence != nil {
          copyLine()
          isAtLineStart = true
          continue
        }
      }

      let next = byte(at: index + 1)
      switch bytes[index] {
      case .newline:
        copy(1)
        isAtLineStart = true

      case .backtick:
        copyCodeSpan()

      case .backslash where next == .openParen:
        scanFormula(opening: 2, closing: [.backslash, .closeParen], isDisplay: false)

      case .backslash where next == .openBracket:
        scanFormula(opening: 2, closing: [.backslash, .closeBracket], isDisplay: true)

      case .backslash:
        // An escape, like `\$`. Both characters stay.
        copy(2)

      case .dollar where next == .dollar:
        scanFormula(opening: 2, closing: [.dollar, .dollar], isDisplay: true)

      case .dollar:
        scanInlineDollarFormula()

      default:
        copy(1)
      }
    }
  }

  /// Opens or closes a code block when the line is a fence: three or more backticks or
  /// tildes, after up to three spaces. Returns whether the line is a fence.
  private mutating func updateFence() -> Bool {
    var start = index
    while start < index + 3, byte(at: start) == .space {
      start += 1
    }

    let character = byte(at: start)
    guard character == .backtick || character == .tilde else { return false }

    var end = start
    while byte(at: end) == character {
      end += 1
    }

    let length = end - start
    guard length >= 3, let character else { return false }

    if let fence {
      // Only the same character, at least as many times, closes the block.
      if fence.character == character, length >= fence.length {
        self.fence = nil
      }
    } else {
      fence = (character, length)
    }
    return true
  }

  /// Copies a code span as is: backticks, the code, and the same number of backticks.
  private mutating func copyCodeSpan() {
    let length = backtickCount(at: index)

    var search = index + length
    while search < bytes.count, !isBlankLine(at: search) {
      guard bytes[search] == .backtick else {
        search += 1
        continue
      }

      let count = backtickCount(at: search)
      if count == length {
        copy(search + count - index)
        return
      }
      search += count
    }

    // Never closed, so the backticks are just text.
    copy(length)
  }

  /// A formula between `opening` bytes and `closing`, inside one paragraph.
  private mutating func scanFormula(opening: Int, closing: [UInt8], isDisplay: Bool) {
    let contentStart = index + opening

    var search = contentStart
    while search + closing.count <= bytes.count, !isBlankLine(at: search) {
      guard bytes[search..<search + closing.count].elementsEqual(closing) else {
        search += 1
        continue
      }

      let latex = String(decoding: bytes[contentStart..<search], as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard !latex.isEmpty else { break }

      appendToken(for: MathExtraction.Formula(latex: latex, isDisplay: isDisplay))
      index = search + closing.count
      return
    }

    // Never closed, so it's just text.
    copy(opening)
  }

  /// A formula in single dollars: no space after the opening one, no space before the
  /// closing one, and no digit right after it. That keeps `$5 and $10` as text.
  private mutating func scanInlineDollarFormula() {
    guard let first = byte(at: index + 1), !first.isWhitespace else {
      copy(1)
      return
    }

    var search = index + 1
    while search < bytes.count, !isBlankLine(at: search) {
      if isClosingDollar(at: search) {
        let latex = String(decoding: bytes[index + 1..<search], as: UTF8.self)
        appendToken(for: MathExtraction.Formula(latex: latex, isDisplay: false))
        index = search + 1
        return
      }
      search += 1
    }

    copy(1)
  }

  private func isClosingDollar(at index: Int) -> Bool {
    guard bytes[index] == .dollar else { return false }

    let before = bytes[index - 1]
    let isDigitAfter = byte(at: index + 1)?.isDigit ?? false
    return !before.isWhitespace && before != .backslash && !isDigitAfter
  }

  private mutating func appendToken(for formula: MathExtraction.Formula) {
    output += Array("\u{E000}\(formulas.count)\u{E001}".utf8)
    formulas.append(formula)
  }

  private mutating func copyLine() {
    while index < bytes.count, bytes[index] != .newline {
      copy(1)
    }
    if index < bytes.count {
      copy(1)
    }
  }

  private mutating func copy(_ count: Int) {
    let end = min(index + count, bytes.count)
    output += bytes[index..<end]
    index = end
  }

  private func backtickCount(at start: Int) -> Int {
    var end = start
    while byte(at: end) == .backtick {
      end += 1
    }
    return end - start
  }

  /// A blank line ends the paragraph. Code spans and formulas don't go past it.
  private func isBlankLine(at index: Int) -> Bool {
    guard bytes[index] == .newline else { return false }

    var next = index + 1
    while let character = byte(at: next), character == .space || character == .tab {
      next += 1
    }
    return byte(at: next) == .newline
  }

  private func byte(at index: Int) -> UInt8? {
    index < bytes.count ? bytes[index] : nil
  }
}

extension UInt8 {
  fileprivate static let newline = UInt8(ascii: "\n")
  fileprivate static let space = UInt8(ascii: " ")
  fileprivate static let tab = UInt8(ascii: "\t")
  fileprivate static let backtick = UInt8(ascii: "`")
  fileprivate static let tilde = UInt8(ascii: "~")
  fileprivate static let backslash = UInt8(ascii: "\\")
  fileprivate static let dollar = UInt8(ascii: "$")
  fileprivate static let openParen = UInt8(ascii: "(")
  fileprivate static let closeParen = UInt8(ascii: ")")
  fileprivate static let openBracket = UInt8(ascii: "[")
  fileprivate static let closeBracket = UInt8(ascii: "]")

  fileprivate var isWhitespace: Bool {
    self == .space || self == .newline || self == .tab
  }

  fileprivate var isDigit: Bool {
    self >= UInt8(ascii: "0") && self <= UInt8(ascii: "9")
  }
}
