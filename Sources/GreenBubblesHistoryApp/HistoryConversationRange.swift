import Foundation

enum HistoryConversationRange: String, CaseIterable, Identifiable {
  case week
  case month
  case threeMonths
  case year
  case all

  static let defaultsKey = "history.conversationRange.v1"
  var id: String { rawValue }

  var title: String {
    switch self {
    case .week: "1 周"
    case .month: "1 个月"
    case .threeMonths: "3 个月"
    case .year: "1 年"
    case .all: "所有"
    }
  }

  func cutoff(relativeTo now: Date, calendar: Calendar = .current) -> Date? {
    switch self {
    case .week: calendar.date(byAdding: .day, value: -7, to: now)
    case .month: calendar.date(byAdding: .month, value: -1, to: now)
    case .threeMonths: calendar.date(byAdding: .month, value: -3, to: now)
    case .year: calendar.date(byAdding: .year, value: -1, to: now)
    case .all: nil
    }
  }

  func includes(_ date: Date?, relativeTo now: Date) -> Bool {
    guard let cutoff = cutoff(relativeTo: now) else { return true }
    guard let date else { return false }
    return date >= cutoff
  }
}
