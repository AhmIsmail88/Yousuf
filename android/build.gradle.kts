allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// whisper_ggml يطلب NDK 29 بالاسم؛ نوحّد كل المكتبات على NDK المثبّت (28.2)
// حتى لا يتطلب البناء تنزيل NDK إضافي. يُسجَّل قبل تقييم المشاريع.
subprojects {
    val pinNdk = { p: Project ->
        p.extensions.findByType(com.android.build.gradle.BaseExtension::class.java)
            ?.ndkVersion = "28.2.13676358"
    }
    if (state.executed) pinNdk(this) else afterEvaluate { pinNdk(this) }
}
subprojects {
    project.evaluationDependsOn(":app")
}
