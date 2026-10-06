import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, dark, light
    var id: String { rawValue }
    var title: String {
        switch self { case .system: return "跟随系统"; case .dark: return "深色"; case .light: return "浅色" }
    }
    var colorScheme: ColorScheme? {
        switch self { case .system: return nil; case .dark: return .dark; case .light: return .light }
    }
    static var preferences: UserDefaults {
        #if DEBUG
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--test-library"), arguments.count > index + 1,
           let id = UUID(uuidString: arguments[index + 1]), let defaults = UserDefaults(suiteName: "VimemoUITests.\(id.uuidString)") { return defaults }
        #endif
        return .standard
    }
}

enum StudioTheme {
    static func adaptive(dark: UInt32, light: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }
    static let background = adaptive(dark: 0x0C1421, light: 0xF2F5F9)
    static let surface = adaptive(dark: 0x172334, light: 0xFFFFFF)
    static let raised = adaptive(dark: 0x223247, light: 0xE4EBF3)
    static let accent = adaptive(dark: 0x91DDF0, light: 0x226781)
    static let onAccent = adaptive(dark: 0x0C1421, light: 0xFFFFFF)
    static let ink = adaptive(dark: 0xF0F4FA, light: 0x24344A)
    static let secondary = adaptive(dark: 0x93A6BD, light: 0x61748D)
    static let peach = adaptive(dark: 0xF4BC9A, light: 0xA4522A)
    static let line = adaptive(dark: 0x31445B, light: 0xD9E2EC)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
    }
}

struct StudioCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(18).background(StudioTheme.surface, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(StudioTheme.line.opacity(0.35), lineWidth: 1))
    }
}

struct SectionLabel: View {
    var title: String
    var detail: String = ""
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(.headline, design: .rounded))
            Spacer()
            if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(StudioTheme.secondary) }
        }
    }
}

struct PillButton: View {
    var title: String
    var selected = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 16).frame(minHeight: 44)
                .foregroundStyle(selected ? StudioTheme.onAccent : StudioTheme.ink)
                .background(selected ? StudioTheme.accent : StudioTheme.raised, in: Capsule())
        }.buttonStyle(.plain).accessibilityValue(selected ? "已选择" : "未选择")
    }
}

struct PrimaryButton: View {
    var title: String
    var symbol: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity).frame(minHeight: 54)
                .foregroundStyle(StudioTheme.onAccent)
                .background(StudioTheme.accent, in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain)
    }
}
