iOS Build & Run Checklist

Prerequisites (macOS):
- Xcode installed (>= 13)
- CocoaPods installed (`sudo gem install cocoapods` or `brew install cocoapods`)
- Flutter SDK installed and on PATH
- Apple Developer account for provisioning (for device builds)

Quick steps:

1. Prepare project

```bash
flutter clean
flutter pub get
```

2. Install iOS pods

```bash
cd ios
pod install
cd ..
```

If `Podfile` is missing, run:

```bash
flutter create .
pod install
```

3. Open Xcode workspace

```bash
open ios/Runner.xcworkspace
```

4. Configure in Xcode
- Select the `Runner` target → Signing & Capabilities
- Set the correct `Bundle Identifier` (must match `GoogleService-Info.plist`)
- Add `Push Notifications` and `Background Modes` (check `Remote notifications`) if using `firebase_messaging`
- Ensure `Privacy - Microphone Usage Description` exists in `Info.plist` (added by repo)

5. Build & Run
- Choose a simulator or device and run (`Cmd+R`) or from terminal:

```bash
flutter build ios --release
```

6. Troubleshooting
- CocoaPods errors: run `pod repo update` then `pod install`.
- Signing errors: ensure provisioning profiles and team are set in Xcode.
- Missing iOS entitlements: follow plugin docs (e.g., `firebase_messaging`, `camera`, `flutter_webrtc`).

Notes
- After first generation, always open the `.xcworkspace`, not `.xcodeproj`.
- For push notifications, upload APNs key/certificate in Firebase Console and enable capabilities in Xcode.
