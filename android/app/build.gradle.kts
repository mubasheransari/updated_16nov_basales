import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: values come from android/key.properties (never commit it).
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKey = keystorePropertiesFile.exists()
if (hasReleaseKey) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

// Google Maps key lives in android/local.properties (MAPS_API_KEY=...), never in source control.
val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localPropertiesFile.inputStream().use { localProperties.load(it) }
}
val mapsApiKey: String = localProperties.getProperty("MAPS_API_KEY")
    ?: System.getenv("MAPS_API_KEY")
    ?: ""

// Stop a release build from shipping with a missing Maps key (the map would be blank).
gradle.taskGraph.whenReady {
    val isRelease = hasTask(":app:bundleRelease") || hasTask(":app:assembleRelease")
    if (isRelease && (mapsApiKey.isBlank() || mapsApiKey.startsWith("PUT_YOUR"))) {
        throw GradleException("MAPS_API_KEY is not set. Add MAPS_API_KEY=... to android/local.properties")
    }
}

android {
    namespace = "com.sales.ba"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.sales.ba"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = 36
        manifestPlaceholders["MAPS_API_KEY"] = mapsApiKey
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        // Optional: add `signDebugWithRelease=true` to android/key.properties so `flutter run`
        // uses the SAME key as release => the Android ID (Device ID) stays identical in testing.
        debug {
            if (hasReleaseKey && keystoreProperties.getProperty("signDebugWithRelease") == "true") {
                signingConfig = signingConfigs.getByName("release")
            }
        }
        release {
            // Signed with your own key. If key.properties is missing the APK
            // comes out unsigned (so it can never be mistaken for a release).
            signingConfig = if (hasReleaseKey) signingConfigs.getByName("release") else null
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}
