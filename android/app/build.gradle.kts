import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

// Machine-specific service keys, never committed (mirrors ios/Config.xcconfig).
// Missing file or placeholder values leave the app in dev mode: auth shows a
// friendly "not configured" error and the paywall never gates.
val secrets = Properties().apply {
    val f = rootProject.file("secrets.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

fun secret(key: String): String = (secrets.getProperty(key) ?: "").trim()

android {
    namespace = "com.sulav.sleepblock"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.sulav.sleepblock"
        minSdk = 26
        targetSdk = 35
        versionCode = 2
        versionName = "1.0"

        buildConfigField("String", "SUPABASE_URL", "\"${secret("SUPABASE_URL")}\"")
        buildConfigField("String", "SUPABASE_ANON_KEY", "\"${secret("SUPABASE_ANON_KEY")}\"")
        buildConfigField("String", "REVENUECAT_API_KEY", "\"${secret("REVENUECAT_API_KEY")}\"")
        buildConfigField("String", "GOOGLE_WEB_CLIENT_ID", "\"${secret("GOOGLE_WEB_CLIENT_ID")}\"")
    }

    // Only configured when a release keystore exists (see docs/android.md —
    // generated once via keytool, gitignored). Without it, `assembleRelease`
    // still produces an unsigned APK for local inspection, but Play Console
    // will reject it — signing is required to upload.
    val releaseKeystoreFile = secret("RELEASE_STORE_FILE").ifEmpty { null }
        ?.let { rootProject.file(it) }
        ?.takeIf { it.exists() }
    signingConfigs {
        if (releaseKeystoreFile != null) {
            create("release") {
                storeFile = releaseKeystoreFile
                storePassword = secret("RELEASE_STORE_PASSWORD")
                keyAlias = secret("RELEASE_KEY_ALIAS")
                keyPassword = secret("RELEASE_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            if (releaseKeystoreFile != null) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.ui)
    implementation(libs.androidx.ui.graphics)
    implementation(libs.androidx.ui.tooling.preview)
    implementation(libs.androidx.material3)
    implementation(libs.androidx.material.icons.extended)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.okhttp)
    implementation(libs.androidx.glance.appwidget)
    implementation(libs.revenuecat.purchases)
    implementation(libs.androidx.credentials)
    implementation(libs.androidx.credentials.play.services)
    implementation(libs.googleid)
}
