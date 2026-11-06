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
  static let title = Font.system(size: 18, weight: .semibold)
  static let hover = adaptive(light: 0xEBEDEB, dark: 0x303330)
  static let group = adaptive(light: 0xF5F5F5, dark: 0x242424)
  static let groupLine = adaptive(light: 0xDEDEDE, dark: 0x3A3A3A)

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

/// Shared desktop toolbar geometry. Native Button keeps keyboard activation/focus.
struct HistoryIconButtonStyle: ButtonStyle {
  var selected = false
  @Environment(\.isEnabled) private var isEnabled
  @State private var hovered = false

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 15, weight: .regular))
      .frame(width: 32, height: 32)
      .foregroundStyle(selected ? HistoryDesign.accent : hovered ? Color.primary : Color.secondary)
      .background(
        selected
          ? HistoryDesign.selection
          : hovered || configuration.isPressed
            ? HistoryDesign.hover : Color.clear,
        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
      )
      .contentShape(RoundedRectangle(cornerRadius: 8))
      .opacity(isEnabled ? (configuration.isPressed ? 0.65 : 1) : 0.4)
      .onHover { hovered = $0 }
  }
}

struct HistoryConversationRowStyle: ButtonStyle {
  let selected: Bool
  @State private var hovered = false

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .padding(.horizontal, 10)
      .padding(.vertical, 9)
      .background(
        selected
          ? HistoryDesign.selection
          : hovered || configuration.isPressed
            ? HistoryDesign.hover : Color.clear,
        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
      )
      .contentShape(RoundedRectangle(cornerRadius: 10))
      .opacity(configuration.isPressed ? 0.75 : 1)
      .onHover { hovered = $0 }
  }
}

struct HistorySettingsGroup<Content: View>: View {
  var title: String? = nil
  @ViewBuilder var content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let title {
        Text(title).font(.system(size: 12, weight: .semibold))
          .foregroundStyle(.secondary).padding(.leading, 4)
      }
      VStack(alignment: .leading, spacing: 12) { content }
        .font(.system(size: 13))
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HistoryDesign.group, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
          RoundedRectangle(cornerRadius: 14)
            .strokeBorder(HistoryDesign.groupLine, lineWidth: 0.5)
        }
    }
  }
}

struct HistoryHelpButton: View {
  let title: String
  let text: String
  @Binding var presented: Bool

  var body: some View {
    Button {
      presented.toggle()
    } label: {
      Image(systemName: "questionmark.circle")
    }
    .buttonStyle(HistoryIconButtonStyle())
    .help(title)
    .accessibilityLabel(title)
    .popover(isPresented: $presented) {
      Text(text).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
        .padding(16).frame(width: 280, alignment: .leading)
        .onExitCommand { presented = false }
    }
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
