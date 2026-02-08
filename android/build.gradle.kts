// 1. Bloc ajouté pour charger le plugin Google Services
buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        // Version compatible avec Flutter 3.x
        classpath("com.google.gms:google-services:4.4.0")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Force a modern compileSdk across ALL Android subprojects (including Flutter plugins).
// This prevents AAPT errors like "android:attr/lStar not found" from plugins such as
// google_mlkit_commons when Flutter's default compileSdk is older.
subprojects {
    afterEvaluate {
        val androidExt = extensions.findByName("android") ?: return@afterEvaluate

        // AGP 7/8: CommonExtension has property `compileSdk` (setter `setCompileSdk(int)`).
        // AGP older: BaseExtension exposes `compileSdkVersion(int)`.
        val desiredCompileSdk = 36
        runCatching {
            androidExt.javaClass.getMethod("setCompileSdk", Int::class.javaPrimitiveType)
                .invoke(androidExt, desiredCompileSdk)
        }.recoverCatching {
            androidExt.javaClass.getMethod("compileSdkVersion", Int::class.javaPrimitiveType)
                .invoke(androidExt, desiredCompileSdk)
        }
    }
}

// Ensure Java/Kotlin compile target is modern to suppress obsolete-8 warnings
tasks.withType(org.gradle.api.tasks.compile.JavaCompile::class.java).configureEach {
    sourceCompatibility = "17"
    targetCompatibility = "17"
    options.release.set(17)
}

// Ta configuration personnalisée du répertoire de build
val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
