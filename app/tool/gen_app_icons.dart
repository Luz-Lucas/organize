// Gera os ícones adaptativos por tema (Android) a partir de
// docs/superpowers/specs/assets/themes-10.json (índice 0 de cada token = escuro).
// Uso (a partir de app/): dart run tool/gen_app_icons.dart
//
// Saída em android/app/src/main/res/:
//   values/ic_launcher_colors.xml
//   drawable/ic_launcher_fg_<id>.xml, drawable/ic_launcher_mono.xml
//   mipmap-anydpi-v26/ic_launcher_<id>.xml
//
// Desenho (viewport 108dp, zona segura central de 66dp): fundo = surface; um
// cartão arredondado em accent-deep com um "check" em on-accent e uma faixa
// superior (cabeçalho de calendário) em accent-text. A camada monochrome tem a
// mesma silhueta (cartão e cabeçalho cheios, check vazado).
import 'dart:convert';
import 'dart:io';

const _ids = [
  'violeta', 'safira', 'musgo', 'lunar', 'indigo',
  'grafite', 'coral', 'cobalto', 'cacto', 'bronze',
];

const _res = 'android/app/src/main/res';

// Geometria (dp no viewport de 108).
const _header = 'M34,40 A7,7 0 0 1 41,33 L67,33 A7,7 0 0 1 74,40 L74,41 L34,41 Z';
const _body = 'M34,42.5 L74,42.5 L74,68 A7,7 0 0 1 67,75 L41,75 A7,7 0 0 1 34,68 Z';
const _check = 'M43,59.5 L46.5,56 L51,60.5 L62,49.5 L65.5,53 L51,67.5 Z';

String _hex(Map tokens, String name) =>
    (tokens[name][0] as String).substring(1).toUpperCase();

void _write(String path, String content) {
  final f = File(path)..createSync(recursive: true);
  f.writeAsStringSync(content);
}

void main() {
  final json = jsonDecode(File('../docs/superpowers/specs/assets/themes-10.json').readAsStringSync())
      as Map<String, dynamic>;
  final colors = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="utf-8"?>')
    ..writeln('<!-- GERADO por tool/gen_app_icons.dart a partir de themes-10.json. Não edite à mão. -->')
    ..writeln('<resources>');
  for (final id in _ids) {
    final t = (json[id] as Map<String, dynamic>)['tokens'] as Map;
    colors
      ..writeln('    <color name="ic_bg_$id">#${_hex(t, 'surface')}</color>')
      ..writeln('    <color name="ic_card_$id">#${_hex(t, 'accent-deep')}</color>')
      ..writeln('    <color name="ic_head_$id">#${_hex(t, 'accent-text')}</color>')
      ..writeln('    <color name="ic_check_$id">#${_hex(t, 'on-accent')}</color>');

    _write('$_res/drawable/ic_launcher_fg_$id.xml', '''<?xml version="1.0" encoding="utf-8"?>
<!-- GERADO por tool/gen_app_icons.dart. Não edite à mão. -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <path android:fillColor="@color/ic_head_$id" android:pathData="$_header" />
    <path android:fillColor="@color/ic_card_$id" android:pathData="$_body" />
    <path android:fillColor="@color/ic_check_$id" android:pathData="$_check" />
</vector>
''');

    _write('$_res/mipmap-anydpi-v26/ic_launcher_$id.xml', '''<?xml version="1.0" encoding="utf-8"?>
<!-- GERADO por tool/gen_app_icons.dart. Não edite à mão. -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_bg_$id" />
    <foreground android:drawable="@drawable/ic_launcher_fg_$id" />
    <monochrome android:drawable="@drawable/ic_launcher_mono" />
</adaptive-icon>
''');
  }
  colors.writeln('</resources>');
  _write('$_res/values/ic_launcher_colors.xml', colors.toString());

  _write('$_res/drawable/ic_launcher_mono.xml', '''<?xml version="1.0" encoding="utf-8"?>
<!-- GERADO por tool/gen_app_icons.dart. Não edite à mão. -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <path android:fillColor="#FF000000" android:pathData="$_header" />
    <path
        android:fillColor="#FF000000"
        android:fillType="evenOdd"
        android:pathData="$_body $_check" />
</vector>
''');
  stdout.writeln('Ícones gerados em $_res');
}
