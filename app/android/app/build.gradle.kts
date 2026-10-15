plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.organizacional.organizacional"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // java.time nos widgets (minSdk 24 < 26).
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "dev.organizacional.organizacional"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = maxOf(flutter.minSdkVersion, 26)
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Comprime as bibliotecas nativas dentro do APK (o Android as extrai na
    // instalação): o APK fica bem menor e passa do limite de envio.
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    // A chave que assina o app instalado: o Android só aceita uma atualização assinada
    // com a mesma chave. Por padrão é a ~/.android/debug.keystore do computador que gera
    // os releases; o GitHub Actions aponta ORGANIZE_KEYSTORE para a cópia do segredo
    // ANDROID_KEYSTORE_B64. O caminho é explícito para o build não cair numa chave nova
    // gerada na hora (o que quebrava as atualizações).
    val organizeKeystore = file(
        System.getenv("ORGANIZE_KEYSTORE") ?: "${System.getProperty("user.home")}/.android/debug.keystore",
    )
    signingConfigs {
        create("organize") {
            storeFile = organizeKeystore
            storePassword = System.getenv("ORGANIZE_KEYSTORE_PASSWORD") ?: "android"
            keyAlias = System.getenv("ORGANIZE_KEY_ALIAS") ?: "androiddebugkey"
            keyPassword = System.getenv("ORGANIZE_KEY_PASSWORD") ?: "android"
        }
    }

    buildTypes {
        release {
            // Mantém as classes do ML Kit (reconhecimento de escrita) no R8.
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = signingConfigs.getByName(if (organizeKeystore.isFile) "organize" else "debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
}
