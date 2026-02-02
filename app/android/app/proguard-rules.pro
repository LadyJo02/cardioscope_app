# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Audio / USB
-keep class android.media.** { *; }
-keep class androidx.media.** { *; }

# Record plugin
-keep class com.llfbandit.record.** { *; }

# Flutter Sound
-keep class com.dooboolab.flutter_sound.** { *; }

# TFLite
-keep class org.tensorflow.** { *; }
-keep class org.tensorflow.lite.** { *; }
-keepclassmembers class * {
  native <methods>;
}

-dontwarn org.tensorflow.**
-dontwarn org.tensorflow.lite.**
-dontwarn com.dooboolab.flutter_sound.**
-dontwarn com.llfbandit.record.**
