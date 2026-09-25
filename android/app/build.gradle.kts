import java.io.FileInputStream
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android plugin.
    id("dev.flutter.flutter-gradle-plugin")
}

val updateKeystoreProperties = Properties()
val updateKeystorePropertiesFile = rootProject.file("key.properties")
require(updateKeystorePropertiesFile.exists()) {
    "Missing android/key.properties. Restore it together with the fixed update keystore."
}
updateKeystoreProperties.load(FileInputStream(updateKeystorePropertiesFile))

// Seconds since 2020 stay inside Android's versionCode limit for decades and
// automatically increase on every later build without editing pubspec.yaml.
val automaticVersionCode =
    ((System.currentTimeMillis() / 1000L) - 1577836800L).toInt()
val automaticVersionName =
    "1.0.${LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyyMMdd.HHmmss"))}"
val xiaomiAppId = providers.gradleProperty("XIAOMI_APP_ID").orElse("0").get()
val isolatedTestBuild = providers.environmentVariable("BLUE_HYDRANGEA_ISOLATED_TEST")
    .orElse("0").get() == "1"

android {
    namespace = "com.example.blue_hydrangea"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.example.blue_hydrangea"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = automaticVersionCode
        versionName = automaticVersionName
        manifestPlaceholders["xiaomiAppId"] = xiaomiAppId
        manifestPlaceholders["xiaomiBuildDebug"] = "false"
        manifestPlaceholders["appLabel"] = "给你的蓝色绣球花"
    }

    signingConfigs {
        create("fixedUpdate") {
            keyAlias = updateKeystoreProperties["keyAlias"] as String
            keyPassword = updateKeystoreProperties["keyPassword"] as String
            storeFile = file(updateKeystoreProperties["storeFile"] as String)
            storePassword = updateKeystoreProperties["storePassword"] as String
        }
    }

    buildTypes {
        debug {
            signingConfig = signingConfigs.getByName("fixedUpdate")
            manifestPlaceholders["xiaomiBuildDebug"] = "true"
            if (isolatedTestBuild) {
                applicationIdSuffix = ".stage3test"
                manifestPlaceholders["appLabel"] = "蓝色绣球花·测试"
            }
        }
        release {
            signingConfig = signingConfigs.getByName("fixedUpdate")
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
