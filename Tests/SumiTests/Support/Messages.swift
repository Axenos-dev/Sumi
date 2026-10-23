/// Messages for the tests, each aimed at something that can break while text streams in.
enum Messages {
  /// A typical agent answer: a heading, links, inline code, lists, a code block, a table,
  /// a quote, and math.
  static let answer = """
    ## The volume switch

    The branch is close. **One problem blocks the push:** `Switch` unmounts the old \
    volume \
    before the new mount is ready. If the mount fails, the server has no volume. The \
    problem \
    is in [@switch.go](file:///Users/demo/tarn/internal/volume/switch.go#L88), and the \
    test \
    [@switch_test.go](file:///Users/demo/tarn/internal/volume/switch_test.go) did not \
    find it.

    I changed two things:

    1. Move `unmount(old)` after `waitHealthy(new)`, so a failed mount keeps the old \
    volume.
    2. Add a health check to the test fixture. The test now fails on the old code.

    - File: `internal/volume/delete.go`, line 42
    - Fix: delete the branch first, then remove the directory.

    ```go
    func (s *Switcher) Switch(ctx context.Context, old, new Volume) error {
    \tif err := s.mount(ctx, new); err != nil {
    \t\treturn fmt.Errorf("mount %s: %w", new.ID, err)
    \t}
    \treturn s.unmount(ctx, old)
    }
    ```

    | Area | Result |
    | --- | --- |
    | Creation | No problems |
    | Deletion | Branch stays after a failed delete |

    > The old volume stays mounted until the new one passes its health check.

    The switch takes about $t = 2 \\cdot n$ seconds for $n$ volumes.

    """

  /// New characters change blocks that came before them: a setext heading, emphasis that
  /// closes later, a list that turns loose, a fenced block with a blank line, and link
  /// references defined after their links.
  static let tricky = """
    Hello
    ***Note*** and more text.

    Title
    ---

    | a | b |
    | --- | --- |
    | 1 | 2 |

    - one

    - two

    ```swift
    let a = 1

    let b = 2
    ```

    See [the docs][1] and [the guide][guide].

    [1]: https://example.com/docs
    [guide]: https://example.com/guide

    Last paragraph.

    """

  /// Headings, inline styles, breaks, nested lists, and an item with more than one block.
  static let lists = """
    # Title one

    Text with **bold**, *italic*, ***both***, ~~gone~~, `code`, and a \
    [link](https://a.com).
    Soft break here.\\
    Hard break here.

    ### Level three with `code`

    - one
    - two **bold**
      - nested *item*
        1. deep
    - three

      A second paragraph in the item.

      ```sh
      make build
      ```
    3. three
    4. four

    ---

    Last.

    """

  /// Link icons, task lists, code blocks with and without a language, a code block with a
  /// custom view, aligned table columns, and a quote with a list.
  static let mixed = """
    ## Links

    The fix is in [**the volume package**](file:///Users/demo/tarn/internal/volume/), \
    and \
    the [incident note](https://example.com/incidents/42) has the timeline. The icon \
    stays \
    with the first word: [@a_file_with_a_long_name.swift](file:///Users/demo/a.swift).

    - [ ] Update [@delete.go](file:///Users/demo/tarn/internal/volume/delete.go).
    - [x] Read [the switch notes](myapp://notes/42).

    ```
    make build
    ```

    ```chart
    mounts 3
    unmounts 2
    ```

    | Area | Result | Owner |
    | :--- | :---: | ---: |
    | Creation | No problems | `volume` team |
    | Deletion | **Branch stays** after a failed delete, and someone removes it by \
    hand | ops |

    > The old volume stays mounted until the new one passes its health check.
    >
    > - First, the server mounts the new volume.
    > - Then it unmounts the old one.

    """

  /// A table that streams in row by row. Some rows have a long cell, so the column widths
  /// change along the way.
  static let bigTable: String = {
    var lines = ["| Volume | Server | Result |", "| --- | --- | --- |"]
    for row in 0..<60 {
      let result =
        row % 13 == 0
        ? "**Failed** health check after the mount took longer than the timeout"
        : "Healthy"
      lines.append("| vol-\(1000 + row) | server-\(row % 12) | \(result) |")
    }
    return lines.joined(separator: "\n") + "\n"
  }()

  /// The text after each update of a stream that adds `chunk` characters at a time.
  static func stream(_ text: String, chunk: Int) -> [String] {
    var prefixes: [String] = []
    var end = text.startIndex
    while end < text.endIndex {
      end = text.index(end, offsetBy: chunk, limitedBy: text.endIndex) ?? text.endIndex
      prefixes.append(String(text[..<end]))
    }
    return prefixes
  }
}
