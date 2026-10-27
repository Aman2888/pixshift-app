# Flutter
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# flutter_avif native bridge
-keep class com.teknorota.flutter_avif.** { *; }
-dontwarn com.teknorota.flutter_avif.**

# Keep Parcelable / Serializable used by plugins
-keepclassmembers class * implements android.os.Parcelable {
    public static final ** CREATOR;
}
