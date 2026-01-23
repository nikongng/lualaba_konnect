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
    
    // Support des dernières bibliothèques AndroidX
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Nécessaire pour les notifications et la gestion des dates
        isCoreLibraryDesugaringEnabled = true 

        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.example.lualaba_konnect"
        
        // Requis pour WebRTC, Caméra et les dernières API
        minSdk = 23
        targetSdk = 36
        
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        
        multiDexEnabled = true
    }

    buildTypes {
        getByName("debug") {
            // Configuration standard
        }
        getByName("release") {
            // Utilise la signature debug par défaut sur Codemagic
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
 * SOLUTION CRUCIALE POUR L'ERREUR lStar
 * Ce bloc force tous les modules (y compris Google ML Kit) à utiliser 
 * une version de core-ktx compatible qui contient la ressource lStar.
 */
subprojects {
    project.configurations.all {
        resolutionStrategy.eachDependency {
            if (requested.group == "androidx.core" && requested.name == "core-ktx") {
                useVersion("1.9.0")
            }
            // Sécurité supplémentaire pour l'autre erreur d'activité
            if (requested.group == "androidx.activity" && requested.name == "activity") {
                useVersion("1.11.0")
            }
        }
    }
}