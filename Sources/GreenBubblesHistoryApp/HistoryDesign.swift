import AppKit
import SwiftUI

/// Desktop interpretation of ChunUI's monochrome hierarchy and single brand accent.
/// Original implementation: no UIKit dependency or global replacement of native controls.
enum HistoryDesign {
  static let accent = adaptive(light: 0x237A52, dark: 0x74D6A0)
  static let canvas = adaptive(light: 0xF5F6F5, dark: 0x191C1A)
  static let card = adaptive(light: 0xFFFFFF, dark: 0x2C312D)
  static let selection = adaptive(light: 0xE5EFE8, dark: 0x2C4435)
  static let border = adaptive(light: 0xDDE3DE, dark: 0x414A43)
  static let radius: CGFloat = 12

  private static func adaptive(light: UInt32, dark: UInt32) -> Color {
    func color(_ value: UInt32) -> NSColor {
      NSColor(
        srgbRed: CGFloat((value >> 16) & 255) / 255,
        green: CGFloat((value >> 8) & 255) / 255,
        blue: CGFloat(value & 255) / 255, alpha: 1)
    }
    let day = color(light)
    let night = color(dark)
    return Color(
      nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? night : day
      })
  }
}

/// Explicitly applied to action buttons; menus, search and list selection stay native.
struct HistoryActionStyle: ButtonStyle {
  var prominent = false
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.colorScheme) private var colorScheme

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 13, weight: .semibold))
      .padding(.horizontal, 14)
      .padding(.vertical, 8)
      .foregroundStyle(
        prominent ? (colorScheme == .dark ? Color.black : .white) : Color.primary
      )
      .background(
        prominent ? HistoryDesign.accent : HistoryDesign.card,
        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
          .strokeBorder(prominent ? Color.white.opacity(0.15) : HistoryDesign.border, lineWidth: 1)
      }
      .shadow(color: .black.opacity(configuration.isPressed ? 0 : 0.06), radius: 2, y: 1)
      .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
  }
}
