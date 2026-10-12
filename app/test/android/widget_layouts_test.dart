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
}
