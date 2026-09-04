# watchOS 10/11+ Native APIs (Apple Watch)

Comprehensive reference for building Apple Watch apps with modern WatchKit, SwiftUI, Digital Crown, and WatchConnectivity.

---

## 1. Digital Crown Interaction

The Digital Crown provides high-precision scrolling and value stepping:

```swift
import SwiftUI

struct CrownValuePicker: View {
    @State private var crownAccumulator: Double = 0.0
    @FocusState private var isCrownFocused: Bool

    var body: some View {
        VStack {
            Text("Adjust Intensity: \(Int(crownAccumulator))")
                .font(.headline)
        }
        .focusable()
        .focused($isCrownFocused)
        .digitalCrownRotation(
            $crownAccumulator,
            from: 0.0,
            through: 100.0,
            by: 1.0,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onAppear {
            isCrownFocused = true
        }
    }
}
```

---

## 2. Watch Tactile Haptics

Always provide physical confirmation when an agent starts, finishes, or asks a question:

```swift
import WatchKit

public enum WatchHaptic {
    public static func click() {
        WKInterfaceDevice.current().play(.click)
    }

    public static func success() {
        WKInterfaceDevice.current().play(.success)
    }

    public static func alert() {
        WKInterfaceDevice.current().play(.notification)
    }

    public static func failure() {
        WKInterfaceDevice.current().play(.failure)
    }
}
```

---

## 3. WatchConnectivity (`WCSession`)

Enables real-time bidirectional communication and background data transfer between iPhone and Apple Watch:

```swift
import WatchConnectivity

public final class WatchLinkManager: NSObject, WCSessionDelegate {
    public static let shared = WatchLinkManager()

    public override init() {
        super.init()
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
    }

    // Send immediate high-priority message (both devices reachable)
    public func sendActionToPhone(action: String, data: [String: Any]) {
        guard WCSession.default.isReachable else {
            // Queue via application context if phone is not immediately active
            var currentContext = WCSession.default.applicationContext
            currentContext[action] = data
            try? WCSession.default.updateApplicationContext(currentContext)
            return
        }

        var payload = data
        payload["action"] = action
        WCSession.default.sendMessage(payload, replyHandler: nil) { error in
            print("WCSession send error: \(error)")
        }
    }

    // WCSessionDelegate
    public func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}

    public func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        DispatchQueue.main.async {
            // Handle incoming event from iPhone
        }
    }
}
```
