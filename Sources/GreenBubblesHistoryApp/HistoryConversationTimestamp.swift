import SwiftUI

/// Shared by live and imported conversation lists. Refreshes as the local day changes.
struct HistoryConversationTimestamp: View {
  let date: Date

  var body: some View {
    TimelineView(.everyMinute) { context in
      Text(label(for: date, now: context.date))
        .fixedSize(horizontal: true, vertical: false)
    }
  }

  private func label(for date: Date, now: Date) -> String {
    let calendar = Calendar.autoupdatingCurrent
    let today = calendar.startOfDay(for: now)
    let yesterday = calendar.date(byAdding: .day, value: -1, to: today)
    let isToday = calendar.isDate(date, inSameDayAs: today)
    let isYesterday = yesterday.map { calendar.isDate(date, inSameDayAs: $0) } ?? false
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = isToday || isYesterday ? "HH:mm" : "MM/dd"
    return (isYesterday ? "昨天 " : "") + formatter.string(from: date)
  }
}
