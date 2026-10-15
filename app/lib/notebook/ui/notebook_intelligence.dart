import '../intelligence/recognizer.dart';
import '../intelligence/spell_checker.dart';
import '../intelligence/transcript.dart';

/// O que a tela do Caderno precisa da "inteligência da escrita" (fase 2).
///
/// Como a [NotebookSession], a tela não conhece Riverpod nem o controller: a rota
/// monta este objeto com os providers e o controller; os testes, com falsos. O
/// padrão ([NotebookIntelligence.off]) desliga tudo: sem gestos, sem corretor e
/// sem conversão (como no Linux sem reconhecedor).
class NotebookIntelligence {
  const NotebookIntelligence({
    this.recognizer = const NoopInkRecognizer(),
    this.spellChecker = const NoopSpellChecker(),
    this.gestures = false,
    this.spellCheck = false,
    this.transcripts = const Stream.empty(),
    this.transcriptOf,
    this.recognizedTextOf,
    this.ignoredWords = const {},
    this.onIgnoreWord,
  });

  static const off = NotebookIntelligence();

  /// Reconhecedor para "Converter em texto". `supported == false` (Linux, Windows)
  /// esconde a conversão e mostra a dica "disponível no Android".
  final InkRecognizer recognizer;

  final SpellChecker spellChecker;

  /// "Gestos de edição" ligado: rabisco apaga, ∧ abre espaço, traço vertical
  /// separa, arco junta.
  final bool gestures;

  /// "Corretor ortográfico" ligado: palavras suspeitas ganham sublinhado ondulado.
  final bool spellCheck;

  /// Cada transcrição feita em segundo plano (para recalcular o sublinhado).
  final Stream<({String pageId, PageTranscript transcript})> transcripts;

  /// A última transcrição da página neste aparelho, se houver.
  final PageTranscript? Function(String pageId)? transcriptOf;

  /// O texto reconhecido da página (deste aparelho ou do servidor), para
  /// "Copiar texto da página" também no Linux e no Windows.
  final String Function(String pageId)? recognizedTextOf;

  /// Dicionário pessoal ("Ignorar"): minúsculas, sem pontuação.
  final Set<String> ignoredWords;

  /// Guarda uma palavra no dicionário pessoal.
  final void Function(String word)? onIgnoreWord;
}
