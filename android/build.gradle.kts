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
subprojects {
    project.evaluationDependsOn(":app")
}

subprojects {
    plugins.withId("com.android.library") {
        project.extensions.configure<com.android.build.gradle.LibraryExtension>("android") {
            compileSdk = 36
            if (namespace == null) {
                namespace = project.group.toString()
            }
        }
    }
    
    val configureAndroid = Action<Project> {
        if (hasProperty("android")) {
            val android = extensions.getByName("android")
            try {
                val compileSdkVersionMethod = android.javaClass.getMethod("compileSdkVersion", Int::class.javaPrimitiveType)
                compileSdkVersionMethod.invoke(android, 36)
            } catch (e: Exception) {
                try {
                    val compileSdkProperty = android.javaClass.getMethod("setCompileSdk", Integer::class.java)
                    compileSdkProperty.invoke(android, 36)
                } catch (ex: Exception) {
                    // Ignore
                }
            }
        }
    }
    
    if (state.executed) {
        configureAndroid.execute(this)
    } else {
        afterEvaluate {
            configureAndroid.execute(this)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
