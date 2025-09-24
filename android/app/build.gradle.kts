import java.util.Properties
import java.io.File

// >>> CHARGEMENT DU KEYPROPERTIES POUR RELEASE >>>
val keystorePropertiesFile = File(rootProject.projectDir, "key.properties")
val keystoreProperties = Properties()

println("DEBUG: keystorePropertiesFile exists = ${keystorePropertiesFile.exists()}")

if (keystorePropertiesFile.exists() && keystorePropertiesFile.isFile) {
    keystorePropertiesFile.inputStream().use { input ->
        keystoreProperties.load(input)
    }
    println("DEBUG: storeFile property = ${keystoreProperties.getProperty("storeFile")}")
} else {
    println("WARNING: key.properties not found at ${keystorePropertiesFile.absolutePath}")
}

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services") // Firebase
}

android {
    namespace = "com.example.flutter_application_1"
    compileSdk = 36

    signingConfigs {
        create("release") {
            val storeFilePath = keystoreProperties.getProperty("storeFile")
            if (!storeFilePath.isNullOrEmpty()) {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = File(storeFilePath)
                storePassword = keystoreProperties.getProperty("storePassword")
                println("DEBUG: Using release signing config: $storeFilePath")
            } else {
                println("WARNING: storeFile property is missing in key.properties")
            }
        }
    }

    defaultConfig {
        applicationId = "com.example.flutter_application_1"
        minSdk = 24
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            isShrinkResources = false
            signingConfig = signingConfigs.getByName("release")
        }
        debug {
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

dependencies {
    implementation(platform("com.google.firebase:firebase-bom:34.2.0"))
    implementation("com.google.firebase:firebase-analytics")
    implementation("com.google.firebase:firebase-firestore")
    implementation("com.google.firebase:firebase-auth")
}
