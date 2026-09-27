pluginManagement {
    repositories { google(); mavenCentral(); gradlePluginPortal() }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        maven {
            url = uri("https://maven.example.com/releases")
            credentials {
                username = "CANARY_USER"
                password = "CANARY_REPO_PASSWORD"
            }
        }
    }
}
rootProject.name = "fixture-kts"
include(":app", ":lib")
