import SwiftUI

/// The text of one top-level block. A block with a new id replaces the stored text from
/// that block to the end.
struct TextBlock {
  let id: Int
  let text: NSAttributedString

  @MainActor private static var lastID = 0

  @MainActor init(text: NSAttributedString) {
    Self.lastID += 1
    id = Self.lastID
    self.text = text
  }
}

/// Puts the blocks in a `BlockTextView`.
struct MarkdownTextView: NSViewRepresentable {
  var blocks: [TextBlock]

  func makeNSView(context: Context) -> BlockTextView {
    let textView = BlockTextView(usingTextLayoutManager: false)
    textView.textContainer?.replaceLayoutManager(RoundedBackgroundLayoutManager())
    textView.delegate = context.coordinator
    textView.drawsBackground = false
    textView.isEditable = false
    textView.usesAdaptiveColorMappingForDarkAppearance = true

    // Links have their own color. The default attributes would paint them blue and
    // underline them.
    textView.linkTextAttributes = [.cursor: NSCursor.pointingHand]

    // For the underline under the pointer.
    textView.addTrackingArea(.hover(owner: textView))

    // SwiftUI sets the width, and the text sets the height.
    textView.textContainerInset = .zero
    textView.setContentHuggingPriority(.required, for: .vertical)
    textView.isVerticallyResizable = false
    textView.isHorizontallyResizable = false
    textView.textContainer?.widthTracksTextView = true
    textView.textContainer?.heightTracksTextView = false
    textView.textContainer?.lineFragmentPadding = 0

    return textView
  }

  func updateNSView(_ textView: BlockTextView, context: Context) {
    context.coordinator.openURL = context.environment.openURL
    textView.show(blocks)
  }

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  final class Coordinator: NSObject, NSTextViewDelegate {
    var openURL: OpenURLAction?

    /// Lets the app handle link clicks through its `openURL` action.
    func textView(
      _ textView: NSTextView,
      clickedOnLink link: Any,
      at charIndex: Int
    ) -> Bool {
      let url = link as? URL ?? (link as? String).flatMap(URL.init(string:))
      guard let url, let openURL else { return false }

      openURL(url)
      return true
    }
  }
}
