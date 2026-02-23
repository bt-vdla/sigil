import SwiftUI

@main
struct SigilApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No visible windows — Sigil lives entirely in the menu bar.
        // Settings scene is required to satisfy the Scene protocol.
        Settings {
            EmptyView()
        }
    }
}
