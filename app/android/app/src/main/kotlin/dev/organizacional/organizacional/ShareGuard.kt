package dev.organizacional.organizacional

import android.content.Intent
import java.io.InputStream
import java.io.OutputStream

/**
 * Regras de segurança do compartilhamento recebido (ACTION_SEND), sem depender de classes do Android
 * que não existem nos testes JUnit (por isso recebem strings/streams em vez de Uri/ContentResolver).
 */
object ShareGuard {
    /** Teto por arquivo copiado para o cache do app. */
    const val MAX_FILE_BYTES = 100L * 1024 * 1024

    /**
     * Só `content://` de OUTRO app. `file://` (e qualquer outro esquema) deixaria o remetente apontar para
     * arquivos privados do próprio app; e um provider do próprio pacote (inclusive FileProvider/plugins,
     * `<applicationId>` ou `<applicationId>.algo`) expõe esses mesmos arquivos. O Android aceita o prefixo
     * multiusuário `<userId>@autoridade`, que também é removido antes de comparar.
     */
    fun isAcceptableUri(scheme: String?, authority: String?, ownPackage: String): Boolean {
        if (scheme == null || !scheme.equals("content", ignoreCase = true)) return false
        val auth = authority?.substringAfterLast('@')?.trim()?.lowercase()
        if (auth.isNullOrEmpty()) return false
        val own = ownPackage.lowercase()
        return auth != own && !auth.startsWith("$own.")
    }

    /**
     * Copia até [max] bytes. Devolve false (e para de ler) se [input] tiver mais do que isso; o chamador
     * descarta o arquivo parcial.
     */
    fun copyLimited(input: InputStream, output: OutputStream, max: Long = MAX_FILE_BYTES, bufferSize: Int = 64 * 1024): Boolean {
        val buf = ByteArray(bufferSize)
        var total = 0L
        while (true) {
            val n = input.read(buf)
            if (n < 0) return true
            total += n
            if (total > max) return false
            output.write(buf, 0, n)
        }
    }

    /**
     * Tipo MIME concreto do arquivo: [reported] (do provider) ou [fallback] (do intent) quando não têm `*`;
     * senão deduz pela extensão de [fileName] via [byExtension] (ex.: `MimeTypeMap`). Null se nada resolver
     * (o Dart então deduz pelo nome).
     */
    fun resolveMime(reported: String?, fallback: String?, fileName: String, byExtension: (String) -> String?): String? {
        for (candidate in listOf(reported, fallback)) {
            val c = candidate?.trim()
            if (!c.isNullOrEmpty() && '*' !in c && '/' in c) return c
        }
        val ext = fileName.substringAfterLast('.', "").lowercase()
        if (ext.isEmpty()) return null
        return byExtension(ext)?.takeIf { '*' !in it }
    }

    /** O Android reentrega o intent original ao reabrir o app pelo histórico de recentes: não é um novo compartilhamento. */
    fun launchedFromHistory(flags: Int): Boolean = flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0
}
