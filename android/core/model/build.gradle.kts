plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.serialization)
}

val generatedCategoryTestResources = layout.buildDirectory.dir("generated/categoryTestResources")
val syncCategoryTestResources by tasks.registering(org.gradle.api.tasks.Sync::class) {
    from(rootProject.file("../Mistia/Shared/CoreLogic/MistiaSystemCategories.json"))
    from(rootProject.file("../contracts/golden/credit-card-statements-v1.json"))
    from(rootProject.file("../Mistia/Localizable.xcstrings"))
    into(generatedCategoryTestResources)
}

android {
    namespace = "vn.com.quyln.mistia.core.model"
    compileSdk = 36
    defaultConfig { minSdk = 26 }
    sourceSets.getByName("test").resources.srcDir(generatedCategoryTestResources)
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

tasks.named("preBuild").configure { dependsOn(syncCategoryTestResources) }

kotlin { jvmToolchain(17) }

dependencies {
    api(libs.kotlinx.serialization.json)
    api(libs.kotlinx.coroutines.core)
    testImplementation(libs.junit)
}
