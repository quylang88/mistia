pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "MistiaAndroid"

include(
    ":app",
    ":core:model",
    ":core:database",
    ":core:network",
    ":core:sync",
    ":core:auth",
    ":core:designsystem",
    ":core:testing",
    ":feature:overview",
    ":feature:transactions",
    ":feature:planning",
    ":feature:management",
    ":feature:family",
    ":feature:investment",
    ":feature:notifications",
    ":feature:settings",
)
