plugins {
    id("com.android.library")
    id("com.example.plug") version "1.0" + "-SNAPSHOT"
}
val suffix = "-rc1"
android {
    namespace = "com.example.lib"
    defaultConfig {
        versionName = "1.0" + "-SNAPSHOT"
    }
}
dependencies {
    implementation("a:b:1.0" + "-SNAPSHOT")
    implementation("c:d:2.0" + suffix)
}
