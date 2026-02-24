# Suppress warnings for Play Core classes referenced by Flutter engine
# (deferred components / dynamic feature modules — not used in this app)
-dontwarn com.google.android.play.core.**

# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Firebase
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# Kotlin
-keep class kotlin.** { *; }
-keepclassmembers class **$WhenMappings { <fields>; }
