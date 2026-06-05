import SwiftUI

@main
struct MeshWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchRootView()   // owns its own WatchMeshStore; see WatchViews.swift
        }
    }
}
