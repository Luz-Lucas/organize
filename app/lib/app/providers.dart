import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/alexa_repository.dart';
import '../data/news_repository.dart';
import '../data/repository.dart';
import '../data/settings_repository.dart';
import '../domain/alexa.dart';
import '../domain/calendar_event.dart';
import '../domain/event_tag.dart';
import '../domain/news.dart';
import '../domain/note.dart';
import '../domain/notice.dart';
import '../domain/space.dart';
import '../domain/task_item.dart';
import '../domain/user_settings.dart';
import '../domain/wake_override.dart';

final repositoryProvider = Provider<Repository>(
  (ref) => throw UnimplementedError('repositoryProvider precisa de override'),
);

final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Callback injetável para sair da conta. O padrão (sem-op) evita que os
/// testes precisem de um cliente Supabase de verdade; main.dart sobrescreve
/// com Supabase.instance.client.auth.signOut. O redirecionamento para
/// /login já acontece via o refreshListenable do router (mudança de sessão).
final signOutProvider = Provider<Future<void> Function()>((ref) => () async {});

/// Desligado nos testes (sem carregar fontes do Google Fonts).
final googleFontsEnabledProvider = Provider<bool>((ref) => true);

/// E-mail da conta logada (main.dart sobrescreve com o usuário do Supabase).
final currentEmailProvider = Provider<String?>((ref) => null);

final spacesProvider =
    StreamProvider<List<Space>>((ref) => ref.watch(repositoryProvider).watchSpaces());

final notesProvider =
    StreamProvider<List<Note>>((ref) => ref.watch(repositoryProvider).watchNotes());

final tasksProvider =
    StreamProvider<List<TaskItem>>((ref) => ref.watch(repositoryProvider).watchTasks());

/// Etiquetas coloridas dos eventos (por posição).
final eventTagsProvider =
    StreamProvider<List<EventTag>>((ref) => ref.watch(repositoryProvider).watchTags());

final eventsFromProvider = StreamProvider.autoDispose.family<List<CalendarEvent>, DateTime>(
  (ref, from) => ref.watch(repositoryProvider).watchEvents(from: from),
);

/// Guarda em memória edições de notas que não puderam ser salvas ao sair da
/// tela (ex.: falha de rede), para que sejam recuperadas na próxima abertura.
class NoteDrafts {
  final _drafts = <String, Note>{};

  void put(Note note) => _drafts[note.id] = note;

  Note? take(String id) => _drafts.remove(id);
}

final noteDraftsProvider = Provider<NoteDrafts>((ref) => NoteDrafts());

final newsRepositoryProvider = Provider<NewsRepository>(
  (ref) => throw UnimplementedError('newsRepositoryProvider precisa de override'),
);

// autoDispose: cada visita a Hoje/Notícias relê o servidor e nada vaza entre contas.
final newsFeedProvider =
    FutureProvider.autoDispose<List<NewsItem>>((ref) => ref.watch(newsRepositoryProvider).feed());

final newsSourcesProvider =
    FutureProvider.autoDispose<List<NewsSource>>((ref) => ref.watch(newsRepositoryProvider).sources());

final newsPrefsProvider =
    FutureProvider.autoDispose<NewsPrefs>((ref) => ref.watch(newsRepositoryProvider).prefs());

/// Abre o link no app externo; devolve false se não foi possível.
final linkOpenerProvider = Provider<Future<bool> Function(Uri)>(
  (ref) => (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

final alexaRepositoryProvider = Provider<AlexaRepository>(
  (ref) => throw UnimplementedError('alexaRepositoryProvider precisa de override'),
);

final bridgeStatusProvider =
    StreamProvider<BridgeStatus?>((ref) => ref.watch(alexaRepositoryProvider).watchStatus());

final alexaDevicesProvider =
    StreamProvider<List<AlexaDevice>>((ref) => ref.watch(alexaRepositoryProvider).watchDevices());

final alexaRoutinesProvider =
    StreamProvider<List<AlexaRoutine>>((ref) => ref.watch(alexaRepositoryProvider).watchRoutines());

final wakePlansProvider =
    StreamProvider<List<WakePlan>>((ref) => ref.watch(alexaRepositoryProvider).watchWakePlans());

final wakeOverridesProvider =
    StreamProvider<List<WakeOverride>>((ref) => ref.watch(alexaRepositoryProvider).watchOverrides());

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => throw UnimplementedError('settingsRepositoryProvider precisa de override'),
);

final settingsProvider = StreamProvider<UserSettings>(
    (ref) => ref.watch(settingsRepositoryProvider).watchSettings());

final noticesProvider =
    StreamProvider<List<Notice>>((ref) => ref.watch(repositoryProvider).watchNotices());
