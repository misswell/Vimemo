import SwiftUI

@main struct VimemoApp: App {
    @StateObject private var store = ProjectStore()
    @StateObject private var exporter = ExportCoordinator()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            HomeView().environmentObject(store).environmentObject(exporter)
                .preferredColorScheme(.dark).tint(StudioTheme.accent)
                .onChange(of: scenePhase) { _, phase in if phase != .active { store.persist() } }
        }
    }
}
