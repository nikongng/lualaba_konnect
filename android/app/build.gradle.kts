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
    
    // SDK de compilation principal
    compileSdk = 36
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
        
        // Requis pour la stabilité de la caméra et WebRTC
        minSdk = 23
        targetSdk = 36
        
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        
        multiDexEnabled = true
    }

    buildTypes {
        getByName("debug") {
        }
        getByName("release") {
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
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.3")
}

/**
 * SOLUTION ULTIME POUR L'ERREUR lStar
 * Ce bloc force CHAQUE sous-module (plugin) à utiliser le SDK 34 minimum
 * et impose la version 1.9.0 de core-ktx.
 */
subprojects {
    afterEvaluate {
        if (project.hasProperty("android")) {
            val android = project.extensions.getByName("android") as com.android.build.gradle.BaseExtension
            // On force le SDK de compilation des plugins pour qu'ils trouvent 'lStar'
            android.compileSdkVersion(34)
        }
    }
    project.configurations.all {
        resolutionStrategy.eachDependency {
            if (requested.group == "androidx.core" && requested.name == "core-ktx") {
                useVersion("1.9.0")
            }
        }
    }
}