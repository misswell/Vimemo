import SwiftUI

enum StudioTheme {
    static let background = Color(hex: 0xEDF2F3)
    static let surface = Color.white
    static let raised = Color(hex: 0xDFEAEC)
    static let accent = Color(hex: 0x086C70)
    static let ink = Color(hex: 0x183B43)
    static let secondary = Color(hex: 0x5B727A)
    static let peach = Color(hex: 0xB1523F)
    static let line = Color(hex: 0xCCDADD)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
    }
}

struct StudioCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(18).background(StudioTheme.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(StudioTheme.line.opacity(0.65), lineWidth: 1))
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
                .foregroundStyle(selected ? .white : StudioTheme.ink)
                .background(selected ? StudioTheme.accent : StudioTheme.raised, in: RoundedRectangle(cornerRadius: 10))
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
                .frame(maxWidth: .infinity).frame(minHeight: 52)
                .foregroundStyle(.white)
                .background(StudioTheme.accent, in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain)
    }
}
