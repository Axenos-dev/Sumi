# Benchmarks

For benchmarks, we are going to stream a synthetic answer to different markdown renderers, imitating an agent streaming its response.

## Measures

- **Missed frames** - how many frames a 60 Hz screen couldn't show on time, due to the main thread being busy. The answer takes about 14 seconds, so about 800 frames. A stall of 20 ms misses 1 frame, and a freeze of half a second misses 30. Scrolling and typing stutter at each missed frame.
- **CPU** - the CPU time of all used threads while the answer arrives, as a share of one core.
- **Memory** - the most memory that the view added while the answer arrived.
- **Open** - the time to show the whole answer at once in a brand new view, e.g. opening an old thread.

## Setup

- Each answer is about 32 KB long, in four kinds: `mixed`, `prose`, `code`, and `table`.
- The answer arrives in real time - 120 bytes every 50 ms, so 20 updates a second. Fairly, this is faster than a real model, but it keeps runs shorter.
- The view is 720 points wide, in an 800 point window on screen and above other windows.
- Each library uses its default look.
- The libraries are: [Sumi](https://github.com/Axenos-dev/Sumi), Microsoft's [SwiftStreamingMarkdown](https://github.com/microsoft/SwiftStreamingMarkdown), [MarkdownUI](https://github.com/gonzalezreal/swift-markdown-ui), [Textual](https://github.com/gonzalezreal/textual), and a plain `NSTextView` that only appends text. The plain text view we interpret as a baseline.
- Each library runs five times for each kind, and the summary takes the median.
- The summary marks a run when the window was hidden, the view did not follow the end of the answer, Low Power Mode was on, or the Mac was hot.

## Running

To keep the benchmark fair, we quit other apps and leave the Mac alone while it runs.

```
./run.sh                  all libraries
./run.sh Sumi MarkdownUI  only specified
```

Each run saves `results/runs/<library>-<kind>-<run>.json` and a picture of the end of the answer. At the end, `run.sh` saves a summary to `results/<date>.json`, with the medians, every run, the machine, and the Sumi commit. The commit also gives the version of each library, in the `Package.resolved` files. Git ignores `results`, because the numbers depend on the machine.

A run of all libraries also draws the README charts to `charts/`, with `charts.swift`, and prints all results as a Markdown table for the README. To draw them from an older summary, run `swift charts.swift results/<date>.json`.

Note: SwiftStreamingMarkdown pins an older [swift-markdown](https://github.com/swiftlang/swift-markdown) than Sumi, so it builds in a package of its own, `StreamingMarkdown`.
