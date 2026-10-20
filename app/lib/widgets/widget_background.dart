import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';

import '../domain/calendar_event.dart';
import '../domain/event_tag.dart';
import '../domain/shopping.dart';
import '../domain/task_item.dart';
import '../domain/user_settings.dart';
import '../location/location_background.dart';
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
}) async {
  final c = client();
  final Map<String, String> data;
  if (c == null || c.auth.currentSession == null) {
    data = buildWidgetSnapshot(
        now: now, events: const [], tasks: const [], themeId: 'violeta', state: 'signed_out');
  } else {
    data = await fetchSnapshot(SupabaseWidgetDataSource(c), now);
  }
  await sink.save(data);
  await sink.refresh();
  return data['w_state'] != 'error';
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
/// (`widgetsRefresh` ou `locationReport`).
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
      await refreshWidgetsInBackground(
        client: () => client,
        sink: const HomeWidgetSink(),
        now: DateTime.now(),
      );
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
