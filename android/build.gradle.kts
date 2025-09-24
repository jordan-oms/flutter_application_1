// Top-level build.gradle.kts for Flutter project

buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.android.tools.build:gradle:8.5.0")
        classpath(kotlin("gradle-plugin", version = "1.8.22"))
        classpath("com.google.gms:google-services:4.4.0") // Google Services pour Firebase
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Redirection du build directory
val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// Clean task
tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
