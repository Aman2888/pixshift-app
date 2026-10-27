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

// Align Java/Kotlin JVM targets across plugins (e.g. flutter_avif: Java 11 vs Kotlin 25).
subprojects {
    fun alignJvmTargets() {
        extensions.findByName("android")?.let { ext ->
            try {
                // Keep plugins in sync with app compileSdk (lifecycle requires 36+).
                try {
                    ext.javaClass.getMethod("setCompileSdkVersion", Int::class.javaPrimitiveType)
                        .invoke(ext, 36)
                } catch (_: Exception) {
                    try {
                        ext.javaClass.getMethod("setCompileSdk", Int::class.javaPrimitiveType)
                            .invoke(ext, 36)
                    } catch (_: Exception) {
                        // Older/newer AGP API shape.
                    }
                }
                val compileOptions =
                    ext.javaClass.getMethod("getCompileOptions").invoke(ext)
                compileOptions.javaClass
                    .getMethod("setSourceCompatibility", JavaVersion::class.java)
                    .invoke(compileOptions, JavaVersion.VERSION_17)
                compileOptions.javaClass
                    .getMethod("setTargetCompatibility", JavaVersion::class.java)
                    .invoke(compileOptions, JavaVersion.VERSION_17)
            } catch (_: Exception) {
                // Non-Android or unexpected extension shape.
            }
        }
        tasks.withType<JavaCompile>().configureEach {
            sourceCompatibility = JavaVersion.VERSION_17.toString()
            targetCompatibility = JavaVersion.VERSION_17.toString()
        }
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions {
                jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
            }
        }
    }

    if (state.executed) {
        alignJvmTargets()
    } else {
        afterEvaluate { alignJvmTargets() }
    }
}

// flutter_avif_android 3.1.0 ships duplicate FlutterAvifPlugin.java + .kt (upstream bug).
subprojects {
    if (name == "flutter_avif_android") {
        pluginManager.withPlugin("com.android.library") {
            extensions.configure<com.android.build.gradle.LibraryExtension>("android") {
                sourceSets.getByName("main") {
                    java.setSrcDirs(listOf("src/main/kotlin"))
                }
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
