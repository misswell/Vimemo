import SwiftUI

@main struct VimemoApp: App {
    @StateObject private var store = ProjectStore()
    @StateObject private var exporter = ExportCoordinator()
    @StateObject private var purchases = PurchaseStore()
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
