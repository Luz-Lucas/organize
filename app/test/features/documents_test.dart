import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/file_picker_service.dart';
import 'package:organizacional/data/memory_drive_repository.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/drive.dart';
import 'package:organizacional/domain/local_file.dart';
import 'package:organizacional/features/documents/documents_screen.dart';
import 'package:organizacional/features/more/more_screen.dart';
import 'package:organizacional/features/settings/settings_screen.dart';

import '../helpers.dart';

const _phone = Size(400, 800);

class _FakePicker implements FilePickerService {
  _FakePicker(this.files);
  final List<LocalFile> files;
  int calls = 0;
  @override
  Future<List<LocalFile>> pickFiles({bool multiple = true}) async {
    calls++;
    return files;
  }
}

Future<void> _pump(
  WidgetTester tester,
  MemoryDriveRepository drive, {
  FilePickerService? picker,
  Future<bool> Function(Uri)? openLink,
  String location = '/documentos',
}) =>
    pumpApp(tester, MemoryRepository(), driveRepo: drive, filePicker: picker, openLink: openLink, location: location, size: _phone);

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

Future<void> _back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

void main() {
  group('estados', () {
    testWidgets('não conectado explica e leva aos Ajustes', (tester) async {
      final drive = MemoryDriveRepository(state: const DriveState());
      await _pump(tester, drive);
      expect(find.byKey(const Key('docs-not-connected')), findsOneWidget);
      await _tap(tester, 'docs-open-settings');
      expect(find.byType(SettingsScreen), findsOneWidget);
    });

    testWidgets('acesso expirado oferece reconectar', (tester) async {
      final drive = MemoryDriveRepository(state: const DriveState(status: DriveStatus.authRequired, rootFolderId: 'org-root'));
      await _pump(tester, drive);
      expect(find.byKey(const Key('docs-reconnect')), findsOneWidget);
      expect(find.textContaining('expirou'), findsOneWidget);
    });

    testWidgets('falha ao listar mostra erro com "Tentar de novo"', (tester) async {
      final drive = MemoryDriveRepository()..failActions = true;
      await _pump(tester, drive);
      expect(find.byKey(const Key('docs-error')), findsOneWidget);
      drive.failActions = false;
      drive.addFile('a.pdf', drive.rootFolderId);
      await _tap(tester, 'docs-retry');
      expect(find.text('a.pdf'), findsOneWidget);
      expect(find.byKey(const Key('docs-error')), findsNothing);
    });

    testWidgets('a lista vazia diz que a pasta está vazia', (tester) async {
      await _pump(tester, MemoryDriveRepository());
      expect(find.byKey(const Key('docs-empty')), findsOneWidget);
    });
  });

  group('navegação', () {
    testWidgets('lista a raiz Organizacional: pastas primeiro, com tamanho', (tester) async {
      final drive = MemoryDriveRepository();
      drive.addFile('Edital.pdf', drive.rootFolderId, size: 2048);
      drive.addFolder('Provas', drive.rootFolderId);
      await _pump(tester, drive);
      expect(find.byKey(const Key('docs-crumb-0')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('docs-crumb-0')), matching: find.text('Organizacional')), findsOneWidget);
      final y1 = tester.getTopLeft(find.text('Provas')).dy;
      final y2 = tester.getTopLeft(find.text('Edital.pdf')).dy;
      expect(y1, lessThan(y2));
      expect(find.textContaining('2,0 KB'), findsOneWidget);
    });

    testWidgets('entrar na pasta mostra a trilha; voltar do sistema sobe um nível; na raiz fecha a tela', (tester) async {
      final drive = MemoryDriveRepository();
      final provas = drive.addFolder('Provas', drive.rootFolderId);
      final p1 = drive.addFolder('Prova 1', provas.id);
      drive.addFile('gabarito.pdf', p1.id);
      await _pump(tester, drive, location: '/mais');
      await tester.tap(find.byKey(const ValueKey('more-/documentos')));
      await tester.pumpAndSettle();
      expect(find.byType(DocumentsScreen), findsOneWidget);

      await tester.tap(find.text('Provas'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Prova 1'));
      await tester.pumpAndSettle();
      expect(find.text('gabarito.pdf'), findsOneWidget);
      expect(find.byKey(const Key('docs-crumb-2')), findsOneWidget);

      await _back(tester);
      expect(find.text('Prova 1'), findsOneWidget);
      expect(find.text('gabarito.pdf'), findsNothing);
      expect(find.byType(DocumentsScreen), findsOneWidget);

      await _back(tester);
      expect(find.text('Provas'), findsOneWidget); // volta a ser item da raiz
      expect(find.byType(DocumentsScreen), findsOneWidget);
      expect(find.byKey(const Key('docs-crumb-1')), findsNothing);

      await _back(tester); // na raiz: fecha a tela e volta para "Mais"
      expect(find.byType(DocumentsScreen), findsNothing);
      expect(find.byType(MoreScreen), findsOneWidget);
    });

    testWidgets('a seta do topo sobe uma pasta e tocar numa migalha vai direto a ela', (tester) async {
      final drive = MemoryDriveRepository();
      final a = drive.addFolder('A', drive.rootFolderId);
      final b = drive.addFolder('B', a.id);
      drive.addFolder('C', b.id);
      await _pump(tester, drive);
      await tester.tap(find.text('A'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('B'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('docs-crumb-2')), findsOneWidget);
      await _tap(tester, 'docs-back');
      expect(find.byKey(const Key('docs-crumb-2')), findsNothing);
      await tester.tap(find.byKey(const Key('docs-crumb-0')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('docs-crumb-1')), findsNothing);
      expect(find.text('A'), findsOneWidget);
    });

    testWidgets('sem pilha, a seta de voltar vai para Mais', (tester) async {
      await _pump(tester, MemoryDriveRepository());
      await _tap(tester, 'docs-back');
      expect(find.byType(MoreScreen), findsOneWidget);
    });

    testWidgets('alternar entre Organizacional e Meu Drive', (tester) async {
      final drive = MemoryDriveRepository();
      drive.addFile('dentro.pdf', drive.rootFolderId);
      await _pump(tester, drive);
      await _tap(tester, 'docs-root-my');
      expect(find.descendant(of: find.byKey(const Key('docs-crumb-0')), matching: find.text('Meu Drive')), findsOneWidget);
      expect(find.text('Organizacional'), findsWidgets);
      expect(find.text('dentro.pdf'), findsNothing);
      await _tap(tester, 'docs-root-org');
      expect(find.text('dentro.pdf'), findsOneWidget);
    });

    testWidgets('busca mostra resultados e limpar volta à pasta', (tester) async {
      final drive = MemoryDriveRepository();
      final p = drive.addFolder('Provas', drive.rootFolderId);
      drive.addFile('Edital Concurso.pdf', p.id);
      drive.addFile('outro.txt', drive.rootFolderId);
      await _pump(tester, drive);
      await tester.enterText(find.byKey(const Key('docs-search')), 'edital');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text('Edital Concurso.pdf'), findsOneWidget);
      expect(find.text('outro.txt'), findsNothing);
      // o botão voltar do sistema limpa a busca antes de sair da tela
      await _back(tester);
      expect(find.text('outro.txt'), findsOneWidget);
      expect(find.byType(DocumentsScreen), findsOneWidget);
    });

    testWidgets('abrir um arquivo usa o link do Drive', (tester) async {
      final opened = <Uri>[];
      final drive = MemoryDriveRepository();
      final f = drive.addFile('Aula.pdf', drive.rootFolderId);
      await _pump(tester, drive, openLink: (u) async {
        opened.add(u);
        return true;
      });
      await tester.tap(find.text('Aula.pdf'));
      await tester.pumpAndSettle();
      expect(opened.single.toString(), f.webViewLink);
    });
  });

  group('ações', () {
    testWidgets('nova pasta', (tester) async {
      final drive = MemoryDriveRepository();
      await _pump(tester, drive);
      await _tap(tester, 'docs-fab');
      await _tap(tester, 'docs-new-folder');
      await tester.enterText(find.byKey(const Key('doc-folder-field')), 'Provas 2026');
      await _tap(tester, 'doc-folder-ok');
      expect(find.text('Provas 2026'), findsOneWidget);
      expect((await drive.list()).items.single.name, 'Provas 2026');
    });

    testWidgets('renomear pelo menu e pelo toque longo', (tester) async {
      final drive = MemoryDriveRepository();
      final f = drive.addFile('velho.pdf', drive.rootFolderId);
      await _pump(tester, drive);
      await _tap(tester, 'doc-menu-${f.id}');
      await _tap(tester, 'doc-act-rename');
      await tester.enterText(find.byKey(const Key('doc-rename-field')), 'novo.pdf');
      await _tap(tester, 'doc-rename-ok');
      expect(find.text('novo.pdf'), findsOneWidget);
      expect(find.text('velho.pdf'), findsNothing);

      await tester.longPress(find.text('novo.pdf'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('doc-actions')), findsOneWidget);
    });

    testWidgets('mover para outra pasta', (tester) async {
      final drive = MemoryDriveRepository();
      final dest = drive.addFolder('Destino', drive.rootFolderId);
      final f = drive.addFile('mover.pdf', drive.rootFolderId);
      await _pump(tester, drive);
      await _tap(tester, 'doc-menu-${f.id}');
      await _tap(tester, 'doc-act-move');
      expect(find.byKey(const Key('doc-move-dialog')), findsOneWidget);
      await tester.tap(find.byKey(Key('picker-folder-${dest.id}')));
      await tester.pumpAndSettle();
      await _tap(tester, 'doc-move-here');
      expect(find.text('mover.pdf'), findsNothing);
      expect((await drive.list(folderId: dest.id)).items.single.name, 'mover.pdf');
    });

    testWidgets('lixeira com desfazer restaura', (tester) async {
      final drive = MemoryDriveRepository();
      final f = drive.addFile('apagar.pdf', drive.rootFolderId);
      await _pump(tester, drive);
      await _tap(tester, 'doc-menu-${f.id}');
      await _tap(tester, 'doc-act-trash');
      expect(find.text('apagar.pdf'), findsNothing);
      expect(find.textContaining('lixeira'), findsOneWidget);
      await tester.tap(find.text('Desfazer'));
      await tester.pumpAndSettle();
      expect(find.text('apagar.pdf'), findsOneWidget);
    });

    testWidgets('compartilhar: liga o link, copia, convida por e-mail e remove o acesso', (tester) async {
      final drive = MemoryDriveRepository();
      final f = drive.addFile('Notas.pdf', drive.rootFolderId);
      String? clip;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') clip = (call.arguments as Map)['text'] as String?;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await _pump(tester, drive);
      await _tap(tester, 'doc-menu-${f.id}');
      await _tap(tester, 'doc-act-share');
      expect(find.byKey(const Key('doc-share-sheet')), findsOneWidget);

      await _tap(tester, 'doc-link-switch');
      expect((await drive.permissions(f.id)).any((p) => p.isAnyone), isTrue);
      await _tap(tester, 'doc-link-copy');
      expect(clip, f.webViewLink);
      await tester.pump(const Duration(seconds: 5)); // some o aviso "Link copiado."
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('doc-share-email')), 'isso não é e-mail');
      await _tap(tester, 'doc-share-invite');
      expect(find.text('E-mail inválido.'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('doc-share-email')), 'amiga@exemplo.com');
      await _tap(tester, 'doc-share-role');
      await tester.tap(find.text('Editor').last);
      await tester.pumpAndSettle();
      await _tap(tester, 'doc-share-invite');
      final invited = (await drive.permissions(f.id)).firstWhere((p) => p.email == 'amiga@exemplo.com');
      expect(invited.role, 'writer');
      expect(find.text('amiga@exemplo.com'), findsOneWidget);

      await _tap(tester, 'doc-perm-remove-${invited.id}');
      expect((await drive.permissions(f.id)).any((p) => p.email == 'amiga@exemplo.com'), isFalse);

      await _tap(tester, 'doc-link-switch');
      expect((await drive.permissions(f.id)).any((p) => p.isAnyone), isFalse);
    });

    testWidgets('enviar arquivo: escolhe, envia para a pasta atual e atualiza a lista', (tester) async {
      final drive = MemoryDriveRepository();
      final picker = _FakePicker([LocalFile.memory(name: 'Aula.pdf', bytes: List.filled(10, 1))]);
      await _pump(tester, drive, picker: picker);
      await _tap(tester, 'docs-fab');
      await _tap(tester, 'docs-upload');
      expect(picker.calls, 1);
      expect(drive.uploads.single.name, 'Aula.pdf');
      expect(drive.uploads.single.parentId, drive.rootFolderId);
      expect(find.text('Aula.pdf'), findsWidgets);
      expect(find.textContaining('enviado'), findsOneWidget);
    });

    testWidgets('arquivo acima de 100 MB pede confirmação; cancelar não envia', (tester) async {
      final drive = MemoryDriveRepository();
      final picker = _FakePicker([LocalFile(name: 'video.mp4', size: 200 * 1024 * 1024)]);
      await _pump(tester, drive, picker: picker);
      await _tap(tester, 'docs-fab');
      await _tap(tester, 'docs-upload');
      expect(find.byKey(const Key('docs-big-dialog')), findsOneWidget);
      expect(find.textContaining('200,0 MB'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(drive.uploads, isEmpty);

      await _tap(tester, 'docs-fab');
      await _tap(tester, 'docs-upload');
      await _tap(tester, 'docs-big-confirm');
      expect(drive.uploads.single.name, 'video.mp4');
    });

    testWidgets('falha ao renomear mostra o aviso e mantém o nome', (tester) async {
      final drive = MemoryDriveRepository();
      final f = drive.addFile('fica.pdf', drive.rootFolderId);
      await _pump(tester, drive);
      drive.failActions = true;
      await _tap(tester, 'doc-menu-${f.id}');
      await _tap(tester, 'doc-act-rename');
      await tester.enterText(find.byKey(const Key('doc-rename-field')), 'outro.pdf');
      await _tap(tester, 'doc-rename-ok');
      expect(find.textContaining('Sem conexão'), findsOneWidget);
    });
  });

  testWidgets('"Mais" tem a entrada Documentos', (tester) async {
    await _pump(tester, MemoryDriveRepository(), location: '/mais');
    expect(find.byKey(const ValueKey('more-/documentos')), findsOneWidget);
    expect(find.text('Documentos'), findsOneWidget);
  });
}
