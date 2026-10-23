import SwiftStreamingMarkdown
import SwiftUI

/// Gives the snapshots of the model to `StreamedMarkdownView`, as the sample app of the
/// library does: each value is the whole text so far.
struct ModelSource: StreamedMarkdownSource {
  let text: AsyncStream<String>
}

@MainActor
func libraryView(_ library: String, model: StreamModel) -> AnyView {
  switch library {
  case "SwiftStreamingMarkdown":
    AnyView(StreamedMarkdownView(source: ModelSource(text: model.snapshots)))
  default:
    fatalError("Unknown library \(library)")
  }
}
