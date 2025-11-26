buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        // This line represents your Android Gradle Plugin version. Keep it as it is.
        // Replace '8.1.1' with the exact version you have if it's different.
        classpath("com.android.tools.build:gradle:8.1.1") // <--- Changed from ' to ("...")

        // ADD THIS LINE for Google Services plugin dependency
        // Replace '4.4.1' with the exact version you used or the latest.
        classpath("com.google.gms:google-services:4.4.1") // <--- Changed from ' to ("...")
    }
}

plugins {
    // Keep any existing plugins here if you have them, e.g.:
    // id("com.android.application") version "7.2.2" apply false
    // id("org.jetbrains.kotlin.android") version "1.7.10" apply false
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}