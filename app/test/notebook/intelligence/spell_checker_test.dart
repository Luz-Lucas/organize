import 'dart:ui' show Locale, TextRange;

import 'package:flutter/services.dart' show SpellCheckService, SuggestionSpan;
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/notebook/intelligence/spell_checker.dart';

class _FakeService implements SpellCheckService {
  _FakeService(this.dictionary);

  /// palavra errada -> sugestões; o que não está aqui está certo.
  final Map<String, List<String>> dictionary;
  final calls = <String>[];
  final locales = <Locale>[];
  int inFlight = 0;
  int maxInFlight = 0;
  Duration delay = Duration.zero;
  bool returnNull = false;
  bool throwError = false;

  @override
  Future<List<SuggestionSpan>?> fetchSpellCheckSuggestions(Locale locale, String text) async {
    calls.add(text);
    locales.add(locale);
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    await Future<void>.delayed(delay);
    inFlight--;
    if (throwError) throw StateError('canal indisponível');
    if (returnNull) return null;
    final sug = dictionary[text];
    return sug == null ? const [] : [SuggestionSpan(TextRange(start: 0, end: text.length), sug)];
  }
}

void main() {
  late _FakeService service;
  late PlatformSpellChecker checker;

  setUp(() {
    service = _FakeService({
      'cassa': ['casa', 'cassa-se'],
      'xyzzy': <String>[],
    });
    checker = PlatformSpellChecker(service: service);
  });

  test('palavra correta devolve null', () async {
    expect(await checker.suggestions('casa'), isNull);
  });

  test('palavra errada devolve as sugestões, na ordem do corretor', () async {
    expect(await checker.suggestions('cassa'), ['casa', 'cassa-se']);
  });

  test('errada sem sugestão devolve lista vazia (diferente de null)', () async {
    expect(await checker.suggestions('xyzzy'), isEmpty);
    expect(await checker.suggestions('xyzzy'), isNotNull);
  });

  test('consulta em pt-BR', () async {
    await checker.suggestions('casa');
    expect(service.locales.single, const Locale('pt', 'BR'));
  });

  test('pontuação nas pontas é ignorada; números e vazio nem são consultados', () async {
    expect(await checker.suggestions('cassa,'), ['casa', 'cassa-se']);
    expect(service.calls, ['cassa']);
    service.calls.clear();
    expect(await checker.suggestions(''), isNull);
    expect(await checker.suggestions('  '), isNull);
    expect(await checker.suggestions('2024'), isNull);
    expect(await checker.suggestions('a1b'), isNull);
    expect(service.calls, isEmpty);
  });

  test('guarda o resultado: a mesma palavra é consultada uma vez só', () async {
    await checker.suggestions('cassa');
    await checker.suggestions('cassa');
    await checker.suggestions('casa');
    await checker.suggestions('casa');
    expect(service.calls, ['cassa', 'casa']);
  });

  test('chamadas simultâneas são feitas uma de cada vez (o canal cancela pedidos concorrentes)', () async {
    service.delay = const Duration(milliseconds: 5);
    final results = await Future.wait([for (final w in ['cassa', 'casa', 'xyzzy', 'mesa']) checker.suggestions(w)]);
    expect(service.maxInFlight, 1);
    expect(results[0], ['casa', 'cassa-se']);
    expect(results[1], isNull);
    expect(results[2], isEmpty);
    expect(results[3], isNull);
  });

  test('serviço sem resposta (null) ou com erro conta como "correta" e não é guardado', () async {
    service.returnNull = true;
    expect(await checker.suggestions('cassa'), isNull);
    service.returnNull = false;
    service.throwError = true;
    expect(await checker.suggestions('cassa'), isNull);
    service.throwError = false;
    expect(await checker.suggestions('cassa'), ['casa', 'cassa-se']); // não ficou "correta" para sempre
  });

  test('NoopSpellChecker nunca marca nada', () async {
    expect(await const NoopSpellChecker().suggestions('cassa'), isNull);
  });
}
