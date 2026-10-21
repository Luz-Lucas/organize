import 'package:flutter_riverpod/misc.dart' show Override;

import '../data/alexa_repository.dart';
import '../data/local_alexa_repository.dart';
import '../data/local_fitness_repository.dart';
import '../data/local_repository.dart';
import '../data/local_settings_repository.dart';
import '../data/local_shopping_repository.dart';
import '../features/fitness/fitness_providers.dart';
import '../features/shopping/shopping_providers.dart';
import '../sync/local_store.dart';
import '../sync/sync_engine.dart';
import '../sync/sync_session.dart';
import 'providers.dart';
import 'sync_providers.dart';

/// Troca os repositórios das features que salvam no aparelho primeiro pelos local-primeiro da conta
/// [session]. Dispositivos, rotinas, status e comandos da Alexa seguem em [onlineAlexa].
List<Override> localFirstOverrides({
  required SyncSession session,
  required AlexaRepository onlineAlexa,
  Future<int> Function()? seedEventTagsRemote,
}) =>
    localFirstOverridesFor(
      userId: session.userId,
      store: session.store,
      engine: session.engine,
      ready: session.ready,
      onlineAlexa: onlineAlexa,
      seedEventTagsRemote: seedEventTagsRemote,
    );

/// Mesma troca a partir das peças (testes montam o banco e o sincronizador à mão).
List<Override> localFirstOverridesFor({
  required String userId,
  required LocalStore store,
  required SyncEngine engine,
  required Future<void> ready,
  required AlexaRepository onlineAlexa,
  Future<int> Function()? seedEventTagsRemote,
}) =>
    [
      repositoryProvider.overrideWithValue(LocalFirstRepository(store, seedEventTagsRemote: seedEventTagsRemote)),
      fitnessRepositoryProvider.overrideWithValue(LocalFirstFitnessRepository(store)),
      shoppingRepositoryProvider.overrideWithValue(LocalFirstShoppingRepository(store)),
      settingsRepositoryProvider.overrideWithValue(LocalFirstSettingsRepository(store, userId)),
      alexaRepositoryProvider.overrideWithValue(LocalFirstAlexaRepository(store, onlineAlexa)),
      syncEngineProvider.overrideWithValue(engine),
      syncReadyProvider.overrideWithValue(ready),
    ];
