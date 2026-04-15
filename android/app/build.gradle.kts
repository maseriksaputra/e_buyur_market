// android/app/build.gradle.kts
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("kotlin-android") // atau: kotlin("android")
    // Flutter plugin HARUS terakhir
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.e_buyur_market_flutter_5"   // Ganti jika paketmu berbeda

    // Versi dari Flutter plugin (aman). NDK DIPIN ke 27 agar cocok dengan plugin (camera/geolocator/isar, dll)
    compileSdk = flutter.compileSdkVersion.toInt()
    ndkVersion = "27.0.12077973" // ⬅️ NDK 27 sesuai instruksi

    defaultConfig {
        applicationId = "com.example.e_buyur_market_flutter_5" // Ganti jika paketmu berbeda
        minSdk        = flutter.minSdkVersion.toInt()
        targetSdk     = flutter.targetSdkVersion.toInt()
        versionCode   = flutter.versionCode.toInt()
        versionName   = flutter.versionName
        multiDexEnabled = true
    }

    // ✅ Jangan kompres model *.tflite / *.lite
    aaptOptions {
        noCompress("tflite")
        noCompress("lite")
    }

    // Pakai Java 17 (AGP 8+ direkomendasikan)
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildTypes {
        // Debug: allow HTTP dan nonaktifkan shrink/minify agar dev lancar
        getByName("debug") {
            // 🔽 Toggle cleartext ON di debug
            manifestPlaceholders["usesCleartextTraffic"] = "true"

            isMinifyEnabled = false
            isShrinkResources = false
        }
        // Release: wajib HTTPS dan aktifkan shrink/minify
        getByName("release") {
            // 🔽 Toggle cleartext OFF di release
            manifestPlaceholders["usesCleartextTraffic"] = "false"

            // sementara pakai debug keystore agar build jalan; ganti ke release keystore milikmu
            signingConfig = signingConfigs.getByName("debug")

            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    packaging {
        resources {
            excludes += listOf(
                "META-INF/LICENSE*",
                "META-INF/DEPENDENCIES",
                "META-INF/AL2.0",
                "META-INF/LGPL2.1"
            )
            // (Opsional AGP modern)
            // noCompress += setOf("tflite", "lite")
        }
    }
}

// ✅ Kotlin compiler options
kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
    jvmToolchain(17)
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.multidex:multidex:2.0.1")

    // >>> WAJIB untuk GpuDelegate (samakan versi dengan ekosistem TFLite di proyekmu)
    implementation("org.tensorflow:tensorflow-lite-gpu:2.12.0")
    // (opsional) jika butuh ops lanjutan:
    // implementation("org.tensorflow:tensorflow-lite-select-tf-ops:2.12.0")
}

// (opsional) fallback untuk setup Gradle/Kotlin lama
tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile> {
    kotlinOptions { jvmTarget = "17" }
}
