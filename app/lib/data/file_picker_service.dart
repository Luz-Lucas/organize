import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/local_file.dart';

/// Escolha de arquivos do aparelho. Injetável para os testes.
abstract interface class FilePickerService {
  /// Arquivos escolhidos (vazio se o usuário cancelou).
  Future<List<LocalFile>> pickFiles({bool multiple = true});
}

/// Usa o seletor do sistema (Android e Linux).
class SystemFilePickerService implements FilePickerService {
  const SystemFilePickerService();

  @override
  Future<List<LocalFile>> pickFiles({bool multiple = true}) async {
    final res = await FilePicker.platform.pickFiles(allowMultiple: multiple, withData: false);
    if (res == null) return const [];
    return [
      for (final f in res.files)
        if (f.path != null) LocalFile(name: f.name, path: f.path, size: f.size),
    ];
  }
}

final filePickerProvider = Provider<FilePickerService>((ref) => const SystemFilePickerService());
