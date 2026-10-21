import 'dart:async';

import 'package:flutter/material.dart';

import '../sync/sync_session.dart';

/// Dono do banco local da conta logada: abre a [SyncSession] do usuário ao entrar, fecha e APAGA ao sair
/// ou ao trocar de conta, e manda a sessão recarregar quando o app volta ao primeiro plano.
///
/// O [builder] roda sem sessão quando está deslogado (ou se o banco local não abriu — o app cai para o
/// modo online) e com a sessão quando está pronta. Cada conta devolve um [builder] novo: quem o usa deve
/// pôr um `ProviderScope(key: ValueKey(session?.userId))` para que nenhum estado vaze entre contas.
class SyncHost extends StatefulWidget {
  const SyncHost({
    super.key,
    required this.userIds,
    required this.initialUserId,
    required this.openSession,
    required this.builder,
    this.loading = const ColoredBox(color: Color(0xFF000000), child: Center(child: CircularProgressIndicator())),
  });

  /// Id do usuário logado a cada mudança de sessão (`null` = deslogado). Repetições são ignoradas.
  final Stream<String?> userIds;
  final String? initialUserId;
  final Future<SyncSession> Function(String userId) openSession;
  final Widget Function(BuildContext context, SyncSession? session) builder;

  /// Mostrado enquanto o banco do usuário que acabou de entrar abre (milissegundos).
  final Widget loading;

  @override
  State<SyncHost> createState() => _SyncHostState();
}

class _SyncHostState extends State<SyncHost> with WidgetsBindingObserver {
  StreamSubscription<String?>? _sub;
  String? _userId;
  SyncSession? _session;
  bool _opening = false;

  /// Fechamentos em andamento (um de cada vez: o arquivo é apagado só depois de fechado).
  Future<void> _closing = Future.value();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _userId = widget.initialUserId;
    _opening = _userId != null;
    _sub = widget.userIds.listen(_onUser);
    if (_userId != null) unawaited(_open(_userId!));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    final s = _session;
    _session = null;
    if (s != null) unawaited(_enqueueClose(s, erase: false)); // o app foi fechado: o banco fica para a próxima abertura
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_session?.onResume());
  }

  Future<void> _enqueueClose(SyncSession s, {required bool erase}) =>
      _closing = _closing.then((_) => s.close(erase: erase)).catchError((Object _) {});

  void _onUser(String? id) {
    if (id == _userId) return; // token renovado, perfil atualizado…
    final old = _session;
    setState(() {
      _userId = id;
      _session = null;
      _opening = id != null;
    });
    // Sair ou trocar de conta apaga o que era da anterior.
    if (old != null) unawaited(_enqueueClose(old, erase: true));
    if (id != null) unawaited(_open(id));
  }

  Future<void> _open(String id) async {
    SyncSession? session;
    try {
      session = await widget.openSession(id);
    } on Object {
      session = null; // sem banco local o app segue online
    }
    if (!mounted || _userId != id) {
      // Saiu/trocou/fechou enquanto abria: o que acabou de abrir não é de ninguém.
      if (session != null) unawaited(_enqueueClose(session, erase: _userId != id));
      return;
    }
    setState(() {
      _session = session;
      _opening = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_userId != null && _session == null && _opening) return widget.loading;
    return widget.builder(context, _session);
  }
}
