package dev.organizacional.organizacional

import java.io.File

/**
 * Regras de "instalar atualização" sem depender de classes do Android (testadas com JUnit): só um arquivo `.apk`
 * comum, de dentro de `cache/updates/`, é entregue ao instalador do sistema. Reusa a checagem de caminho do
 * [DriveCacheGuard] (canonicaliza, recusa `..` e links simbólicos), mas com a raiz e o tipo próprios das
 * atualizações: o canal de arquivos do Drive continua restrito a `drive_cache`.
 */
object UpdateGuard {
    /** Pasta (dentro de `cacheDir`) onde o Dart baixa o APK; coberta pelo `file_paths.xml`. */
    const val DIR = "updates"

    const val APK_MIME = "application/vnd.android.package-archive"

    /** Autoridade do FileProvider declarado no manifesto (a mesma `${applicationId}.drive_files`). */
    fun authority(applicationId: String): String = DriveCacheGuard.authority(applicationId)

    /** [file] é um `.apk` comum estritamente dentro de [root], sem `..` nem links simbólicos no caminho. */
    fun isInstallable(root: File, file: File): Boolean =
        file.name.endsWith(".apk", ignoreCase = true) && file.name.length > ".apk".length &&
            DriveCacheGuard.isOpenable(root, file)
}
