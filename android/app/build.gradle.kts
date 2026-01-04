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
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // AJOUTE CETTE LIGNE - Crucial pour régler l'erreur flutter_local_notifications
        isCoreLibraryDesugaringEnabled = true 

        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.example.lualaba_konnect"
        
        // CONSEIL : Si l'erreur persiste, change flutter.minSdkVersion par 21 ici
        minSdk = flutter.minSdkVersion 
        
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        
        // Utile pour éviter les erreurs de limite de méthodes
        multiDexEnabled = true
    }

    buildTypes {
        getByName("debug") {
            // Pas de keystore nécessaire pour debug
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
    // Cette ligne est correcte, elle fonctionne avec isCoreLibraryDesugaringEnabled ci-dessus
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.3")
}