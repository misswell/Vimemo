import SwiftUI

private enum PurchaseTheme {
    static let buttonText = StudioTheme.adaptive(dark: 0x100F0D, light: 0xFFFFFF)
    static let background = StudioTheme.adaptive(dark: 0x100F0D, light: 0xF5F3EE)
    static let card = StudioTheme.adaptive(dark: 0x252320, light: 0xFFFFFF)
    static let gold = StudioTheme.adaptive(dark: 0xFFB84D, light: 0xA96800)
    static let orange = StudioTheme.adaptive(dark: 0xF47D27, light: 0xB95D16)
    static let text = StudioTheme.adaptive(dark: 0xF6F1E8, light: 0x302B24)
    static let secondary = StudioTheme.adaptive(dark: 0xAEA79E, light: 0x71695F)
}

struct UnlimitedPurchaseView: View {
    @EnvironmentObject private var purchases: PurchaseStore
    @Environment(\.dismiss) private var dismiss
    var onUnlocked: () -> Void = {}
    @State private var delivered = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    hero
                    VStack(spacing: 8) {
                        Text("让回忆，完整发生。")
                            .font(.system(.title, design: .rounded, weight: .bold))
                            .multilineTextAlignment(.center)
                        Text("解锁不限制时长，留下完整的那一刻。")
                            .font(.subheadline).foregroundStyle(PurchaseTheme.secondary)
                            .multilineTextAlignment(.center)
                    }
                    benefits
                    lifetimePlan
                    Text("3 秒内导出、静态照片、自选封面和全部编辑功能继续免费。")
                        .font(.caption).foregroundStyle(PurchaseTheme.secondary)
                        .multilineTextAlignment(.center).lineSpacing(3)
                    Text("长实况的播放与动态壁纸效果由 iOS 决定。")
                        .font(.caption2).foregroundStyle(PurchaseTheme.secondary.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: 520).frame(maxWidth: .infinity)
                .padding(.horizontal, 24).padding(.bottom, 22)
            }
            .scrollIndicators(.hidden)
            .background(PurchaseTheme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .topTrailing) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PurchaseTheme.secondary)
                        .frame(width: 36, height: 36)
                        .background(PurchaseTheme.text.opacity(0.07), in: Circle())
                }.disabled(purchases.busy).accessibilityLabel("关闭").padding(.trailing, 20).padding(.top, 8)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { purchaseFooter }
            .interactiveDismissDisabled(purchases.busy)
            .task { await purchases.prepare(); deliverUnlock() }
            .onChange(of: purchases.hasUnlimited) { _, _ in deliverUnlock() }
        }.foregroundStyle(PurchaseTheme.text)
    }

    private var hero: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack {
                ForEach(1...3, id: \.self) { index in
                    if let url = Bundle.main.url(forResource: "Paywall-\(index)", withExtension: "jpg"),
                       let image = UIImage(contentsOfFile: url.path) {
                        Image(uiImage: image).resizable().scaledToFill()
                            .frame(width: width * (index == 2 ? 0.39 : 0.33), height: index == 2 ? 130 : 114)
                            .clipped().clipShape(RoundedRectangle(cornerRadius: 17))
                            .overlay(RoundedRectangle(cornerRadius: 17).stroke(.white.opacity(0.12), lineWidth: 1))
                            .rotationEffect(.degrees(index == 1 ? -9 : index == 3 ? 9 : 0))
                            .offset(x: index == 1 ? -width * 0.32 : index == 3 ? width * 0.32 : 0, y: index == 2 ? -3 : 10)
                            .opacity(index == 2 ? 1 : 0.65)
                    }
                }
                LinearGradient(colors: [.clear, PurchaseTheme.background], startPoint: .top, endPoint: .bottom)
                    .frame(height: 85).frame(maxHeight: .infinity, alignment: .bottom)
                HStack(spacing: 8) {
                    Image(systemName: "livephoto").foregroundStyle(PurchaseTheme.gold)
                    Text("实刻").font(.system(.headline, design: .rounded, weight: .bold))
                }.padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.1), lineWidth: 1))
                    .frame(maxHeight: .infinity, alignment: .top).offset(y: -3)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.frame(height: 140).padding(.top, 8).accessibilityHidden(true)
    }

    private var benefits: some View {
        VStack(spacing: 16) {
            benefit("livephoto", title: "完整实况", detail: "把长片段留成实况照片")
            benefit("film.stack", title: "长视频与 GIF", detail: "整段导出，保留构图与调色")
            benefit("checkmark.seal", title: "一次购买，永久使用", detail: "无需订阅，同一账号可恢复")
        }.padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PurchaseTheme.card, in: RoundedRectangle(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).stroke(.white.opacity(0.1), lineWidth: 1))
    }

    private func benefit(_ symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: symbol).font(.system(size: 23, weight: .medium))
                .foregroundStyle(PurchaseTheme.gold)
                .frame(width: 44, height: 44)
                .background(PurchaseTheme.gold.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(PurchaseTheme.text)
                Text(detail).font(.caption).foregroundStyle(PurchaseTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true).lineSpacing(2)
            }
            Spacer(minLength: 0)
        }
    }

    private var lifetimePlan: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("永久解锁").font(.system(.title3, design: .rounded, weight: .bold))
                Spacer()
                Text("一次性购买").font(.caption.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .foregroundStyle(PurchaseTheme.buttonText)
                    .background(PurchaseTheme.gold, in: Capsule())
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let product = purchases.product {
                    Text(product.displayPrice).font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .accessibilityIdentifier("unlimitedPrice")
                    Text("/ 永久").font(.subheadline).foregroundStyle(PurchaseTheme.secondary)
                } else {
                    Text(purchases.loadingProduct ? "正在获取价格…" : "价格暂不可用")
                        .font(.headline).foregroundStyle(PurchaseTheme.secondary)
                }
                Spacer()
                Image(systemName: "checkmark.circle.fill").font(.system(size: 29))
                    .foregroundStyle(PurchaseTheme.gold).accessibilityHidden(true)
            }
            Text("一次解锁，适用于已有草稿与之后导入的视频。")
                .font(.caption).foregroundStyle(PurchaseTheme.secondary)
        }.padding(20).foregroundStyle(PurchaseTheme.text)
            .background(LinearGradient(colors: [PurchaseTheme.gold.opacity(0.2), PurchaseTheme.gold.opacity(0.07)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).stroke(PurchaseTheme.gold.opacity(0.8), lineWidth: 1.5))
            .accessibilityElement(children: .contain).accessibilityIdentifier("unlimitedLifetimePlan")
    }

    private var purchaseFooter: some View {
        VStack(spacing: 10) {
            if let message = purchases.message {
                Text(message).font(.caption).foregroundStyle(PurchaseTheme.gold)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("purchaseMessage")
            }
            Button {
                Task {
                    if purchases.product == nil { await purchases.loadProduct() }
                    else { await purchases.purchase() }
                }
            } label: {
                HStack(spacing: 10) {
                    if purchases.loadingProduct || purchases.busy { ProgressView().tint(PurchaseTheme.buttonText) }
                    Text(buttonTitle).font(.system(.headline, design: .rounded, weight: .bold))
                        .multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity).padding(.vertical, 20)
                    .foregroundStyle(PurchaseTheme.buttonText)
                    .background(LinearGradient(colors: [PurchaseTheme.gold, PurchaseTheme.orange], startPoint: .leading, endPoint: .trailing), in: Capsule())
                    .shadow(color: PurchaseTheme.orange.opacity(0.2), radius: 18, y: 7)
                    .opacity(purchases.loadingProduct || purchases.busy ? 0.65 : 1)
            }.buttonStyle(.plain)
                .disabled(purchases.loadingProduct || purchases.busy || !purchases.entitlementReady)
                .accessibilityIdentifier(purchases.product == nil ? "reloadPurchase" : "buyUnlimited")
            Text("以 Apple 购买确认页价格为准 · 不自动续费")
                .font(.caption2).foregroundStyle(PurchaseTheme.secondary)
            HStack(spacing: 24) {
                Button { Task { await purchases.restore() } } label: { Text("恢复购买").frame(minHeight: 44) }
                    .disabled(purchases.busy).accessibilityIdentifier("restoreUnlimited")
                Button { dismiss() } label: { Text("继续使用免费功能").frame(minHeight: 44) }
                    .disabled(purchases.busy).accessibilityIdentifier("continueFree")
            }.font(.caption).foregroundStyle(PurchaseTheme.secondary)
                .buttonStyle(.plain).frame(minHeight: 44)
        }.frame(maxWidth: 520).frame(maxWidth: .infinity)
            .padding(.horizontal, 24).padding(.top, 14)
            .background(PurchaseTheme.background)
    }

    private var buttonTitle: String {
        if purchases.busy { return "正在处理…" }
        if purchases.loadingProduct { return "正在获取价格…" }
        guard let product = purchases.product else { return "重新获取价格" }
        return "立即解锁 · \(product.displayPrice)"
    }

    private func deliverUnlock() {
        guard purchases.hasUnlimited, !delivered else { return }
        delivered = true; dismiss(); onUnlocked()
    }
}
