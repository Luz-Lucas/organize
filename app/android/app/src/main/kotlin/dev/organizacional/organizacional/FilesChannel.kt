package dev.organizacional.organizacional

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Canal `dev.organizacional/files`: arquivos do Drive baixados para o aparelho.
 *
 * - `cacheRoot`: a pasta persistente (`filesDir/drive_cache`, que o Android não limpa sozinho) onde o Dart guarda
 *   os arquivos e o índice.
 * - `openFile(path, mime)`: abre o arquivo por `ACTION_VIEW` + FileProvider no app padrão do sistema para o tipo
 *   (ou no seletor do Android). Só aceita arquivos comuns de dentro da pasta (ver [DriveCacheGuard]).
 */
class FilesChannel(private val activity: Activity) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "dev.organizacional/files"

        /** Pastas de versões antigas do app (cache do Samsung Notes), apagadas na primeira execução. */
        private val LEGACY_CACHE_DIRS = listOf("samsung_open", "samsung_sync")
    }

    fun attach(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
        Thread { cleanLegacy() }.start()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "cacheRoot" -> result.success(cacheRoot()?.absolutePath)
            "openFile" -> {
                val path = call.argument<String>("path")
                if (path == null) {
                    result.error("bad_args", "path ausente", null)
                } else {
                    result.success(openFile(File(path), call.argument<String>("mime")))
                }
            }
            else -> result.notImplemented()
        }
    }

    /** Pasta do cache; null se não deu para criá-la. */
    private fun cacheRoot(): File? {
        val dir = File(activity.filesDir, DriveCacheGuard.DIR)
        return if (dir.isDirectory || dir.mkdirs()) dir else null
    }

    private fun openFile(file: File, mime: String?): Boolean {
        val root = cacheRoot() ?: return false
        if (!DriveCacheGuard.isOpenable(root, file)) return false
        val uri = try {
            FileProvider.getUriForFile(activity, DriveCacheGuard.authority(activity.packageName), file)
        } catch (e: IllegalArgumentException) {
            return false
        }
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, DriveCacheGuard.safeMime(mime))
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        return try {
            activity.startActivity(intent)
            true
        } catch (e: ActivityNotFoundException) {
            false
        } catch (e: SecurityException) {
            false
        }
    }

    private fun cleanLegacy() {
        for (name in LEGACY_CACHE_DIRS) File(activity.cacheDir, name).deleteRecursively()
    }
}
