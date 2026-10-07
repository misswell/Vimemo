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
    static let background = Color(uiColor: .systemBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let raised = Color(uiColor: .tertiarySystemFill)
    static let accent = adaptive(dark: 0xFF375F, light: 0xFA233B)
    static let onAccent = Color.white
    static let ink = Color(uiColor: .label)
    static let secondary = Color(uiColor: .secondaryLabel)
    static let peach = accent
    static let line = Color(uiColor: .separator)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
    }
}

struct StudioCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(18).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct SectionLabel: View {
    var title: String
    var detail: String = ""
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
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
                .padding(.horizontal, 16).frame(minHeight: 44)
                .foregroundStyle(selected ? StudioTheme.accent : StudioTheme.ink)
                .contentShape(Capsule())
                .studioGlass(in: Capsule(), interactive: true, tint: selected ? StudioTheme.accent.opacity(0.18) : nil)
        }.buttonStyle(.plain).accessibilityValue(selected ? "已选择" : "未选择")
    }
}

struct PrimaryButton: View {
    var title: String
    var symbol: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.body.weight(.semibold))
                .frame(maxWidth: .infinity).frame(minHeight: 48)
        }.tint(StudioTheme.accent).modifier(StudioPrimaryButtonStyle())
    }
}

struct StudioGlassGroup<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: Content
    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else { content }
    }
}

private struct StudioGlassModifier<Surface: Shape>: ViewModifier {
    var shape: Surface
    var interactive: Bool
    var overImage: Bool
    var tint: Color?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(tint ?? (overImage ? Color.black : StudioTheme.raised), in: shape)
                .overlay(shape.stroke(StudioTheme.line.opacity(0.5), lineWidth: 1))
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(tint ?? (overImage ? .black.opacity(0.2) : nil)).interactive(interactive), in: shape)
                .environment(\.colorScheme, overImage ? .dark : colorScheme)
        } else {
            content.background(tint ?? .clear, in: shape)
                .background(.regularMaterial, in: shape)
                .overlay(shape.stroke(.white.opacity(colorScheme == .dark ? 0.12 : 0.5), lineWidth: 1))
                .environment(\.colorScheme, overImage ? .dark : colorScheme)
        }
    }
}

extension View {
    func studioGlass<Surface: Shape>(in shape: Surface, interactive: Bool = true, overImage: Bool = false, tint: Color? = nil) -> some View {
        modifier(StudioGlassModifier(shape: shape, interactive: interactive, overImage: overImage, tint: tint))
    }
}

private struct StudioGlassButtonModifier: ViewModifier {
    var circular: Bool
    var overImage: Bool
    var tint: Color?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    private var shape: AnyShape { circular ? AnyShape(Circle()) : AnyShape(Capsule()) }

    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency {
            content.buttonStyle(.plain).background(tint ?? (overImage ? Color.black : StudioTheme.raised), in: shape)
                .overlay(shape.stroke(StudioTheme.line.opacity(0.5), lineWidth: 1))
        } else if #available(iOS 26.0, *) {
            content.tint(tint).buttonStyle(.glass).buttonBorderShape(circular ? .circle : .capsule)
                .controlSize(.mini).environment(\.colorScheme, overImage ? .dark : colorScheme)
        } else {
            content.buttonStyle(.plain).background(tint ?? .clear, in: shape)
                .background(.regularMaterial, in: shape)
                .overlay(shape.stroke(.white.opacity(colorScheme == .dark ? 0.12 : 0.5), lineWidth: 1))
                .environment(\.colorScheme, overImage ? .dark : colorScheme)
        }
    }
}

extension View {
    func studioGlassButton(circular: Bool = false, overImage: Bool = false, tint: Color? = nil) -> some View {
        modifier(StudioGlassButtonModifier(circular: circular, overImage: overImage, tint: tint))
    }
}

private struct StudioPrimaryButtonStyle: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.buttonStyle(.glassProminent).buttonBorderShape(.capsule).controlSize(.large)
        } else {
            content.buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.large)
        }
    }
}

extension View {
    @ViewBuilder func studioTabBarBehavior() -> some View {
        if #available(iOS 26.0, *) {
            self.tabBarMinimizeBehavior(.onScrollDown)
        } else { self }
    }
}
