import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/domain/alexa.dart';
import 'package:organizacional/domain/system_notices.dart';
import 'package:organizacional/domain/task_item.dart';

void main() {
  final now = DateTime(2026, 10, 10, 22); // sábado
  final yesterday = DateTime(2026, 10, 9, 12);
  TaskItem late(String id) => TaskItem(id: id, title: id, dueAt: yesterday);
  const plan = WakePlan(id: 'p1', label: 'Aula', days: [7], hour: 6, minute: 30, echoDeviceId: 'E');
  final okBridge = BridgeStatus(state: BridgeState.ok, lastSeen: now);

  test('duas tarefas atrasadas', () {
    final n = systemNotices(now: now, tasks: [late('a'), late('b')], bridge: okBridge, wakePlans: const []);
    expect(n.single.id, 'overdue');
    expect(n.single.text, '2 tarefas atrasadas');
    expect(n.single.route, '/tarefas');
  });
  test('uma tarefa atrasada', () {
    final n = systemNotices(now: now, tasks: [late('a')], bridge: okBridge, wakePlans: const []);
    expect(n.single.text, '1 tarefa atrasada');
  });
  test('tarefa feita não conta', () {
    final done = late('a').moved(TaskStatus.done, now);
    expect(systemNotices(now: now, tasks: [done], bridge: okBridge, wakePlans: const []), isEmpty);
  });
  test('despertar ativo nas próximas 24h', () {
    final n = systemNotices(now: now, tasks: const [], bridge: okBridge, wakePlans: const [plan]);
    expect(n.single.id, 'wake-p1');
    expect(n.single.text, 'Despertar “Aula” amanhã às 06:30');
    expect(n.single.route, '/casa');
  });
  test('despertar desativado não avisa', () {
    final off = plan.copyWith(enabled: false);
    expect(systemNotices(now: now, tasks: const [], bridge: okBridge, wakePlans: [off]), isEmpty);
  });
  test('ponte offline com plano ativo', () {
    final off = BridgeStatus(state: BridgeState.ok, lastSeen: now.subtract(const Duration(hours: 1)));
    final n = systemNotices(now: now, tasks: const [], bridge: off, wakePlans: const [plan]);
    expect(n.firstWhere((x) => x.id == 'bridge').text, bridgeWarning(off, const [plan], now));
  });
}
