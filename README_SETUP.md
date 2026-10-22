# PixShift Flutter app (all 89 tools)

1. `flutter create --org com.pixshift --platforms android pixshift_tmp`
2. Copy this folder's `lib/` and `pubspec.yaml` over the new project, then `flutter pub get`.
3. android/app/build.gradle: `minSdk 24`. AndroidManifest.xml: add `<uses-permission android:name="android.permission.INTERNET"/>` (Google Fonts).
4. `flutter run`

Needs Flutter 3.27+ (uses Color.withValues).
All 89 tools (12 engines) are included.
