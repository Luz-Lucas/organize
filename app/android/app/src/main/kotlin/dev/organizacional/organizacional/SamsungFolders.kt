package dev.organizacional.organizacional

import java.io.File

/**
 * Onde o Samsung Notes costuma salvar os arquivos exportados. Lógica pura (só java.io), testada com JUnit.
 *
 * Ordem das buscas: pastas fixas conhecidas (as que existirem) e, por fim, qualquer pasta chamada
 * "Samsung Notes" até a profundidade [MAX_DEPTH] sob a raiz do armazenamento.
 * "Download" é uma pasta geral (mistura vários apps): quem escolhe se vale usá-la é o usuário, no Dart.
 */
object SamsungFolders {
    const val PACKAGE = "com.samsung.android.app.notes"
    const val SEARCH_NAME = "Samsung Notes"
    const val MAX_DEPTH = 3

    private val FIXED = listOf(
        "Documents/Samsung Notes",
        "Download/Samsung Notes",
        "Samsung Notes",
        "Documents/Samsung",
        "Download",
    )

    /** Pastas da raiz que não valem a pena varrer (dados de apps, ocultas). */
    private fun skipped(name: String) = name.startsWith(".") || name == "Android"

    fun find(root: File): List<File> {
        if (!root.isDirectory) return emptyList()
        val out = LinkedHashMap<String, File>()
        for (rel in FIXED) {
            val f = File(root, rel)
            if (f.isDirectory) out.putIfAbsent(f.canonicalPath, f)
        }
        // Busca por nível (largura), então as mais rasas vêm primeiro.
        var level = listOf(root)
        for (depth in 1..MAX_DEPTH) {
            val next = mutableListOf<File>()
            for (parent in level) {
                val children = parent.listFiles { f -> f.isDirectory && !skipped(f.name) }?.sortedBy { it.name } ?: continue
                for (child in children) {
                    if (child.name.equals(SEARCH_NAME, ignoreCase = true)) out.putIfAbsent(child.canonicalPath, child)
                    next.add(child)
                }
            }
            level = next
        }
        return out.values.toList()
    }

    /** Nome curto para mostrar de um id de documento do seletor (`primary:Documents/Samsung Notes`). */
    fun labelFromDocumentId(documentId: String): String {
        val rel = documentId.substringAfter(':', "")
        val last = rel.trimEnd('/').substringAfterLast('/')
        return when {
            last.isNotEmpty() -> last
            documentId.startsWith("primary:") -> "Armazenamento interno"
            else -> "pasta"
        }
    }
}
