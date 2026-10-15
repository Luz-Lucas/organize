import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Classes que o Android aceita dentro de um widget de tela inicial (RemoteViews).
/// Qualquer outra (até um `<View>` simples) faz o launcher mostrar "Couldn't add widget".
const _allowed = {
  'FrameLayout', 'LinearLayout', 'RelativeLayout', 'GridLayout',
  'AnalogClock', 'Button', 'Chronometer', 'ImageButton', 'ImageView', 'ProgressBar', 'TextView',
  'ViewFlipper', 'ListView', 'GridView', 'StackView', 'AdapterViewFlipper', 'ViewStub',
  'CheckBox', 'RadioButton', 'RadioGroup', 'Switch',
};

void main() {
  final layouts = Directory('android/app/src/main/res/layout')
      .listSync()
      .whereType<File>()
      .where((f) => f.uri.pathSegments.last.startsWith('widget_'))
      .toList();

  test('existem layouts de widget', () => expect(layouts.length, greaterThanOrEqualTo(4)));

  for (final f in layouts) {
    test('${f.uri.pathSegments.last} só usa elementos permitidos em widgets', () {
      final tags = RegExp(r'<([A-Za-z][A-Za-z0-9_.]*)').allMatches(f.readAsStringSync()).map((m) => m.group(1)!);
      final bad = tags.where((t) => !_allowed.contains(t)).toSet();
      expect(bad, isEmpty, reason: 'elementos proibidos em RemoteViews: $bad');
    });
  }

  for (final f in layouts) {
    test('${f.uri.pathSegments.last} tem o ImageView de fundo @+id/bg (transparência vale para todos)', () {
      final src = f.readAsStringSync();
      final bg = RegExp(r'<ImageView[^>]*android:id="@\+id/bg"[^>]*>').firstMatch(src);
      expect(bg, isNotNull);
      expect(bg!.group(0), contains('@drawable/widget_bg'));
    });
  }

  group('widget_agenda_tarefas', () {
    final src = File('android/app/src/main/res/layout/widget_agenda_tarefas.xml').readAsStringSync();

    String tag(String id) {
      final m = RegExp('<[A-Za-z]+[^>]*android:id="@\\+id/$id"[^>]*>').firstMatch(src);
      expect(m, isNotNull, reason: 'faltou @+id/$id');
      return m!.group(0)!;
    }

    for (final id in ['section_events', 'section_tasks']) {
      test('$id ocupa metade da altura (0dp, peso 1)', () {
        final t = tag(id);
        expect(t, contains('android:layout_height="0dp"'));
        expect(t, contains('android:layout_weight="1"'));
      });
    }

    test('seis linhas por seção, cada uma com horário e título', () {
      for (final p in ['ev', 'tk']) {
        for (var i = 1; i <= 6; i++) {
          tag('${p}_row$i');
          tag('${p}_row${i}_time');
          tag('${p}_row${i}_title');
        }
        expect(src, isNot(contains('@+id/${p}_row7')));
        tag('${p}_more');
        tag('${p}_empty');
        tag('${p}_title');
        tag('${p}_icon');
      }
    });

    test('o horário/prazo tem largura fixa para alinhar em coluna', () {
      for (var i = 1; i <= 6; i++) {
        expect(tag('ev_row${i}_time'), contains('android:layout_width="52dp"'));
        expect(tag('tk_row${i}_time'), contains('android:layout_width="52dp"'));
      }
    });
  });
}
