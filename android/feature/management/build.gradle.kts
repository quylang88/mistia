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
    namespace = "vn.com.quyln.mistia.feature.management"
    compileSdk = 36
    defaultConfig { minSdk = 26; testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner" }
    buildFeatures { compose = true }
    sourceSets.getByName("test").resources.srcDir(generatedCategoryAssets)
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
}
tasks.named("preBuild").configure { dependsOn(syncSharedCategoryCatalog) }
kotlin { jvmToolchain(17) }
dependencies {
    implementation(project(":core:model")); implementation(project(":core:database")); implementation(project(":core:designsystem"))
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(platform(libs.compose.bom)); implementation(libs.compose.ui); implementation(libs.compose.material3)
    implementation(libs.compose.icons)
    implementation(libs.kotlinx.serialization.json)
    testImplementation(libs.junit)
    androidTestImplementation(platform(libs.compose.bom))
    androidTestImplementation(libs.compose.ui.test)
    androidTestImplementation("androidx.test:core:1.7.0")
    androidTestImplementation("androidx.test.ext:junit:1.3.0")
    androidTestImplementation(libs.androidx.test.runner)
    debugImplementation(libs.compose.ui.test.manifest)
}
