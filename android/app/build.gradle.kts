import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing. The key lives in android/key.properties (never committed).
// In CI it is written from GitHub Actions secrets before the build starts.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKey = keystorePropertiesFile.exists()
if (hasReleaseKey) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

android {
    namespace = "io.github.ishor22.mylifebusinesstycoon"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Permanent application ID. Changing it would make Android treat the app as a new one.
        applicationId = "io.github.ishor22.mylifebusinesstycoon"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // versionCode and versionName come from pubspec.yaml, or from --build-number/--build-name in CI.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseKey) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

// Fail closed: never produce a release APK signed with the debug key or unsigned.
gradle.taskGraph.whenReady {
    val buildsRelease = allTasks.any {
        (it.name.startsWith("assemble") || it.name.startsWith("bundle")) && it.name.contains("Release")
    }
    if (buildsRelease && !hasReleaseKey) {
        throw GradleException(
            "Release signing key is missing (android/key.properties). " +
                "Refusing to build an unsigned or debug-signed release."
        )
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
