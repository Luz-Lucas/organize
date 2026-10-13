package dev.organizacional.organizacional

import androidx.core.content.FileProvider

/**
 * FileProvider próprio de "Editar no Samsung Notes". Subclasse só para ter um nome único no manifesto:
 * outro plugin que declare o `androidx.core.content.FileProvider` puro não colide na mesclagem.
 */
class SamsungFileProvider : FileProvider()
