import AppKit

/// An attachment that turns into text when you copy it.
protocol CopyableAttachment: NSTextAttachment {
  var copiedText: String { get }
}

/// No width, and no line break around it. Keeps a link icon with the first word.
let wordJoiner = "\u{2060}"

/// No width, but the line can break there. Inline code needs it in front, because a word
/// joiner right after a space also stops the break after the space.
let zeroWidthSpace = "\u{200B}"

extension NSAttributedString {
  /// The text as a copy should have it: attachments become their text, and the invisible
  /// characters go away.
  func replacingCopyableAttachments() -> NSAttributedString {
    let text = NSMutableAttributedString(attributedString: self)

    text.enumerateAttribute(
      .attachment,
      in: text.fullRange,
      options: .reverse
    ) { value, range, _ in
      guard let attachment = value as? any CopyableAttachment else { return }

      var attributes = text.attributes(at: range.location, effectiveRange: nil)
      attributes[.attachment] = nil
      let replacement = NSAttributedString(
        string: attachment.copiedText,
        attributes: attributes
      )
      text.replaceCharacters(in: range, with: replacement)
    }

    for character in [wordJoiner, zeroWidthSpace] {
      text.mutableString.replaceOccurrences(
        of: character,
        with: "",
        options: [],
        range: text.fullRange
      )
    }
    return text
  }

  /// The visible text of a link, without its icon and the invisible characters in front.
  func textRange(ofLinkAt range: NSRange) -> NSRange {
    let string = string as NSString
    let invisible: [unichar] = [0xFFFC, 0x2060, 0x200B]

    var range = range
    while range.length > 0, invisible.contains(string.character(at: range.location)) {
      range.location += 1
      range.length -= 1
    }
    return range
  }
}
