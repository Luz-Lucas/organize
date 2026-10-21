import 'dart:async';
import 'dart:io';

import 'local_store.dart';
import 'remote_source.dart';
import 'sync_engine.dart';

/// Tabelas espelhadas no aparelho (todas enviam e recebem).
const syncTables = <String>[
  'spaces',
  'notes',
  'tasks',
  'events',
  'event_tags',
  'workouts',
  'workout_exercises',
  'workout_sessions',
  'set_logs',
  'shopping_lists',
  'shopping_items',
  'user_settings',
  'wake_plans',
  'wake_overrides',
];

/// Tabelas só de leitura: o aparelho recebe, nunca envia.
const syncReadOnlyTables = <String>['shopping_frequent'];

String _safeName(String userId) => userId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

/// Arquivo do banco local do usuário: `<pasta de dados do app>/sync/<usuário>.db`.
File syncDbFile(Directory supportDir, String userId) =>
    File('${supportDir.path}${Platform.pathSeparator}sync${Platform.pathSeparator}${_safeName(userId)}.db');

bool _belongsTo(String fileName, String userId) {
  final base = '${_safeName(userId)}.db';
  return fileName == base || fileName.startsWith('$base-');
}

/// Apaga o banco do usuário e os arquivos auxiliares do SQLite (`-wal`, `-shm`, `-journal`).
Future<void> deleteSyncDb(Directory supportDir, String userId) async {
  final dir = Directory('${supportDir.path}${Platform.pathSeparator}sync');
  if (!await dir.exists()) return;
  await for (final f in dir.list()) {
    if (f is File && _belongsTo(f.uri.pathSegments.last, userId)) {
      try {
        await f.delete();
      } on FileSystemException {
        // já apagado (ou segurado por outro processo): o próximo login tenta de novo
      }
    }
  }
}

/// Apaga os bancos de qualquer outra conta que tenha sobrado (o app foi fechado sem passar pelo "sair").
Future<void> purgeOtherAccounts(Directory supportDir, String keepUserId) async {
  final dir = Directory('${supportDir.path}${Platform.pathSeparator}sync');
  if (!await dir.exists()) return;
  await for (final f in dir.list()) {
    if (f is! File) continue;
    final name = f.uri.pathSegments.last;
    if (!name.contains('.db') || _belongsTo(name, keepUserId)) continue;
    try {
      await f.delete();
    } on FileSystemException {
      // segue
    }
  }
}

/// O banco local + o sincronizador de uma conta logada. Um por usuário: trocar de conta fecha este
/// (apagando o arquivo) e abre outro.
class SyncSession {
  SyncSession._(
    this.userId,
    this.supportDir,
    this.store,
    this.engine,
    this.ready,
    this._stateSub,
    this._externalTimer,
    this._readyTimer,
  );

  final String userId;
  final Directory supportDir;
  final LocalStore store;
  final SyncEngine engine;

  /// Completa quando a carga inicial da nuvem terminou, ou depois de [open]`.readyTimeout` (sem rede), ou
  /// já na abertura se o aparelho tem listas de compras (não há risco de criar a lista padrão em duplicidade).
  final Future<void> ready;

  final StreamSubscription<SyncState> _stateSub;
  final Timer? _externalTimer;
  final Timer? _readyTimer;
  bool _closed = false;

  static Future<SyncSession> open({
    required String userId,
    required Directory supportDir,
    required RemoteSource remote,
    DateTime Function()? now,
    Duration readyTimeout = const Duration(seconds: 8),
    Duration Function(int failures)? retryDelay,
    Duration flushDelay = const Duration(milliseconds: 250),
    Duration? flushInterval = const Duration(seconds: 30),
    Duration? refreshInterval = const Duration(minutes: 5),
    Duration? externalCheckInterval = const Duration(seconds: 3),
  }) async {
    await purgeOtherAccounts(supportDir, userId);
    final store = await LocalStore.open(syncDbFile(supportDir, userId).path, now: now);
    final engine = SyncEngine(
      store,
      remote,
      tables: syncTables,
      readOnly: syncReadOnlyTables,
      now: now,
      retryDelay: retryDelay,
      flushDelay: flushDelay,
      flushInterval: flushInterval,
      refreshInterval: refreshInterval,
    );

    final readyCompleter = Completer<void>();
    void markReady() {
      if (!readyCompleter.isCompleted) readyCompleter.complete();
    }

    Timer? readyTimer;
    if ((await store.all('shopping_lists')).isNotEmpty) {
      markReady();
    } else {
      readyTimer = Timer(readyTimeout, markReady);
    }

    // Voltou a ficar online depois de uma falha: eventos em tempo real podem ter se perdido, recarrega.
    var wasOnline = true;
    final stateSub = engine.state.listen((s) {
      if (!wasOnline && s.online) unawaited(engine.refresh());
      wasOnline = s.online;
    });
    final external = externalCheckInterval == null
        ? null
        : Timer.periodic(externalCheckInterval, (_) {
            try {
              store.checkExternalChanges();
            } on Object {
              // banco já fechado
            }
          });

    final session = SyncSession._(userId, supportDir, store, engine, readyCompleter.future, stateSub, external, readyTimer);
    unawaited(engine.start().catchError((Object _) {}).whenComplete(() {
      readyTimer?.cancel();
      markReady();
    }));
    return session;
  }

  /// Ao voltar ao app: pega o que o segundo plano gravou e recarrega a nuvem.
  Future<void> onResume() async {
    if (_closed) return;
    try {
      store.checkExternalChanges();
    } on Object {
      // banco já fechado
    }
    await engine.refresh();
  }

  /// Para o sincronizador e fecha o banco. Com [erase] (sair da conta) apaga também as linhas, a fila e o arquivo.
  Future<void> close({required bool erase, Duration timeout = const Duration(seconds: 5)}) async {
    if (_closed) return;
    _closed = true;
    _externalTimer?.cancel();
    _readyTimer?.cancel();
    await _stateSub.cancel();
    // Um envio preso na rede não pode segurar o "sair da conta".
    await engine.dispose().timeout(timeout, onTimeout: () {});
    if (erase) await store.wipe();
    await store.close();
    if (erase) await deleteSyncDb(supportDir, userId);
  }
}
