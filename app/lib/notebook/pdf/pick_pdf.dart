import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Maior PDF aceito (o arquivo inteiro fica na memória durante a importação).
const int kMaxPdfBytes = 60 * 1024 * 1024;

/// Um PDF escolhido pelo usuário.
class PickedPdf {
  const PickedPdf({required this.bytes, required this.name, this.storedPath});

  final Uint8List bytes;

  /// Nome do arquivo (vira o título do caderno criado a partir dele).
  final String name;

  /// Caminho no Storage, se este PDF já está guardado no caderno (um livro que
  /// vira caderno de escrever): não precisa enviar de novo.
  final String? storedPath;
}

/// Abre o seletor de arquivos do sistema só com PDFs (Android, Linux e Windows).
Future<PickedPdf?> pickPdfFromSystem() async {
  final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf'], withData: true);
  if (res == null || res.files.isEmpty) return null;
  final f = res.files.first;
  var bytes = f.bytes;
  if (bytes == null && f.path != null) bytes = await File(f.path!).readAsBytes();
  if (bytes == null) return null;
  return PickedPdf(bytes: bytes, name: f.name);
}
