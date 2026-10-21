import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/local_repository.dart';
import 'package:organizacional/data/local_shopping_repository.dart';
import 'package:organizacional/domain/calendar_event.dart';
import 'package:organizacional/domain/shopping.dart';
import 'package:organizacional/domain/task_item.dart';
import 'package:organizacional/domain/user_settings.dart';
import 'package:organizacional/reminders/reminder_background.dart';
import 'package:organizacional/sync/background_local.dart';
import 'package:organizacional/sync/fake_remote_source.dart';
import 'package:organizacional/sync/local_store.dart';
import 'package:organizacional/sync/sync_session.dart';
import 'package:organizacional/widgets/widget_background.dart';
import 'package:organizacional/widgets/widget_shop_action.dart';

void main() {
  late Directory dir;
  late FakeRemoteSource remote;
  late LocalStore app; // a conexão do app aberto

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('bg-local');
    remote = FakeRemoteSource();
    app = await LocalStore.open(syncDbFile(dir, 'u1').path);
  });
  tearDown(() async {
    await app.close();
    await remote.close();
    dir.deleteSync(recursive: true);
  });

  Future<BackgroundLocal?> open({String? user = 'u1'}) =>
      BackgroundLocal.open(userId: user, remote: remote, supportDir: () async => dir);

  test('sem usuário, ou sem banco local desse usuário, não abre (o segundo plano usa a nuvem como antes)', () async {
    expect(await open(user: null), isNull);
    expect(await open(user: 'outro'), isNull);
    expect(File(syncDbFile(dir, 'outro').path).existsSync(), isFalse, reason: 'não cria banco vazio');
  });

  test('vê a fila do app, envia uma vez só e as duas conexões convivem no mesmo arquivo', () async {
    await LocalFirstRepository(app).upsertTask(const TaskItem(id: 't1', title: 'Do app'));
    final bg = (await open())!;
    expect(bg.store.pendingNow, 1);
    await bg.push();
    expect(remote.rows('tasks').single['id'], 't1');
    expect(remote.calls.where((c) => c.op == 'upsert'), hasLength(1));
    expect(app.pendingNow, 0, reason: 'o app enxerga a fila já enviada');
    await bg.close();
  });

  test('push sem rede não lança e deixa tudo na fila', () async {
    await LocalFirstRepository(app).upsertTask(const TaskItem(id: 't1', title: 'Do app'));
    remote.online = false;
    final bg = (await open())!;
    await bg.push();
    expect(bg.store.pendingNow, 1);
    await bg.close();
  });

  test('pullAndPush traz da nuvem só as tabelas do segundo plano', () async {
    remote.serverUpsert('events', {
      'id': 'e1',
      'title': 'Dentista',
      'starts_at': '2026-10-22T15:00:00Z',
      'ends_at': '2026-10-22T16:00:00Z',
    });
    remote.serverUpsert('notes', {'id': 'n1', 'title': 'não precisa'});
    final bg = (await open())!;
    expect(await bg.pullAndPush(), isTrue);
    expect(await bg.store.get('events', 'e1'), isNotNull);
    expect(await bg.store.get('notes', 'n1'), isNull);
    await bg.close();
  });

  test('pullAndPush sem rede devolve false e mantém o que já havia no aparelho', () async {
    await LocalFirstRepository(app).upsertTask(const TaskItem(id: 't1', title: 'Local'));
    remote.online = false;
    final bg = (await open())!;
    expect(await bg.pullAndPush(), isFalse);
    expect((await bg.store.all('tasks')), hasLength(1));
    await bg.close();
  });

  test('o que o segundo plano grava entra na fila e o app percebe', () async {
    final seen = <int>[];
    final sub = app.watchPending().listen(seen.add);
    final bg = (await open())!;
    await LocalFirstShoppingRepository(bg.store).upsertList(const ShoppingList(id: 'l1', name: 'Mercado'));
    await bg.close();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(app.checkExternalChanges(), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(seen.last, 1);
    await sub.cancel();
  });

  group('fontes locais', () {
    test('LocalWidgetDataSource lê eventos da janela, tarefas abertas, etiquetas, tema e compras', () async {
      final repo = LocalFirstRepository(app);
      await repo.upsertEvent(CalendarEvent(
          id: 'dentro', title: 'Dentista', startsAt: DateTime.utc(2026, 10, 22, 15), endsAt: DateTime.utc(2026, 10, 22, 16)));
      await repo.upsertEvent(CalendarEvent(
          id: 'fora', title: 'Velho', startsAt: DateTime.utc(2026, 1, 1, 15), endsAt: DateTime.utc(2026, 1, 1, 16)));
      await repo.upsertTask(const TaskItem(id: 'aberta', title: 'A'));
      await repo.upsertTask(const TaskItem(id: 'feita', title: 'B', status: TaskStatus.done));
      await app.put('user_settings', {'user_id': 'u1', 'theme': 'coral'});
      final shop = LocalFirstShoppingRepository(app);
      final list = await shop.ensureDefaultList();
      await shop.addItem(listId: list.id, name: 'Arroz');
      await shop.addItem(listId: list.id, name: 'Feijão');
      final feijao = (await shop.watchItems().first).firstWhere((i) => i.name == 'Feijão');
      await shop.setChecked(feijao.id, true);

      final src = LocalWidgetDataSource(app);
      expect((await src.events(DateTime.utc(2026, 10, 1), DateTime.utc(2026, 10, 31))).map((e) => e.id), ['dentro']);
      expect((await src.openTasks()).map((t) => t.id), ['aberta']);
      expect(await src.themeId(), 'coral');
      expect((await src.shoppingLists()).map((l) => l.name), ['Mercado']);
      expect((await src.shoppingItems()).map((i) => i.name), ['Arroz']);
      expect(await src.tags(), isEmpty);
    });

    test('LocalReminderDataSource lê tarefas abertas com prazo, eventos e ajustes', () async {
      final repo = LocalFirstRepository(app);
      await repo.upsertTask(TaskItem(id: 'com', title: 'Com prazo', dueAt: DateTime.utc(2026, 10, 22, 18)));
      await repo.upsertTask(const TaskItem(id: 'sem', title: 'Sem prazo'));
      await repo.upsertEvent(CalendarEvent(
          id: 'e', title: 'E', startsAt: DateTime.utc(2026, 10, 22, 15), endsAt: DateTime.utc(2026, 10, 22, 16)));
      await app.put('user_settings', {'user_id': 'u1', 'reminders_phone': false});
      final src = LocalReminderDataSource(app);
      expect((await src.openTasks()).map((t) => t.id), ['com']);
      expect((await src.events(DateTime.utc(2026, 10, 22), DateTime.utc(2026, 10, 23))).map((e) => e.id), ['e']);
      expect((await src.settings()).remindersPhone, isFalse);
      await app.wipe();
      expect((await src.settings()).remindersPhone, const UserSettings().remindersPhone);
    });
  });

  group('escritas em segundo plano', () {
    test('Concluir do lembrete grava a tarefa inteira na fila e envia', () async {
      await LocalFirstRepository(app).upsertTask(TaskItem(id: 't1', title: 'Pagar a luz', dueAt: DateTime.utc(2026, 10, 22, 18)));
      app.ackOutbox(app.pendingOutbox()); // já estava na nuvem
      remote.serverUpsert('tasks', {'id': 't1', 'title': 'Pagar a luz', 'status': 'todo'});
      final bg = (await open())!;
      final now = DateTime.utc(2026, 10, 22, 9);
      expect(await completeTaskLocally(bg, 't1', now), isTrue);
      expect((await bg.store.get('tasks', 't1'))!['status'], 'done');
      final queued = bg.store.pendingOutbox().single.data!;
      expect([queued['title'], queued['status']], ['Pagar a luz', 'done'], reason: 'a linha inteira vai para a fila');
      await bg.push();
      expect(remote.row('tasks', 't1')!['status'], 'done');
      await bg.close();
    });

    test('Concluir de tarefa que não está no banco local devolve false (cai no caminho online)', () async {
      final bg = (await open())!;
      expect(await completeTaskLocally(bg, 'nao-existe', DateTime.utc(2026, 10, 22)), isFalse);
      await bg.close();
    });

    test('toque no item do widget Mercado marca no banco local e envia', () async {
      final shop = LocalFirstShoppingRepository(app);
      final list = await shop.ensureDefaultList();
      await shop.addItem(listId: list.id, name: 'Arroz', section: ShopSection.mercearia);
      final id = (await shop.watchItems().first).single.id;
      app.ackOutbox(app.pendingOutbox());
      remote.serverUpsert('shopping_lists', {'id': list.id, 'name': 'Mercado'});
      remote.serverUpsert('shopping_items', {
        'id': id, 'list_id': list.id, 'name': 'Arroz', 'quantity': '', 'section': 'mercearia', 'checked': false, 'position': 0,
      });
      final bg = (await open())!;
      final ok = await handleWidgetInteraction(shopCheckUri(id), () async => LocalFirstShoppingRepository(bg.store));
      expect(ok, isTrue);
      await bg.push();
      expect(remote.row('shopping_items', id)!['checked'], isTrue);
      await bg.close();
    });
  });

  test('várias escritas simultâneas do app e do segundo plano no mesmo arquivo não travam', () async {
    final bg = (await open())!;
    final appRepo = LocalFirstRepository(app);
    final bgRepo = LocalFirstRepository(bg.store);
    await Future.wait([
      for (var i = 0; i < 30; i++) appRepo.upsertTask(TaskItem(id: 'a$i', title: 'a$i')),
      for (var i = 0; i < 30; i++) bgRepo.upsertTask(TaskItem(id: 'b$i', title: 'b$i')),
    ]);
    expect(await app.all('tasks'), hasLength(60));
    expect(await bg.store.all('tasks'), hasLength(60));
    await bg.close();
  });
}
