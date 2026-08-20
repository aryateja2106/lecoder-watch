import Foundation

// Getting this wrong does not degrade push, it deletes it: a TestFlight token sent to
// the sandbox gateway comes back BadDeviceToken, and meshd used to treat that as a dead
// device and unregister the phone. Nothing would ever arrive again, with no error
// anywhere the user could see.
@main
struct CheckAPNsEnv {
    static func main() {
        func profile(_ entitlements: String) -> Data {
            // A .mobileprovision is a CMS blob with a plain XML plist inside it, so the
            // parser has to find the plist rather than decode the file.
            var bytes = Data([0x30, 0x82, 0xDE, 0xAD])      // DER noise before
            bytes.append(Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0"><dict>
              <key>Name</key><string>iOS Team Provisioning Profile</string>
              <key>Entitlements</key><dict>\(entitlements)</dict>
            </dict></plist>
            """.utf8))
            bytes.append(Data([0x00, 0xFF, 0x00, 0xFF]))    // signature after
            return bytes
        }

        assert(apnsEnvironment(fromProfile: profile("<key>aps-environment</key><string>production</string>")) == "prod",
               "a TestFlight or App Store profile must report prod")
        assert(apnsEnvironment(fromProfile: profile("<key>aps-environment</key><string>development</string>")) == "dev")

        // Anything we cannot read must fall to "dev". Sandbox is the safe guess: a dev
        // token sent to production fails loudly and gets retried, and the retry now
        // covers the other direction too.
        assert(apnsEnvironment(fromProfile: profile("<key>application-identifier</key><string>X.y</string>")) == "dev",
               "a profile with no aps-environment is not production")
        assert(apnsEnvironment(fromProfile: Data()) == "dev", "empty data")
        assert(apnsEnvironment(fromProfile: Data("not a provisioning profile at all".utf8)) == "dev", "garbage")
        assert(apnsEnvironment(fromProfile: Data("<?xml version=\"1.0\"?><plist>truncated".utf8)) == "dev",
               "a truncated plist must not throw")

        // A profile carrying several entitlements still resolves.
        let many = "<key>get-task-allow</key><false/><key>aps-environment</key><string>production</string><key>com.apple.security.application-groups</key><array><string>group.x</string></array>"
        assert(apnsEnvironment(fromProfile: profile(many)) == "prod")

        print("check-apns-env: OK")
    }
}
