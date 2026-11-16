plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "app.yousuf"
    // flutter_local_notifications 23 وandroidx.core 1.19 يتطلبان API 37
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // مطلوب من flutter_local_notifications (java.time على API 26+)
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    androidResources {
        // ملفات الأذان تُشغَّل بـMediaPlayer من الأصول مباشرة.
        noCompress += listOf("ogg", "mp3")
    }

    defaultConfig {
        applicationId = "app.yousuf"
        // أدنى إصدار مدعوم حسب SPEC §3: Android 8.0 (API 26)
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // R8 يكسر WorkManager/Room بلا قواعد الإبقاء (proguard-rules.pro).
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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

dependencies {
    // محرك حساب المواقيت Kotlin — نفس خوارزمية adhan_dart (SPEC §2)
    implementation("com.batoulapps.adhan:adhan2:0.0.5")
    // تخزين إعدادات الأذان (AdhanPrefs)
    implementation("androidx.datastore:datastore-preferences:1.1.1")
    // شبكة أمان المنبّهات (SafetyNetWorker)
    implementation("androidx.work:work-runtime-ktx:2.9.1")

    // desugaring المطلوب من flutter_local_notifications
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
}
