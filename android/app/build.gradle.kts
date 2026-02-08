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
    // google_mlkit_* requires API 31+ attrs (e.g. android:attr/lStar).
    // Pinning compileSdk here avoids CI/build failures when Flutter's default is lower.
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
        
        // MODIFICATION ICI : Forcer le minSdk à 21 pour WebRTC
        // flutter.minSdkVersion est souvent trop bas (16 ou 19)
        minSdk = flutter.minSdkVersion 
        
        targetSdk = 34
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        
        multiDexEnabled = true
    }

    buildTypes {
        getByName("debug") {
            // Pas de changement
        }
        getByName("release") {
            signingConfig = signingConfigs.getByName("debug")
            // Conseil : Pour la production, vous passerez minifyEnabled à true
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
    implementation(platform("com.google.firebase:firebase-bom:32.7.0"))
}
