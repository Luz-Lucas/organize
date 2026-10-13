import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../data/drive_repository.dart';
import '../../data/imported_files_repository.dart';
import '../../data/repository.dart';
import '../../domain/drive.dart';
import '../../domain/ids.dart';
import '../../domain/imported_file.dart';
import '../../domain/local_file.dart';
import '../../domain/note.dart';
import '../../domain/space.dart';
import '../../domain/wikilinks.dart';
import '../../ui/common.dart' show plural;
import '../import/importer.dart' show driveLinkNoteBody, noteStem, plainTextToMarkdown;
import 'samsung_folder.dart';

/// Espaço que recebe as notas-link dos arquivos do Samsung Notes.
const samsungSpaceName = 'Samsung Notes';

/// Caminho no Drive (a partir do Meu Drive) que recebe os arquivos; o servidor acha/cria cada nível.
const samsungDrivePath = ['Organizacional', 'Samsung Notes'];

/// Arquivos modificados há menos que isso ainda podem estar sendo gravados: ficam para a próxima rodada.
const samsungMinFileAge = Duration(seconds: 10);

const _syncableExtensions = {'pdf', 'docx', 'doc', 'txt', 'md', 'png', 'jpg', 'jpeg', 'sdocx'};

String _extension(String name) {
  final i = name.lastIndexOf('.');
  return i <= 0 ? '' : name.substring(i + 1).toLowerCase();
}

/// Só estes formatos são sincronizados (`.sdocx` é a nota editável do Samsung Notes: sobe como binário opaco).
/// Ocultos ficam de fora.
bool isSyncableName(String name) => !name.startsWith('.') && _syncableExtensions.contains(_extension(name));

/// A pasta não pôde ser lida (sem permissão, apagada...). A mensagem já é para o usuário.
class FolderAccessException implements Exception {
  const FolderAccessException(this.message);

  final String message;

  @override
  String toString() => 'FolderAccessException: $message';
}

/// Um arquivo listado na pasta vigiada.
class SyncEntry {
  const SyncEntry({required this.id, required this.name, required this.size, required this.modified});

  /// Identificador opaco para reabrir o arquivo (caminho ou URI).
  final String id;
  final String name;
  final int size;
  final DateTime modified;
}

/// Arquivo aberto para leitura. [close] libera o que foi preciso criar (cópia temporária do SAF).
abstract interface class SyncSource {
  int get size;
  Stream<List<int>> read();
  Future<void> close();
}

abstract interface class FolderFileSystem {
  /// Arquivos (não pastas) do primeiro nível de [folder].
  Future<List<SyncEntry>> list(SamsungFolder folder);

  Future<SyncSource> open(SamsungFolder folder, SyncEntry entry);
}

class SyncResult {
  int uploaded = 0;

  /// Já estavam sincronizados (no registro ou no Drive).
  int skipped = 0;

  /// Formatos que não sincronizamos (`.xlsx`, `.zip`...) ou grandes demais.
  int ignored = 0;

  /// Ainda sendo gravados: ficam para a próxima rodada.
  int pending = 0;
  final errors = <String>[];
  final noteIds = <String>[];

  /// O acesso ao Drive expirou: a rodada foi interrompida.
  bool needsReconnect = false;

  /// Ex.: "12 enviados, 2 ignorados" (+ ", 1 com erro").
  String get text {
    final base = '${plural(uploaded, 'enviado', 'enviados')}, ${plural(ignored, 'ignorado', 'ignorados')}';
    return errors.isEmpty ? base : '$base, ${errors.length} com erro';
  }
}

String _two(int n) => n.toString().padLeft(2, '0');

/// "Aula.pdf" -> "Aula (2026-10-13).pdf".
String nameWithDate(String name, DateTime date) {
  final i = name.lastIndexOf('.');
  final stem = i > 0 ? name.substring(0, i) : name;
  final ext = i > 0 ? name.substring(i) : '';
  return '$stem (${date.year}-${_two(date.month)}-${_two(date.day)})$ext';
}

/// Uma rodada de sincronização: lê a pasta, sobe o que ainda não existe no Drive e cria uma nota-link para cada
/// arquivo novo. Nunca apaga nada, nem no aparelho nem no Drive.
class FolderSync {
  FolderSync({
    required this.repo,
    required this.drive,
    required this.imported,
    required this.fs,
    required this.now,
    this.device,
    this.maxFileBytes = driveWarnUploadBytes,
  });

  final Repository repo;
  final DriveRepository drive;
  final ImportedFilesRepository imported;
  final FolderFileSystem fs;
  final DateTime Function() now;
  final String? device;
  final int maxFileBytes;

  String? _driveFolderId;
  String? _spaceId;
  final _created = <Note>[];
  final _seenShas = <String>{};
  final _usedNames = <String>{};

  Future<SyncResult> run(SamsungFolder folder) async {
    final result = SyncResult();
    final List<SyncEntry> entries;
    try {
      entries = await fs.list(folder);
    } on FolderAccessException catch (e) {
      result.errors.add(e.message);
      return result;
    } catch (_) {
      result.errors.add('Não foi possível ler a pasta.');
      return result;
    }
    entries.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    for (final entry in entries) {
      if (!isSyncableName(entry.name) || entry.size > maxFileBytes) {
        result.ignored++;
        continue;
      }
      if (now().difference(entry.modified) < samsungMinFileAge) {
        result.pending++;
        continue;
      }
      try {
        await _sync(folder, entry, result);
      } on DriveException catch (e) {
        if (e.needsReconnect) {
          result.needsReconnect = true;
          result.errors.add('${entry.name}: ${e.message}');
          return result;
        }
        result.errors.add('${entry.name}: ${e.message}');
      } on RepositoryException catch (e) {
        result.errors.add('${entry.name}: ${e.message}');
      } catch (_) {
        result.errors.add('${entry.name}: não foi possível sincronizar.');
      }
    }
    return result;
  }

  Future<void> _sync(SamsungFolder folder, SyncEntry entry, SyncResult result) async {
    final source = await fs.open(folder, entry);
    try {
      final sha = (await sha256.bind(source.read()).first).toString();
      if (_seenShas.contains(sha) || await imported.has(sha)) {
        _seenShas.add(sha);
        result.skipped++;
        return;
      }
      final onDrive = await drive.findBySha256(sha);
      if (onDrive != null) {
        await imported.record(_record(sha, entry.name, source.size, driveFileId: onDrive.id));
        _seenShas.add(sha);
        result.skipped++;
        return;
      }

      final folderId = _driveFolderId ??= await drive.ensurePath(samsungDrivePath);
      final isNewVersion = _usedNames.contains(entry.name) || await imported.hasName(entry.name);
      final name = isNewVersion ? nameWithDate(entry.name, now()) : entry.name;
      final up = await drive.upload(
        parentId: folderId,
        name: name,
        mimeType: mimeForFileName(entry.name),
        size: source.size,
        data: source.read(),
        appProperties: {'sha256': sha},
      );
      String? text;
      if (isTextFileName(entry.name) && source.size <= maxNoteTextBytes) {
        text = await _readText(source);
      }
      final note = await _createNote(name, text, entry.name, up.webViewLink);
      await imported.record(_record(sha, entry.name, source.size, driveFileId: up.id, noteId: note.id));
      _seenShas.add(sha);
      _usedNames.add(entry.name);
      result.uploaded++;
      result.noteIds.add(note.id);
    } finally {
      await source.close();
    }
  }

  ImportedFile _record(String sha, String name, int size, {String? driveFileId, String? noteId}) =>
      ImportedFile(sha256: sha, name: name, sizeBytes: size, driveFileId: driveFileId, noteId: noteId, device: device);

  Future<String> _readText(SyncSource source) async {
    final bytes = <int>[];
    await for (final chunk in source.read()) {
      bytes.addAll(chunk);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  Future<String> _ensureSpace() async {
    final cached = _spaceId;
    if (cached != null) return cached;
    final spaces = await repo.watchSpaces().first;
    for (final s in spaces) {
      if (normalizeTitle(s.name) == normalizeTitle(samsungSpaceName)) return _spaceId = s.id;
    }
    final space = Space(id: newId(), name: samsungSpaceName, position: spaces.length);
    await repo.upsertSpace(space);
    return _spaceId = space.id;
  }

  /// Nota-link (e, para `.txt`/`.md` pequenos, com o texto do arquivo antes do link).
  Future<Note> _createNote(String driveName, String? text, String originalName, String? link) async {
    final space = await _ensureSpace();
    final linkBody = driveLinkNoteBody(driveName, link);
    String title = driveName;
    String body = linkBody;
    if (text != null) {
      final isMd = _extension(originalName) == 'md';
      final content = isMd ? text.replaceAll('\r\n', '\n').trimRight() : plainTextToMarkdown(text);
      title = noteStem(driveName);
      body = content.isEmpty ? linkBody : '$content\n\n$linkBody';
    }
    final existing = [...await repo.watchNotes().first, ..._created];
    final note = Note(id: newId(), title: uniqueTitle(title, existing), body: body, spaceId: space);
    await repo.upsertNote(note);
    _created.add(note);
    return note;
  }
}
