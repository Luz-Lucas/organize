allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// Alguns plugins (ex.: keyboard_height_plugin, do appflowy_editor) ainda
// declaram um compileSdk antigo e quebram o build com as AndroidX atuais.
subprojects {
    plugins.withId("com.android.library") {
        extensions.configure<com.android.build.api.variant.LibraryAndroidComponentsExtension>("androidComponents") {
            finalizeDsl { ext ->
                if ((ext.compileSdk ?: 0) < 36) ext.compileSdk = 36
            }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
