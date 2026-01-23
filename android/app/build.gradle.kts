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
    
    // Correction Erreur 19 & 20 : On monte au SDK 36 pour satisfaire les libs récentes
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Nécessaire pour flutter_local_notifications et les dates (Java 8+)
        isCoreLibraryDesugaringEnabled = true 

        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.example.lualaba_konnect"
        
        // Correction pour flutter_webrtc et camera : minSdk 23 minimum
        minSdk = 23
        
        // Aligné sur compileSdk pour éviter les conflits de ressources
        targetSdk = 36
        
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        
        // Évite l'erreur "Too many method references"
        multiDexEnabled = true
    }

    buildTypes {
        getByName("debug") {
            // Pas de configuration de signature spécifique requise pour le debug
        }
        getByName("release") {
            // Utilise la signature de debug pour Codemagic si tu n'as pas encore de keystore
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
    // Support pour les fonctionnalités Java modernes sur vieux Android
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.3")
}

// FORCE les versions pour régler l'erreur "resource android:attr/lStar not found"
configurations.all {
    resolutionStrategy {
        force("androidx.core:core-ktx:1.9.0")
        force("androidx.activity:activity:1.11.0")
    }
}