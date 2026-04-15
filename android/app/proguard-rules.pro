# TensorFlow Lite & GPU
-keep class org.tensorflow.** { *; }
-dontwarn org.tensorflow.**

# FlatBuffers (digunakan TFLite)
-keep class com.google.flatbuffers.** { *; }
-dontwarn com.google.flatbuffers.**

# (opsional) NNAPI
-keep class org.tensorflow.lite.nnapi.** { *; }

# (opsional) kurangi warning anotasi
-dontwarn org.checkerframework.**
