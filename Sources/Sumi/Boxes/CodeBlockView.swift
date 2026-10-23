import AppKit

/// A code block. Code is monospaced and never wraps, so the height comes from the line
/// count and TextKit gets it without a layout pass. Streaming code gets appended to
/// what's there.
struct CodeBlockContent: BoxContent {
  var code: String
  var language: String?
  var font: NSFont
  var background: NSColor
  var theme: CodeTheme

  var copiedText: String {
    code
  }

  var lineCount: Int {
    code.utf8.count(where: { $0 == UInt8(ascii: "\n") }) + 1
  }

  func makeView() -> NSView {
    CodeBlockView(content: self)
  }

  func update(_ view: NSView) {
    (view as? CodeBlockView)?.show(self)
  }

  func size(forWidth width: CGFloat) -> CGSize {
    CGSize(width: width, height: CodeBlockView.height(lineCount: lineCount, font: font))
  }
}

final class CodeBlockView: NSView {
  private static let padding: CGFloat = 18
  private static let horizontalPadding: CGFloat = 24
  private static let headerHeight: CGFloat = 20
  private static let headerSpacing: CGFloat = 18
  private static let iconSpacing: CGFloat = 9
  private static let lineSpacing: CGFloat = 6

  /// Names for common language tags. Any other tag just gets a capital first letter.
  private static let languageNames = [
    "bash": "Bash", "c++": "C++", "cpp": "C++", "cs": "C#", "csharp": "C#", "css": "CSS",
    "graphql": "GraphQL", "html": "HTML", "javascript": "JavaScript", "js": "JavaScript",
    "json": "JSON", "jsx": "JSX", "md": "Markdown", "objc": "Objective-C", "php": "PHP",
    "sh": "Shell", "sql": "SQL", "toml": "TOML", "ts": "TypeScript", "tsx": "TSX",
    "typescript": "TypeScript", "xml": "XML", "yaml": "YAML", "yml": "YAML",
  ]

  static func height(lineCount: Int, font: NSFont) -> CGFloat {
    let chrome = padding * 2 + headerHeight + headerSpacing
    return chrome + codeHeight(lineCount: lineCount, font: font)
  }

  private static func codeHeight(lineCount: Int, font: NSFont) -> CGFloat {
    CGFloat(lineCount) * (lineHeight(for: font) + lineSpacing) - lineSpacing
  }

  private static func lineHeight(for font: NSFont) -> CGFloat {
    ceil(font.ascender - font.descender + font.leading)
  }

  private var content: CodeBlockContent

  // The header: language icon and name on the left, copy button on the right.
  private let languageIcon = NSImageView()
  private let languageLabel = NSTextField(labelWithString: "")
  private let copyButton = NSButton()
  private var copyCount = 0

  // The code: a text view that scrolls sideways.
  private let scrollView = CodeScrollView()
  private let textStorage = NSTextStorage()
  private let layoutManager = NSLayoutManager()
  private let textContainer: NSTextContainer
  private let textView: NSTextView

  private var isHighlighting = false
  private var needsHighlight = false
  private var lastHighlightStart: ContinuousClock.Instant?

  init(content: CodeBlockContent) {
    self.content = content

    let unlimited = CGFloat.greatestFiniteMagnitude
    textContainer = NSTextContainer(size: NSSize(width: unlimited, height: unlimited))
    textContainer.widthTracksTextView = false
    textContainer.lineFragmentPadding = 0
    textStorage.addLayoutManager(layoutManager)
    layoutManager.addTextContainer(textContainer)
    textView = NSTextView(frame: .zero, textContainer: textContainer)

    super.init(frame: .zero)

    wantsLayer = true
    layer?.cornerRadius = 16
    layer?.cornerCurve = .continuous
    layer?.borderWidth = 1
    layer?.masksToBounds = true

    setUpHeader()
    setUpCode()

    showLanguage(content.language)
    textStorage.setAttributedString(codeText(content.code))
    highlight()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setUpHeader() {
    languageIcon.image = NSImage(
      systemSymbolName: "chevron.left.forwardslash.chevron.right",
      accessibilityDescription: nil
    )
    let iconConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
    languageIcon.symbolConfiguration = iconConfiguration
    languageIcon.contentTintColor = .labelColor
    addSubview(languageIcon)

    languageLabel.font = .systemFont(ofSize: 15)
    languageLabel.textColor = .labelColor
    languageLabel.lineBreakMode = .byTruncatingTail
    addSubview(languageLabel)

    copyButton.isBordered = false
    copyButton.imagePosition = .imageOnly
    copyButton.contentTintColor = .labelColor
    let buttonConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
    copyButton.symbolConfiguration = buttonConfiguration
    copyButton.toolTip = "Copy"
    copyButton.target = self
    copyButton.action = #selector(copyCode)
    setCopyButton(symbol: "square.on.square")
    addSubview(copyButton)
  }

  private func setUpCode() {
    textView.isEditable = false
    textView.isSelectable = true
    textView.drawsBackground = false
    textView.isHorizontallyResizable = true
    textView.isVerticallyResizable = false
    textView.textContainerInset = NSSize(width: Self.horizontalPadding, height: 0)

    scrollView.drawsBackground = false
    scrollView.hasHorizontalScroller = true
    scrollView.hasVerticalScroller = false
    scrollView.autohidesScrollers = true
    scrollView.scrollerStyle = .overlay
    scrollView.verticalScrollElasticity = .none
    scrollView.documentView = textView
    addSubview(scrollView)
  }

  override var isFlipped: Bool { true }

  override var wantsUpdateLayer: Bool { true }

  override func updateLayer() {
    layer?.backgroundColor = content.background.cgColor
    layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.04).cgColor
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    highlight()
  }

  // MARK: Layout

  override func layout() {
    super.layout()
    layoutHeader()
    layoutCode()
  }

  private func layoutHeader() {
    let left = Self.horizontalPadding
    let right = bounds.width - Self.horizontalPadding

    func centeredY(_ height: CGFloat) -> CGFloat {
      Self.padding + (Self.headerHeight - height) / 2
    }

    copyButton.sizeToFit()
    let buttonSize = copyButton.frame.size
    let buttonX = right - buttonSize.width
    let buttonOrigin = CGPoint(x: buttonX, y: centeredY(buttonSize.height))
    copyButton.frame = CGRect(origin: buttonOrigin, size: buttonSize)

    // The size is the shape of the symbol. The frame adds the empty space around it.
    let iconSize = languageIcon.isHidden ? .zero : languageIcon.intrinsicContentSize
    let iconOrigin = CGPoint(x: left, y: centeredY(iconSize.height))
    let iconRect = CGRect(origin: iconOrigin, size: iconSize)
    languageIcon.frame = languageIcon.frame(forAlignmentRect: iconRect)

    // The name stops before the copy button.
    languageLabel.sizeToFit()
    let labelX = left + iconSize.width + Self.iconSpacing
    let labelMaxWidth = copyButton.frame.minX - Self.horizontalPadding - labelX
    languageLabel.frame = CGRect(
      x: labelX,
      y: centeredY(languageLabel.frame.height),
      width: max(0, min(languageLabel.frame.width, labelMaxWidth)),
      height: languageLabel.frame.height
    )
  }

  /// The code fills the rest. The text view is as wide as the longest line, to scroll.
  private func layoutCode() {
    let codeHeight = Self.codeHeight(lineCount: content.lineCount, font: content.font)
    scrollView.frame = CGRect(
      x: 0,
      y: Self.padding + Self.headerHeight + Self.headerSpacing,
      width: bounds.width,
      height: codeHeight
    )

    layoutManager.ensureLayout(for: textContainer)
    let usedWidth = ceil(layoutManager.usedRect(for: textContainer).width)
    let textWidth = max(usedWidth + Self.horizontalPadding * 2, bounds.width)
    textView.frame = CGRect(x: 0, y: 0, width: textWidth, height: codeHeight)
  }

  // MARK: Content

  /// Shows new content. Streaming code only appends the new end, so the layout and the
  /// colors that are already there stay.
  func show(_ content: CodeBlockContent) {
    let oldContent = self.content
    self.content = content
    showLanguage(content.language)

    if content.background != oldContent.background {
      needsDisplay = true
    }

    let isSameFont = content.font == oldContent.font
    guard content.code != oldContent.code || !isSameFont else {
      if content.theme != oldContent.theme {
        highlight()
      }
      return
    }

    if isSameFont, content.code.utf8.starts(with: oldContent.code.utf8) {
      let newPart = content.code.utf8.dropFirst(oldContent.code.utf8.count)
      textStorage.append(codeText(String(decoding: newPart, as: UTF8.self)))
    } else {
      textStorage.setAttributedString(codeText(content.code))
    }

    needsLayout = true
    highlight()
  }

  /// Shows the language name with an icon, like "Swift" for `swift`, or "Text" without one.
  private func showLanguage(_ language: String?) {
    let name = language.map(Self.displayName(of:)) ?? "Text"
    let isNameShown = languageLabel.stringValue == name
    let isIconShown = languageIcon.isHidden == name.isEmpty
    guard !(isNameShown && isIconShown) else { return }

    languageLabel.stringValue = name
    languageIcon.isHidden = name.isEmpty
    needsLayout = true
  }

  private static func displayName(of language: String) -> String {
    if let name = languageNames[language.lowercased()] {
      return name
    }
    return language.prefix(1).uppercased() + language.dropFirst()
  }

  private func codeText(_ code: String) -> NSAttributedString {
    NSAttributedString(string: code, attributes: textAttributes)
  }

  /// A fixed line height, so the height of the block follows from the line count. Tabs
  /// are four spaces wide.
  private var textAttributes: TextAttributes {
    let font = content.font
    let lineHeight = Self.lineHeight(for: font)
    let spaceWidth = (" " as NSString).size(withAttributes: [.font: font]).width

    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.minimumLineHeight = lineHeight
    paragraphStyle.maximumLineHeight = lineHeight
    paragraphStyle.lineSpacing = Self.lineSpacing
    paragraphStyle.tabStops = []
    paragraphStyle.defaultTabInterval = spaceWidth * 4

    return [
      .font: font,
      .paragraphStyle: paragraphStyle,
      .foregroundColor: NSColor.labelColor,
    ]
  }

  // MARK: Highlighting

  /// Highlights at most every 200 ms, so streaming code doesn't get highlighted on every
  /// update. Requests that come in while one waits or runs become one more run after it.
  private func highlight() {
    guard !isHighlighting else {
      needsHighlight = true
      return
    }
    isHighlighting = true

    let interval = Duration.milliseconds(200)
    let delay = lastHighlightStart.map { interval - (ContinuousClock.now - $0) } ?? .zero

    Task { [weak self] in
      if delay > .zero {
        try? await Task.sleep(for: delay)
      }
      guard let self else { return }

      lastHighlightStart = .now
      let code = content.code
      let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      let highlighted = await CodeHighlighter.shared.highlight(
        code,
        language: content.language,
        themeName: isDark ? content.theme.dark : content.theme.light
      )

      isHighlighting = false
      if let highlighted {
        applyColors(of: highlighted, for: code)
      }

      if needsHighlight {
        needsHighlight = false
        highlight()
      }
    }
  }

  private func applyColors(of highlighted: HighlightedCode, for code: String) {
    let colored = highlighted.string

    // The colors only fit while the text still starts with the code that got highlighted.
    guard colored.string == code else { return }
    guard textStorage.mutableString.hasPrefix(code) else { return }

    // Only runs with a new color change, so TextKit redoes only those lines.
    textStorage.beginEditing()
    let wholeCode = colored.fullRange
    colored.enumerateAttribute(.foregroundColor, in: wholeCode) { color, range, _ in
      let newColor = color as? NSColor ?? .labelColor

      var currentRange = NSRange()
      let current = textStorage.attribute(
        .foregroundColor,
        at: range.location,
        longestEffectiveRange: &currentRange,
        in: range
      )

      if current as? NSColor != newColor || currentRange.length < range.length {
        textStorage.addAttribute(.foregroundColor, value: newColor, range: range)
      }
    }
    textStorage.endEditing()
  }

  // MARK: Copy

  @objc private func copyCode() {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(content.code, forType: .string)

    // A check mark for two seconds.
    setCopyButton(symbol: "checkmark")
    copyCount += 1
    let count = copyCount
    Task { [weak self] in
      try? await Task.sleep(for: .seconds(2))
      guard let self, copyCount == count else { return }
      setCopyButton(symbol: "square.on.square")
    }
  }

  private func setCopyButton(symbol: String) {
    copyButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Copy")
    needsLayout = true
  }
}

/// Scrolls only sideways. Vertical scrolls go on to the scroll view around the text.
private final class CodeScrollView: NSScrollView {
  override func scrollWheel(with event: NSEvent) {
    if abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) {
      nextResponder?.scrollWheel(with: event)
    } else {
      super.scrollWheel(with: event)
    }
  }
}
