# Flutter specific rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Keep Play Store split compatibility classes
-keep class com.google.android.play.core.** { *; }

# Keep essential TTS classes
-keep class android.speech.tts.** { *; }

# Keep Vosk classes
-keep class org.vosk.** { *; }

# Keep HTTP classes for Gemini API
-keep class io.flutter.plugins.webviewflutter.** { *; }

# Keep URL launcher classes
-keep class io.flutter.plugins.urllauncher.** { *; }

# Keep shared preferences classes
-keep class io.flutter.plugins.sharedpreferences.** { *; }

# Keep phone caller classes
-keep class io.flutter.plugins.flutter_phone_direct_caller.** { *; }

# Keep contacts classes
-keep class io.flutter.plugins.flutter_contacts.** { *; }

# Keep audio player classes
-keep class xyz.luan.audioplayers.** { *; }

# Keep bluetooth classes
-keep class com.boskokg.flutter_blue_plus.** { *; }

# Keep permission handler classes
-keep class com.baseflow.permissionhandler.** { *; }

# Gson rules for HTTP requests
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn sun.misc.**
-keep class com.google.gson.** { *; }
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer

# Basic optimization rules (less aggressive)
-optimizationpasses 2
-dontusemixedcaseclassnames
-dontskipnonpubliclibraryclasses
-verbose

# Remove logging in release builds
-assumenosideeffects class android.util.Log {
    public static boolean isLoggable(java.lang.String, int);
    public static int v(...);
    public static int i(...);
    public static int w(...);
    public static int d(...);
    public static int e(...);
}
