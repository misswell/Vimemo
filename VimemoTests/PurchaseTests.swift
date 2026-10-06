import XCTest
import StoreKitTest
import StoreKit
import UIKit
@testable import Vimemo

final class PurchaseTests: XCTestCase {
    private func draft(end: Double = 6, speed: Double = 1, format: OutputFormat = .livePhoto) -> VideoProject {
        var project = VideoProject(title: "Purchase test", filename: "missing.mov", thumbnailFilename: "missing.jpg", duration: 6, width: 960, height: 1280, frameRate: 30, clips: [Clip(start: 0, end: end, cover: 1)])
        project.settings.unlimitedDuration = true
        project.settings.speed = speed; project.settings.format = format
        return project
    }

    func testOnlyActualLongMotionRequiresPurchase() {
        for format in [OutputFormat.livePhoto, .video, .gif] {
            XCTAssertTrue(ExportAccess.requiresUnlimited([draft(format: format)]))
            XCTAssertFalse(ExportAccess.requiresUnlimited([draft(end: 3, format: format)]))
            XCTAssertFalse(ExportAccess.requiresUnlimited([draft(speed: 2, format: format)]))
            XCTAssertTrue(ExportAccess.requiresUnlimited([draft(end: 2, speed: 0.5, format: format)]))
        }
        XCTAssertFalse(ExportAccess.requiresUnlimited([draft(format: .photo)]))
        XCTAssertFalse(ExportAccess.requiresUnlimited([draft()], format: .photo))
        var limited = draft(); limited.settings.unlimitedDuration = nil
        XCTAssertFalse(ExportAccess.requiresUnlimited([limited]))
        XCTAssertTrue(ExportAccess.requiresUnlimited([draft(end: 2), draft()]))
    }

    @MainActor func testLockedBatchIsRejectedBeforeAnyFilesOrDraftChanges() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectStore(root: root)
        let coordinator = ExportCoordinator()
        let purchases = PurchaseStore(observeTransactions: false)
        let projects = [draft(end: 2), draft()]
        XCTAssertFalse(coordinator.start(projects: projects, store: store, saveToPhotos: false, purchases: purchases))
        XCTAssertFalse(coordinator.running)
        XCTAssertTrue(coordinator.completed.isEmpty)
        XCTAssertTrue(store.exports.isEmpty)
        XCTAssertEqual(projects[1].clips[0].end, 6)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Exports").path))
    }

    @MainActor func testUnavailableProductsKeepRetryFeedbackAndNeverUnlock() async throws {
        var requests = 0
        let store = PurchaseStore(observeTransactions: false, productLoader: {
            requests += 1
            if requests == 1 { throw URLError(.notConnectedToInternet) }
            return []
        })
        await store.prepare()
        XCTAssertTrue(store.entitlementReady)
        XCTAssertNil(store.product)
        XCTAssertNotNil(store.message)
        XCTAssertFalse(store.loadingProduct)
        await store.loadProduct()
        XCTAssertEqual(requests, 2)
        XCTAssertEqual(store.message, "暂时无法获取商品，请稍后重试。其他功能可继续免费使用。")
        XCTAssertFalse(store.hasUnlimited)
        XCTAssertFalse(store.loadingProduct)
    }

    @MainActor func testVerifiedPurchaseSurvivesRelaunchAndRefundRevokesAccess() async throws {
        if UIDevice.current.systemVersion.hasPrefix("26.5") {
            throw XCTSkip("iOS 26.5 StoreKitTest configuration sync is affected by Apple FB22237318; run on a supported runtime.")
        }
        let config = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Unlimited", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: config)
        session.resetToDefaultState(); session.clearTransactions(); session.disableDialogs = true
        try await session.setSimulatedError(nil, forAPI: .verification)
        XCTAssertNotNil(UIDevice.current.identifierForVendor)
        defer { session.clearTransactions() }
        let purchases = PurchaseStore(observeTransactions: false)
        await purchases.prepare()
        XCTAssertFalse(purchases.hasUnlimited)
        XCTAssertEqual(purchases.product?.id, PurchaseStore.productID)
        await purchases.purchase()
        if !purchases.hasUnlimited {
            for await result in StoreKit.Transaction.currentEntitlements {
                if case .unverified(let transaction, let error) = result,
                   transaction.environment == .xcode, error == .invalidDeviceVerification {
                    XCTAssertFalse(purchases.hasUnlimited)
                    throw XCTSkip("This simulator rejects Xcode test transaction device verification. Production verification remains required; confirm the purchase/restore/refund flow in TestFlight sandbox.")
                }
            }
        }
        XCTAssertTrue(purchases.hasUnlimited, purchases.message ?? "Purchase not unlocked")
        let restored = PurchaseStore(observeTransactions: false)
        await restored.refreshEntitlement()
        XCTAssertTrue(restored.hasUnlimited)
        await restored.restore()
        XCTAssertTrue(restored.hasUnlimited)
        let transaction = try XCTUnwrap(session.allTransactions().first)
        try session.refundTransaction(identifier: transaction.identifier)
        await restored.refreshEntitlement()
        XCTAssertFalse(restored.hasUnlimited)
    }
}
