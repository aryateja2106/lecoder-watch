import Foundation

/// Which APNs gateway will accept this build's device token.
///
/// This matters more than it looks. A development build's token is only valid at
/// `api.sandbox.push.apple.com`; a TestFlight or App Store build's token is only valid
/// at `api.push.apple.com`. Send to the wrong one and Apple answers `BadDeviceToken` —
/// which meshd treats as a dead device and removes, so the very first push after a
/// TestFlight install would silently unregister the phone and never be retried.
///
/// The truth is in the embedded provisioning profile, so read it rather than guessing
/// from `#if DEBUG`: a Release build sideloaded for development is still `development`,
/// and the same source archived for TestFlight is `production`.
enum APNsEnvironment {
    /// "dev" or "prod" — the wire values `meshd/push.ts` stores.
    static var current: String {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else {
            // No profile: the simulator, or a Mac-signed build. Sandbox is the only
            // gateway either could ever use.
            return "dev"
        }
        return apnsEnvironment(fromProfile: data)
    }
}

/// Pull `Entitlements.aps-environment` out of a `.mobileprovision`.
///
/// The file is a CMS signature wrapping a plain XML plist. Rather than decode PKCS#7,
/// find the plist by its delimiters — the long-standing way to do this, and stable
/// because the payload has to stay a readable plist for the OS to use it too.
func apnsEnvironment(fromProfile data: Data) -> String {
    guard let start = data.range(of: Data("<?xml".utf8)),
          let end = data.range(of: Data("</plist>".utf8), options: [.backwards]) else { return "dev" }
    let xml = data[start.lowerBound..<end.upperBound]
    guard let plist = try? PropertyListSerialization.propertyList(from: xml, format: nil) as? [String: Any],
          let entitlements = plist["Entitlements"] as? [String: Any],
          let environment = entitlements["aps-environment"] as? String else { return "dev" }
    // Apple writes "production" for App Store and TestFlight, "development" otherwise.
    return environment == "production" ? "prod" : "dev"
}
