plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeystorePath = System.getenv("STASH_FLOW_KEYSTORE")
val releaseKeyAlias = System.getenv("STASH_FLOW_KEY_ALIAS")
val releaseStorePassword = System.getenv("STASH_FLOW_STORE_PASSWORD")
val releaseKeyPassword = System.getenv("STASH_FLOW_KEY_PASSWORD")
val hasReleaseSigning = listOf(
    releaseKeystorePath,
    releaseKeyAlias,
    releaseStorePassword,
    releaseKeyPassword,
).all { !it.isNullOrBlank() }

android {
    namespace = "io.github.sakurabluer.stashflow"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "io.github.sakurabluer.stashflow"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Keep dependency native libraries aligned with Flutter's selected targets.
        // ABI splits configure their own filters.
        if (project.findProperty("split-per-abi") != "true") {
            val selectedAbis = (project.findProperty("target-platform") as? String)
                ?.split(",")
                ?.mapNotNull {
                    when (it.trim()) {
                        "android-arm" -> "armeabi-v7a"
                        "android-arm64" -> "arm64-v8a"
                        "android-x64" -> "x86_64"
                        else -> null
                    }
                }.orEmpty()
            if (selectedAbis.isNotEmpty()) {
                ndk {
                    abiFilters.clear()
                    abiFilters.addAll(selectedAbis)
                }
            }
        }
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(releaseKeystorePath!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
        }
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
