import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.ksp)
    alias(libs.plugins.hilt)
}

fun String.asBuildConfigString(): String =
    "\"" + replace("\\", "\\\\").replace("\"", "\\\"") + "\""

val localProperties = Properties().apply {
    val file = rootProject.file("local.properties")
    if (file.isFile) file.inputStream().use(::load)
}

fun plistValue(key: String, fileName: String = "../Mistia/MistiaSyncConfig.plist"): String? {
    val plist = rootProject.file(fileName)
    if (!plist.isFile) return null
    val match = Regex("<key>\\s*${Regex.escape(key)}\\s*</key>\\s*<string>([^<]+)</string>")
        .find(plist.readText())
    return match?.groupValues?.get(1)?.trim()?.takeIf(String::isNotEmpty)
}

fun resolveConfig(environment: String, property: String, plistKey: String): String =
    providers.environmentVariable(environment).orNull?.trim()?.takeIf(String::isNotEmpty)
        ?: localProperties.getProperty(property)?.trim()?.takeIf(String::isNotEmpty)
        ?: plistValue(plistKey)
        ?: ""

val supabaseUrl = resolveConfig("MISTIA_SUPABASE_URL", "mistia.supabase.url", "SUPABASE_URL")
val supabaseAnonKey = resolveConfig("MISTIA_SUPABASE_ANON_KEY", "mistia.supabase.anonKey", "SUPABASE_ANON_KEY")
val googleWebClientId = providers.environmentVariable("MISTIA_GOOGLE_SERVER_CLIENT_ID").orNull
    ?: localProperties.getProperty("mistia.google.serverClientId")
    ?: plistValue("GIDServerClientID", "../MistiaInfo.plist")
    ?: ""

android {
    namespace = "vn.com.quyln.mistia"
    compileSdk = 36

    defaultConfig {
        applicationId = "vn.com.quyln.mistia"
        minSdk = 26
        targetSdk = 36
        versionCode = 3
        versionName = "0.1.2-apk0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        vectorDrawables.useSupportLibrary = true
        buildConfigField("String", "SUPABASE_URL", supabaseUrl.asBuildConfigString())
        buildConfigField("String", "SUPABASE_ANON_KEY", supabaseAnonKey.asBuildConfigString())
        buildConfigField("boolean", "ALLOW_CLOUD_WRITES", "false")
        buildConfigField("boolean", "ALLOW_CATEGORY_CLOUD_WRITES", "false")
        buildConfigField("boolean", "ALLOW_WALLET_CLOUD_WRITES", "false")
        buildConfigField("boolean", "ALLOW_CREDIT_CARD_CLOUD_WRITES", "false")
        buildConfigField("String", "GOOGLE_WEB_CLIENT_ID", googleWebClientId.trim().asBuildConfigString())
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin {
    jvmToolchain(17)
}

dependencies {
    implementation(project(":core:model"))
    implementation(project(":core:database"))
    implementation(project(":core:network"))
    implementation(project(":core:sync"))
    implementation(project(":core:auth"))
    implementation(project(":core:designsystem"))
    implementation(project(":feature:overview"))
    implementation(project(":feature:transactions"))
    implementation(project(":feature:planning"))
    implementation(project(":feature:management"))
    implementation(project(":feature:family"))
    implementation(project(":feature:investment"))
    implementation(project(":feature:notifications"))
    implementation(project(":feature:settings"))

    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.runtime)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    testImplementation(libs.junit)
    testImplementation("org.mockito:mockito-core:5.20.0")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.10.2")
    androidTestImplementation(platform(libs.compose.bom))
    androidTestImplementation(libs.compose.ui.test)
    androidTestImplementation(libs.androidx.test.runner)
    androidTestImplementation(libs.espresso.core)
    androidTestImplementation("androidx.test.ext:junit:1.3.0")
    implementation(libs.androidx.navigation.compose)
    implementation(libs.androidx.work.runtime)
    implementation(libs.hilt.android)
    ksp(libs.hilt.compiler)

    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.ui.tooling.preview)
    implementation(libs.compose.material3)
    implementation(libs.compose.icons)
    debugImplementation(libs.compose.ui.tooling)
    debugImplementation(libs.compose.ui.test.manifest)
}
