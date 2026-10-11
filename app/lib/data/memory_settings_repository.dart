import 'dart:async';

import '../domain/user_settings.dart';
import 'repository.dart';
import 'settings_repository.dart';

/// Implementação em memória usada nos testes.
class MemorySettingsRepository implements SettingsRepository {
  MemorySettingsRepository({UserSettings initial = const UserSettings(), this.failWrites = false})
      : _current = initial;

  UserSettings _current;
  final _changes = StreamController<void>.broadcast(sync: true);

  /// Quando true, toda escrita falha, simulando uma queda de conexão.
  bool failWrites;

  @override
  Stream<UserSettings> watchSettings() {
    StreamSubscription<void>? sub;
    late final StreamController<UserSettings> controller;
    controller = StreamController<UserSettings>(
      onListen: () {
        controller.add(_current);
        sub = _changes.stream.listen((_) => controller.add(_current));
      },
      onCancel: () {
        sub?.cancel();
        controller.close();
      },
    );
    return controller.stream;
  }

  /// Substitui todos os ajustes (apoio para os testes).
  Future<void> saveSettings(UserSettings settings) async {
    if (failWrites) throw const RepositoryException('Sem conexão (simulado)');
    _current = settings;
    _changes.add(null);
  }

  @override
  Future<void> setTheme(String themeId) =>
      saveSettings(_current.copyWith(theme: themeId));

  @override
  Future<void> setDeviceHidden(String deviceId, bool hidden) => saveSettings(_current.copyWith(
        hiddenAlexaDevices: [..._current.hiddenAlexaDevices.where((x) => x != deviceId), if (hidden) deviceId],
      ));
}
