package dev.organizacional.organizacional

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID

/**
 * Canal `dev.organizacional/samsung_notes`: o que só o Android sabe fazer para a sincronização do Samsung Notes.
 *
 * - `isInstalled` / `open`: o app da Samsung (não há como abrir uma nota específica).
 * - `hasAllFilesAccess` / `requestAllFilesAccess`: "Acesso a todos os arquivos" (Android 11+).
 * - `findFolders`: pastas candidatas (ver [SamsungFolders]).
 * - `pickFolder`: seletor de pasta do sistema (SAF), com a permissão persistida.
 * - `listTree` / `copyToCache`: leitura de uma pasta escolhida pelo seletor.
 * - `deviceName`: fabricante e modelo.
 *
 * Só existe com o app aberto (registrado na MainActivity); a tarefa em segundo plano lê pelo caminho.
 */
class SamsungNotesChannel(private val activity: Activity) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "dev.organizacional/samsung_notes"
        private const val REQUEST_PICK_TREE = 4711
        private const val REQUEST_READ_STORAGE = 4712
        private const val CACHE_DIR = "samsung_sync"
        private const val MAX_AGE_MS = 24L * 60 * 60 * 1000
    }

    private val main = Handler(Looper.getMainLooper())
    private var pendingPick: MethodChannel.Result? = null

    fun attach(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
        Thread { cleanOld() }.start()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isInstalled" -> result.success(launchIntent() != null)
            "open" -> result.success(openApp())
            "hasAllFilesAccess" -> result.success(hasAllFilesAccess())
            "requestAllFilesAccess" -> result.success(requestAllFilesAccess())
            "findFolders" -> background(result) {
                SamsungFolders.find(Environment.getExternalStorageDirectory()).map { it.absolutePath }
            }
            "pickFolder" -> pickFolder(result)
            "listTree" -> {
                val uri = call.argument<String>("uri")
                if (uri == null) result.error("bad_args", "uri ausente", null) else background(result) { listTree(Uri.parse(uri)) }
            }
            "copyToCache" -> {
                val uri = call.argument<String>("uri")
                if (uri == null) result.error("bad_args", "uri ausente", null) else background(result) { copyToCache(Uri.parse(uri)) }
            }
            "deviceName" -> result.success("${Build.MANUFACTURER} ${Build.MODEL}".trim())
            else -> result.notImplemented()
        }
    }

    /** Trabalho de disco fora da thread principal; o resultado volta nela. */
    private fun background(result: MethodChannel.Result, work: () -> Any?) {
        Thread {
            try {
                val value = work()
                main.post { result.success(value) }
            } catch (e: Exception) {
                main.post { result.error("failed", e.message, null) }
            }
        }.start()
    }

    private fun launchIntent(): Intent? = activity.packageManager.getLaunchIntentForPackage(SamsungFolders.PACKAGE)

    private fun openApp(): Boolean {
        val intent = launchIntent() ?: return false
        return try {
            activity.startActivity(intent)
            true
        } catch (e: ActivityNotFoundException) {
            false
        }
    }

    private fun hasAllFilesAccess(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            activity.checkSelfPermission(Manifest.permission.READ_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
        }

    private fun requestAllFilesAccess(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            activity.requestPermissions(arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE), REQUEST_READ_STORAGE)
            return true
        }
        val own = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION, Uri.parse("package:${activity.packageName}"))
        return try {
            activity.startActivity(own)
            true
        } catch (e: ActivityNotFoundException) {
            try {
                activity.startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
                true
            } catch (e2: ActivityNotFoundException) {
                false
            }
        }
    }

    private fun pickFolder(result: MethodChannel.Result) {
        if (pendingPick != null) {
            result.error("busy", "Já existe um seletor de pasta aberto.", null)
            return
        }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(
            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or Intent.FLAG_GRANT_PREFIX_URI_PERMISSION,
        )
        pendingPick = result
        try {
            @Suppress("DEPRECATION")
            activity.startActivityForResult(intent, REQUEST_PICK_TREE)
        } catch (e: ActivityNotFoundException) {
            pendingPick = null
            result.success(null)
        }
    }

    /** Chamado pela MainActivity; devolve true se o resultado era do seletor de pasta. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_PICK_TREE) return false
        val result = pendingPick ?: return true
        pendingPick = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return true
        }
        try {
            activity.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        } catch (e: SecurityException) {
            result.success(null)
            return true
        }
        val label = SamsungFolders.labelFromDocumentId(DocumentsContract.getTreeDocumentId(uri))
        result.success(mapOf("uri" to uri.toString(), "label" to label))
        return true
    }

    /** Arquivos (sem subpastas) do primeiro nível de uma pasta escolhida pelo seletor. */
    private fun listTree(tree: Uri): List<Map<String, Any?>> {
        val docId = DocumentsContract.getTreeDocumentId(tree)
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, docId)
        val columns = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
        )
        val out = mutableListOf<Map<String, Any?>>()
        activity.contentResolver.query(children, columns, null, null, null)?.use { c ->
            while (c.moveToNext()) {
                if (c.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR) continue
                val id = DocumentsContract.buildDocumentUriUsingTree(tree, c.getString(0)).toString()
                out.add(
                    mapOf(
                        "id" to id,
                        "name" to c.getString(1),
                        "size" to (if (c.isNull(3)) 0L else c.getLong(3)),
                        "modified" to (if (c.isNull(4)) 0L else c.getLong(4)),
                    ),
                )
            }
        } ?: throw IllegalStateException("Sem acesso à pasta.")
        return out
    }

    /** Copia o arquivo para o cache do app (o Dart apaga a cópia depois do envio). Null se passar de 100 MB. */
    private fun copyToCache(uri: Uri): String? {
        // Só content:// de outro app (nada de file:// nem providers do próprio pacote).
        if (!ShareGuard.isAcceptableUri(uri.scheme, uri.authority, activity.packageName)) return null
        val folder = File(File(activity.cacheDir, CACHE_DIR), UUID.randomUUID().toString()).apply { mkdirs() }
        val target = File(folder, "arquivo")
        return try {
            val input = activity.contentResolver.openInputStream(uri) ?: run {
                folder.deleteRecursively()
                return null
            }
            val complete = input.use { src -> target.outputStream().use { dst -> ShareGuard.copyLimited(src, dst) } }
            if (!complete) {
                folder.deleteRecursively()
                null
            } else {
                target.absolutePath
            }
        } catch (e: Exception) {
            folder.deleteRecursively()
            null
        }
    }

    private fun cleanOld() {
        val root = File(activity.cacheDir, CACHE_DIR)
        val limit = System.currentTimeMillis() - MAX_AGE_MS
        root.listFiles()?.forEach { if (it.lastModified() < limit) it.deleteRecursively() }
    }
}
