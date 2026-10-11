import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/domain/notice.dart';

void main() {
  final now = DateTime(2026, 10, 11, 12);
  test('activeNotices tira arquivados e expirados e ordena fixado > alta > recente', () {
    final list = activeNotices([
      Notice(id: 'velho', title: 'a', createdAt: DateTime(2026, 10, 1)),
      Notice(id: 'novo', title: 'b', createdAt: DateTime(2026, 10, 10)),
      Notice(id: 'alta', title: 'c', priority: NoticePriority.alta, createdAt: DateTime(2026, 9, 1)),
      Notice(id: 'fixo', title: 'd', pinned: true, createdAt: DateTime(2026, 8, 1)),
      Notice(id: 'exp', title: 'e', expiresAt: DateTime(2026, 10, 10)),
      Notice(id: 'arq', title: 'f', archivedAt: DateTime(2026, 10, 9)),
    ], now);
    expect(list.map((n) => n.id), ['fixo', 'alta', 'novo', 'velho']);
  });
  test('expira exatamente agora conta como expirado', () {
    expect(activeNotices([Notice(id: 'x', title: 'x', expiresAt: now)], now), isEmpty);
  });
  test('toMap/fromMap ida e volta', () {
    final n = Notice(id: 'i', title: 't', body: 'b', priority: NoticePriority.alta, pinned: true,
        expiresAt: DateTime.utc(2026, 10, 12).toLocal());
    final back = Notice.fromMap({...n.toMap(), 'created_at': '2026-10-11T00:00:00Z'});
    expect([back.title, back.body, back.priority, back.pinned, back.expiresAt],
        [n.title, n.body, n.priority, n.pinned, n.expiresAt]);
  });
  test('prioridade desconhecida vira normal e copyWith limpa o prazo', () {
    final n = Notice.fromMap({'id': 'i', 'title': 't', 'priority': 'x', 'expires_at': '2026-10-12T00:00:00Z'});
    expect(n.priority, NoticePriority.normal);
    expect(n.copyWith(clearExpires: true).expiresAt, isNull);
  });
}
