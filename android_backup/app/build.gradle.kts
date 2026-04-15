// android/app/build.gradle.kts (MODUL APP)
plugins {
  id("com.android.application")
  id("org.jetbrains.kotlin.android")
  id("dev.flutter.flutter-gradle-plugin")
}

android {
  namespace = "com.example.e_buyur_market_flutter_4"
  // Menggunakan ekstensi dari plugin Flutter untuk keamanan versi
  compileSdk = flutter.compileSdkVersion

  defaultConfig {
    applicationId = "com.example.e_buyur_market_flutter_4"
    minSdk = flutter.minSdkVersion
    targetSdk = flutter.targetSdkVersion
    versionCode = flutter.versionCode
    versionName = flutter.versionName
  }

  buildTypes {
    release {
      isMinifyEnabled = false // Atur ke true jika Anda ingin menggunakan ProGuard
      proguardFiles(
        getDefaultProguardFile("proguard-android-optimize.txt"),
        "proguard-rules.pro"
      )
    }
  }

  compileOptions {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
  }
  kotlinOptions { jvmTarget = "17" }
}

// Wajib untuk integrasi Flutter (mengarahkan ke root project)
flutter {
  source = "../.."
}

dependencies {
  implementation("org.jetbrains.kotlin:kotlin-stdlib")
  // Dependensi Android lainnya bisa ditambahkan di sini
}
