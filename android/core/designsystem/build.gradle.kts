plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
}

val generatedCategoryAssets = layout.buildDirectory.dir("generated/mistiaCategoryAssets")
val syncSharedCategoryCatalog by tasks.registering(org.gradle.api.tasks.Sync::class) {
    from(rootProject.file("../Mistia/Shared/CoreLogic/MistiaSystemCategories.json"))
    into(generatedCategoryAssets)
}
android {
    namespace = "vn.com.quyln.mistia.core.designsystem"
    compileSdk = 36
    defaultConfig { minSdk = 26 }
    buildFeatures { compose = true }
    sourceSets.getByName("main").assets.srcDir(generatedCategoryAssets)
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

tasks.named("preBuild").configure { dependsOn(syncSharedCategoryCatalog) }
kotlin { jvmToolchain(17) }

dependencies {
    testImplementation(libs.junit)
    implementation(project(":core:model"))
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.androidx.core.ktx)
    implementation(platform(libs.compose.bom))
    api(libs.compose.ui)
    api(libs.compose.foundation)
    api(libs.compose.material3)
    api(libs.compose.icons)
    implementation(libs.compose.ui.tooling.preview)
    debugImplementation(libs.compose.ui.tooling)
}
