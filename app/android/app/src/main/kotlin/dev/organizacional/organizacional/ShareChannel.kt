package dev.organizacional.organizacional

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID

/**
 * Canal `dev.organizacional/share`: recebe ACTION_SEND / ACTION_SEND_MULTIPLE (qualquer app).
 *
 * Os arquivos chegam como `content://` temporários; aqui são copiados para `cacheDir/shared/<id>/<nome>`
 * (fora da thread principal) e o Dart recebe só caminhos locais. Depois do envio ao Drive o Dart não precisa
 * mais deles; entradas com mais de 24 h são apagadas ao abrir o app.
 *
 * - App fechado: o Dart chama `getInitialShare` (devolve uma vez e esquece).
 * - App aberto (`onNewIntent`): o Kotlin chama `onShare` no Dart.
 */
class ShareChannel(private val activity: Activity) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "dev.organizacional/share"
        private const val DIR = "shared"
        private const val MAX_AGE_MS = 24L * 60 * 60 * 1000
    }

    private lateinit var channel: MethodChannel
    private val main = Handler(Looper.getMainLooper())

    private var initial: Map<String, Any?>? = null
    private var initialPending = false
    private var initialResult: MethodChannel.Result? = null

    fun attach(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, CHANNEL)
        channel.setMethodCallHandler(this)
        Thread { cleanOld() }.start()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getInitialShare" -> {
                val ready = initial
                when {
                    ready != null -> {
                        initial = null
                        result.success(ready)
                    }
                    initialPending -> initialResult = result
                    else -> result.success(null)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun isShare(intent: Intent) =
        intent.action == Intent.ACTION_SEND || intent.action == Intent.ACTION_SEND_MULTIPLE

    /** Trata um intent de compartilhamento (ignora qualquer outro). */
    fun handleIntent(intent: Intent?, isInitial: Boolean) {
        if (intent == null || !isShare(intent)) return
        if (isInitial) initialPending = true
        Thread {
            val payload = try {
                build(intent)
            } catch (e: Exception) {
                mapOf<String, Any?>("text" to null, "subject" to null, "files" to emptyList<Any>())
            }
            main.post { deliver(payload, isInitial) }
        }.start()
    }

    private fun deliver(payload: Map<String, Any?>, isInitial: Boolean) {
        if (isInitial) {
            initialPending = false
            val waiting = initialResult
            if (waiting != null) {
                initialResult = null
                waiting.success(payload)
            } else {
                initial = payload
            }
        } else {
            channel.invokeMethod("onShare", payload)
        }
    }

    @Suppress("DEPRECATION")
    private fun streams(intent: Intent): List<Uri> {
        val out = LinkedHashSet<Uri>()
        if (intent.action == Intent.ACTION_SEND_MULTIPLE) {
            val list = if (Build.VERSION.SDK_INT >= 33) {
                intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
            }
            list?.let { out.addAll(it) }
        } else {
            val one = if (Build.VERSION.SDK_INT >= 33) {
                intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
            }
            one?.let { out.add(it) }
        }
        val clip = intent.clipData
        if (out.isEmpty() && clip != null) {
            for (i in 0 until clip.itemCount) clip.getItemAt(i).uri?.let { out.add(it) }
        }
        return out.toList()
    }

    private fun build(intent: Intent): Map<String, Any?> {
        val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
        val subject = intent.getStringExtra(Intent.EXTRA_SUBJECT)
        val files = streams(intent).mapNotNull { copy(it, intent.type) }
        return mapOf("text" to text, "subject" to subject, "files" to files)
    }

    private fun displayName(uri: Uri): String {
        if (uri.scheme == "content") {
            activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                if (c.moveToFirst()) {
                    val i = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (i >= 0 && !c.isNull(i)) return c.getString(i)
                }
            }
        }
        return uri.lastPathSegment?.substringAfterLast('/') ?: "arquivo"
    }

    private fun copy(uri: Uri, fallbackMime: String?): Map<String, Any?>? {
        // Só content:// de outro app: nada de file:// nem providers do próprio pacote (arquivos privados).
        if (!ShareGuard.isAcceptableUri(uri.scheme, uri.authority, activity.packageName)) return null
        var dir: File? = null
        return try {
            val name = displayName(uri).replace(Regex("[\\\\/:*?\"<>|\\u0000-\\u001f]"), "_").ifBlank { "arquivo" }
                .let { if (it == "." || it == "..") "arquivo" else it }
            val folder = File(File(activity.cacheDir, DIR), UUID.randomUUID().toString()).apply { mkdirs() }
            dir = folder
            val target = File(folder, name)
            val input = activity.contentResolver.openInputStream(uri) ?: run {
                folder.deleteRecursively()
                return null
            }
            val complete = input.use { src -> target.outputStream().use { dst -> ShareGuard.copyLimited(src, dst) } }
            if (!complete) {
                // Passou de 100 MB: descarta o que já tinha sido copiado.
                folder.deleteRecursively()
                return null
            }
            mapOf(
                "path" to target.absolutePath,
                "name" to name,
                "mimeType" to ShareGuard.resolveMime(
                    activity.contentResolver.getType(uri),
                    fallbackMime,
                    name,
                ) { MimeTypeMap.getSingleton().getMimeTypeFromExtension(it) },
                "size" to target.length(),
            )
        } catch (e: Exception) {
            dir?.deleteRecursively()
            null
        }
    }

    private fun cleanOld() {
        val root = File(activity.cacheDir, DIR)
        val limit = System.currentTimeMillis() - MAX_AGE_MS
        root.listFiles()?.forEach { if (it.lastModified() < limit) it.deleteRecursively() }
    }
}
