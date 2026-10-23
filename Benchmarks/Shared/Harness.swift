// Streams a long Markdown answer into a library's view in a real window, and measures
// what a user would notice.
//
//   Bench <library> <kind> <run>          one run, saved to results/runs
//   Bench summary <commit> <library>...   medians of the saved runs, saved to results
//   Bench preview                         Sumi in a light and a dark window, to record
//
// The answer arrives in real time: 120 bytes every 50 ms. A view that falls behind gets
// everything that arrived in the meantime on its next update, like in a chat app.

import AppKit
import IOKit.ps
import QuartzCore
import SwiftUI

let width: CGFloat = 720
let height: CGFloat = 800
let targetBytes = 32_000
let chunkLength = 120
let interval = 0.05
let kinds = ["mixed", "prose", "code", "table"]

// One frame at 60 Hz, in ms.
let frameTime = 1000.0 / 60

let arguments = Array(CommandLine.arguments.dropFirst())

// main.swift is a link in <package>/Sources/Bench, four levels below Benchmarks.
let benchmarksDirectory = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent()
  .deletingLastPathComponent()
  .deletingLastPathComponent()
  .deletingLastPathComponent()
let resultsDirectory = benchmarksDirectory.appendingPathComponent("results")
let runsDirectory = resultsDirectory.appendingPathComponent("runs")

// MARK: - Window

/// The text so far. Views that take a string read `text`. Views that take a stream of
/// snapshots read `snapshots`, which gets every value of `text`.
@MainActor
final class StreamModel: ObservableObject {
  @Published var text = ""
  let snapshots: AsyncStream<String>
  private let continuation: AsyncStream<String>.Continuation

  init() {
    (snapshots, continuation) = AsyncStream.makeStream(of: String.self)
  }

  func show(_ text: String) {
    self.text = text
    continuation.yield(text)
  }
}

struct HostView: View {
  let library: String
  @ObservedObject var model: StreamModel

  var body: some View {
    ScrollView {
      libraryView(library, model: model)
        .frame(width: width, alignment: .leading)
    }
    .defaultScrollAnchor(.bottom)
    .defaultScrollAnchor(.bottom, for: .sizeChanges)
  }
}

/// A window on screen and above other windows, like the app a user looks at.
@MainActor
final class Host {
  let window: NSWindow
  let hostingView: NSHostingView<HostView>
  let model = StreamModel()

  init(library: String) {
    hostingView = NSHostingView(rootView: HostView(library: library, model: model))

    let screen = NSScreen.main?.visibleFrame ?? .zero
    window = NSWindow(
      contentRect: NSRect(
        x: screen.minX,
        y: screen.maxY - height,
        width: width,
        height: height
      ),
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    window.level = .floating
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    window.appearance = NSAppearance(named: .aqua)
    window.backgroundColor = .white
    window.contentView = hostingView
    window.orderFrontRegardless()
  }

  var isVisible: Bool {
    window.occlusionState.contains(.visible)
  }

  /// True when the view shows the end of the answer.
  var followsEnd: Bool {
    guard let scrollView, let documentView = scrollView.documentView else { return false }

    let visible = scrollView.contentView.documentVisibleRect
    let documentHeight = documentView.frame.height
    let bottom = documentView.isFlipped ? visible.maxY : documentHeight - visible.minY
    return documentHeight > height && documentHeight - bottom < 2
  }

  private var scrollView: NSScrollView? {
    func find(_ view: NSView) -> NSScrollView? {
      if let scrollView = view as? NSScrollView { return scrollView }
      for subview in view.subviews {
        if let found = find(subview) { return found }
      }
      return nil
    }
    return find(hostingView)
  }

  func screenshot(to url: URL) {
    hostingView.layoutSubtreeIfNeeded()
    let bounds = hostingView.bounds
    guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: bounds) else {
      return
    }

    hostingView.cacheDisplay(in: bounds, to: bitmap)
    try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
  }
}

// MARK: - Measuring

/// Records the stretches in which the main run loop is busy, and the most memory seen at
/// the end of each one. The start observer runs before all others and the end observer
/// after all others, so SwiftUI updates and the Core Animation commit fall inside.
@MainActor
final class Meter {
  struct Stretch {
    var start: Double
    var duration: Double
  }

  private(set) var stretches: [Stretch] = []
  private(set) var peakMemory = 0.0
  private var start: CFTimeInterval?
  private var observers: [CFRunLoopObserver] = []

  func begin() {
    let wake = CFRunLoopObserverCreateWithHandler(
      nil,
      CFRunLoopActivity.afterWaiting.rawValue,
      true,
      CFIndex.min
    ) { [unowned self] _, _ in
      MainActor.assumeIsolated { self.start = CACurrentMediaTime() }
    }
    let sleep = CFRunLoopObserverCreateWithHandler(
      nil,
      CFRunLoopActivity.beforeWaiting.rawValue,
      true,
      CFIndex.max
    ) { [unowned self] _, _ in
      MainActor.assumeIsolated { self.close() }
    }

    observers = [wake!, sleep!]
    for observer in observers {
      CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }
    start = CACurrentMediaTime()
  }

  func end() {
    close()
    for observer in observers {
      CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes)
    }
    observers = []
  }

  private func close() {
    guard let start else { return }

    let now = CACurrentMediaTime()
    stretches.append(Stretch(start: start, duration: (now - start) * 1000))
    self.start = nil

    // After the clock stops, so it doesn't count as busy.
    peakMemory = max(peakMemory, memory())
  }
}

/// The memory of the process as Activity Monitor shows it, in MB.
func memory() -> Double {
  var info = task_vm_info_data_t()
  var count = mach_msg_type_number_t(
    MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
  )
  let result = withUnsafeMutablePointer(to: &info) { pointer in
    pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
      task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
    }
  }
  return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
}

/// CPU time of all threads of the process, in seconds.
func processorTime() -> Double {
  var usage = rusage()
  getrusage(RUSAGE_SELF, &usage)
  return Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1e6
    + Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1e6
}

/// Runs the app like `NSApp.run()` does. Without the window events, AppKit thinks the
/// window is hidden, and SwiftUI can pause animations in it.
@MainActor
func runApp(for seconds: Double) {
  let deadline = Date().addingTimeInterval(seconds)
  while let event = NSApp.nextEvent(
    matching: .any,
    until: deadline,
    inMode: .default,
    dequeue: true
  ) {
    NSApp.sendEvent(event)
  }
}

/// Waits until the process uses almost no CPU, so leftover work doesn't leak into the
/// next step.
@MainActor
func settle(timeout: Double = 30) {
  let deadline = Date().addingTimeInterval(timeout)
  var quietIntervals = 0
  while quietIntervals < 3, Date() < deadline {
    let before = processorTime()
    runApp(for: 0.05)
    quietIntervals = processorTime() - before < 0.005 ? quietIntervals + 1 : 0
  }
}

/// Spins for a moment, so the processor is at full speed when the clock starts.
func warmUp(seconds: Double = 0.1) {
  let deadline = CACurrentMediaTime() + seconds
  var value: UInt64 = 1
  while CACurrentMediaTime() < deadline {
    for _ in 0..<1_000 { value = value &* 6_364_136_223_846_793_005 &+ 1 }
  }
  if value == 0 { print("") }
}

/// Runs the app until the main thread has had no busy stretch over 2 ms for one second,
/// and returns the end of the last such stretch.
@MainActor
@discardableResult
func runUntilQuiet(
  _ meter: Meter,
  after start: CFTimeInterval,
  timeout: Double = 20
) -> CFTimeInterval {
  let deadline = CACurrentMediaTime() + timeout
  var lastWork = start
  while CACurrentMediaTime() < deadline {
    runApp(for: 0.1)
    if let last = meter.stretches.last(where: { $0.duration > 2 }) {
      lastWork = max(lastWork, last.start + last.duration / 1000)
    }
    if CACurrentMediaTime() - lastWork > 1 { break }
  }
  return lastWork
}

func streamPrefixes(of text: String, length: Int = chunkLength) -> [String] {
  var prefixes: [String] = []
  var end = text.startIndex
  while end < text.endIndex {
    let next = text.index(end, offsetBy: length, limitedBy: text.endIndex)
    end = next ?? text.endIndex
    prefixes.append(String(text[..<end]))
  }
  return prefixes
}

// MARK: - One run

struct Run: Codable {
  var library: String
  var kind: String
  var run: Int
  /// Frames at 60 Hz that the screen couldn't show on time, because the main thread was
  /// busy.
  var missedFrames: Int
  /// CPU time of all threads while the answer arrived, as a share of one core.
  var cpu: Double
  /// The share of that time in which the main thread was busy.
  var mainThread: Double
  /// The most memory the view added while the answer arrived, in MB.
  var memory: Double
  /// The time to show the whole answer in a new view, in ms.
  var open: Double
  var updates: Int
  var seconds: Double
  /// Anything that makes the run unfair, such as a hidden window.
  var problems: [String]
}

@MainActor
func measure(library: String, kind: String, run: Int) {
  let text = message(kind: kind)
  let prefixes = streamPrefixes(of: text)

  // Stream: each tick shows everything that has arrived so far.
  let host = Host(library: library)
  settle()
  warmUp()
  let wasVisible = host.isVisible
  let meter = Meter()
  let startMemory = memory()
  let startCPU = processorTime()
  meter.begin()

  let streamStart = CACurrentMediaTime()
  var shown = -1
  var updates = 0
  var lastInput: CFTimeInterval?
  let timer = Timer(timeInterval: interval, repeats: true) { timer in
    MainActor.assumeIsolated {
      let now = CACurrentMediaTime()
      let arrived = min(Int((now - streamStart) / interval + 0.1), prefixes.count)
      guard arrived - 1 > shown else { return }

      shown = arrived - 1
      updates += 1
      host.model.show(prefixes[shown])
      if shown == prefixes.count - 1 {
        lastInput = now
        timer.invalidate()
      }
    }
  }
  RunLoop.main.add(timer, forMode: .common)
  while lastInput == nil {
    runApp(for: 0.1)
  }

  let streamEnd = lastInput!
  runUntilQuiet(meter, after: streamEnd)
  meter.end()
  let cpuTime = processorTime() - startCPU
  let seconds = streamEnd - streamStart
  let busy = meter.stretches
    .filter { $0.start <= streamEnd }
    .map(\.duration)
    .reduce(0, +)

  var problems: [String] = []
  if !wasVisible || !host.isVisible {
    problems.append("the window was hidden")
  }
  if !host.followsEnd {
    problems.append("the view did not follow the end")
  }
  if ProcessInfo.processInfo.isLowPowerModeEnabled {
    problems.append("Low Power Mode was on")
  }
  if [.serious, .critical].contains(ProcessInfo.processInfo.thermalState) {
    problems.append("the Mac was hot")
  }

  let name = "\(library)-\(kind)-\(run)"
  try? FileManager.default.createDirectory(
    at: runsDirectory,
    withIntermediateDirectories: true
  )
  host.screenshot(to: runsDirectory.appendingPathComponent("\(name).png"))
  host.window.orderOut(nil)
  settle()

  // Open: the whole answer at once in a new view, like opening an old thread. The app is
  // warm by now, like it would be in real use.
  let openHost = Host(library: library)
  settle()
  warmUp()
  let openMeter = Meter()
  openMeter.begin()
  let openStart = CACurrentMediaTime()
  openHost.model.show(text)
  let openEnd = runUntilQuiet(openMeter, after: openStart)
  openMeter.end()
  openHost.window.orderOut(nil)

  let result = Run(
    library: library,
    kind: kind,
    run: run,
    missedFrames: meter.stretches.map { Int($0.duration / frameTime) }.reduce(0, +),
    cpu: cpuTime / seconds,
    mainThread: busy / 1000 / seconds,
    memory: meter.peakMemory - startMemory,
    open: (openEnd - openStart) * 1000,
    updates: updates,
    seconds: seconds,
    problems: problems
  )
  print(
    String(
      format: "%@ %@ %ld: %ld missed frames, CPU %.0f%%, memory %+.0f MB, open %.0f ms",
      library,
      kind,
      run,
      result.missedFrames,
      result.cpu * 100,
      result.memory,
      result.open
    )
  )
  for problem in problems {
    print("  Problem: \(problem)")
  }
  save(result, to: runsDirectory.appendingPathComponent("\(name).json"))
}

// MARK: - Summary

struct Row: Encodable {
  var library: String
  var kind: String
  // Medians of the runs.
  var missedFrames: Double
  var cpu: Double
  var mainThread: Double
  var memory: Double
  var open: Double
  var runs: [Run]
}

struct Machine: Encodable {
  var chip: String
  var memoryGB: UInt64
  var macOS: String
  var displayHz: Int
  var power: String
}

struct Summary: Encodable {
  var date: String
  var sumi: String
  var machine: Machine
  var results: [Row]
}

@MainActor
func summarize(commit: String, libraries: [String]) {
  let files = try? FileManager.default.contentsOfDirectory(
    at: runsDirectory,
    includingPropertiesForKeys: nil
  )
  let runs = (files ?? [])
    .filter { $0.pathExtension == "json" }
    .compactMap { try? JSONDecoder().decode(Run.self, from: Data(contentsOf: $0)) }
    .sorted { $0.run < $1.run }

  var rows: [Row] = []
  for kind in kinds {
    let kindRows = libraries.compactMap { library -> Row? in
      let group = runs.filter { $0.library == library && $0.kind == kind }
      guard !group.isEmpty else { return nil }

      return Row(
        library: library,
        kind: kind,
        missedFrames: median(group.map { Double($0.missedFrames) }),
        cpu: median(group.map(\.cpu)),
        mainThread: median(group.map(\.mainThread)),
        memory: median(group.map(\.memory)),
        open: median(group.map(\.open)),
        runs: group
      )
    }
    guard !kindRows.isEmpty else { continue }

    print("")
    print(
      kind.padding(toLength: 24, withPad: " ", startingAt: 0)
        + column("Missed frames", 15)
        + column("CPU", 8)
        + column("Memory", 10)
        + column("Open", 10)
    )
    for row in kindRows {
      print(
        row.library.padding(toLength: 24, withPad: " ", startingAt: 0)
          + column(String(format: "%.0f", row.missedFrames), 15)
          + column(String(format: "%.0f%%", row.cpu * 100), 8)
          + column(String(format: "%+.0f MB", row.memory), 10)
          + column(String(format: "%.0f ms", row.open), 10)
      )
      for run in row.runs {
        for problem in run.problems {
          print("  Run \(run.run): \(problem)")
        }
      }
    }
    rows += kindRows
  }

  let now = Date()
  let summary = Summary(
    date: now.ISO8601Format(),
    sumi: commit,
    machine: Machine(
      chip: sysctlString("machdep.cpu.brand_string"),
      memoryGB: ProcessInfo.processInfo.physicalMemory / 1_073_741_824,
      macOS: ProcessInfo.processInfo.operatingSystemVersionString,
      displayHz: NSScreen.main?.maximumFramesPerSecond ?? 0,
      power: IOPSGetProvidingPowerSourceType(nil).takeUnretainedValue() as String
    ),
    results: rows
  )

  let formatter = DateFormatter()
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.dateFormat = "yyyy-MM-dd-HHmm"
  let url = resultsDirectory.appendingPathComponent("\(formatter.string(from: now)).json")
  save(summary, to: url)
  print("\nSaved \(url.path)")
}

func median(_ values: [Double]) -> Double {
  let sorted = values.sorted()
  let middle = sorted.count / 2
  if sorted.count % 2 == 1 { return sorted[middle] }
  return (sorted[middle - 1] + sorted[middle]) / 2
}

func column(_ text: String, _ width: Int) -> String {
  String(repeating: " ", count: max(0, width - text.count)) + text
}

func sysctlString(_ name: String) -> String {
  var size = 0
  sysctlbyname(name, nil, &size, nil, 0)
  var bytes = [CChar](repeating: 0, count: size)
  sysctlbyname(name, &bytes, &size, nil, 0)
  return bytes.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
}

func save(_ value: some Encodable, to url: URL) {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  try? encoder.encode(value).write(to: url)
}

// MARK: - Preview

struct PreviewView: View {
  @ObservedObject var model: StreamModel
  @State private var position = ScrollPosition(edge: .top)

  var body: some View {
    ScrollView {
      libraryView("Sumi", model: model)
        .font(.system(size: 14))
        .padding(28)
    }
    .scrollPosition($position)
    .scrollIndicators(.hidden)
    // Follows the end of the answer once it's taller than the window, like a chat app.
    .onChange(of: model.text) {
      position.scrollTo(edge: .bottom)
    }
  }
}

/// Streams a short answer into a light and a dark window, side by side, at about the
/// speed of a model. Both windows show the same stream.
@MainActor
func preview() -> Never {
  let model = StreamModel()
  // Wide enough for the longest code line, which doesn't wrap.
  let size = CGSize(width: 680, height: 640)
  let gap = 24.0
  let screen = NSScreen.main?.visibleFrame ?? .zero

  var windows: [NSWindow] = []
  for (index, appearance) in [NSAppearance.Name.aqua, .darkAqua].enumerated() {
    let window = NSWindow(
      contentRect: NSRect(
        x: screen.midX - size.width - gap / 2 + Double(index) * (size.width + gap),
        y: screen.midY - size.height / 2,
        width: size.width,
        height: size.height
      ),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden

    // Only one window can be active, so its buttons would look different.
    for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
      window.standardWindowButton(button)?.isHidden = true
    }
    window.appearance = NSAppearance(named: appearance)
    window.backgroundColor = .textBackgroundColor
    window.level = .floating
    window.contentView = NSHostingView(rootView: PreviewView(model: model))
    window.orderFrontRegardless()
    windows.append(window)
  }

  print("The answer starts in 3 seconds. Start the recording now.")
  runApp(for: 3)

  // 24 characters every 50 ms, about 500 a second.
  let prefixes = streamPrefixes(of: mixedSection + proseSection, length: 24)
  var shown = 0
  let timer = Timer(timeInterval: interval, repeats: true) { timer in
    MainActor.assumeIsolated {
      model.show(prefixes[shown])
      shown += 1
      if shown == prefixes.count {
        timer.invalidate()
        print("Done. Press Control-C to quit.")
      }
    }
  }
  RunLoop.main.add(timer, forMode: .common)
  NSApp.run()
  exit(0)
}

// MARK: - Main

MainActor.assumeIsolated {
  _ = NSApplication.shared
  NSApp.setActivationPolicy(.accessory)
  NSApp.finishLaunching()

  if arguments.first == "summary" {
    summarize(commit: arguments[1], libraries: Array(arguments.dropFirst(2)))
    exit(0)
  }

  if arguments.first == "preview" {
    preview()
  }

  // Keeps macOS from slowing down a background app, and keeps the display awake.
  let activity = ProcessInfo.processInfo.beginActivity(
    options: [.userInitiated, .idleDisplaySleepDisabled],
    reason: "Benchmark"
  )
  measure(library: arguments[0], kind: arguments[1], run: Int(arguments[2])!)
  ProcessInfo.processInfo.endActivity(activity)
  exit(0)
}
