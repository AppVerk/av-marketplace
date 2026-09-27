plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "com.example.kts"
    compileSdk = libs.versions.compileSdk.get().toInt()

    defaultConfig {
        applicationId = "com.example.kts"
        minSdk = 26
        targetSdk = 35
        manifestPlaceholders["mapsKey"] = "CANARY_PLACEHOLDER"
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
}

kotlin {
    jvmToolchain(17)
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(platform(libs.compose.bom))
    implementation(projects.lib)
    testImplementation(libs.junit)
    testImplementation(libs.turbine)
    androidTestImplementation(libs.bundles.androidtest)
    androidTestImplementation(libs.compose.ui.test)
}
