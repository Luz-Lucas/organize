final _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');

/// SHA-256 em hexadecimal minúsculo (64 caracteres), como a tabela `imported_files` exige.
bool isValidSha256(String s) => _sha256Pattern.hasMatch(s);

/// Origem do arquivo (coluna `source` de `imported_files`).
const importSourceSamsungNotes = 'samsung_notes';

/// Um arquivo já sincronizado: o hash do CONTEÚDO é a chave de deduplicação entre aparelhos.
class ImportedFile {
  ImportedFile({
    required this.sha256,
    required this.name,
    required this.sizeBytes,
    this.source = importSourceSamsungNotes,
    this.driveFileId,
    this.noteId,
    this.device,
  }) : assert(isValidSha256(sha256), 'sha256 inválido');

  final String sha256;
  final String name;
  final int sizeBytes;
  final String source;
  final String? driveFileId;
  final String? noteId;
  final String? device;

  /// Sem `user_id`: o servidor preenche com `auth.uid()`.
  Map<String, dynamic> toMap() => {
        'sha256': sha256,
        'name': name,
        'size_bytes': sizeBytes,
        'source': source,
        'drive_file_id': driveFileId,
        'note_id': noteId,
        'device': device,
      };
}
