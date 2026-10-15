package dev.organizacional.organizacional

import androidx.core.content.FileProvider

/**
 * FileProvider próprio dos arquivos baixados do Drive (`files/drive_cache/`). Subclasse só para ter um nome único
 * no manifesto: outro plugin que declare o `androidx.core.content.FileProvider` puro não colide na mesclagem.
 */
class DriveFileProvider : FileProvider()
