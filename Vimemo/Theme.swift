import SwiftUI

enum StudioTheme {
    static let background = Color(hex: 0x0C1421)
    static let surface = Color(hex: 0x172334)
    static let raised = Color(hex: 0x223247)
    static let accent = Color(hex: 0x91DDF0)
    static let secondary = Color(hex: 0x93A6BD)
    static let peach = Color(hex: 0xF4BC9A)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
    }
}

struct StudioCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(18).background(StudioTheme.surface, in: RoundedRectangle(cornerRadius: 22))
    }
}

struct SectionLabel: View {
    var title: String
    var detail: String = ""
    var body: some View {
        HStack {
            Text(title).font(.headline)
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
                .padding(.horizontal, 16).padding(.vertical, 11)
                .foregroundStyle(selected ? StudioTheme.background : .white)
                .background(selected ? StudioTheme.accent : StudioTheme.raised, in: Capsule())
        }.buttonStyle(.plain)
    }
}

struct PrimaryButton: View {
    var title: String
    var symbol: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.system(size: 16, weight: .bold))
                .frame(maxWidth: .infinity).padding(.vertical, 18)
                .foregroundStyle(StudioTheme.background)
                .background(StudioTheme.accent, in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain)
    }
}
