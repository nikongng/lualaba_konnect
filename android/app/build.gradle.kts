import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.lualaba_konnect"

    // SDK STABLE recommandé (OBLIGATOIRE pour ML Kit)
    compileSdk = 34
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.example.lualaba_konnect"

        // Compatible caméra, WebRTC, ML Kit
        minSdk = 23
        targetSdk = 34

        versionCode = flutter.versionCode
        versionName = flutter.versionName

        multiDexEnabled = true
    }

    buildTypes {
        getByName("debug") {
            // config debug par défaut
        }

        getByName("release") {
            // ⚠️ Pour test — à changer par une vraie signature plus tard
            signingConfig = signingConfigs.getByName("debug")

            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Requis pour Java 17
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.3")
}

/**
 * 🔥 BLOC CRITIQUE — CORRECTION DÉFINITIVE DE lStar
 * Force TOUS les plugins (ML Kit inclus) à utiliser SDK 34
 * Empêche les crashes AAPT
 */
subprojects {
    afterEvaluate {
        if (project.hasProperty("android")) {
            val androidExt =
                project.extensions.getByName("android") as com.android.build.gradle.BaseExtension
            androidExt.compileSdkVersion(34)
        }
    }

    configurations.all {
        resolutionStrategy.eachDependency {
            if (
                requested.group == "androidx.core" &&
                requested.name == "core-ktx"
            ) {
                useVersion("1.9.0")
            }
        }
    }
}
