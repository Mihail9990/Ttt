plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.example.apkstarter"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.example.apkstarter"
        minSdk = 23
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"
    }

    signingConfigs {
        if (file("signing.keystore").isFile) {
            create("privateDebug") {
                storeFile = file("signing.keystore")
                storePassword = System.getenv("APP_KEYSTORE_PASSWORD")
                    ?: error("Missing APP_KEYSTORE_PASSWORD secret")
                keyAlias = System.getenv("APP_KEY_ALIAS")
                    ?: error("Missing APP_KEY_ALIAS secret")
                keyPassword = System.getenv("APP_KEY_PASSWORD")
                    ?: error("Missing APP_KEY_PASSWORD secret")
            }
        }
    }

    buildTypes {
        getByName("debug") {
            if (file("signing.keystore").isFile) {
                signingConfig = signingConfigs.getByName("privateDebug")
            }
        }
        getByName("release") {
            isMinifyEnabled = false
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
