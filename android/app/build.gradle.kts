plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "online.novaproxy.nova_client"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "online.novaproxy.nova_client"
        // libbox.aar (main variant) is built with androidapi 23, so minSdk >= 23.
        minSdk = 24
        // Target 33 to keep the foreground-service / VPN flow simple for this
        // sideloaded test build (avoids the Android 14 FGS-type requirements).
        targetSdk = 33
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // The gomobile-built libbox.aar ships native .so files that must be
    // extracted (legacy packaging) to load reliably.
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    buildTypes {
        release {
            // Signed with the debug key for now so the release APK is
            // sideloadable. Replace with a real signing config for distribution.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    // The sing-box core. Built by CI (build-apk workflow) and copied into
    // app/libs/ before assembling the APK; absent during plain analysis.
    val libbox = file("libs/libbox.aar")
    if (libbox.exists()) {
        implementation(files(libbox))
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
