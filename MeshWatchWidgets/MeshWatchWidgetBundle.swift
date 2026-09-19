// MeshWatchWidgetBundle.swift — registers the iOS Live Activity in the widget extension.
import WidgetKit
import SwiftUI

@main
struct MeshWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        SessionLiveActivity()
    }
}
