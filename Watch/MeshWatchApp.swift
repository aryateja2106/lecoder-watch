import SwiftUI

@main
struct MeshWatchApp: App {
    /// Installed in init, not onAppear: the notification tap that launched the app
    /// delivers its response before any view has appeared, and a delegate set too late
    /// means the button did nothing.
    init() { WatchNotifications.shared.activate() }

    var body: some Scene {
        WindowGroup {
            WatchRootView()   // owns its own WatchMeshStore; see WatchViews.swift
        }
    }
}
