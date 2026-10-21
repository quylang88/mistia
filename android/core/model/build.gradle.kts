plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.serialization)
}

val generatedCategoryTestResources = layout.buildDirectory.dir("generated/categoryTestResources")
val syncCategoryTestResources by tasks.registering(org.gradle.api.tasks.Sync::class) {
    from(rootProject.file("../Mistia/Shared/CoreLogic/MistiaSystemCategories.json"))
    from(rootProject.file("../contracts/golden/credit-card-statements-v1.json"))
    from(rootProject.file("../contracts/golden/installment-due-v1.json"))
    from(rootProject.file("../contracts/golden/amount-calculator-v1.json"))
    from(rootProject.file("../contracts/golden/investment-accounting-v1.json"))
    from(rootProject.file("../Mistia/Localizable.xcstrings"))
    into(generatedCategoryTestResources)
}

val generatedInvestmentTestAssets = layout.buildDirectory.dir("generated/investmentTestAssets")
val syncInvestmentTestAssets by tasks.registering(org.gradle.api.tasks.Sync::class) {
    from(rootProject.file("../contracts/golden/investment-accounting-v1.json"))
    into(generatedInvestmentTestAssets)
}

android {
    namespace = "vn.com.quyln.mistia.core.model"
    compileSdk = 36
    defaultConfig { minSdk = 26; testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner" }
    testOptions { targetSdk = 36 }
    sourceSets.getByName("test").java.srcDir("src/sharedTest/java")
    sourceSets.getByName("androidTest").java.srcDir("src/sharedTest/java")
    sourceSets.getByName("androidTest").assets.srcDir(generatedInvestmentTestAssets)
    sourceSets.getByName("test").resources.srcDir(generatedCategoryTestResources)
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

tasks.named("preBuild").configure { dependsOn(syncCategoryTestResources, syncInvestmentTestAssets) }

kotlin { jvmToolchain(17) }

dependencies {
    api(libs.kotlinx.serialization.json)
    api(libs.kotlinx.coroutines.core)
    testImplementation(libs.junit)
    androidTestImplementation(libs.junit)
    androidTestImplementation(libs.androidx.test.runner)
    androidTestImplementation("androidx.test.ext:junit:1.3.0")
}
