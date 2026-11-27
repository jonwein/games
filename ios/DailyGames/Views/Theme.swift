import SwiftUI
import UIKit

/// The web version's palette, light and dark. The accent is the AccentColor asset.
extension Color {
    static let page = Color(light: 0xF6F3EE, dark: 0x16151A)
    static let surface = Color(light: 0xFFFFFF, dark: 0x222128)
    static let ink = Color(light: 0x1D1B20, dark: 0xF2EFF5)
    static let muted = Color(light: 0x6F6A72, dark: 0xA19CA8)
    static let line = Color(light: 0xE6E1D9, dark: 0x34323B)
    static let accentInk = Color(light: 0xFFFFFF, dark: 0x1A1208)
    static let done = Color(light: 0x2B8A3E, dark: 0x69DB7C)
    static let danger = Color(light: 0xE03131, dark: 0xFF6B6B)

    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor(light: light, dark: dark))
    }
}

extension UIColor {
    nonisolated convenience init(light: UInt32, dark: UInt32) {
        self.init { traits in UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light) }
    }

    nonisolated convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// The big buttons along the bottom.
struct BarButtonStyle: ButtonStyle {
    var prominent: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(prominent ? Color.accentInk : Color.ink)
            .background(prominent ? Color.accentColor : Color.surface, in: .rect(cornerRadius: 14, style: .continuous))
            .overlay {
                if !prominent { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.line) }
            }
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// The circle at the start of each row, ticked once the game's result is in.
struct CheckCircle: View {
    var done: Bool

    var body: some View {
        ZStack {
            Circle().fill(done ? Color.done : .clear)
            Circle().strokeBorder(done ? Color.done : Color.line, lineWidth: 2)
            if done {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Color.surface)
            }
        }
        .frame(width: 26, height: 26)
        .animation(.snappy, value: done)
    }
}
