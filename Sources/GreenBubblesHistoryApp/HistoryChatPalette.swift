import AppKit
import SwiftUI

/// Shared opaque chat surfaces. Dynamic colors follow the window's native appearance.
enum HistoryChatPalette {
  static let sidebar = adaptive(light: 0xF5F5F5, dark: 0x242424)
  static let timeline = adaptive(light: 0xEDEDED, dark: 0x191919)
  static let incoming = adaptive(light: 0xFFFFFF, dark: 0x2C2C2C)
  static let outgoing = adaptive(light: 0xD4F0C4, dark: 0x38B375)
  static let outgoingText = Color(red: 16 / 255, green: 32 / 255, blue: 24 / 255)

  private static func adaptive(light: UInt32, dark: UInt32) -> Color {
    Color(
      nsColor: NSColor(name: nil) { appearance in
        let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        return NSColor(
          srgbRed: Double((value >> 16) & 255) / 255,
          green: Double((value >> 8) & 255) / 255,
          blue: Double(value & 255) / 255, alpha: 1)
      })
  }
}
