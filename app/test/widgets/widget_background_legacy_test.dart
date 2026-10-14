import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/widgets/widget_background.dart';

void main() {
  test('cancelLegacySamsungSync cancela a tarefa periódica antiga "samsung-notes-sync"', () async {
    final cancelled = <String>[];
    await cancelLegacySamsungSync(cancel: (name) async => cancelled.add(name));
    expect(cancelled, ['samsung-notes-sync']);
  });

  test('cancelLegacySamsungSync ignora erros (plugin ausente, sem Android)', () async {
    await cancelLegacySamsungSync(cancel: (name) async => throw Exception('sem workmanager'));
  });

  test('a tarefa antiga é reconhecida pelo nome e não faz nada', () {
    expect(isLegacySamsungTask('samsungNotesSync'), isTrue);
    expect(isLegacySamsungTask('widgetsRefresh'), isFalse);
    expect(isLegacySamsungTask('locationReport'), isFalse);
  });
}
