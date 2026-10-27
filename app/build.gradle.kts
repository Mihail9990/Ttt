plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

// Every new GitHub Actions run gets a larger versionCode.
// Local builds still work with the fallback version number.
val ciVersionCode = System.getenv("GITHUB_RUN_NUMBER")?.toIntOrNull() ?: 1
val signingKeystore = file("signing.keystore")
val signingPassword = System.getenv("APP_KEYSTORE_PASSWORD")

android {
    namespace = "com.example.apkstarter"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.example.apkstarter"
        minSdk = 23
        targetSdk = 35
        versionCode = ciVersionCode
        versionName = "1.0.$ciVersionCode"
    }

    signingConfigs {
        if (signingKeystore.isFile) {
            create("persistent") {
                val password = requireNotNull(signingPassword) {
                    "APP_KEYSTORE_PASSWORD is required when signing.keystore exists"
                }
                storeFile = signingKeystore
                storePassword = password
                // Matches the keytool command in docs/SIGNING_ON_ANDROID.md.
                keyAlias = "apkbuilder"
                keyPassword = password
            }
        }
    }

    buildTypes {
        getByName("debug") {
            if (signingKeystore.isFile) {
                // Use the same permanent certificate across subsequent APKs.
                signingConfig = signingConfigs.getByName("persistent")
            }
        }
        getByName("release") {
            isMinifyEnabled = false
            if (signingKeystore.isFile) {
                signingConfig = signingConfigs.getByName("persistent")
            }
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}
