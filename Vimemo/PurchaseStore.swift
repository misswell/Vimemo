import Foundation
import StoreKit
import Combine

enum ExportAccess {
    static func requiresUnlimited(_ projects: [VideoProject], format: OutputFormat? = nil) -> Bool {
        projects.contains { project in
            guard (format ?? project.settings.format) != .photo else { return false }
            return project.clips.contains { clip in
                var output = clip
                output.normalize(sourceDuration: project.duration, speed: project.settings.speed, maxOutputDuration: project.settings.maxOutputDuration)
                return output.duration / project.settings.speed > 3.001
            }
        }
    }
}

@MainActor final class PurchaseStore: ObservableObject {
    static let productID = "com.vimemo.live.unlimited"
    @Published private(set) var hasUnlimited = false
    @Published private(set) var entitlementReady = false
    @Published private(set) var product: Product?
    @Published private(set) var loadingProduct = false
    @Published private(set) var busy = false
    @Published private(set) var message: String?
    private var updatesTask: Task<Void, Never>?

    init(observeTransactions: Bool = true) {
        if observeTransactions {
            updatesTask = Task { [weak self] in
                for await result in Transaction.updates {
                    guard let self else { return }
                    guard case .verified(let transaction) = result, transaction.productID == Self.productID else { continue }
                    await self.refreshEntitlement()
                    await transaction.finish()
                }
            }
        }
    }
    deinit { updatesTask?.cancel() }

    func prepare() async {
        await refreshEntitlement()
        await loadProduct()
    }

    func refreshEntitlement() async {
        var unlocked = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productID == Self.productID,
                  transaction.productType == .nonConsumable,
                  transaction.revocationDate == nil, !transaction.isUpgraded else { continue }
            unlocked = true
        }
        hasUnlimited = unlocked
        entitlementReady = true
    }

    func loadProduct() async {
        guard !loadingProduct else { return }
        loadingProduct = true
        defer { loadingProduct = false }
        do {
            product = try await Product.products(for: [Self.productID]).first { $0.id == Self.productID && $0.type == .nonConsumable }
            message = product == nil ? "暂时无法获取商品，请稍后重试。其他功能可继续免费使用。" : nil
        } catch { message = "商品加载失败：\(error.localizedDescription)" }
    }

    func purchase() async {
        guard !busy else { return }
        busy = true; message = nil
        defer { busy = false }
        do {
            if product == nil { await loadProduct() }
            guard let product else { return }
            switch try await product.purchase() {
            case .success(let result):
                guard case .verified(let transaction) = result,
                      transaction.productID == Self.productID,
                      transaction.productType == .nonConsumable,
                      transaction.revocationDate == nil else {
                    message = "无法验证这次购买，请尝试恢复购买。"; return
                }
                await refreshEntitlement()
                await transaction.finish()
            case .pending:
                message = "购买正在等待批准。批准后会自动解锁，其他功能可继续免费使用。"
            case .userCancelled:
                message = nil
            @unknown default:
                message = "购买尚未完成，请稍后重试。"
            }
        } catch { message = "购买未完成：\(error.localizedDescription)" }
    }

    func restore() async {
        guard !busy else { return }
        busy = true; message = nil
        defer { busy = false }
        do {
            try await AppStore.sync()
            await refreshEntitlement()
            message = hasUnlimited ? "已恢复不限制时长。" : "未找到这项购买，请确认使用购买时的 Apple 账户。"
        } catch { message = "恢复购买失败：\(error.localizedDescription)" }
    }
}
