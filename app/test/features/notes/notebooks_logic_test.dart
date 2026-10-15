import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:organizacional/domain/note.dart';
import 'package:organizacional/domain/space.dart';
import 'package:organizacional/features/notes/notebooks/notebooks_logic.dart';

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  group('splitFolders', () {
    test('matérias primeiro, depois as outras pastas; cada grupo por posição e nome', () {
      final r = splitFolders(const [
        Space(id: 'g1', name: 'Zeta', position: 0),
        Space(id: 'm2', name: 'Redes', kind: SpaceKind.materia, position: 1),
        Space(id: 'h1', name: 'Fotos', kind: SpaceKind.hobby, position: 2),
        Space(id: 'm1', name: 'Cálculo', kind: SpaceKind.materia, position: 0),
        Space(id: 'm3', name: 'Ágil', kind: SpaceKind.materia, position: 1),
        Space(id: 't1', name: 'Obra', kind: SpaceKind.trabalho, position: 1),
      ]);
      expect(r.materias.map((s) => s.id), ['m1', 'm3', 'm2']);
      expect(r.others.map((s) => s.id), ['g1', 't1', 'h1']);
    });
  });

  group('selectNotebooks', () {
    const spaces = [Space(id: 's1', name: 'A'), Space(id: 's2', name: 'B')];
    final notes = [
      Note(id: 'c1', title: 'Beta', spaceId: 's1', kind: NoteKind.notebook, updatedAt: DateTime(2026, 10, 1)),
      Note(id: 'c2', title: 'alfa', spaceId: 's2', kind: NoteKind.notebook, updatedAt: DateTime(2026, 10, 3)),
      Note(id: 'c3', title: 'Gama', kind: NoteKind.notebook, updatedAt: DateTime(2026, 10, 2)),
      Note(id: 'c4', title: 'Órfão', spaceId: 'apagado', kind: NoteKind.notebook, updatedAt: DateTime(2026, 9, 1)),
      const Note(id: 'n1', title: 'Texto', spaceId: 's1'),
    ];
    List<String> ids(String folder, {NotebookSort sort = NotebookSort.recent, String query = '', Map<String, String> rec = const {}}) =>
        selectNotebooks(notes, spaces, folder: folder, sort: sort, query: query, recognized: rec).map((n) => n.id).toList();

    test('Todos traz só cadernos, mais recentes primeiro', () {
      expect(ids(kFolderAll), ['c2', 'c3', 'c1', 'c4']);
    });
    test('por nome ignora caixa e acento', () {
      expect(ids(kFolderAll, sort: NotebookSort.name), ['c2', 'c1', 'c3', 'c4']);
    });
    test('pasta filtra pelo espaço', () {
      expect(ids('s1'), ['c1']);
    });
    test('Sem pasta inclui espaço inexistente', () {
      expect(ids(kFolderNone), ['c3', 'c4']);
    });
    test('busca no título e no texto reconhecido, sem acento', () {
      expect(ids(kFolderAll, query: 'ORFAO'), ['c4']);
      expect(ids(kFolderAll, query: 'integral', rec: {'c1': 'Regra da Integral'}), ['c1']);
    });
    test('busca vale dentro da pasta aberta', () {
      expect(ids('s2', query: 'beta'), isEmpty);
    });
  });

  group('notebookDateLabel', () {
    final now = DateTime(2026, 10, 13, 12, 0);
    test('relativo nas últimas 24 h', () {
      expect(notebookDateLabel(now.subtract(const Duration(seconds: 20)), now), 'agora');
      expect(notebookDateLabel(now.subtract(const Duration(minutes: 5)), now), 'há 5 min');
      expect(notebookDateLabel(now.subtract(const Duration(hours: 2, minutes: 10)), now), 'há 2 h');
    });
    test('data curta depois disso, com o ano só se for outro', () {
      expect(notebookDateLabel(DateTime(2026, 10, 12, 8), now), '12 out');
      expect(notebookDateLabel(DateTime(2025, 3, 5), now), '5 mar 2025');
    });
    test('sem data não mostra nada', () {
      expect(notebookDateLabel(null, now), '');
    });
  });

  group('cores de pasta', () {
    test('hex ida e volta e valor inválido vira nulo', () {
      expect(parseFolderColor('#E5484D'), const Color(0xFFE5484D));
      expect(parseFolderColor('e5484d'), const Color(0xFFE5484D));
      expect(parseFolderColor('xyz'), isNull);
      expect(parseFolderColor(null), isNull);
      expect(folderColorHex(const Color(0xFF3E63DD)), '#3E63DD');
    });
    test('a paleta tem cores distintas', () {
      expect(folderPalette.toSet().length, folderPalette.length);
      expect(folderPalette.length, greaterThanOrEqualTo(8));
    });
  });
}
