import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';

import 'package:path_provider/path_provider.dart';

import '../domain/calendar_event.dart';
import '../domain/event_tag.dart';
import '../domain/shopping.dart';
import '../domain/task_item.dart';
import '../domain/user_settings.dart';
import '../location/location_background.dart';
import '../sync/background_local.dart';
import '../sync/local_store.dart';
import '../sync/supabase_remote_source.dart';
import '../reminders/reminder_background.dart';
import 'widget_sink.dart';
import 'widget_snapshot.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseKey = String.fromEnvironment('SUPABASE_ANON_KEY');

const widgetsRefreshUniqueName = 'widgets-refresh';
const widgetsRefreshTask = 'widgetsRefresh';

/// Consultas usadas pelo segundo plano (injetáveis nos testes).
abstract interface class WidgetDataSource {
  Future<List<CalendarEvent>> events(DateTime from, DateTime to);
  Future<List<TaskItem>> openTasks();
  Future<String> themeId();

  /// Etiquetas dos eventos (só para a cor no widget).
  Future<List<EventTag>> tags();

  /// Listas e itens de compras (widget Mercado).
  Future<List<ShoppingList>> shoppingLists();
  Future<List<ShoppingItem>> shoppingItems();
}

class SupabaseWidgetDataSource implements WidgetDataSource {
  SupabaseWidgetDataSource(this._db);

  final SupabaseClient _db;

  @override
  Future<List<CalendarEvent>> events(DateTime from, DateTime to) async {
    final rows = await _db
        .from('events')
        .select()
        .gte('ends_at', from.toUtc().toIso8601String())
        .lte('starts_at', to.toUtc().toIso8601String())
        .order('starts_at', ascending: true);
    return rows.map(CalendarEvent.fromMap).toList();
  }

  @override
  Future<List<TaskItem>> openTasks() async {
    final rows = await _db.from('tasks').select().neq('status', 'done');
    return rows.map(TaskItem.fromMap).toList();
  }

  @override
  Future<List<EventTag>> tags() async {
    final rows = await _db.from('event_tags').select();
    return rows.map(EventTag.fromMap).toList();
  }

  @override
  Future<List<ShoppingList>> shoppingLists() async {
    final rows = await _db.from('shopping_lists').select().order('position');
    return rows.map(ShoppingList.fromMap).toList();
  }

  @override
  Future<List<ShoppingItem>> shoppingItems() async {
    final rows = await _db.from('shopping_items').select().eq('checked', false);
    return rows.map(ShoppingItem.fromMap).toList();
  }

  @override
  Future<String> themeId() async {
    final row = await _db.from('user_settings').select('theme').maybeSingle();
    final t = row?['theme'];
    return t is String && themeIds.contains(t) ? t : 'violeta';
  }
}

/// Lê do banco local do app (o mesmo que as telas mostram, com o que ainda não subiu): o widget fica
/// certo mesmo sem rede.
class LocalWidgetDataSource implements WidgetDataSource {
  LocalWidgetDataSource(this._store);

  final LocalStore _store;

  @override
  Future<List<CalendarEvent>> events(DateTime from, DateTime to) async {
    final out = [
      for (final r in await _store.all('events')) CalendarEvent.fromMap(r),
    ].where((e) => !e.endsAt.isBefore(from) && !e.startsAt.isAfter(to)).toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return out;
  }

  @override
  Future<List<TaskItem>> openTasks() async => [
        for (final r in await _store.all('tasks'))
          if (r['status'] != 'done') TaskItem.fromMap(r),
      ];

  @override
  Future<List<EventTag>> tags() async => [for (final r in await _store.all('event_tags')) EventTag.fromMap(r)];

  @override
  Future<List<ShoppingList>> shoppingLists() async => [
        for (final r in await _store.all('shopping_lists')) ShoppingList.fromMap(r),
      ]..sort((a, b) => a.position.compareTo(b.position));

  @override
  Future<List<ShoppingItem>> shoppingItems() async => [
        for (final r in await _store.all('shopping_items'))
          if (r['checked'] != true) ShoppingItem.fromMap(r),
      ];

  @override
  Future<String> themeId() async {
    final rows = await _store.all('user_settings');
    final t = rows.isEmpty ? null : rows.first['theme'];
    return t is String && themeIds.contains(t) ? t : 'violeta';
  }
}

/// Busca os dados e monta o resumo. Em falha devolve apenas
/// `{'w_state': 'error'}`, para não sobrescrever o último resumo bom.
Future<Map<String, String>> fetchSnapshot(WidgetDataSource source, DateTime now) async {
  try {
    // Uma consulta só: a janela do calendário (mês anterior ao seguinte) contém a dos 14 dias,
    // e buildWidgetSnapshot filtra cada chave pela sua janela.
    final events = await source.events(calendarWindowStart(now), calendarWindowEnd(now));
    final tasks = await source.openTasks();
    final theme = await source.themeId();
    // A cor é só enfeite: sem as etiquetas o resumo sai igual, sem o ponto colorido.
    var tags = const <EventTag>[];
    try {
      tags = await source.tags();
    } catch (_) {}
    // Mercado também é secundário: se falhar, w_shop não é gravado e o último continua valendo.
    List<ShoppingList>? lists;
    List<ShoppingItem>? items;
    try {
      lists = await source.shoppingLists();
      items = await source.shoppingItems();
    } catch (_) {
      lists = null;
      items = null;
    }
    return buildWidgetSnapshot(
      now: now,
      events: events,
      tasks: tasks,
      themeId: theme,
      tags: tags,
      calendarEvents: events,
      shoppingLists: lists,
      shoppingItems: items,
    );
  } catch (_) {
    return {'w_state': 'error'};
  }
}

/// Executa uma atualização completa: sessão → consulta → grava → atualiza widgets.
Future<bool> refreshWidgetsInBackground({
  required SupabaseClient? Function() client,
  required WidgetSink sink,
  required DateTime now,
  WidgetDataSource? localSource,
}) async {
  final c = client();
  final Map<String, String> data;
  if (c == null || c.auth.currentSession == null) {
    data = buildWidgetSnapshot(
        now: now, events: const [], tasks: const [], themeId: 'violeta', state: 'signed_out');
  } else {
    data = await fetchSnapshot(localSource ?? SupabaseWidgetDataSource(c), now);
  }
  await sink.save(data);
  await sink.refresh();
  return data['w_state'] != 'error';
}

/// Abre o banco local da conta logada para o segundo plano (`null` se não houver: o app nunca abriu com
/// ela, ou não há sessão). Quem abriu deve fechar.
Future<BackgroundLocal?> openBackgroundLocal(SupabaseClient? client) {
  if (client == null) return Future.value(null);
  return BackgroundLocal.open(
    userId: client.auth.currentUser?.id,
    remote: SupabaseRemoteSource(client),
    supportDir: getApplicationSupportDirectory,
  );
}

/// Cliente do Supabase para o isolate de segundo plano (reaproveita o do app
/// quando a execução é dentro dele; senão inicializa com as chaves do build).
Future<SupabaseClient?> backgroundSupabaseClient() async {
  try {
    return Supabase.instance.client; // já inicializado (execução no app)
  } catch (_) {
    if (_supabaseUrl.isNotEmpty && _supabaseKey.isNotEmpty) {
      await Supabase.initialize(url: _supabaseUrl, publishableKey: _supabaseKey);
      return Supabase.instance.client;
    }
    return null;
  }
}

/// Único despachante do workmanager: roteia pelo nome da tarefa
/// (`widgetsRefresh`, que também reagenda os lembretes, ou `locationReport`).
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      if (isLegacySamsungTask(taskName)) return true; // sincronização removida: se ainda disparar, não faz nada
      final client = await backgroundSupabaseClient();
      if (taskName == locationReportTask) {
        await runLocationReportTask(client);
        return true; // sem sessão/casa/permissão não é erro: tenta de novo em 15 min
      }
      // Com o banco local da conta: envia o que ficou na fila, recarrega e lê dele (o widget e os lembretes
      // mostram o mesmo que o app, até sem rede). Sem ele, fala direto com a nuvem.
      final local = await openBackgroundLocal(client);
      try {
        final pulled = local == null ? false : await local.pullAndPush();
        final useLocal = local != null && (pulled || await local.hasData());
        await refreshWidgetsInBackground(
          client: () => client,
          sink: const HomeWidgetSink(),
          now: DateTime.now(),
          localSource: useLocal ? LocalWidgetDataSource(local.store) : null,
        );
        // Reagenda os lembretes do celular (a janela de 3 dias anda e o app pode estar fechado há dias).
        try {
          await rescheduleRemindersInBackground(
            client: () => client,
            now: DateTime.now(),
            localSource: useLocal ? LocalReminderDataSource(local.store) : null,
          );
        } catch (_) {
          // Lembretes são secundários: a atualização dos widgets já valeu.
        }
      } finally {
        await local?.close();
      }
      return true;
    } catch (_) {
      return false;
    }
  });
}

Future<void> registerWidgetBackgroundRefresh() async {
  await Workmanager().initialize(callbackDispatcher);
  await cancelLegacySamsungSync();
  await Workmanager().registerPeriodicTask(
    widgetsRefreshUniqueName,
    widgetsRefreshTask,
    frequency: const Duration(minutes: 30),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
  );
}

/// Relatório periódico de localização (a cada 15 min, só com rede). A tarefa
/// decide sozinha se deve reportar (casa, chave e permissão "o tempo todo").
Future<void> registerLocationBackgroundReport() async {
  await Workmanager().initialize(callbackDispatcher);
  await Workmanager().registerPeriodicTask(
    locationReportUniqueName,
    locationReportTask,
    frequency: locationReportFrequency,
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
  );
}

/// A sincronização do Samsung Notes foi removida. Quem instalou uma versão antiga ainda tem a tarefa periódica
/// agendada: o app a cancela ao iniciar para ela não gastar bateria.
const legacySamsungSyncTask = 'samsungNotesSync';
const legacySamsungSyncUniqueName = 'samsung-notes-sync';

bool isLegacySamsungTask(String taskName) => taskName == legacySamsungSyncTask;

Future<void> cancelLegacySamsungSync({Future<void> Function(String uniqueName)? cancel}) async {
  try {
    await (cancel ?? (name) => Workmanager().cancelByUniqueName(name))(legacySamsungSyncUniqueName);
  } catch (_) {
    // sem a tarefa antiga ou sem plugin: nada a fazer
  }
}
