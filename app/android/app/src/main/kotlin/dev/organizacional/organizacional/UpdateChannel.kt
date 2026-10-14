package dev.organizacional.organizacional

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Canal `dev.organizacional/update`: atualização do app por dentro.
 *
 * - `updatesDir`: a pasta `cache/updates` onde o Dart baixa o APK.
 * - `install(path, promptForPermission)`: abre o APK no instalador do sistema (`ACTION_VIEW` + FileProvider).
 *   Devolve `started`, `needs_permission` (falta liberar "instalar apps desconhecidos"; com
 *   `promptForPermission` abre os ajustes do pacote) ou `failed`. Só aceita `.apk` de dentro da pasta
 *   (ver [UpdateGuard]). Canal separado do `FilesChannel`, que continua restrito ao `drive_cache`.
 */
class UpdateChannel(private val activity: Activity) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "dev.organizacional/update"
    }

    fun attach(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
        // APKs de atualizações anteriores não servem mais (o app já foi trocado ou o download foi abandonado).
        Thread { cleanOld() }.start()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "updatesDir" -> result.success(updatesDir()?.absolutePath)
            "install" -> {
                val path = call.argument<String>("path")
                if (path == null) {
                    result.error("bad_args", "path ausente", null)
                } else {
                    val prompt = call.argument<Boolean>("promptForPermission") ?: true
                    result.success(install(File(path), prompt))
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun updatesDir(): File? {
        val dir = File(activity.cacheDir, UpdateGuard.DIR)
        return if (dir.isDirectory || dir.mkdirs()) dir else null
    }

    private fun install(file: File, promptForPermission: Boolean): String {
        val root = updatesDir() ?: return "failed"
        if (!UpdateGuard.isInstallable(root, file)) return "failed"
        if (!activity.packageManager.canRequestPackageInstalls()) {
            if (promptForPermission) openUnknownSourcesSettings()
            return "needs_permission"
        }
        val uri = try {
            FileProvider.getUriForFile(activity, UpdateGuard.authority(activity.packageName), file)
        } catch (e: IllegalArgumentException) {
            return "failed"
        }
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, UpdateGuard.APK_MIME)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        return try {
            activity.startActivity(intent)
            "started"
        } catch (e: ActivityNotFoundException) {
            "failed"
        } catch (e: SecurityException) {
            "failed"
        }
    }

    /** Ajustes "Instalar apps desconhecidos" já no pacote do Organize. */
    private fun openUnknownSourcesSettings() {
        val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${activity.packageName}"))
        try {
            activity.startActivity(intent)
        } catch (e: ActivityNotFoundException) {
            // sem a tela: o Dart ainda explica o que fazer
        }
    }

    private fun cleanOld() {
        File(activity.cacheDir, UpdateGuard.DIR).listFiles()?.forEach { it.deleteRecursively() }
    }
}
