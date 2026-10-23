import Testing

@testable import Sumi

/// What counts as a formula, and what stays text.
struct MathTests {
  @Test(arguments: [
    // Formulas.
    ("$x^2$", ["x^2"]),
    ("Energy is $E = mc^2$ here.", ["E = mc^2"]),
    ("$$\\int x$$", ["\\int x"]),
    ("$$\n\\int x\n$$", ["\\int x"]),
    ("\\(a_1\\) and \\[b_2\\]", ["a_1", "b_2"]),

    // Dollar signs that aren't math.
    ("Price is $5 and $10.", []),
    ("From $HOME/bin to $PATH.", []),
    ("An escaped \\$5.", []),
    ("A lone $ sign.", []),

    // Code keeps its dollar signs.
    ("Use `$x$` in code.", []),
    ("```sh\necho $x$\n```", []),

    // A formula doesn't go past a blank line.
    ("$a\n\nb$", []),
  ])
  func findsFormulas(markdown: String, formulas: [String]) {
    let math = MathExtraction(markdown)
    #expect(math.formulas.map(\.latex) == formulas)
  }

  @Test func tokensSplitBackIntoTextAndFormulas() {
    let math = MathExtraction("Before $x$ after")
    let pieces = MathExtraction.pieces(of: math.text).map { piece in
      switch piece {
      case .text(let text): String(text)
      case .formula(let number): "formula \(number)"
      }
    }
    #expect(pieces == ["Before ", "formula 0", " after"])
  }
}
