import AppKit

/// Only boxes on screen, or within one screen of it, get views. Every view in the window
/// makes geometry changes slower (tracking areas, for one), so boxes far away stay
/// without a view.
extension BlockTextView {
  /// Shows the views of the boxes near the visible part and removes the rest.
  func placeBoxViews() {
    boxViewArea = nearVisibleArea

    var shownViews = Set<ObjectIdentifier>()
    for (box, frame) in boxFrames(in: boxViewArea) {
      let view = box.view
      view.frame = frame
      if view.superview !== self {
        addSubview(view)
      }

      shownViews.insert(ObjectIdentifier(view))
      boxViews[ObjectIdentifier(view)] = view
    }

    for (id, view) in boxViews where !shownViews.contains(id) {
      view.removeFromSuperview()
      boxViews[id] = nil
    }
  }

  /// The boxes in `area`, and where their views go.
  private func boxFrames(in area: CGRect) -> [(box: BoxAttachment, frame: CGRect)] {
    guard !area.isEmpty else { return [] }
    guard let layoutManager, let textContainer, let textStorage else { return [] }

    layoutManager.ensureLayout(for: textContainer)
    let origin = textContainerOrigin
    let containerArea = area.offsetBy(dx: -origin.x, dy: -origin.y)
    let glyphs = layoutManager.glyphRange(
      forBoundingRect: containerArea,
      in: textContainer
    )
    let characters = layoutManager.characterRange(
      forGlyphRange: glyphs,
      actualGlyphRange: nil
    )

    var frames: [(BoxAttachment, CGRect)] = []
    textStorage.enumerateAttribute(.attachment, in: characters) { value, range, _ in
      guard let box = value as? BoxAttachment else { return }

      let glyph = layoutManager.glyphIndexForCharacter(at: range.location)
      let size = layoutManager.attachmentSize(forGlyphAt: glyph)
      guard size.width > 0, size.height > 0 else { return }

      // TextKit 1 puts the bottom of an attachment on the baseline.
      let line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
      let baseline = layoutManager.location(forGlyphAt: glyph)
      let frameOrigin = CGPoint(
        x: origin.x + line.minX + baseline.x,
        y: origin.y + line.minY + baseline.y - size.height
      )
      frames.append((box, CGRect(origin: frameOrigin, size: size)))
    }
    return frames
  }

  /// What the user sees of the scroll view, in the coordinates of this view.
  private var viewport: CGRect {
    guard let clipView = enclosingScrollView?.contentView else { return visibleRect }
    return convert(clipView.bounds, from: clipView)
  }

  /// The visible part, plus one screen above and below.
  private var nearVisibleArea: CGRect {
    let viewport = viewport
    return viewport.insetBy(dx: 0, dy: -viewport.height).intersection(bounds)
  }

  private func visibleAreaDidChange() {
    // Far off screen: drop the views, once.
    if nearVisibleArea.isEmpty {
      if !boxViewArea.isEmpty {
        placeBoxViews()
      }
      return
    }

    // Scrolled out of the area that has views.
    let visiblePart = viewport.intersection(bounds)
    if !visiblePart.isEmpty, !boxViewArea.contains(visiblePart) {
      placeBoxViews()
    }
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    observeScrollView()
  }

  override func viewDidMoveToSuperview() {
    super.viewDidMoveToSuperview()
    observeScrollView()
  }

  /// A scroll can show a box that has no view yet.
  private func observeScrollView() {
    scrollObservers.forEach(NotificationCenter.default.removeObserver)
    scrollObservers = []

    guard window != nil, let clipView = enclosingScrollView?.contentView else { return }

    let names = [NSView.boundsDidChangeNotification, NSView.frameDidChangeNotification]
    scrollObservers = names.map { name in
      NotificationCenter.default.addObserver(
        forName: name,
        object: clipView,
        queue: nil
      ) { [weak self] _ in
        MainActor.assumeIsolated { self?.visibleAreaDidChange() }
      }
    }
  }
}
