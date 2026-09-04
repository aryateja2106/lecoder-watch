---
name: native-app-builder
description: Autonomous native Apple app builder for Route 1 (users with an Apple Developer account). Scaffolds SwiftUI apps with XcodeGen, configures Team ID and bundle prefix, sets up deep linking, archives with xcodebuild, packages OTA Wireless manifests or uploads to TestFlight, and emits the APP_READY signal.
---

# Route 1: Autonomous Native Apple App Builder (TestFlight & Wireless OTA)

Use this skill when building native iOS, watchOS, iPadOS, or macOS applications for users who connect their Apple Developer Account.

---

## 1. Specification & Requirements

1. **Target Developer Account:**
   - Development Team ID: Configured via environment `DEVELOPMENT_TEAM` (e.g. `B5B87F7AXF`).
   - Bundle Identifier Prefix: `com.aryateja.` (or user's prefix).
   - Bundle ID Format: `<prefix>.<app-slug>` (e.g. `com.aryateja.pomodoro`).
2. **Frameworks & Baseline:**
   - iOS 17.0+, watchOS 10.0+, macOS 14.0+, Swift 5.9+.
   - Pure SwiftUI and modern `@Observable`.
3. **Mandatory Deep-Link Scheme:**
   Every app MUST declare a custom URL scheme in its `Info.plist` matching its bundle ID (`<prefix>.<app-slug>`):
   ```yaml
   CFBundleURLTypes:
     - CFBundleURLName: com.aryateja.<app-slug>
       CFBundleURLSchemes:
         - com.aryateja.<app-slug>
   ```
   This allows LeSearch Mesh and mobile clients to detect installation and launch the app directly.

---

## 2. Standard XcodeGen `project.yml` Template

```yaml
name: {{APP_NAME}}
options:
  bundleIdPrefix: {{BUNDLE_ID_PREFIX}}
  deploymentTarget:
    iOS: "17.0"
settings:
  base:
    DEVELOPMENT_TEAM: "{{DEVELOPMENT_TEAM}}"
    CODE_SIGN_STYLE: Automatic
    SWIFT_VERSION: "5.0"
targets:
  {{APP_NAME}}:
    type: application
    platform: iOS
    sources:
      - path: Sources
    info:
      path: Info.plist
      properties:
        CFBundleDisplayName: "{{APP_NAME}}"
        CFBundleIdentifier: "{{BUNDLE_ID_PREFIX}}.{{APP_SLUG}}"
        CFBundleShortVersionString: "1.0"
        CFBundleVersion: "1"
        UILaunchScreen: {}
        CFBundleURLTypes:
          - CFBundleURLSchemes:
              - "{{BUNDLE_ID_PREFIX}}.{{APP_SLUG}}"
```

---

## 3. Build & Archive Pipeline

### Step A: Generate Project
```bash
xcodegen generate
```

### Step B: Build & Archive
```bash
xcodebuild archive \
  -project {{APP_NAME}}.xcodeproj \
  -scheme {{APP_NAME}} \
  -configuration Release \
  -sdk iphoneos \
  -archivePath build/App.xcarchive \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM={{DEVELOPMENT_TEAM}} \
  -allowProvisioningUpdates
```

### Step C: Export IPA
Create `build/ExportOptions.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>development</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>stripSwiftSymbols</key>
    <true/>
    <key>teamID</key>
    <string>{{DEVELOPMENT_TEAM}}</string>
</dict>
</plist>
```

Run export:
```bash
xcodebuild -exportArchive \
  -archivePath build/App.xcarchive \
  -exportPath build/ipa \
  -exportOptionsPlist build/ExportOptions.plist \
  -allowProvisioningUpdates
```

---

## 4. Packaging Release Artifacts

Move files to `releases/{{APP_SLUG}}/`:
1. `App.ipa` (from `build/ipa/{{APP_NAME}}.ipa`)
2. `meta.json`:
   ```json
   {
     "name": "{{APP_NAME}}",
     "bundleId": "{{BUNDLE_ID_PREFIX}}.{{APP_SLUG}}",
     "version": "1.0",
     "buildType": "Release",
     "platform": "ios",
     "buildDate": "2026-09-04T00:00:00Z",
     "hasIPA": true
   }
   ```
3. `manifest.plist` (for wireless installation over `itms-services://`):
   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
     <key>items</key>
     <array>
       <dict>
         <key>assets</key>
         <array>
           <dict>
             <key>kind</key>
             <string>software-package</string>
             <key>url</key>
             <string>https://localhost/releases/{{APP_SLUG}}/App.ipa</string>
           </dict>
         </array>
         <key>metadata</key>
         <dict>
           <key>bundle-identifier</key>
           <string>{{BUNDLE_ID_PREFIX}}.{{APP_SLUG}}</string>
           <key>bundle-version</key>
           <string>1.0</string>
           <key>kind</key>
           <string>software</string>
           <key>title</key>
           <string>{{APP_NAME}}</string>
         </dict>
       </dict>
     </array>
   </dict>
   </plist>
   ```

---

## 5. Mandatory Completion Signal

When the build is verified and packaged, the agent MUST emit this exact line to trigger client notification and UI card rendering:

```html
<!-- APP_READY slug="<app-slug>" name="<App Display Name>" -->
```

Followed by a 2-sentence summary of the built application.
