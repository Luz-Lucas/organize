import 'dart:async';
import 'dart:io';

import 'local_store.dart';
import 'remote_source.dart';
import 'sync_engine.dart';
import 'sync_session.dart';

/// Tabelas que os widgets e os lembretes leem; o segundo plano só recarrega estas.
const backgroundTables = <String>['events', 'tasks', 'event_tags', 'shopping_lists', 'shopping_items', 'user_settings'];

/// O banco local da conta, aberto pelo isolate de segundo plano (workmanager, ação do widget, botão
/// "Concluir" do lembrete). É outra conexão ao MESMO arquivo que o app usa (WAL + espera por trava no
/// [LocalStore]): o que é gravado aqui entra na fila e o app percebe sozinho.
///
/// Sem timers nem tempo real: o isolate vive pouco. Abre, grava/lê, tenta enviar e fecha.
class BackgroundLocal {
  BackgroundLocal._(this.store, this.engine, this._timeout);

  final LocalStore store;
  final SyncEngine engine;
  final Duration _timeout;

  /// Abre o banco local de [userId] se ele já existir (o app já abriu alguma vez com essa conta);
  /// senão devolve `null` e o segundo plano segue falando direto com a nuvem. Nunca lança.
  static Future<BackgroundLocal?> open({
    required String? userId,
    required RemoteSource remote,
    required Future<Directory> Function() supportDir,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (userId == null) return null;
    try {
      final dir = await supportDir();
      if (!syncDbFile(dir, userId).existsSync()) return null;
      final store = await LocalStore.open(syncDbFile(dir, userId).path);
      final engine = SyncEngine(
        store,
        remote,
        tables: backgroundTables,
        autoFlush: false,
        flushInterval: null,
        refreshInterval: null,
      );
      return BackgroundLocal._(store, engine, timeout);
    } on Object {
      return null;
    }
  }

  /// Tenta enviar a fila. Nunca lança; sem rede, tudo continua na fila.
  Future<void> push() async {
    try {
      await engine.flush().timeout(_timeout);
    } on Object {
      // fica na fila
    }
  }

  /// Envia a fila e recarrega da nuvem as [backgroundTables]. `false` se não deu (sem rede): os dados
  /// locais seguem valendo.
  Future<bool> pullAndPush() async {
    await push();
    try {
      await engine.refresh().timeout(_timeout);
    } on Object {
      return false;
    }
    return engine.currentState.online;
  }

  /// O aparelho já recebeu dados da conta (alguma tarefa, evento ou ajuste)? Vazio e sem rede = melhor
  /// perguntar à nuvem em vez de mostrar um widget vazio.
  Future<bool> hasData() async {
    for (final tbl in const ['tasks', 'events', 'user_settings', 'shopping_lists']) {
      if ((await store.all(tbl)).isNotEmpty) return true;
    }
    return false;
  }

  Future<void> close() async {
    try {
      await engine.dispose().timeout(const Duration(seconds: 3), onTimeout: () {});
    } on Object {
      // segue
    }
    await store.close();
  }
}
