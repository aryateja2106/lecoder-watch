import BackgroundTasks
import Foundation

/// Periodic usage/limit polling while the app is closed.
///
/// Limit *reset* alerts don't need this — the reset time is known in advance, so
/// NotificationManager schedules those locally and iOS delivers them whatever the
/// app is doing. What does need it is noticing you've *crossed* a threshold, or
/// that an agent is waiting: nothing detects that unless something polls.
///
/// iOS decides when these actually run (opportunistically, based on usage
/// patterns and power), so this is best-effort by design — it is not a timer.
/// APNs pushes from meshd remain the fast lane; this is the fallback for alerts
/// no daemon pushes, like crossing a spend tier.
enum BackgroundRefresh {
    static let taskIdentifier = "com.lecoder.meshwatch.refresh"

    /// Must be called before the app finishes launching, or BGTaskScheduler traps.
    static func register(store: MeshStore) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            handle(task, store: store)
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        // Floor, not a promise: iOS will not run it sooner, and may run it much later.
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Submission fails on simulators and when the user has disabled
            // Background App Refresh. Neither is worth surfacing — the app still
            // works, it just won't notice thresholds until you open it.
        }
    }

    private static func handle(_ task: BGAppRefreshTask, store: MeshStore) {
        // Always queue the next one first: if this run is killed, the chain survives.
        schedule()

        let work = Task { @MainActor in
            await store.refresh()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}
