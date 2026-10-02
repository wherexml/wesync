// Run via scripts/verify-message-timestamps.sh. Synthetic native rendering only.
import AppKit
import SwiftUI

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
var calendar = HistoryMessageTime.calendar
calendar.timeZone = TimeZone(identifier: "Asia/Singapore")!
func date(_ text: String) -> Date {
  let f = DateFormatter()
  f.locale = Locale(identifier: "en_US_POSIX")
  f.timeZone = calendar.timeZone
  f.dateFormat = "yyyy-MM-dd HH:mm:ss"
  return f.date(from: text)!
}
let now = date("2026-10-02 18:00:00")
let moments = ["2026-08-20 18:13:00", "2026-09-30 18:22:00", "2026-10-01 22:56:00",
  "2026-10-02 10:00:00", "2026-10-02 10:14:59", "2026-10-02 10:29:59", "2026-10-02 10:29:59"]
let dates = moments.map(date)
let labels = dates.indices.compactMap { i -> String? in
  HistoryMessageTime.showsSeparator(for: dates[i], after: i == 0 ? nil : dates[i - 1], calendar: calendar)
    ? HistoryMessageTime.label(for: dates[i], now: now, calendar: calendar) : nil
}
let expected = ["8 月 20 日 18:13", "星期三 18:22", "昨天 22:56", "10:00", "10:29"]
let checks = [
  "chronological-timeline-labels": labels == expected,
  "midnight-boundary": HistoryMessageTime.showsSeparator(for: date("2026-10-02 00:01:00"), after: date("2026-10-01 23:59:00"), calendar: calendar),
  "missing-date": !HistoryMessageTime.showsSeparator(for: nil, after: nil, calendar: calendar),
  "year-visible": HistoryMessageTime.label(for: date("2025-08-20 18:13:00"), now: now, calendar: calendar) == "2025 年 8 月 20 日 18:13",
  "last-week-sunday": HistoryMessageTime.label(for: date("2026-09-27 18:13:00"), now: now, calendar: calendar) == "9 月 27 日 18:13",
  "monday-yesterday-priority": HistoryMessageTime.label(for: date("2026-09-27 18:13:00"), now: date("2026-09-28 18:00:00"), calendar: calendar) == "昨天 18:13",
]
let view = VStack(spacing: 10) {
  ForEach(dates.indices, id: \.self) { i in
    if HistoryMessageTime.showsSeparator(for: dates[i], after: i == 0 ? nil : dates[i - 1], calendar: calendar) {
      HistoryMessageTimestamp(date: dates[i])
    }
    HStack {
      if i % 2 == 1 { Spacer() }
      Text("合成消息 \(i + 1)").padding(11).background(i % 2 == 1 ? Color.green.opacity(0.2) : Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
      if i % 2 == 0 { Spacer() }
    }
  }
}.padding(20).frame(width: 700).background(Color(nsColor: .textBackgroundColor))
let app = NSApplication.shared
let host = NSHostingView(rootView: view)
host.frame = NSRect(origin: .zero, size: host.fittingSize)
let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
window.contentView = host
window.orderFrontRegardless()
RunLoop.main.run(until: Date().addingTimeInterval(0.5))
host.layoutSubtreeIfNeeded()
let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
host.cacheDisplay(in: host.bounds, to: bitmap)
try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("synthetic-timeline.png"))
let report: [String: Any] = ["checks": checks, "passed": checks.values.allSatisfy { $0 }, "labels": labels,
  "source": "synthetic-only", "scope": "production separator native rendering; installed acceptance recorded separately"]
try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("rendering.json"))
exit(checks.values.allSatisfy { $0 } ? 0 : 1)
