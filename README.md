# PixShift

Free, private image tools for Android — compress, resize, convert, crop, edit, PDFs, and more. Processing stays on-device.

**Application ID:** `com.pixshift.app`  
**Min SDK:** 24

## Run (debug)

```bash
flutter pub get
flutter run
```

## Release / Play Store

1. Create an upload keystore (once):

```bash
keytool -genkey -v -keystore android/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias pixshift
```

2. Copy `android/key.properties.example` → `android/key.properties` and fill in passwords / paths.

3. Build:

```bash
flutter build appbundle --release
# or
flutter build apk --release
```

Outputs:

- AAB: `build/app/outputs/bundle/release/app-release.aab`
- APK: `build/app/outputs/flutter-apk/app-release.apk`

`key.properties` and `*.jks` are gitignored — never commit them.

## Notes

- Release builds use R8 minify + resource shrinking.
- Without `key.properties`, release falls back to the debug keystore (local testing only).
- Internet is used only for Google Fonts; photos are never uploaded.
