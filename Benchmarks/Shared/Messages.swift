// MARK: - Messages

let mixedSection = """
  ## The volume switch

  The branch is close. **One problem blocks the push:** `Switch` unmounts the old volume \
  before the new mount is ready. If the mount fails, the server has no volume. The \
  problem is in [@switch.go](file:///Users/demo/tarn/internal/volume/switch.go#L88), and \
  the test [@switch_test.go](file:///Users/demo/tarn/internal/volume/switch_test.go) did \
  not find it.

  I changed two things:

  1. Move `unmount(old)` after `waitHealthy(new)`, so a failed mount keeps the old \
  volume in place.
  2. Add a health check to the test fixture. The test now fails on the old code and \
  passes on the fix.

  - File: `internal/volume/delete.go`, line 42
  - Fix: delete the branch first, then remove the directory.

  ```go
  func (s *Switcher) Switch(ctx context.Context, old, new Volume) error {
  \tif err := s.mount(ctx, new); err != nil {
  \t\treturn fmt.Errorf("mount %s: %w", new.ID, err)
  \t}
  \tif err := s.waitHealthy(ctx, new); err != nil {
  \t\treturn err
  \t}
  \treturn s.unmount(ctx, old)
  }
  ```

  | Area | Result |
  | --- | --- |
  | Creation | No problems |
  | Deletion | Branch stays after a failed delete |
  | Console | Cancelled switch leaves the server stopped |

  > The old volume stays mounted until the new one passes its health check.

  The switch takes about $t = 2 \\cdot n$ seconds for $n$ volumes.

  """

let proseSection = """
  ## Why the switch failed

  The switch failed because the server unmounted the old volume **before** the new \
  volume was ready. When the mount of the new volume took longer than usual, the server \
  had no volume for about *two seconds*, and the game process stopped. The logs in \
  `server.log` show the order of the steps, and the [incident \
  note](https://example.com/incidents/42) has the full timeline.

  The fix changes the order. The server now mounts the new volume, waits until the \
  health check passes, and only then unmounts the old one. If the mount fails, the old \
  volume stays in place, and the player sees no change.

  Three things still need work:

  - The health check uses a fixed timeout of `30s`, which is too long for small volumes.
  - The console shows **Stopped** for a cancelled switch, although the server still runs.
  - The test fixture does not cover a slow mount, so a regression could pass the tests.

  1. First, make the timeout depend on the size of the volume.
  2. Then, show the real state of the server in the console.
  3. Last, add a slow mount to the fixture.

  """

let codeSection: String = {
  var lines = [
    "## Step \\(index)",
    "",
    "The next part of the switch checks each volume and stops at the first error:",
    "",
    "```go",
    "func (s *Switcher) CheckAll(ctx context.Context, volumes []Volume) error {",
  ]
  for step in 0..<28 {
    let volume = "volumes[\(step % 7)]"
    lines.append("\tif err := s.check\(step)(ctx, \(volume)); err != nil {")
    lines.append("\t\treturn fmt.Errorf(\"check \(step) of %s: %w\", \(volume).ID, err)")
  }
  lines.append("\treturn nil")
  lines.append("}")
  lines.append("```")
  lines.append("")
  return lines.joined(separator: "\n") + "\n"
}()

let tableSection: String = {
  var lines = [
    "## Volumes", "", "Every volume and the result of its last check:", "",
    "| Volume | Server | Size | Result |", "| --- | --- | ---: | --- |",
  ]
  for row in 0..<150 {
    let result = row % 9 == 0 ? "**Failed** health check" : "Healthy"
    let size = "\(4 + row % 60) GB"
    lines.append("| vol-\(1000 + row) | server-\(row % 12) | \(size) | \(result) |")
  }
  lines.append("")
  return lines.joined(separator: "\n") + "\n"
}()

func message(kind: String) -> String {
  let section: String
  switch kind {
  case "mixed": section = mixedSection
  case "prose": section = proseSection
  case "code": section = codeSection
  case "table": section = tableSection
  default: fatalError("Unknown kind \(kind)")
  }
  var text = ""
  var index = 1
  while text.utf8.count < targetBytes {
    text += section.replacingOccurrences(of: "\\(index)", with: "\(index)")
    index += 1
  }
  return text
}
