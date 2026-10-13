import '../../data/drive_repository.dart';
import '../../data/repository.dart';
import '../../domain/drive.dart';
import '../../domain/ids.dart';
import '../../domain/local_file.dart';
import '../../domain/note.dart';
import '../../domain/space.dart';
import '../../domain/wikilinks.dart';
import '../../ui/common.dart' show plural;

/// Espaço padrão das notas criadas por importação/compartilhamento.
const importSpaceName = 'Importadas';

/// Pasta do Drive (dentro de "Organizacional") que recebe os arquivos importados.
const importFolderName = 'Importados';

const _maxTitle = 80;
const _defaultTitle = 'Nota importada';

final _blockStart = RegExp(r'^(\s*)([#>*+\-]|\d+[.)])(?=\s)', multiLine: true);

/// Texto simples -> Markdown seguro: cada linha vira um parágrafo e marcas de bloco
/// no começo da linha (`#`, `-`, `1.`...) são escapadas para não virarem formatação.
String plainTextToMarkdown(String text) {
  final lines = [
    for (final l in text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n'))
      if (l.trim().isNotEmpty) l.trimRight(),
  ];
  return lines
      .map((l) => l.replaceFirstMapped(_blockStart, (m) {
            final mark = m.group(2)!;
            final esc = RegExp(r'^\d').hasMatch(mark)
                ? '${mark.substring(0, mark.length - 1)}\\${mark.substring(mark.length - 1)}'
                : '\\$mark';
            return '${m.group(1)}$esc';
          }))
      .join('\n\n');
}

/// (título, corpo em Markdown): título = primeira linha (até 80 caracteres), corpo = o resto.
(String, String) splitSharedText(String text) {
  final lines = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  final i = lines.indexWhere((l) => l.trim().isNotEmpty);
  if (i < 0) return (_defaultTitle, '');
  final first = lines[i].trim();
  var title = first;
  final rest = <String>[];
  if (first.length > _maxTitle) {
    title = first.substring(0, _maxTitle).trimRight();
    rest.add(first.substring(_maxTitle));
  }
  rest.addAll(lines.skip(i + 1));
  return (title, plainTextToMarkdown(rest.join('\n')));
}

String _stem(String name) {
  final i = name.lastIndexOf('.');
  return i > 0 ? name.substring(0, i) : name;
}

class ImportSummary {
  int notes = 0;
  int files = 0;
  final errors = <String>[];
  final noteIds = <String>[];

  /// Ex.: "12 notas criadas, 3 arquivos enviados" (+ ", 1 com erro").
  String get text {
    final base = '${plural(notes, 'nota criada', 'notas criadas')}, ${plural(files, 'arquivo enviado', 'arquivos enviados')}';
    return errors.isEmpty ? base : '$base, ${errors.length} com erro';
  }
}

/// Cria notas a partir de texto e arquivos recebidos (compartilhamento do Android e importação em lote).
class Importer {
  Importer({required this.repo, required this.drive, required this.driveState});

  final Repository repo;
  final DriveRepository drive;
  final DriveState? driveState;

  String? _folderId;
  final _created = <Note>[];

  bool get driveReady => driveState?.status == DriveStatus.ok && (driveState?.rootFolderId ?? '').isNotEmpty;

  /// Id do espaço "Importadas"; cria se não existir.
  Future<String> ensureImportSpace() async {
    final spaces = await repo.watchSpaces().first;
    for (final s in spaces) {
      if (normalizeTitle(s.name) == normalizeTitle(importSpaceName)) return s.id;
    }
    final space = Space(id: newId(), name: importSpaceName, position: spaces.length);
    await repo.upsertSpace(space);
    return space.id;
  }

  Future<Note> _createNote(String title, String body, String? spaceId) async {
    final existing = [...await repo.watchNotes().first, ..._created];
    final note = Note(id: newId(), title: uniqueTitle(title, existing), body: body, spaceId: spaceId);
    await repo.upsertNote(note);
    _created.add(note);
    return note;
  }

  /// Texto compartilhado -> nota. Sem [spaceId] usa (e cria se preciso) o espaço "Importadas".
  Future<Note> saveText(String text, {String? spaceId}) async {
    final target = spaceId ?? await ensureImportSpace();
    final (title, body) = splitSharedText(text);
    return _createNote(title, body, target);
  }

  Future<String> _importFolder() async {
    final cached = _folderId;
    if (cached != null) return cached;
    final folder = await drive.ensureFolder(driveState!.rootFolderId!, importFolderName);
    return _folderId = folder.id;
  }

  /// `.txt`/`.md` viram notas; o resto vai ao Drive e ganha uma nota com o link.
  /// Falha de um arquivo não interrompe os outros: vira item em [ImportSummary.errors].
  Future<ImportSummary> importFiles(
    List<LocalFile> files, {
    String? spaceId,
    void Function(int done, int total)? onProgress,
  }) async {
    final summary = ImportSummary();
    String? space = spaceId;
    var done = 0;
    for (final file in files) {
      try {
        space ??= await ensureImportSpace();
        if (isTextFileName(file.name)) {
          final raw = await file.readAsString();
          final isMd = file.name.toLowerCase().endsWith('.md');
          final note = await _createNote(_stem(file.name), isMd ? raw.replaceAll('\r\n', '\n').trimRight() : plainTextToMarkdown(raw), space);
          summary
            ..notes += 1
            ..noteIds.add(note.id);
        } else {
          if (!driveReady) {
            throw const RepositoryException('Google Drive não conectado.');
          }
          final up = await drive.upload(
            parentId: await _importFolder(),
            name: file.name,
            mimeType: file.mimeType,
            size: file.size,
            data: file.openRead(),
          );
          summary.files += 1;
          final link = up.webViewLink;
          final body = link == null ? 'Arquivo enviado ao Google Drive: ${file.name}' : 'Arquivo no Google Drive: [${file.name}]($link)';
          final note = await _createNote(file.name, body, space);
          summary
            ..notes += 1
            ..noteIds.add(note.id);
        }
      } on RepositoryException catch (e) {
        summary.errors.add('${file.name}: ${e.message}');
      } catch (_) {
        summary.errors.add('${file.name}: não foi possível importar.');
      }
      onProgress?.call(++done, files.length);
    }
    return summary;
  }
}
