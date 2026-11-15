group = "dev.securitysdk.security_flutter"
version = "1.0-SNAPSHOT"

// AGP and Kotlin versions come from the Flutter host; do not upgrade its toolchain.
allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    id("com.android.library")
}

// Match Flutter's cross-version plugin guidance: AGP 8 needs external KGP;
// On AGP 9 the host controls Kotlin (built-in or Flutter migration bridge).
val agpMajor = com.android.Version.ANDROID_GRADLE_PLUGIN_VERSION.substringBefore('.').toInt()
if (agpMajor < 9) {
    apply(plugin = "org.jetbrains.kotlin.android")
}

android {
    namespace = "dev.securitysdk.security_flutter"

    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
        getByName("test") {
            java.srcDirs("src/test/kotlin")
        }
    }

    defaultConfig {
        minSdk = 24
    }

    testOptions {
        unitTests {
            isIncludeAndroidResources = true
            all {
                it.useJUnit()
                // Robolectric resolves framework jars outside Gradle repositories.
                // Use Maven Central's canonical endpoint; keep SHA-512 verification.
                it.systemProperty("robolectric.dependency.repo.url", "https://repo.maven.apache.org/maven2")
                providers.gradleProperty("securityTestSdks").orNull?.let { sdks ->
                    it.systemProperty("robolectric.enabledSdks", sdks)
                }

                it.outputs.upToDateWhen { false }

                it.testLogging {
                    events("passed", "skipped", "failed", "standardOut", "standardError")
                    showStandardStreams = true
                }
            }
        }
    }
}

project.extensions.configure(org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension::class.java) {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.16.1")
}
