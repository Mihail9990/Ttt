plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

// GitHub run numbers increase for each new build.
val ciVersionCode = System.getenv("GITHUB_RUN_NUMBER")?.toIntOrNull() ?: 1

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

    // The public TEST key is tracked in this private repository on purpose.
    // Never use this key to sign production or publicly distributed apps.
    signingConfigs {
        create("stableTest") {
            storeFile = rootProject.file("signing/test-debug.jks")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
    }

    buildTypes {
        getByName("debug") {
            // This certificate stays the same across GitHub Actions runs.
            signingConfig = signingConfigs.getByName("stableTest")
        }
        getByName("release") {
            isMinifyEnabled = false
            // No insecure release APK: the production key will be separate.
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
