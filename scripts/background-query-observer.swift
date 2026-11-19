// Read-only installed-app E2E observer. Never records window titles or chat contents.
import AppKit
import CoreGraphics
import Foundation

let arguments = CommandLine.arguments
let output = URL(fileURLWithPath: arguments[1])
let duration = Double(arguments[2]) ?? 15
RunLoop.current.run(until: Date().addingTimeInterval(1.0))
let baseline = NSWorkspace.shared.frontmostApplication?.processIdentifier
let start = Date()
var samples = 0
var observed = false
var maximumProcesses = 0
var visibleMaximum = 0
var foregroundUnchanged = true
var becameFrontmost = false
var frontmostPIDs = Set<pid_t>()
try Data().write(to: output.appendingPathExtension("ready"))
while Date().timeIntervalSince(start) < duration {
  let apps = NSWorkspace.shared.runningApplications.filter {
    $0.bundleIdentifier == "me.greenbubbles.GreenBubbles"
  }
  let pids = Set(apps.map(\.processIdentifier))
  observed = observed || !apps.isEmpty
  maximumProcesses = max(maximumProcesses, apps.count)
  let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
  if let front { frontmostPIDs.insert(front) }
  foregroundUnchanged = foregroundUnchanged && front == baseline
  becameFrontmost = becameFrontmost || (front != baseline && front.map { pids.contains($0) } == true)
  let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)
    as? [[String: Any]] ?? []
  let visible = windows.filter { item in
    guard let pid = item[kCGWindowOwnerPID as String] as? Int32, pids.contains(pid),
      let layer = item[kCGWindowLayer as String] as? Int, layer == 0,
      let bounds = item[kCGWindowBounds as String] as? [String: Double]
    else { return false }
    return (bounds["Width"] ?? 0) > 100 && (bounds["Height"] ?? 0) > 100
  }.count
  visibleMaximum = max(visibleMaximum, visible)
  samples += 1
  RunLoop.current.run(until: Date().addingTimeInterval(0.04))
}
let result: [String: Any] = [
  "samples": samples, "applicationObserved": observed,
  "maximumApplicationProcesses": maximumProcesses,
  "maximumVisibleWindows": visibleMaximum, "foregroundUnchanged": foregroundUnchanged,
  "applicationBecameFrontmost": becameFrontmost,
  "baselineKnown": baseline != nil, "distinctForegroundProcesses": frontmostPIDs.count,
  "passed": observed && maximumProcesses == 1 && visibleMaximum == 0 && foregroundUnchanged && !becameFrontmost,
]
try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
  .write(to: output)
