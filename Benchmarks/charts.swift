// Draws the README charts from a benchmark summary, and prints what goes under them in
// the README: a line about the runs, and all results as a Markdown table.
//
//   swift charts.swift results/<date>.json
//
// Each chart gets a light and a dark SVG in charts/. Sumi is blue and the other libraries
// are gray, so the chart is about Sumi. The SVGs have no background, so they sit on the
// GitHub page in either theme.

import Foundation

struct Summary: Decodable {
  var date: String
  var machine: Machine
  var results: [Row]
}

struct Machine: Decodable {
  var chip: String
  var memoryGB: Int
  var macOS: String
  var power: String
}

struct Row: Decodable {
  var library: String
  var kind: String
  var missedFrames: Double
  var cpu: Double
  var memory: Double
  var open: Double
  var runs: [Run]
}

struct Run: Decodable {
  var seconds: Double
}

struct Theme {
  var name: String
  var accent: String
  var gray: String
  var axis: String
  var primary: String
  var secondary: String
}

let themes = [
  Theme(
    name: "light",
    accent: "#2a78d6",
    gray: "#898781",
    axis: "#c3c2b7",
    primary: "#0b0b0b",
    secondary: "#52514e"
  ),
  Theme(
    name: "dark",
    accent: "#3987e5",
    gray: "#6f6e69",
    axis: "#383835",
    primary: "#f0efec",
    secondary: "#c3c2b7"
  ),
]

struct Chart {
  var file: String
  var title: String
  var subtitle: String
  var value: (Row) -> Double
  var maximum: Double
}

let kinds = ["mixed", "prose", "code", "table"]

// Room for the library names on the left, then one panel for each kind.
let width = 840.0
let labelWidth = 184.0
let panelWidth = (width - labelWidth) / Double(kinds.count)
let panelGap = 14.0
let valueWidth = 38.0
let barLength = panelWidth - panelGap - valueWidth
let barHeight = 14.0
let rowHeight = 28.0
let font = "-apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif"

// MARK: - Reading

let arguments = CommandLine.arguments.dropFirst()
guard let path = arguments.first else {
  print("Usage: swift charts.swift results/<date>.json")
  exit(1)
}

let summary = try JSONDecoder().decode(
  Summary.self,
  from: Data(contentsOf: URL(fileURLWithPath: path))
)

// The order of the run, which puts Sumi first and the plain text view last.
var libraries: [String] = []
for row in summary.results where !libraries.contains(row.library) {
  libraries.append(row.library)
}

func row(_ library: String, _ kind: String) -> Row? {
  summary.results.first { $0.library == library && $0.kind == kind }
}

func displayName(_ library: String) -> String {
  library == "PlainTextView" ? "Plain NSTextView" : library
}

let runCount = summary.results.map(\.runs.count).max() ?? 0

// A frozen view gets the answer late, so the shortest run is the length of the answer.
let seconds = summary.results.flatMap(\.runs).map(\.seconds).min() ?? 0
let frames = seconds * 60

// "Version 27.0.1 (Build 26A434)" becomes "27.0.1".
let macOSVersion = summary.machine.macOS.split(separator: " ").dropFirst().first ?? ""
let power = summary.machine.power == "AC Power" ? "plugged in" : "on battery"

let date: String = {
  let formatter = DateFormatter()
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.dateFormat = "MMMM d, yyyy"
  let parsed = ISO8601DateFormatter().date(from: summary.date) ?? Date()
  return formatter.string(from: parsed)
}()

let runInfo = """
  Median of \(runCount) runs on \(summary.machine.chip), \(summary.machine.memoryGB) GB, \
  macOS \(macOSVersion), \(power), \(date).
  """

// MARK: - Drawing

func number(_ value: Double) -> String {
  let formatter = NumberFormatter()
  formatter.locale = Locale(identifier: "en_US")
  formatter.numberStyle = .decimal
  formatter.maximumFractionDigits = 0
  return formatter.string(from: NSNumber(value: value.rounded())) ?? "\(value)"
}

/// A bar that grows from the baseline at `x`, square there and round at its end.
func bar(x: Double, y: Double, length: Double, color: String) -> String {
  // Even a zero gets a sliver, so every library has a mark.
  let length = max(length, 2)
  let radius = min(4, length)
  let end = x + length
  let bottom = y + barHeight
  return """
    <path d="M\(x) \(y)H\(end - radius)A\(radius) \(radius) 0 0 1 \(end) \(y + radius)\
    V\(bottom - radius)A\(radius) \(radius) 0 0 1 \(end - radius) \(bottom)H\(x)Z" \
    fill="\(color)"/>
    """
}

func text(
  _ string: String,
  x: Double,
  y: Double,
  size: Double,
  color: String,
  weight: Int = 400
) -> String {
  """
  <text x="\(x)" y="\(y)" font-size="\(size)" font-weight="\(weight)" \
  fill="\(color)">\(string)</text>
  """
}

func svg(_ chart: Chart, theme: Theme) -> String {
  let firstRow = 96.0
  let lastRow = firstRow + Double(libraries.count - 1) * rowHeight
  let height = lastRow + barHeight / 2 + 8
  var parts: [String] = []

  parts.append(
    text(chart.title, x: 0, y: 20, size: 15, color: theme.primary, weight: 600)
  )
  parts.append(text(chart.subtitle, x: 0, y: 41, size: 13, color: theme.secondary))

  for (index, library) in libraries.enumerated() {
    let center = firstRow + Double(index) * rowHeight
    let isSumi = library == "Sumi"
    parts.append(
      text(
        displayName(library),
        x: 0,
        y: center + 4.5,
        size: 13,
        color: isSumi ? theme.primary : theme.secondary,
        weight: isSumi ? 600 : 400
      )
    )
  }

  for (column, kind) in kinds.enumerated() {
    let x = labelWidth + Double(column) * panelWidth
    parts.append(
      text(kind.capitalized, x: x, y: 72, size: 13, color: theme.primary, weight: 600)
    )

    // The baseline of the panel.
    parts.append(
      """
      <rect x="\(x - 1)" y="\(firstRow - barHeight / 2 - 4)" width="1" \
      height="\(lastRow - firstRow + barHeight + 8)" fill="\(theme.axis)"/>
      """
    )

    for (index, library) in libraries.enumerated() {
      guard let row = row(library, kind) else { continue }

      let value = chart.value(row)
      let length = barLength * min(value / chart.maximum, 1)
      let top = firstRow + Double(index) * rowHeight - barHeight / 2
      let isSumi = library == "Sumi"
      parts.append(
        bar(x: x, y: top, length: length, color: isSumi ? theme.accent : theme.gray)
      )
      parts.append(
        text(
          number(value),
          x: x + max(length, 2) + 6,
          y: top + barHeight / 2 + 4,
          size: 12,
          color: isSumi ? theme.primary : theme.secondary,
          weight: isSumi ? 600 : 400
        )
      )
    }
  }

  return """
    <svg xmlns="http://www.w3.org/2000/svg" width="\(width)" height="\(height)" \
    viewBox="0 0 \(width) \(height)" font-family="\(font)" role="img" \
    aria-label="\(chart.title)">
    <title>\(chart.title)</title>
    \(parts.joined(separator: "\n"))
    </svg>

    """
}

// MARK: - Charts

let roundedFrames = Int((frames / 100).rounded()) * 100
let charts = [
  Chart(
    file: "missed-frames",
    title: "Missed frames while the answer streams",
    subtitle: """
      Out of about \(roundedFrames) frames at 60 Hz, while a 32 KB answer arrives. \
      Fewer is better.
      """,
    value: \.missedFrames,
    maximum: max(frames, summary.results.map(\.missedFrames).max() ?? 0)
  ),
  Chart(
    file: "open",
    title: "Time to open a whole answer",
    subtitle: "In milliseconds, for a 32 KB answer in a new view. Less is better.",
    value: \.open,
    maximum: summary.results.map(\.open).max() ?? 1
  ),
]

let chartsDirectory = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent()
  .appendingPathComponent("charts")
try FileManager.default.createDirectory(
  at: chartsDirectory,
  withIntermediateDirectories: true
)

for chart in charts {
  for theme in themes {
    let url = chartsDirectory.appendingPathComponent("\(chart.file)-\(theme.name).svg")
    try svg(chart, theme: theme).write(to: url, atomically: true, encoding: .utf8)
    print("Saved \(url.path)")
  }
}

// MARK: - Table

print("")
print(runInfo)
print("")
print("| Content | Library | Missed frames | CPU | Memory | Open |")
print("| --- | --- | ---: | ---: | ---: | ---: |")
for kind in kinds {
  for (index, library) in libraries.enumerated() {
    guard let row = row(library, kind) else { continue }

    let cells = [
      index == 0 ? kind.capitalized : "",
      displayName(library),
      number(row.missedFrames),
      "\(number(row.cpu * 100))%",
      "\(number(row.memory)) MB",
      "\(number(row.open)) ms",
    ]
    print("| " + cells.joined(separator: " | ") + " |")
  }
}
