import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/drive_repository.dart';
import '../../data/repository.dart';
import 'samsung_platform.dart';

/// Grava [bytes] em [path], criando a pasta se faltar.
typedef WriteFile = Future<void> Function(String path, List<int> bytes);

Future<void> writeFileToDisk(String path, List<int> bytes) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes, flush: true);
}

/// Quem grava o arquivo baixado (trocado nos testes).
final samsungFileWriterProvider = Provider<WriteFile>((ref) => writeFileToDisk);

enum EditOutcome {
  /// O Samsung Notes recebeu o arquivo.
  opened,

  /// Não baixou ou não gravou: [EditResult.message] explica.
  failed,

  /// Baixou, mas nenhum app abriu o arquivo: oferecer "Abrir no Drive".
  notOpened,
}

class EditResult {
  const EditResult(this.outcome, [this.message]);

  final EditOutcome outcome;
  final String? message;
}

const _maxNameLength = 120;
const _sdocxExt = '.sdocx';

/// Nome seguro para o arquivo no cache: sem separadores, controles nem pontos iniciais; no máximo
/// [_maxNameLength] caracteres e sempre com a extensão `.sdocx`.
String safeSdocxFileName(String name) {
  var n = name.replaceAll(RegExp(r'[\u0000-\u001f\u007f/\\:*?"<>|]'), '_').replaceAll(RegExp(r'\.{2,}'), '.').trim();
  n = n.replaceFirst(RegExp(r'^\.+'), '');
  if (n.isEmpty || n.replaceAll('.', '').isEmpty) return 'nota$_sdocxExt';
  if (!n.toLowerCase().endsWith(_sdocxExt)) n = '$n$_sdocxExt';
  if (n.length > _maxNameLength) {
    final stem = n.substring(0, n.length - _sdocxExt.length);
    n = '${stem.substring(0, _maxNameLength - _sdocxExt.length)}${n.substring(n.length - _sdocxExt.length)}';
  }
  return n;
}

/// "Editar no Samsung Notes": baixa o `.sdocx` do Drive para o cache do app e o entrega ao Samsung Notes,
/// que o importa como uma nota editável.
class SamsungEditor {
  SamsungEditor({required this.drive, required this.platform, WriteFile? writeFile}) : _write = writeFile ?? writeFileToDisk;

  final DriveRepository drive;
  final SamsungNotesPlatform platform;
  final WriteFile _write;

  Future<EditResult> edit({required String fileId, required String fileName}) async {
    final Uint8List bytes;
    try {
      bytes = await drive.download(fileId);
    } on RepositoryException catch (e) {
      return EditResult(EditOutcome.failed, e.message);
    } catch (_) {
      return const EditResult(EditOutcome.failed, 'Não foi possível baixar o arquivo. Tente de novo.');
    }
    const storeFailure = EditResult(EditOutcome.failed, 'Não foi possível guardar o arquivo no aparelho.');
    final String path;
    try {
      final dir = await platform.openDir();
      if (dir == null) return storeFailure;
      path = '$dir/${safeSdocxFileName(fileName)}';
      await _write(path, bytes);
    } catch (_) {
      return storeFailure;
    }
    return await platform.openFile(path) ? const EditResult(EditOutcome.opened) : const EditResult(EditOutcome.notOpened);
  }
}

final samsungEditorProvider = Provider<SamsungEditor>((ref) => SamsungEditor(
      drive: ref.watch(driveRepositoryProvider),
      platform: ref.watch(samsungNotesPlatformProvider),
      writeFile: ref.watch(samsungFileWriterProvider),
    ));
