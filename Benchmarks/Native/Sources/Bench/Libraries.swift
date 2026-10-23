import MarkdownUI
import Sumi
import SwiftUI
import Textual

/// Each library with its default look.
@MainActor
func libraryView(_ library: String, model: StreamModel) -> AnyView {
  switch library {
  case "Sumi":
    AnyView(MarkdownText(model.text))
  case "MarkdownUI":
    AnyView(Markdown(model.text))
  case "Textual":
    AnyView(StructuredText(markdown: model.text))
  case "PlainTextView":
    AnyView(PlainTextView(text: model.text))
  default:
    fatalError("Unknown library \(library)")
  }
}

/// The least work for a growing answer in one text view: plain text, appended at the end.
struct PlainTextView: NSViewRepresentable {
  var text: String

  func makeNSView(context: Context) -> NSTextView {
    let textView = NSTextView()
    textView.isEditable = false
    textView.drawsBackground = false
    textView.textContainerInset = .zero
    textView.textContainer?.lineFragmentPadding = 0
    textView.textContainer?.widthTracksTextView = true
    return textView
  }

  func makeCoordinator() -> Coordinator { Coordinator() }

  /// The number of UTF-8 bytes in the text view. Comparing the full strings on each
  /// update costs more than the text view itself.
  final class Coordinator { var shownBytes = 0 }

  func updateNSView(_ textView: NSTextView, context: Context) {
    guard let storage = textView.textStorage else { return }

    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
      .foregroundColor: NSColor.labelColor,
    ]
    let bytes = text.utf8
    let newBytes = bytes.dropFirst(context.coordinator.shownBytes)
    let appended = String(decoding: newBytes, as: UTF8.self)
    storage.append(NSAttributedString(string: appended, attributes: attributes))
    context.coordinator.shownBytes = bytes.count
  }

  func sizeThatFits(
    _ proposal: ProposedViewSize,
    nsView: NSTextView,
    context: Context
  ) -> CGSize? {
    guard let layoutManager = nsView.layoutManager else { return nil }
    guard let container = nsView.textContainer else { return nil }

    let width = proposal.width ?? width
    container.containerSize = CGSize(width: width, height: .greatestFiniteMagnitude)
    layoutManager.ensureLayout(for: container)
    let height = ceil(layoutManager.usedRect(for: container).height)
    return CGSize(width: width, height: height)
  }
}
