plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    packagingOptions {
        jniLibs {
            useLegacyPackaging = true
        }
    }
    namespace = "z43.studios.onyx"
    compileSdk = flutter.compileSdkVersion
    // Плагины требуют разные версии NDK (flutter_v2ray → 27, jni → 28).
    // NDK обратно совместимы, поэтому ставим самую высокую из требуемых.
    // Задаём явно вместо flutter.ndkVersion (по умолчанию был 26).
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "z43.studios.onyx"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Только arm64-v8a (#44): ядро sing-box (libsingbox.so) лежит только под
        // arm64, а библиотеки остальных ABI раздували APK до ~75 МБ и без ядра
        // работали бы не полностью. Современные телефоны (в т.ч. POCO) — arm64.
        // clear(): Flutter Gradle Plugin сам кладёт сюда все свои ABI
        // (armeabi-v7a, arm64-v8a, x86_64) — без очистки «+=» только добавляет.
        ndk {
            abiFilters.clear()
            abiFilters += "arm64-v8a"
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}