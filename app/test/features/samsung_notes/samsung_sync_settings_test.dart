import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/features/samsung_notes/samsung_folder.dart';
import 'package:organizacional/features/samsung_notes/samsung_sync_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('SamsungFolder', () {
    test('rótulo: dois últimos trechos do caminho ou o nome dado pelo seletor', () {
      expect(const SamsungFolder(path: '/storage/emulated/0/Documents/Samsung Notes').label, 'Documents/Samsung Notes');
      expect(const SamsungFolder(path: '/Samsung Notes').label, 'Samsung Notes');
      expect(const SamsungFolder(uri: 'content://x/tree/y', label: 'Minhas notas').label, 'Minhas notas');
    });

    test('vai e volta por JSON; JSON inválido vira null', () {
      const a = SamsungFolder(path: '/a/b');
      const b = SamsungFolder(uri: 'content://x', label: 'L');
      expect(SamsungFolder.fromJson(a.toJson()), a);
      expect(SamsungFolder.fromJson(b.toJson()), b);
      expect(b.isUri, isTrue);
      expect(a.isUri, isFalse);
      expect(SamsungFolder.fromJson(null), isNull);
      expect(SamsungFolder.fromJson({'x': 1}), isNull);
      expect(SamsungFolder.fromJson({'path': ''}), isNull);
    });
  });

  group('MemorySamsungSyncPrefs', () {
    test('guarda ligado, pasta e última rodada', () async {
      final prefs = MemorySamsungSyncPrefs();
      expect((await prefs.load()).enabled, isFalse);
      await prefs.setEnabled(true);
      await prefs.setFolder(const SamsungFolder(path: '/p'));
      await prefs.saveLastRun(SamsungSyncLastRun(at: DateTime(2026, 10, 13), uploaded: 3, ignored: 1));
      final s = await prefs.load();
      expect(s.enabled, isTrue);
      expect(s.folder, const SamsungFolder(path: '/p'));
      expect(s.lastRun!.uploaded, 3);
    });
  });

  group('SharedPreferencesSamsungSyncPrefs', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('padrão: desligado, sem pasta, sem rodada', () async {
      final s = await SharedPreferencesSamsungSyncPrefs().load();
      expect(s.enabled, isFalse);
      expect(s.folder, isNull);
      expect(s.lastRun, isNull);
    });

    test('persiste e relê (inclusive de outra instância, como a tarefa em segundo plano)', () async {
      final a = SharedPreferencesSamsungSyncPrefs();
      await a.setEnabled(true);
      await a.setFolder(const SamsungFolder(uri: 'content://tree/1', label: 'Notas'));
      await a.saveLastRun(SamsungSyncLastRun(
        at: DateTime.utc(2026, 10, 13, 12),
        uploaded: 12,
        skipped: 4,
        ignored: 2,
        errors: 1,
        message: 'falhou',
      ));
      final s = await SharedPreferencesSamsungSyncPrefs().load();
      expect(s.enabled, isTrue);
      expect(s.folder, const SamsungFolder(uri: 'content://tree/1', label: 'Notas'));
      expect(s.lastRun!.at.toUtc(), DateTime.utc(2026, 10, 13, 12));
      expect([s.lastRun!.uploaded, s.lastRun!.skipped, s.lastRun!.ignored, s.lastRun!.errors], [12, 4, 2, 1]);
      expect(s.lastRun!.message, 'falhou');
    });

    test('limpar a pasta (null) remove a chave', () async {
      final p = SharedPreferencesSamsungSyncPrefs();
      await p.setFolder(const SamsungFolder(path: '/p'));
      await p.setFolder(null);
      expect((await p.load()).folder, isNull);
    });

    test('dado corrompido não derruba a leitura', () async {
      SharedPreferences.setMockInitialValues({'samsung_sync_folder': '{nao é json', 'samsung_sync_last_run': 'x'});
      final s = await SharedPreferencesSamsungSyncPrefs().load();
      expect(s.folder, isNull);
      expect(s.lastRun, isNull);
    });
  });

  group('SamsungSyncLastRun', () {
    test('texto: contagens e erro', () {
      final r = SamsungSyncLastRun(at: DateTime(2026), uploaded: 12, ignored: 2);
      expect(r.text, '12 enviados, 2 ignorados');
      final e = SamsungSyncLastRun(at: DateTime(2026), uploaded: 1, ignored: 0, errors: 2);
      expect(e.text, '1 enviado, 0 ignorados, 2 com erro');
    });
  });
}
