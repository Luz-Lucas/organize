import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Escolha de pasta no computador (Linux). Injetável para os testes.
abstract interface class DirectoryPickerService {
  /// Caminho da pasta escolhida (null se cancelou).
  Future<String?> pickDirectory();
}

class SystemDirectoryPickerService implements DirectoryPickerService {
  const SystemDirectoryPickerService();

  @override
  Future<String?> pickDirectory() => FilePicker.platform.getDirectoryPath(dialogTitle: 'Pasta dos arquivos do Samsung Notes');
}

final directoryPickerProvider = Provider<DirectoryPickerService>((ref) => const SystemDirectoryPickerService());
