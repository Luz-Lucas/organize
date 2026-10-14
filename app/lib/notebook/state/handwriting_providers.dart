import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../intelligence/spell_checker.dart';

/// Chaves de "Ajustes → Escrita à mão". Valem **por aparelho** (não vão para a
/// nuvem) e vêm todas ligadas.
class HandwritingPrefs {
  const HandwritingPrefs({this.recognize = true, this.spellCheck = true, this.gestures = true});

  /// "Reconhecer escrita (busca)": transcreve a escrita para a busca e o texto da página.
  final bool recognize;

  /// "Corretor ortográfico": sublinha palavras suspeitas e sugere correções.
  final bool spellCheck;

  /// "Gestos de edição": rabisco apaga, ∧ abre espaço, traço vertical separa, arco junta.
  final bool gestures;

  HandwritingPrefs copyWith({bool? recognize, bool? spellCheck, bool? gestures}) => HandwritingPrefs(
        recognize: recognize ?? this.recognize,
        spellCheck: spellCheck ?? this.spellCheck,
        gestures: gestures ?? this.gestures,
      );

  @override
  bool operator ==(Object other) =>
      other is HandwritingPrefs &&
      other.recognize == recognize &&
      other.spellCheck == spellCheck &&
      other.gestures == gestures;

  @override
  int get hashCode => Object.hash(recognize, spellCheck, gestures);
}

/// Onde as chaves ficam guardadas no aparelho.
abstract interface class HandwritingPrefsStore {
  Future<HandwritingPrefs> load();
  Future<void> save(HandwritingPrefs prefs);
}

class MemoryHandwritingPrefsStore implements HandwritingPrefsStore {
  HandwritingPrefs value = const HandwritingPrefs();

  @override
  Future<HandwritingPrefs> load() async => value;

  @override
  Future<void> save(HandwritingPrefs prefs) async => value = prefs;
}

class SharedPreferencesHandwritingPrefsStore implements HandwritingPrefsStore {
  const SharedPreferencesHandwritingPrefsStore();

  static const _recognize = 'handwriting.recognize';
  static const _spell = 'handwriting.spell';
  static const _gestures = 'handwriting.gestures';

  @override
  Future<HandwritingPrefs> load() async {
    final p = await SharedPreferences.getInstance();
    return HandwritingPrefs(
      recognize: p.getBool(_recognize) ?? true,
      spellCheck: p.getBool(_spell) ?? true,
      gestures: p.getBool(_gestures) ?? true,
    );
  }

  @override
  Future<void> save(HandwritingPrefs prefs) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_recognize, prefs.recognize);
    await p.setBool(_spell, prefs.spellCheck);
    await p.setBool(_gestures, prefs.gestures);
  }
}

/// Os testes usam a memória; `main.dart` troca por [SharedPreferencesHandwritingPrefsStore].
final handwritingPrefsStoreProvider =
    Provider<HandwritingPrefsStore>((ref) => MemoryHandwritingPrefsStore());

class HandwritingPrefsNotifier extends Notifier<HandwritingPrefs> {
  bool _chosen = false;

  @override
  HandwritingPrefs build() {
    unawaited(_restore());
    return const HandwritingPrefs();
  }

  Future<void> _restore() async {
    try {
      final saved = await ref.read(handwritingPrefsStoreProvider).load();
      if (!_chosen && ref.mounted) state = saved;
    } catch (_) {
      // Sem preferência guardada: ficam os padrões (tudo ligado).
    }
  }

  Future<void> _set(HandwritingPrefs next) async {
    _chosen = true;
    state = next;
    try {
      await ref.read(handwritingPrefsStoreProvider).save(next);
    } catch (_) {
      // A escolha vale nesta sessão mesmo que não dê para guardar.
    }
  }

  Future<void> setRecognize(bool v) => _set(state.copyWith(recognize: v));
  Future<void> setSpellCheck(bool v) => _set(state.copyWith(spellCheck: v));
  Future<void> setGestures(bool v) => _set(state.copyWith(gestures: v));
}

final handwritingPrefsProvider =
    NotifierProvider<HandwritingPrefsNotifier, HandwritingPrefs>(HandwritingPrefsNotifier.new);

/// "Reconhecer escrita (busca)" ligado neste aparelho?
final recognizeWritingEnabledProvider =
    Provider<bool>((ref) => ref.watch(handwritingPrefsProvider.select((p) => p.recognize)));

/// "Corretor ortográfico" ligado neste aparelho?
final spellCheckEnabledProvider =
    Provider<bool>((ref) => ref.watch(handwritingPrefsProvider.select((p) => p.spellCheck)));

/// "Gestos de edição" ligado neste aparelho?
final editGesturesEnabledProvider =
    Provider<bool>((ref) => ref.watch(handwritingPrefsProvider.select((p) => p.gestures)));

/// O corretor ortográfico desta plataforma. Padrão: [NoopSpellChecker]; `main.dart`
/// troca por `PlatformSpellChecker` no Android.
final spellCheckerProvider = Provider<SpellChecker>((ref) => const NoopSpellChecker());
