import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/directory_picker_service.dart';
import 'package:organizacional/data/memory_drive_repository.dart';
import 'package:organizacional/data/memory_imported_files_repository.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/drive.dart';
import 'package:organizacional/features/samsung_notes/samsung_folder.dart';
import 'package:organizacional/features/samsung_notes/samsung_sync_controller.dart';
import 'package:organizacional/features/samsung_notes/samsung_sync_settings.dart';

import '../../helpers.dart';
import 'fakes.dart';

const _phone = Size(400, 900);
const _notesFolder = SamsungFolder(path: '/storage/emulated/0/Documents/Samsung Notes');
const _driveOk = DriveState(status: DriveStatus.ok, accountEmail: 'c@g.com', rootFolderId: 'org-root');

class _Scheduler implements SamsungBackgroundScheduler {
  int scheduled = 0;
  int cancelled = 0;
  @override
  Future<void> schedule() async => scheduled++;
  @override
  Future<void> cancel() async => cancelled++;
}

class _DirPicker implements DirectoryPickerService {
  String? result;
  @override
  Future<String?> pickDirectory() async => result;
}

Future<void> _reveal(WidgetTester tester, Key key) async {
  await tester.scrollUntilVisible(find.byKey(key), 300, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

Future<void> _open(
  WidgetTester tester, {
  FakeSamsungPlatform? platform,
  MemorySamsungSyncPrefs? prefs,
  MemoryDriveRepository? drive,
  FakeFolderFileSystem? fs,
  _Scheduler? scheduler,
  MemoryImportedFilesRepository? imported,
  MemoryRepository? repo,
  _DirPicker? picker,
  DateTime? now,
  Future<bool> Function(Uri)? openLink,
}) async {
  await pumpApp(
    tester,
    repo ?? MemoryRepository(),
    location: '/ajustes',
    size: _phone,
    now: now,
    openLink: openLink,
    driveRepo: drive ?? MemoryDriveRepository(state: _driveOk),
    importedRepo: imported,
    samsungPlatform: platform ?? FakeSamsungPlatform(),
    samsungPrefs: prefs ?? MemorySamsungSyncPrefs(),
    samsungFs: fs ?? FakeFolderFileSystem(),
    samsungScheduler: scheduler ?? _Scheduler(),
    directoryPicker: picker,
  );
  await _reveal(tester, const Key('samsung-notes-card'));
}

void main() {
  testWidgets('sem pasta: mostra o aviso, a ajuda e os botões; sincronizar fica desligado', (tester) async {
    await _open(tester);
    expect(find.byKey(const Key('samsung-notes-card')), findsOneWidget);
    expect(find.byKey(const Key('samsung-folder-status')), findsOneWidget);
    expect(find.text('Nenhuma pasta escolhida'), findsOneWidget);
    expect(find.byKey(const Key('samsung-help')), findsOneWidget);
    expect(find.textContaining('Salvar como arquivo'), findsOneWidget);
    expect(find.byKey(const Key('samsung-find-folder')), findsOneWidget);
    expect(find.byKey(const Key('samsung-pick-folder')), findsOneWidget);
    expect(tester.widget<Switch>(find.byKey(const Key('samsung-sync-toggle'))).onChanged, isNull);
    expect(tester.widget<OutlinedButton>(find.byKey(const Key('samsung-sync-now'))).onPressed, isNull);
  });

  testWidgets('Drive não conectado: avisa e o atalho abre a conexão com o Google', (tester) async {
    final drive = MemoryDriveRepository(state: const DriveState());
    final opened = <Uri>[];
    await _open(tester,
        drive: drive, prefs: MemorySamsungSyncPrefs(const SamsungSyncSettings(folder: _notesFolder)), openLink: (u) async {
      opened.add(u);
      return true;
    });
    expect(find.byKey(const Key('samsung-drive-missing')), findsOneWidget);
    expect(tester.widget<Switch>(find.byKey(const Key('samsung-sync-toggle'))).onChanged, isNull);
    await tester.ensureVisible(find.byKey(const Key('samsung-connect-drive')));
    await tester.tap(find.byKey(const Key('samsung-connect-drive')));
    await tester.pumpAndSettle();
    expect(opened, [drive.connectUri]);
    expect(drive.lastConnectEmail, 'sua-conta@exemplo.com');
  });

  testWidgets('com pasta e Drive: mostra a pasta, a última sincronização e habilita os controles', (tester) async {
    final now = DateTime(2026, 10, 13, 10);
    final prefs = MemorySamsungSyncPrefs(SamsungSyncSettings(
      folder: _notesFolder,
      lastRun: SamsungSyncLastRun(at: now.subtract(const Duration(minutes: 5)), uploaded: 12, ignored: 2),
    ));
    await _open(tester, prefs: prefs, now: now);
    expect(find.textContaining('Documents/Samsung Notes'), findsOneWidget);
    expect(find.byKey(const Key('samsung-last-sync')), findsOneWidget);
    expect(find.textContaining('há 5 min'), findsOneWidget);
    expect(find.textContaining('12 enviados, 2 ignorados'), findsOneWidget);
    expect(tester.widget<Switch>(find.byKey(const Key('samsung-sync-toggle'))).onChanged, isNotNull);
    expect(tester.widget<OutlinedButton>(find.byKey(const Key('samsung-sync-now'))).onPressed, isNotNull);
  });

  testWidgets('ligar a chave grava, agenda a tarefa em segundo plano e já sincroniza', (tester) async {
    final prefs = MemorySamsungSyncPrefs(const SamsungSyncSettings(folder: _notesFolder));
    final scheduler = _Scheduler();
    final drive = MemoryDriveRepository(state: _driveOk);
    final fs = FakeFolderFileSystem()..put('Aula.pdf', [1, 2, 3, 4]);
    final repo = MemoryRepository();
    await _open(tester, prefs: prefs, scheduler: scheduler, drive: drive, fs: fs, repo: repo, now: DateTime(2026, 10, 13, 10));
    await tester.tap(find.byKey(const Key('samsung-sync-toggle')));
    await tester.pumpAndSettle();
    expect((await prefs.load()).enabled, isTrue);
    expect(scheduler.scheduled, greaterThanOrEqualTo(1));
    expect(drive.uploads.single.name, 'Aula.pdf');
    expect((await repo.watchNotes().first).single.title, 'Aula.pdf');
    expect(find.textContaining('1 enviado'), findsWidgets);

    await tester.tap(find.byKey(const Key('samsung-sync-toggle')));
    await tester.pumpAndSettle();
    expect((await prefs.load()).enabled, isFalse);
    expect(scheduler.cancelled, 1);
  });

  testWidgets('ao abrir o app já ligado, a tarefa em segundo plano é reagendada', (tester) async {
    final scheduler = _Scheduler();
    await _open(tester,
        prefs: MemorySamsungSyncPrefs(const SamsungSyncSettings(enabled: true, folder: _notesFolder)), scheduler: scheduler);
    expect(scheduler.scheduled, greaterThanOrEqualTo(1));
  });

  testWidgets('"Sincronizar agora" roda mesmo com a chave desligada e mostra o resumo', (tester) async {
    final fs = FakeFolderFileSystem()
      ..put('Aula.pdf', [1, 2, 3, 4])
      ..put('Nota.sdocx', [9]);
    final drive = MemoryDriveRepository(state: _driveOk);
    await _open(tester,
        prefs: MemorySamsungSyncPrefs(const SamsungSyncSettings(folder: _notesFolder)),
        fs: fs,
        drive: drive,
        now: DateTime(2026, 10, 13, 10));
    await tester.tap(find.byKey(const Key('samsung-sync-now')));
    await tester.pumpAndSettle();
    expect(drive.uploads, hasLength(1));
    expect(find.textContaining('1 enviado, 1 ignorado'), findsWidgets);
  });

  testWidgets('Procurar pasta sem "Acesso a todos os arquivos": explica antes e só então abre a tela do sistema', (tester) async {
    final platform = FakeSamsungPlatform()..allFiles = false;
    await _open(tester, platform: platform);
    await tester.tap(find.byKey(const Key('samsung-find-folder')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('samsung-allfiles-dialog')), findsOneWidget);
    expect(platform.requestCalls, 0, reason: 'primeiro a explicação');
    await tester.tap(find.byKey(const Key('samsung-allfiles-continue')));
    await tester.pumpAndSettle();
    expect(platform.requestCalls, 1);
  });

  testWidgets('Procurar pasta com acesso: usa a primeira pasta encontrada', (tester) async {
    final prefs = MemorySamsungSyncPrefs();
    final platform = FakeSamsungPlatform()..found = ['/storage/emulated/0/Documents/Samsung Notes', '/storage/emulated/0/Download'];
    await _open(tester, platform: platform, prefs: prefs);
    await tester.tap(find.byKey(const Key('samsung-find-folder')));
    await tester.pumpAndSettle();
    expect((await prefs.load()).folder, const SamsungFolder(path: '/storage/emulated/0/Documents/Samsung Notes'));
    expect(find.textContaining('Documents/Samsung Notes'), findsOneWidget);
  });

  testWidgets('só achou "Download": pede confirmação antes de vigiar; "Não" mantém sem pasta', (tester) async {
    final prefs = MemorySamsungSyncPrefs();
    final platform = FakeSamsungPlatform()..found = ['/storage/emulated/0/Download'];
    await _open(tester, platform: platform, prefs: prefs);
    await tester.tap(find.byKey(const Key('samsung-find-folder')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('samsung-confirm-download')), findsOneWidget);
    await tester.tap(find.byKey(const Key('samsung-confirm-no')));
    await tester.pumpAndSettle();
    expect((await prefs.load()).folder, isNull);

    await tester.tap(find.byKey(const Key('samsung-find-folder')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('samsung-confirm-yes')));
    await tester.pumpAndSettle();
    expect((await prefs.load()).folder, const SamsungFolder(path: '/storage/emulated/0/Download'));
  });

  testWidgets('nenhuma pasta encontrada: orienta a escolher outra', (tester) async {
    await _open(tester, platform: FakeSamsungPlatform()..found = []);
    await tester.tap(find.byKey(const Key('samsung-find-folder')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('samsung-message')), findsOneWidget);
    expect(find.textContaining('Escolher outra pasta'), findsWidgets);
  });

  testWidgets('Escolher outra pasta (Android): usa o seletor do sistema e guarda o URI', (tester) async {
    final prefs = MemorySamsungSyncPrefs();
    final platform = FakeSamsungPlatform()..picked = const SamsungFolder(uri: 'content://x/tree/y', label: 'Minhas notas');
    await _open(tester, platform: platform, prefs: prefs);
    await tester.tap(find.byKey(const Key('samsung-pick-folder')));
    await tester.pumpAndSettle();
    expect(platform.pickCalls, 1);
    expect((await prefs.load()).folder, const SamsungFolder(uri: 'content://x/tree/y', label: 'Minhas notas'));
    expect(find.textContaining('Minhas notas'), findsOneWidget);
  });

  testWidgets('Escolher outra pasta cancelado não muda nada', (tester) async {
    final prefs = MemorySamsungSyncPrefs(const SamsungSyncSettings(folder: _notesFolder));
    await _open(tester, platform: FakeSamsungPlatform()..picked = null, prefs: prefs);
    await tester.tap(find.byKey(const Key('samsung-pick-folder')));
    await tester.pumpAndSettle();
    expect((await prefs.load()).folder, _notesFolder);
  });

  testWidgets('Linux: Escolher outra pasta usa o seletor de diretório do file_picker', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      final prefs = MemorySamsungSyncPrefs();
      final picker = _DirPicker()..result = '/home/u/Documentos/Notas';
      await _open(tester, prefs: prefs, picker: picker);
      // Sem Android não existe "Procurar pasta" automático nem permissão de arquivos.
      expect(find.byKey(const Key('samsung-find-folder')), findsNothing);
      await tester.tap(find.byKey(const Key('samsung-pick-folder')));
      await tester.pumpAndSettle();
      expect((await prefs.load()).folder, const SamsungFolder(path: '/home/u/Documentos/Notas'));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('trocar de pasta com a chave ligada sincroniza a pasta nova', (tester) async {
    final fs = FakeFolderFileSystem()..put('Aula.pdf', [1, 2, 3, 4]);
    final drive = MemoryDriveRepository(state: _driveOk);
    final platform = FakeSamsungPlatform()..found = ['/storage/emulated/0/Documents/Samsung Notes'];
    await _open(tester,
        platform: platform,
        fs: fs,
        drive: drive,
        prefs: MemorySamsungSyncPrefs(const SamsungSyncSettings(enabled: true)),
        now: DateTime(2026, 10, 13, 10));
    await tester.tap(find.byKey(const Key('samsung-find-folder')));
    await tester.pumpAndSettle();
    expect(drive.uploads, hasLength(1));
  });

  testWidgets('a ajuda explica como exportar pelo Samsung Notes', (tester) async {
    await _open(tester);
    expect(find.textContaining('abra a nota'), findsWidgets);
    expect(find.textContaining('Salvar como arquivo'), findsOneWidget);
    expect(find.textContaining('PDF'), findsWidgets);
  });
}
