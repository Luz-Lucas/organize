package dev.organizacional.organizacional

import java.io.File

/**
 * Regras do "Editar no Samsung Notes" sem depender de classes do Android (testadas com JUnit):
 * só arquivos `.sdocx` de dentro de `cache/samsung_open/` são entregues ao outro app.
 */
object SamsungOpenGuard {
    /** Pasta (dentro de `cacheDir`) coberta pelo `file_paths.xml`; o Dart grava aqui o arquivo baixado. */
    const val DIR = "samsung_open"

    /** Binário opaco: o Samsung Notes reconhece o `.sdocx` pelo conteúdo e pelo nome. Sem curingas. */
    const val MIME = "application/octet-stream"

    private const val EXTENSION = ".sdocx"

    /** Autoridade do FileProvider declarado no manifesto (`${applicationId}.samsung_files`). */
    fun authority(applicationId: String): String = "$applicationId.samsung_files"

    /** Tenta primeiro direto no Samsung Notes (null = sem pacote fixo, ou seja, o seletor do sistema). */
    fun packageAttempts(): List<String?> = listOf(SamsungFolders.PACKAGE, null)

    /** [file] está estritamente dentro de [root], resolvendo `..` e links simbólicos. */
    fun isInside(root: File, file: File): Boolean {
        return try {
            val base = root.canonicalFile
            val target = file.canonicalFile
            target != base && target.path.startsWith(base.path + File.separator)
        } catch (e: java.io.IOException) {
            false
        }
    }

    /** Existe, é arquivo comum `.sdocx` e está dentro de [root]. */
    fun isOpenable(root: File, file: File): Boolean =
        file.name.lowercase().endsWith(EXTENSION) && isInside(root, file) && file.canonicalFile.isFile
}
