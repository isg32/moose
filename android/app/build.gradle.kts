plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: set by the release workflow (from secrets) or by hand,
// never committed. Without them, release builds fall back to the debug key,
// so `flutter build apk --release` still works with no setup.
val releaseStoreFile = System.getenv("MOOSE_KEYSTORE_FILE")?.let { file(it) }
val releaseStorePassword = System.getenv("MOOSE_KEYSTORE_PASSWORD")?.takeIf { it.isNotEmpty() }
val releaseKeyPassword =
    System.getenv("MOOSE_KEY_PASSWORD")?.takeIf { it.isNotEmpty() } ?: releaseStorePassword
val releaseKeyAlias = System.getenv("MOOSE_KEY_ALIAS")?.takeIf { it.isNotEmpty() } ?: "upload"
val canSignRelease = releaseStorePassword != null && releaseStoreFile?.exists() == true

android {
    namespace = "com.isg32.moose"
    // Firebase and notifications need androidx.core 1.19, built for API 37.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications uses java.time on older Androids.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.isg32.moose"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = releaseKeyAlias
            keyPassword = releaseKeyPassword
            storeFile = releaseStoreFile
            storePassword = releaseStorePassword
        }
    }

    buildTypes {
        release {
            signingConfig = if (canSignRelease) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // R8 keeps NewPipe (song clips) and WebRTC (calls) whole.
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

dependencies {
    // NewPipe's extractor finds a song's stream (as in Idris; YouTubeChannel.kt).
    implementation("com.github.TeamNewPipe:NewPipeExtractor:v0.27.0")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
