import AppKit
import Testing

@testable import Sumi

/// Streaming takes shortcuts: it parses only the last blocks again, keeps the blocks that
/// didn't change, and keeps the views of boxes. These tests feed a message in small
/// pieces and check that after every piece, the view looks exactly like a fresh view of
/// the same text: same characters and styles, same height, and boxes in the same places.
@MainActor
struct StreamingTests {
  struct Stream: CustomTestStringConvertible, Sendable {
    var name: String
    var text: String
    var chunk: Int

    var testDescription: String { "\(name), \(chunk) characters at a time" }
  }

  nonisolated static let streams = [
    Stream(
      name: "answer",
      text: String(repeating: Messages.answer, count: 6),
      chunk: 120
    ),
    Stream(name: "tricky", text: Messages.tricky, chunk: 3),
    Stream(name: "lists", text: Messages.lists, chunk: 7),
    Stream(name: "mixed", text: Messages.mixed, chunk: 40),
    Stream(name: "big table", text: Messages.bigTable, chunk: 40),
  ]

  @Test(arguments: streams)
  func everyUpdateMatchesAFreshView(_ stream: Stream) throws {
    let streamed = Host()

    for text in Messages.stream(stream.text, chunk: stream.chunk) {
      streamed.show(text)
      let fresh = Host()
      fresh.show(text)

      let streamedView = try #require(streamed.textView)
      let freshView = try #require(fresh.textView)
      let bytes = text.utf8.count

      let streamedText = streamedView.attributedString()
      let difference = difference(streamedText, freshView.attributedString())
      #expect(difference == nil, "after \(bytes) bytes: \(difference ?? "")")
      #expect(streamedView.frame.height == freshView.frame.height, "after \(bytes) bytes")
      #expect(streamedView.boxFrames == freshView.boxFrames, "after \(bytes) bytes")
    }
  }

  /// The first place where the text or the styles differ. Each view has its own
  /// attachments, so they compare by box id, copied text, and size.
  private func difference(
    _ left: NSAttributedString,
    _ right: NSAttributedString
  ) -> String? {
    guard left.string == right.string else {
      let common = zip(left.string, right.string).prefix { $0 == $1 }.count
      return "text differs after \(common) characters"
    }

    var location = 0
    while location < left.length {
      var leftRange = NSRange()
      var rightRange = NSRange()
      var leftAttributes = left.attributes(at: location, effectiveRange: &leftRange)
      var rightAttributes = right.attributes(at: location, effectiveRange: &rightRange)

      let leftAttachment = leftAttributes.removeValue(forKey: .attachment)
      let rightAttachment = rightAttributes.removeValue(forKey: .attachment)
      guard isSameAttachment(leftAttachment, rightAttachment) else {
        return "attachment differs at \(location)"
      }

      guard NSDictionary(dictionary: leftAttributes).isEqual(to: rightAttributes) else {
        let keys = Set(leftAttributes.keys).union(rightAttributes.keys).filter { key in
          !NSDictionary(dictionary: [key: leftAttributes[key] ?? NSNull()])
            .isEqual(to: [key: rightAttributes[key] ?? NSNull()])
        }
        return "styles differ at \(location): \(keys.map(\.rawValue))"
      }

      location = min(NSMaxRange(leftRange), NSMaxRange(rightRange))
    }
    return nil
  }

  private func isSameAttachment(_ left: Any?, _ right: Any?) -> Bool {
    let left = left as? any CopyableAttachment
    let right = right as? any CopyableAttachment
    let isSameBox = (left as? BoxAttachment)?.id == (right as? BoxAttachment)?.id
    let isSameText = left?.copiedText == right?.copiedText
    return isSameBox && isSameText && left?.bounds == right?.bounds
  }
}

extension BlockTextView {
  /// The frames of the box views, from the top.
  var boxFrames: [CGRect] {
    boxViews.values
      .map { $0.convert($0.bounds, to: self) }
      .sorted { ($0.minY, $0.minX) < ($1.minY, $1.minX) }
  }
}
