package dev.organizacional.organizacional

import java.io.File
import java.io.IOException
import java.nio.file.Files

/**
 * Regras de "abrir arquivo do Drive" sem depender de classes do Android (testadas com JUnit): só arquivos comuns
 * de dentro de `files/drive_cache/` são entregues ao outro app. O caminho é canonicalizado (resolve `..`), não
 * pode sair da pasta e nenhum componente dele (nem o próprio arquivo) pode ser link simbólico.
 */
object DriveCacheGuard {
    /** Pasta (dentro de `filesDir`) coberta pelo `file_paths.xml`; o Dart guarda aqui os arquivos baixados. */
    const val DIR = "drive_cache"

    /** Binário opaco: quando o tipo não é confiável, o app que abre decide pelo conteúdo. Sem curingas. */
    const val FALLBACK_MIME = "application/octet-stream"

    private val MIME_RE = Regex("^[a-z0-9][a-z0-9!#$&^_.+-]*/[a-z0-9][a-z0-9!#$&^_.+-]*$")

    /** Autoridade do FileProvider declarado no manifesto (`${applicationId}.drive_files`). */
    fun authority(applicationId: String): String = "$applicationId.drive_files"

    /** O tipo pedido, em minúsculas, se for um `tipo/subtipo` simples; senão binário opaco (nunca curinga). */
    fun safeMime(mime: String?): String {
        val m = mime?.trim()?.lowercase() ?: return FALLBACK_MIME
        return if (MIME_RE.matches(m)) m else FALLBACK_MIME
    }

    /** [file] está estritamente dentro de [root], sem `..` e sem links simbólicos no caminho. */
    fun isInside(root: File, file: File): Boolean {
        return try {
            val rootPath = root.toPath().toAbsolutePath().normalize()
            val filePath = file.toPath().toAbsolutePath().normalize()
            if (filePath == rootPath || !filePath.startsWith(rootPath)) return false
            // Nenhum componente entre a raiz e o arquivo (inclusive ele) pode ser link.
            var current = rootPath
            for (segment in rootPath.relativize(filePath)) {
                current = current.resolve(segment)
                if (Files.isSymbolicLink(current)) return false
            }
            // Cinto e suspensório: o caminho real também fica dentro da raiz real.
            val base = root.canonicalFile
            val target = file.canonicalFile
            target != base && target.path.startsWith(base.path + File.separator)
        } catch (e: IOException) {
            false
        } catch (e: SecurityException) {
            false
        }
    }

    /** Existe, é arquivo comum (não link, não pasta) e está dentro de [root]. */
    fun isOpenable(root: File, file: File): Boolean = isInside(root, file) && file.isFile
}
