import 'dart:async';

import '../domain/email.dart';
import 'email_repository.dart';
import 'repository.dart';

/// Implementação em memória usada nos testes.
class MemoryEmailRepository implements EmailRepository {
  MemoryEmailRepository({this._state, List<EmailItem> items = const []}) : _items = List.of(items);

  EmailState? _state;
  List<EmailItem> _items;
  final _changes = StreamController<void>.broadcast(sync: true);

  bool failActions = false;
  int syncCalls = 0;
  int disconnectCalls = 0;
  String? lastConnectEmail;
  Uri connectUri = Uri.parse('https://accounts.google.com/o/oauth2/v2/auth?test=1');

  void setState(EmailState? state, {List<EmailItem>? items}) {
    _state = state;
    if (items != null) _items = List.of(items);
    _changes.add(null);
  }

  Stream<T> _watch<T>(T Function() read) {
    StreamSubscription<void>? sub;
    late final StreamController<T> controller;
    controller = StreamController<T>(
      onListen: () {
        controller.add(read());
        sub = _changes.stream.listen((_) => controller.add(read()));
      },
      onCancel: () {
        sub?.cancel();
        controller.close();
      },
    );
    return controller.stream;
  }

  @override
  Stream<EmailState?> watchState() => _watch(() => _state);

  @override
  Stream<List<EmailItem>> watchItems({int limit = 10}) => _watch(() => _items.take(limit).toList());

  void _check() {
    if (failActions) throw const RepositoryException('Sem conexão (simulado)');
  }

  @override
  Future<Uri> connectUrl({String? email}) async {
    _check();
    lastConnectEmail = email;
    return connectUri;
  }

  @override
  Future<void> syncNow() async {
    _check();
    syncCalls++;
  }

  @override
  Future<void> disconnect() async {
    _check();
    disconnectCalls++;
    setState(const EmailState(), items: const []);
  }
}
