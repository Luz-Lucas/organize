import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sync/sync_engine.dart';
import 'providers.dart';

/// O sincronizador da conta logada. `null` nos testes e fora do app real (sem banco local).
final syncEngineProvider = Provider<SyncEngine?>((ref) => null);

/// Completa quando a carga inicial da nuvem terminou (ou o prazo sem rede passou). Telas que criam
/// dados padrão (a lista "Mercado") esperam por aqui para não duplicar o que ainda não chegou.
final syncReadyProvider = Provider<Future<void>>((ref) => Future.value());

/// Estado do envio (fila, online). Sem sincronizador não emite nada.
final syncStateProvider = StreamProvider<SyncState>((ref) {
  final engine = ref.watch(syncEngineProvider);
  return engine == null ? const Stream<SyncState>.empty() : engine.state;
});

/// Alterações que o servidor recusou de vez.
final syncRejectionsProvider = Provider<Stream<SyncRejection>>((ref) {
  final engine = ref.watch(syncEngineProvider);
  return engine == null ? const Stream<SyncRejection>.empty() : engine.rejections;
});

/// Quantas alterações estão esperando para subir, quando a fila está parada há mais de
/// [connectionGraceProvider] (4 s); `0` = nada a mostrar. A contagem recomeça quando a fila anda.
final pendingNoticeProvider = NotifierProvider<PendingNotice, int>(PendingNotice.new);

class PendingNotice extends Notifier<int> {
  Timer? _timer;
  int _lastPending = 0;

  @override
  int build() {
    ref.onDispose(() => _timer?.cancel());
    ref.listen(syncStateProvider, (_, next) {
      final s = next.value;
      if (s != null) _update(s.pending);
    });
    return 0;
  }

  void _update(int pending) {
    final previous = _lastPending;
    _lastPending = pending;
    if (pending == 0) {
      _timer?.cancel();
      _timer = null;
      if (state != 0) state = 0;
      return;
    }
    if (state != 0) {
      state = pending; // já avisando: só acompanha o número
      return;
    }
    // A espera conta desde que a fila apareceu ou andou; mais escritas na fila não a reiniciam.
    if (previous == 0 || pending < previous) {
      _timer?.cancel();
      _timer = Timer(ref.read(connectionGraceProvider), () {
        _timer = null;
        if (_lastPending > 0) state = _lastPending;
      });
    }
  }
}

/// `true` quando o envio está sem conexão há mais de [connectionGraceProvider] (4 s) seguidos; as
/// alterações continuam salvas no aparelho. Quedas curtas não contam.
final offlineNoticeProvider = NotifierProvider<OfflineNotice, bool>(OfflineNotice.new);

class OfflineNotice extends Notifier<bool> {
  Timer? _timer;

  @override
  bool build() {
    ref.onDispose(() => _timer?.cancel());
    ref.listen(syncStateProvider, (_, next) {
      final s = next.value;
      if (s == null) return;
      if (s.online) {
        _timer?.cancel();
        _timer = null;
        if (state) state = false;
      } else if (!state && _timer == null) {
        _timer = Timer(ref.read(connectionGraceProvider), () {
          _timer = null;
          final latest = ref.read(syncStateProvider).value;
          if (latest != null && !latest.online) state = true;
        });
      }
    });
    return false;
  }
}

/// Recusas do servidor ainda não vistas pelo usuário (o ícone de erro fica até ele tocar).
final syncRejectionLogProvider = NotifierProvider<SyncRejectionLog, List<SyncRejection>>(SyncRejectionLog.new);

class SyncRejectionLog extends Notifier<List<SyncRejection>> {
  @override
  List<SyncRejection> build() {
    final sub = ref.watch(syncRejectionsProvider).listen((r) => state = [...state, r]);
    ref.onDispose(sub.cancel);
    return const [];
  }

  void clear() {
    if (state.isNotEmpty) state = const [];
  }
}

/// Texto curto, em português, do motivo de uma recusa do servidor.
String syncRejectionReason(String raw) {
  final m = raw.toLowerCase();
  if (m.contains('duplicate key') || m.contains('already exists')) return 'já existe um registro igual';
  if (m.contains('row-level security') || m.contains('permission denied')) return 'sem permissão';
  if (m.contains('foreign key')) return 'depende de algo que não existe mais';
  if (m.contains('check constraint')) return 'um valor não é aceito';
  if (m.contains('null value') || m.contains('not-null')) return 'falta um campo obrigatório';
  if (m.contains('invalid input')) return 'um valor está inválido';
  return raw;
}
