import AppKit

/// A table, drawn by hand.
///
/// Its size comes from measuring the cells, so TextKit gets it without laying out a view.
/// The first row is the header. There's no border, and the text lines up with the text
/// around it.
struct TableContent: BoxContent {
  var rows: [[NSAttributedString]]
  var showsRowLines: Bool
  fileprivate var measurements = TableMeasurements()

  init(rows: [[NSAttributedString]], showsRowLines: Bool) {
    self.rows = rows
    self.showsRowLines = showsRowLines
  }

  /// A tab between cells, and a line break between rows.
  var copiedText: String {
    let lines = rows.map { row in
      row.map { $0.replacingCopyableAttachments().string }.joined(separator: "\t")
    }
    return lines.joined(separator: "\n")
  }

  /// A streaming table keeps the measurements of the rows it already had.
  mutating func keepWork(from previous: any BoxContent) {
    if let previous = previous as? TableContent {
      measurements = previous.measurements
    }
  }

  func makeView() -> NSView {
    TableView(content: self)
  }

  func update(_ view: NSView) {
    (view as? TableView)?.show(self)
  }

  func size(forWidth width: CGFloat) -> CGSize {
    CGSize(width: width, height: layout(forWidth: width).height)
  }

  fileprivate func layout(forWidth width: CGFloat) -> TableLayout {
    let columnCount = rows.map(\.count).max() ?? 0
    guard columnCount > 0 else { return .empty }

    let spacing = TableLayout.columnSpacing * CGFloat(columnCount - 1)
    let columnWidths = Self.columnWidths(
      natural: naturalColumnWidths(count: columnCount),
      available: max(0, width - spacing)
    )

    let cellHeights = measurements.cellHeights(columnWidths: columnWidths)
    let rowHeights = cellHeights.indices.map { row in
      let above = TableLayout.padding(aboveRow: row)
      let below = TableLayout.padding(belowRow: row, rowCount: rows.count)
      return (cellHeights[row].max() ?? 0) + above + below
    }

    let separators = CGFloat(rows.count - 1) * TableLayout.separatorHeight
    return TableLayout(
      columnWidths: columnWidths,
      rowHeights: rowHeights,
      cellHeights: cellHeights,
      height: rowHeights.reduce(0, +) + separators
    )
  }

  /// The widest line in each column.
  private func naturalColumnWidths(count: Int) -> [CGFloat] {
    var widths = Array(repeating: CGFloat(0), count: count)
    for rowWidths in measurements.naturalWidths(of: rows) {
      for (column, width) in rowWidths.enumerated() {
        widths[column] = max(widths[column], width)
      }
    }
    return widths
  }

  /// When the table fits, each column gets its widest line plus a share of the spare
  /// room. When it doesn't, the columns split the room evenly: a column that needs less
  /// keeps its widest line, and the text in the others wraps.
  private static func columnWidths(natural: [CGFloat], available: CGFloat) -> [CGFloat] {
    let naturalTotal = natural.reduce(0, +)
    if naturalTotal <= available, naturalTotal > 0 {
      let spare = available - naturalTotal
      return natural.map { $0 + spare * $0 / naturalTotal }
    }

    var widths = natural
    var open = Set(natural.indices)
    var remaining = available

    while !open.isEmpty {
      let share = remaining / CGFloat(open.count)
      let narrow = open.filter { natural[$0] <= share }
      if narrow.isEmpty {
        for column in open {
          widths[column] = share
        }
        break
      }

      for column in narrow {
        widths[column] = natural[column]
        remaining -= natural[column]
        open.remove(column)
      }
    }
    return widths
  }
}

/// The widest line and the height of every cell, row by row. Rows that didn't change keep
/// their numbers.
private final class TableMeasurements {
  private struct Row {
    var cells: [NSAttributedString]
    var naturalWidths: [CGFloat]

    /// The heights at `heightsColumnWidths`, or `nil` until measured at those widths.
    var cellHeights: [CGFloat]?
  }

  private var rows: [Row] = []
  private var heightsColumnWidths: [CGFloat] = []

  /// Measures the rows that changed, and returns the widest line of every cell.
  func naturalWidths(of cells: [[NSAttributedString]]) -> [[CGFloat]] {
    rows.removeSubrange(min(rows.count, cells.count)...)

    for (index, rowCells) in cells.enumerated() {
      if index < rows.count, rows[index].cells == rowCells {
        continue
      }

      let widths = rowCells.map { cell in
        ceil(cell.drawnSize(forWidth: .greatestFiniteMagnitude).width)
      }
      let row = Row(cells: rowCells, naturalWidths: widths, cellHeights: nil)

      if index < rows.count {
        rows[index] = row
      } else {
        rows.append(row)
      }
    }
    return rows.map(\.naturalWidths)
  }

  /// Measures the heights of the rows that changed. New column widths remeasure them all.
  func cellHeights(columnWidths: [CGFloat]) -> [[CGFloat]] {
    if columnWidths != heightsColumnWidths {
      heightsColumnWidths = columnWidths
      for index in rows.indices {
        rows[index].cellHeights = nil
      }
    }

    return rows.indices.map { index in
      if let heights = rows[index].cellHeights {
        return heights
      }

      let heights = rows[index].cells.enumerated().map { column, cell in
        ceil(cell.drawnSize(forWidth: max(1, columnWidths[column])).height)
      }
      rows[index].cellHeights = heights
      return heights
    }
  }
}

private struct TableLayout {
  static let columnSpacing: CGFloat = 24
  static let rowPadding: CGFloat = 11
  static let separatorHeight: CGFloat = 1

  static let empty = TableLayout(
    columnWidths: [],
    rowHeights: [],
    cellHeights: [],
    height: 0
  )

  /// No padding above the header, so the gap above the table is just the block spacing.
  static func padding(aboveRow row: Int) -> CGFloat {
    row == 0 ? 0 : rowPadding
  }

  /// No padding below the last row, so the gap below the table is just the block spacing.
  static func padding(belowRow row: Int, rowCount: Int) -> CGFloat {
    row == rowCount - 1 ? 0 : rowPadding
  }

  /// Without the spacing between columns.
  var columnWidths: [CGFloat]
  var rowHeights: [CGFloat]
  var cellHeights: [[CGFloat]]
  var height: CGFloat
}

final class TableView: DrawnTextView {
  private var content: TableContent
  private var cachedLayout: (width: CGFloat, layout: TableLayout)?

  init(content: TableContent) {
    self.content = content
    super.init(frame: .zero)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func show(_ content: TableContent) {
    let isSame = content.rows == self.content.rows
    guard !isSame || content.showsRowLines != self.content.showsRowLines else { return }

    self.content = content
    cachedLayout = nil
    textDidChange()
  }

  /// All cells in a row start at the same height, so their first lines line up.
  override var drawnTexts: [(string: NSAttributedString, rect: CGRect)] {
    let layout = currentLayout
    var texts: [(string: NSAttributedString, rect: CGRect)] = []

    var y: CGFloat = 0
    for (rowIndex, row) in content.rows.enumerated() {
      if rowIndex > 0 {
        y += TableLayout.separatorHeight
      }

      var x: CGFloat = 0
      for (column, cell) in row.enumerated() {
        let rect = CGRect(
          x: x,
          y: y + TableLayout.padding(aboveRow: rowIndex),
          width: max(1, layout.columnWidths[column]),
          height: layout.cellHeights[rowIndex][column]
        )
        texts.append((cell, rect))
        x += layout.columnWidths[column] + TableLayout.columnSpacing
      }

      y += layout.rowHeights[rowIndex]
    }
    return texts
  }

  /// A line under the header, and fainter lines between the other rows.
  override func draw(_ dirtyRect: NSRect) {
    let layout = currentLayout

    let lineHeight = TableLayout.separatorHeight

    var y: CGFloat = 0
    for (row, rowHeight) in layout.rowHeights.dropLast().enumerated() {
      y += rowHeight

      if row == 0 || content.showsRowLines {
        let alpha: CGFloat = row == 0 ? 0.15 : 0.07
        NSColor.labelColor.withAlphaComponent(alpha).setFill()
        NSRect(x: 0, y: y, width: bounds.width, height: lineHeight).fill()
      }

      y += lineHeight
    }

    drawTexts(in: dirtyRect)
  }

  private var currentLayout: TableLayout {
    if let cachedLayout, cachedLayout.width == bounds.width {
      return cachedLayout.layout
    }

    let layout = content.layout(forWidth: bounds.width)
    cachedLayout = (bounds.width, layout)
    return layout
  }
}
