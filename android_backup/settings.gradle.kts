// android/settings.gradle.kts

pluginManagement {
    // Fungsi ini mengambil path Flutter SDK dari file local.properties
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        file("local.properties").inputStream().use { properties.load(it) }
        val flutterSdkPath = properties.getProperty("flutter.sdk")
        require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
        flutterSdkPath
    }

    // Menyertakan build Gradle dari Flutter SDK
    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
        // Tambahkan repository maven Flutter untuk jaga-jaga
        maven { url = uri("https://storage.googleapis.com/download.flutter.io") }
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.4.2" apply false // Sesuaikan versi jika perlu
    id("org.jetbrains.kotlin.android") version "1.9.24" apply false // Sesuaikan versi jika perlu
}

// Perintah ini wajib ada untuk menyertakan modul aplikasi utama Anda
include(":app")
