import 'dart:async';
import 'dart:ui' show Locale;

import 'package:flutter/services.dart' show DefaultSpellCheckService, SpellCheckService;

/// Corretor ortográfico das palavras reconhecidas.
abstract class SpellChecker {
  const SpellChecker();

  /// `null` = a palavra está correta (ou não dá para saber: nunca marcar sem
  /// certeza). Lista = a palavra está errada; as sugestões vêm em ordem e a lista
  /// pode ser vazia (errada, sem sugestão).
  Future<List<String>?> suggestions(String word);
}

/// Não corrige nada (Linux, Windows, web, testes).
class NoopSpellChecker extends SpellChecker {
  const NoopSpellChecker();

  @override
  Future<List<String>?> suggestions(String word) async => null;
}

/// Corretor do Android (`DefaultSpellCheckService` do Flutter), em pt-BR.
///
/// O canal da plataforma **cancela** o pedido anterior quando chega outro, por
/// isso as consultas são feitas uma de cada vez; o resultado de cada palavra fica
/// guardado (corrigir uma página repete muitas palavras).
class PlatformSpellChecker extends SpellChecker {
  PlatformSpellChecker({
    SpellCheckService? service,
    this.locale = const Locale('pt', 'BR'),
    this.cacheLimit = 4000,
  }) : _service = service ?? DefaultSpellCheckService();

  final SpellCheckService _service;
  final Locale locale;
  final int cacheLimit;

  final _cache = <String, List<String>?>{};
  Future<void> _tail = Future<void>.value();

  static final _edges = RegExp(r'^[^\p{L}]+|[^\p{L}]+$', unicode: true);
  static final _hasDigit = RegExp(r'\d');

  /// A palavra sem pontuação nas pontas; `null` se não vale consultar (vazia ou com número).
  static String? clean(String word) {
    final w = word.trim().replaceAll(_edges, '');
    if (w.isEmpty || _hasDigit.hasMatch(w)) return null;
    return w;
  }

  @override
  Future<List<String>?> suggestions(String word) {
    final w = clean(word);
    if (w == null) return Future.value(null);
    if (_cache.containsKey(w)) return Future.value(_cache[w]);
    final run = _tail.then((_) => _lookup(w));
    _tail = run.then((_) {}, onError: (Object _) {});
    return run;
  }

  Future<List<String>?> _lookup(String w) async {
    if (_cache.containsKey(w)) return _cache[w]; // outra chamada da fila já respondeu
    try {
      final spans = await _service.fetchSpellCheckSuggestions(locale, w);
      if (spans == null) return null; // sem resposta: não guarda, tenta de novo depois
      final List<String>? result = spans.isEmpty ? null : [...spans.first.suggestions];
      if (_cache.length >= cacheLimit) _cache.remove(_cache.keys.first);
      _cache[w] = result;
      return result;
    } catch (_) {
      return null;
    }
  }
}
