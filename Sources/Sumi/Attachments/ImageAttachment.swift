import AppKit

/// An image from a file or the web, as wide as the image but no wider than the line. It
/// has no size until it loads, and then the text lays out again around it.
final class ImageAttachment: NSTextAttachment, CopyableAttachment {
  let copiedText: String

  /// The container that last laid out the image, to find the text view once it loads.
  private weak var textContainer: NSTextContainer?

  @MainActor
  init(url: URL, alternativeText: String) {
    copiedText = alternativeText
    super.init(data: nil, ofType: nil)

    image = ImageLoader.shared.image(for: url)
    guard image == nil else { return }

    ImageLoader.shared.load(url) { [weak self] image in
      guard let self else { return }

      self.image = image
      (textContainer?.textView as? BlockTextView)?.attachmentDidChangeSize(self)
    }
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  /// No cell, so TextKit asks `attachmentBounds` even while the image loads. Same trick
  /// as in `BoxAttachment`.
  override var attachmentCell: (any NSTextAttachmentCellProtocol)? {
    get { nil }
    set {}
  }

  override func attachmentBounds(
    for textContainer: NSTextContainer?,
    proposedLineFragment lineFragment: CGRect,
    glyphPosition position: CGPoint,
    characterIndex: Int
  ) -> CGRect {
    self.textContainer = textContainer
    guard let size = image?.size, size.width > 0 else { return .zero }

    let scale = min(1, lineFragment.width / size.width)
    return CGRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale)
  }
}

/// Loads each image once and shares it between all views.
@MainActor
final class ImageLoader {
  static let shared = ImageLoader()

  private let images = NSCache<NSURL, NSImage>()
  private var failedURLs: Set<URL> = []
  private var waiting: [URL: [(NSImage) -> Void]] = [:]

  func image(for url: URL) -> NSImage? {
    images.object(forKey: url as NSURL)
  }

  func load(_ url: URL, completion: @escaping (NSImage) -> Void) {
    guard !failedURLs.contains(url) else { return }

    if let image = image(for: url) {
      completion(image)
      return
    }

    // Already loading: just wait for it.
    guard waiting[url] == nil else {
      waiting[url]?.append(completion)
      return
    }

    waiting[url] = [completion]
    Task {
      let data = try? await URLSession.shared.data(from: url).0
      let completions = waiting.removeValue(forKey: url) ?? []

      guard let image = data.flatMap(NSImage.init(data:)) else {
        failedURLs.insert(url)
        return
      }

      images.setObject(image, forKey: url as NSURL)
      for completion in completions {
        completion(image)
      }
    }
  }
}
