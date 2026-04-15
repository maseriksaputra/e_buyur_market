// android/app/build.gradle.kts (MODULE, semua konfigurasi app di sini)
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // Plugin wajib untuk menghubungkan Flutter
    id("dev.flutter.flutter-gradle-plugin")
}

// Fungsi ini mengambil versi dari local.properties
fun localProperties(key: String, file: File = rootProject.file("local.properties")): String {
    val properties = java.util.Properties()
    if (file.exists()) {
        properties.load(file.inputStream())
    }
    return properties.getProperty(key) ?: ""
}

android {
    namespace = "com.example.e_buyur_market_flutter_4"
    compileSdk = localProperties("flutter.compileSdkVersion").toInt()

    defaultConfig {
        applicationId = "com.example.e_buyur_market_flutter_4"
        minSdk = localProperties("flutter.minSdkVersion").toInt()
        targetSdk = localProperties("flutter.targetSdkVersion").toInt()
        versionCode = localProperties("flutter.versionCode").toInt()
        versionName = localProperties("flutter.versionName")
    }

    buildTypes {
        release {
            isMinifyEnabled = false // Sesuaikan jika perlu ProGuard
            signingConfig = signingConfigs.getByName("debug") // Ganti dengan release signing config Anda
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    // Pakai JDK 17 untuk AGP 8.x
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("org.jetbrains.kotlin:kotlin-stdlib")
    // Tambahkan dependensi Android lain di sini jika perlu
}
