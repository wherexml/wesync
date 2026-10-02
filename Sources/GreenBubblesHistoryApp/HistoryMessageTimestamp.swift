import SwiftUI

/// Uses the preceding message, not the preceding visible timestamp.
enum HistoryMessageTime {
  static var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .autoupdatingCurrent
    calendar.firstWeekday = 2
    calendar.minimumDaysInFirstWeek = 4
    return calendar
  }

  static func showsSeparator(for date: Date?, after previous: Date?, calendar: Calendar = calendar)
    -> Bool
  {
    guard let date else { return false }
    guard let previous else { return true }
    return !calendar.isDate(date, inSameDayAs: previous)
      || date.timeIntervalSince(previous) >= 15 * 60
  }

  static func label(for date: Date, now: Date, calendar: Calendar = calendar) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    let today = calendar.startOfDay(for: now)
    let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
    if calendar.isDate(date, inSameDayAs: today) {
      formatter.dateFormat = "HH:mm"
    } else if calendar.isDate(date, inSameDayAs: yesterday) {
      formatter.dateFormat = "'昨天' HH:mm"
    } else if date < today, calendar.dateInterval(of: .weekOfYear, for: now)?.contains(date) == true
    {
      formatter.dateFormat = "EEEE HH:mm"
    } else if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
      formatter.dateFormat = "M 月 d 日 HH:mm"
    } else {
      formatter.dateFormat = "yyyy 年 M 月 d 日 HH:mm"
    }
    return formatter.string(from: date)
  }
}

struct HistoryMessageTimestamp: View {
  let date: Date

  var body: some View {
    TimelineView(.everyMinute) { context in
      Text(HistoryMessageTime.label(for: date, now: context.date))
        .font(.system(size: 12).monospacedDigit())
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 10)
        .accessibilityIdentifier("message-time-separator")
    }
  }
}
