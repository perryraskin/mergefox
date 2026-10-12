import SwiftUI

@main struct MergefoxApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(model).tint(PajamasTheme.accent).foregroundStyle(PajamasTheme.text)
                .onOpenURL { url in Task { await model.handle(url) } }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await model.restoreSharedAccount() } }
                }
        }
    }
}
