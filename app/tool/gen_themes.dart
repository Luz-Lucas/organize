// Gera lib/ui/themes.dart a partir de docs/superpowers/specs/assets/themes-10.json.
// Uso (a partir de app/): dart run tool/gen_themes.dart
import 'dart:convert';
import 'dart:io';

const _ids = [
  'violeta', 'safira', 'musgo', 'lunar', 'indigo',
  'grafite', 'coral', 'cobalto', 'cacto', 'bronze',
];

const _displayNames = {'indigo': 'Índigo'};

// O JSON traz "wire-" truncado para a Safira; o nome canônico é "wiregrid".
const _motifFix = {'wire-': 'wiregrid'};

String _color(String hex) => 'Color(0xFF${hex.substring(1).toUpperCase()})';

String _str(String s) => "'${s.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll(r'$', r'\$')}'";

void main() {
  final json = jsonDecode(File('../docs/superpowers/specs/assets/themes-10.json').readAsStringSync())
      as Map<String, dynamic>;
  final b = StringBuffer()
    ..writeln('// GERADO por tool/gen_themes.dart a partir de themes-10.json. Não edite à mão.')
    ..writeln("import 'dart:ui' show Color;")
    ..writeln()
    ..writeln('/// Um sistema de design escuro (tokens dos PDFs do usuário).')
    ..writeln('class OrgThemeSpec {')
    ..writeln('  const OrgThemeSpec({')
    ..writeln('    required this.id,')
    ..writeln('    required this.name,')
    ..writeln('    required this.tagline,')
    ..writeln('    required this.display,')
    ..writeln('    required this.sans,')
    ..writeln('    required this.mono,')
    ..writeln('    required this.glyph,')
    ..writeln('    required this.motif,')
    ..writeln('    required this.radiusSm,')
    ..writeln('    required this.radiusMd,')
    ..writeln('    required this.radiusLg,')
    ..writeln('    required this.surface,')
    ..writeln('    required this.surfaceRaised,')
    ..writeln('    required this.line,')
    ..writeln('    required this.ink,')
    ..writeln('    required this.inkMuted,')
    ..writeln('    required this.accent,')
    ..writeln('    required this.accentDeep,')
    ..writeln('    required this.onAccent,')
    ..writeln('    required this.accentText,')
    ..writeln('    required this.accentSoft,')
    ..writeln('    required this.secondary,')
    ..writeln('    required this.secondarySoft,')
    ..writeln('  });')
    ..writeln()
    ..writeln('  final String id, name, tagline, display, sans, mono, glyph, motif;')
    ..writeln('  final double radiusSm, radiusMd, radiusLg;')
    ..writeln('  final Color surface, surfaceRaised, line, ink, inkMuted, accent, accentDeep,')
    ..writeln('      onAccent, accentText, accentSoft, secondary, secondarySoft;')
    ..writeln('}')
    ..writeln()
    ..writeln('/// Os 10 temas, na ordem de `themeIds`.')
    ..writeln('const List<OrgThemeSpec> orgThemes = [');
  for (final id in _ids) {
    final t = json[id] as Map<String, dynamic>;
    final tok = t['tokens'] as Map<String, dynamic>;
    String c(String k) => _color((tok[k] as List)[0] as String);
    final fonts = t['fonts'] as Map<String, dynamic>;
    final r = t['radius'] as Map<String, dynamic>;
    final motif = _motifFix[t['motif']] ?? t['motif'] as String;
    b
      ..writeln('  OrgThemeSpec(')
      ..writeln('    id: ${_str(id)},')
      ..writeln('    name: ${_str(_displayNames[id] ?? t['name'] as String)},')
      ..writeln('    tagline: ${_str(t['tagline'] as String)},')
      ..writeln('    display: ${_str(fonts['display'] as String)},')
      ..writeln('    sans: ${_str(fonts['sans'] as String)},')
      ..writeln('    mono: ${_str(fonts['mono'] as String)},')
      ..writeln('    glyph: ${_str(t['glyph'] as String)},')
      ..writeln('    motif: ${_str(motif)},')
      ..writeln('    radiusSm: ${(r['radius-sm'] as num).toDouble()},')
      ..writeln('    radiusMd: ${(r['radius-md'] as num).toDouble()},')
      ..writeln('    radiusLg: ${(r['radius-lg'] as num).toDouble()},')
      ..writeln('    surface: ${c('surface')},')
      ..writeln('    surfaceRaised: ${c('surface-raised')},')
      ..writeln('    line: ${c('line')},')
      ..writeln('    ink: ${c('ink')},')
      ..writeln('    inkMuted: ${c('ink-muted')},')
      ..writeln('    accent: ${c('accent')},')
      ..writeln('    accentDeep: ${c('accent-deep')},')
      ..writeln('    onAccent: ${c('on-accent')},')
      ..writeln('    accentText: ${c('accent-text')},')
      ..writeln('    accentSoft: ${c('accent-soft')},')
      ..writeln('    secondary: ${c('secondary')},')
      ..writeln('    secondarySoft: ${c('secondary-soft')},')
      ..writeln('  ),');
  }
  b
    ..writeln('];')
    ..writeln()
    ..writeln('/// Tema pelo id; id desconhecido volta para o Violeta.')
    ..writeln('OrgThemeSpec orgThemeById(String id) =>')
    ..writeln('    orgThemes.firstWhere((t) => t.id == id, orElse: () => orgThemes.first);');
  File('lib/ui/themes.dart').writeAsStringSync(b.toString());
}
