import SwiftUI

// Adapted from Pajamas UI color ramps; the lavender canvas follows GitLab's
// navigation chrome. Semantic colors keep content readable in both appearances.
enum PajamasTheme {
    static func uiColor(_ light: UInt32, _ dark: UInt32) -> UIColor {
        UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 255) / 255,
                           green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        }
    }
    static let canvas = Color(uiColor(0xefeaf3, 0x18171d))
    static let surface = Color(uiColor(0xffffff, 0x28272d))
    static let inset = Color(uiColor(0xf4f0fc, 0x3a383d))
    static let border = Color(uiColor(0xdcdbd9, 0x4d4b4e))
    static let text = Color(uiColor(0x18171d, 0xecebea))
    static let secondary = Color(uiColor(0x646163, 0xc1bfbe))
    static let accent = Color(uiColor(0x6a54c0, 0xc9beef))
    static let selected = Color(uiColor(0xe1daf7, 0x362676))
    static let primaryFill = Color(uiColor(0x6a54c0, 0x6a54c0))
    static let orange = Color(uiColor(0xfb8017, 0xfb8017))
    static let link = Color(uiColor(0x2566b5, 0x9dc8f2))
    static let success = Color(uiColor(0x0c7265, 0x84d4b6))
    static let danger = Color(uiColor(0xc52042, 0xffafb8))
}

struct PajamasPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.semibold))
            .foregroundStyle(enabled ? .white : PajamasTheme.secondary)
            .padding(.horizontal, 16).frame(minHeight: 44)
            .background(enabled ? PajamasTheme.primaryFill : PajamasTheme.inset,
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(enabled ? PajamasTheme.primaryFill : PajamasTheme.border, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
struct PajamasDefaultButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.medium)).foregroundStyle(PajamasTheme.text)
            .padding(.horizontal, 14).frame(minHeight: 44)
            .background(PajamasTheme.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(PajamasTheme.border, lineWidth: 1))
            .opacity(!enabled ? 0.5 : configuration.isPressed ? 0.7 : 1)
    }
}
struct PajamasTabs: View {
    @Binding var selection: String
    let options: [(title: String, value: String)]
    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.value) { option in
                Button { selection = option.value } label: {
                    Text(option.title).font(.subheadline.weight(selection == option.value ? .semibold : .regular))
                        .foregroundStyle(PajamasTheme.text)
                        .frame(maxWidth: .infinity).frame(minHeight: 44)
                        .background(selection == option.value ? PajamasTheme.selected : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 8))
                        .overlay(alignment: .bottom) {
                            if selection == option.value { Capsule().fill(PajamasTheme.accent).frame(height: 2).padding(.horizontal, 12) }
                        }
                }.buttonStyle(.plain)
                    .accessibilityAddTraits(selection == option.value ? .isSelected : [])
            }
        }
    }
}
