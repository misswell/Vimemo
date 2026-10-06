import SwiftUI

struct UnlimitedPurchaseView: View {
    @EnvironmentObject private var purchases: PurchaseStore
    @Environment(\.dismiss) private var dismiss
    var onUnlocked: () -> Void = {}
    @State private var delivered = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: "infinity").font(.system(size: 64, weight: .ultraLight)).foregroundStyle(StudioTheme.accent)
                        .frame(maxWidth: .infinity).padding(.top, 20)
                    Text("让回忆，完整发生。").font(.system(size: 30, weight: .bold))
                    Text("一次购买，永久解锁不限制时长的导出。无需订阅，也不按次数收费。")
                        .font(.subheadline).foregroundStyle(StudioTheme.secondary).lineSpacing(4)
                    StudioCard {
                        VStack(alignment: .leading, spacing: 18) {
                            Label("导出超过 3 秒的实况、视频和 GIF", systemImage: "checkmark.circle")
                            Label("适用于整段视频及已有草稿", systemImage: "checkmark.circle")
                            Label("可在同一 Apple 账户下恢复购买", systemImage: "checkmark.circle")
                        }.font(.system(size: 14))
                    }
                    Text("3 秒内的动态导出、静态照片、自选封面和全部编辑功能继续免费。长实况的播放与动态壁纸效果由 iOS 决定。")
                        .font(.caption).foregroundStyle(StudioTheme.secondary).lineSpacing(4)
                    if let message = purchases.message {
                        Text(message).font(.subheadline).foregroundStyle(StudioTheme.peach).accessibilityIdentifier("purchaseMessage")
                    }
                    if purchases.loadingProduct { ProgressView("正在获取价格…") }
                    if let product = purchases.product {
                        PrimaryButton(title: "\(product.displayPrice) · 一次性解锁", symbol: "lock.open") {
                            Task { await purchases.purchase() }
                        }.disabled(purchases.busy || !purchases.entitlementReady).accessibilityIdentifier("buyUnlimited")
                        Text("价格以 Apple 购买确认页为准。").font(.caption).foregroundStyle(StudioTheme.secondary)
                    } else if !purchases.loadingProduct {
                        Button("重新获取价格") { Task { await purchases.loadProduct() } }.accessibilityIdentifier("reloadPurchase")
                    }
                    Button(purchases.busy ? "正在处理…" : "恢复购买") { Task { await purchases.restore() } }
                        .disabled(purchases.busy).accessibilityIdentifier("restoreUnlimited")
                    Button("继续使用免费功能") { dismiss() }.accessibilityIdentifier("continueFree")
                }.padding(24)
            }.scrollIndicators(.hidden).background(StudioTheme.background)
                .navigationTitle("不限制时长").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() }.disabled(purchases.busy) } }
                .interactiveDismissDisabled(purchases.busy)
                .task { await purchases.prepare(); deliverUnlock() }
                .onChange(of: purchases.hasUnlimited) { _, _ in deliverUnlock() }
        }.preferredColorScheme(.dark)
    }
    private func deliverUnlock() {
        guard purchases.hasUnlimited, !delivered else { return }
        delivered = true; dismiss(); onUnlocked()
    }
}
