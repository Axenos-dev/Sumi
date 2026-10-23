import AppKit
@preconcurrency import Highlightr

/// Code with colors from highlight.js. Each result is a new string that never changes.
struct HighlightedCode: @unchecked Sendable {
  let string: NSAttributedString
}

/// One highlight.js engine for the whole app.
///
/// Loading highlight.js takes longer than highlighting a block, so the engine stays
/// loaded. It isn't thread-safe, so all the work runs on one queue.
final class CodeHighlighter: @unchecked Sendable {
  static let shared = CodeHighlighter()

  private let queue = DispatchQueue(
    label: "Sumi.CodeHighlighter",
    qos: .userInitiated
  )

  // Only touched on `queue`.
  private var highlightr: Highlightr?
  private var languages: [String] = []
  private var themeName: String?

  /// The code in the colors of the theme, or `nil` when highlight.js can't read it. An
  /// unknown language means highlight.js guesses.
  func highlight(
    _ code: String,
    language: String?,
    themeName: String
  ) async -> HighlightedCode? {
    await withCheckedContinuation { continuation in
      queue.async {
        let result = self.highlightOnQueue(code, language: language, themeName: themeName)
        continuation.resume(returning: result)
      }
    }
  }

  private func highlightOnQueue(
    _ code: String,
    language: String?,
    themeName: String
  ) -> HighlightedCode? {
    if highlightr == nil {
      highlightr = Highlightr()
      languages = highlightr?.supportedLanguages() ?? []
    }
    guard let highlightr else { return nil }
    guard let language, !["text", "txt", "plaintext"].contains(language.lowercased()) else {
      return nil
    }

    if self.themeName != themeName {
      highlightr.setTheme(to: themeName)
      self.themeName = themeName
    }

    let knownLanguage = languages.first {
      $0.caseInsensitiveCompare(language) == .orderedSame
    }
    return highlightr.highlight(code, as: knownLanguage).map(HighlightedCode.init)
  }
}
