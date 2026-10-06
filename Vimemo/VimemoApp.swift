import SwiftUI

@main struct VimemoApp: App {
    @StateObject private var store = ProjectStore()
    @StateObject private var exporter = ExportCoordinator()
    @StateObject private var purchases = makePurchaseStore()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            HomeView().environmentObject(store).environmentObject(exporter).environmentObject(purchases)
                .preferredColorScheme(.dark).tint(StudioTheme.accent)
                .task { await purchases.prepare() }
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active { store.persist() }
                    else { Task { await purchases.refreshEntitlement() } }
                }
        }
    }
}

@MainActor private func makePurchaseStore() -> PurchaseStore {
    #if DEBUG
    if CommandLine.arguments.contains("--test-purchase-unavailable") {
        return PurchaseStore(observeTransactions: false, productLoader: { [] })
    }
    if CommandLine.arguments.contains("--test-purchase-loading") {
        return PurchaseStore(observeTransactions: false, productLoader: {
            try await Task.sleep(for: .seconds(30))
            return []
        })
    }
    #endif
    return PurchaseStore()
}
