# Sumi

Sumi is small and fast library to render markdown for swift. It should work fast for streaming text content, e.g. LLMs streaming its response.

The default output style is inspired by and looks close to the Codex app.

Currently it supports only macOS, with AppKit and TextKit 1.

## Rules

- Changes must not slow down streaming. Run Benchmarks/run.sh before and after any change to parsing, converting, or the text view, and compare the results.
- Every update of a stream must look exactly like a fresh view of the same text. The streaming test checks this.
- Avoid adding new dependencies without a strong reason.
- Tests check only what user sees. Avoid adding slop unit tests.

## Code style

- Keep tab indentation is 2 spaces. Keep single lines at 90 characters or less.
- When a call or declaration wraps, one argument per line and `) -> Type {`.
- Keep blank lines between the logical steps.
- Short, casual comments that explain why, not what.
- Run `swift-format` with the repo config before you commit.

## Commands

- `swift test` runs the tests.
- `SNAPSHOT=<file> swift test --filter snapshot` writes a picture of a Markdown file.
- `Benchmarks/run.sh` compares Sumi with other libraries in real time.
