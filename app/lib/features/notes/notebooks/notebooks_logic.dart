import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../domain/note.dart';
import '../../../domain/space.dart';
import '../search_fold.dart';

/// Pasta "Todos" (todos os cadernos).
const kFolderAll = '__all__';

/// Pasta "Sem pasta" (cadernos sem espaço).
const kFolderNone = '__none__';

enum NotebookSort { recent, name }

/// Pastas = espaços, em dois grupos: matérias e as demais (pastas livres, trabalho, hobby…),
/// cada um por posição e depois por nome.
({List<Space> materias, List<Space> others}) splitFolders(List<Space> spaces) {
  int byOrder(Space a, Space b) {
    final p = a.position.compareTo(b.position);
    return p != 0 ? p : foldSearch(a.name).compareTo(foldSearch(b.name));
  }

  return (
    materias: [for (final s in spaces) if (s.kind == SpaceKind.materia) s]..sort(byOrder),
    others: [for (final s in spaces) if (s.kind != SpaceKind.materia) s]..sort(byOrder),
  );
}

/// Cadernos da pasta [folder] ([kFolderAll], [kFolderNone] ou o id de um espaço), filtrados
/// pela busca (título + texto reconhecido da escrita) e ordenados.
List<Note> selectNotebooks(
  List<Note> notes,
  List<Space> spaces, {
  required String folder,
  required NotebookSort sort,
  String query = '',
  Map<String, String> recognized = const {},
}) {
  final spaceIds = {for (final s in spaces) s.id};
  final q = foldSearch(query);
  bool inFolder(Note n) {
    final loose = n.spaceId == null || !spaceIds.contains(n.spaceId);
    return switch (folder) {
      kFolderAll => true,
      kFolderNone => loose,
      _ => n.spaceId == folder,
    };
  }

  bool matches(Note n) =>
      q.isEmpty || foldSearch(n.title).contains(q) || foldSearch(recognized[n.id] ?? '').contains(q);

  final out = [for (final n in notes) if (n.isNotebook && inFolder(n) && matches(n)) n];
  switch (sort) {
    case NotebookSort.recent:
      out.sort((a, b) {
        final c = (b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0));
        return c != 0 ? c : foldSearch(a.title).compareTo(foldSearch(b.title));
      });
    case NotebookSort.name:
      out.sort((a, b) => foldSearch(a.title).compareTo(foldSearch(b.title)));
  }
  return out;
}

/// "agora", "há 5 min", "há 2 h" nas últimas 24 h; depois "12 out" (com o ano se for outro).
String notebookDateLabel(DateTime? date, DateTime now) {
  if (date == null) return '';
  final diff = now.difference(date);
  if (!diff.isNegative && diff < const Duration(minutes: 1)) return 'agora';
  if (!diff.isNegative && diff < const Duration(hours: 1)) return 'há ${diff.inMinutes} min';
  if (!diff.isNegative && diff < const Duration(hours: 24)) return 'há ${diff.inHours} h';
  final pattern = date.year == now.year ? 'd MMM' : 'd MMM y';
  return DateFormat(pattern, 'pt_BR').format(date).replaceAll('.', '');
}

/// Cores oferecidas para as pastas (fixas: o valor gravado não muda com o tema).
const folderPalette = <Color>[
  Color(0xFFE5484D), // vermelho
  Color(0xFFF76B15), // laranja
  Color(0xFFFFB224), // âmbar
  Color(0xFF30A46C), // verde
  Color(0xFF12A594), // verde-água
  Color(0xFF0091FF), // azul
  Color(0xFF3E63DD), // índigo
  Color(0xFF8E4EC6), // roxo
  Color(0xFFD6409F), // rosa
  Color(0xFF8B8D98), // cinza
];

/// `#RRGGBB` → cor; `null` se vazio ou inválido.
Color? parseFolderColor(String? hex) {
  if (hex == null) return null;
  final m = RegExp(r'^#?([0-9a-fA-F]{6})$').firstMatch(hex.trim());
  if (m == null) return null;
  return Color(0xFF000000 | int.parse(m.group(1)!, radix: 16));
}

String folderColorHex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
