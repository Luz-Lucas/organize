import '../../data/repository.dart';
import '../core/notebook_core.dart';
import 'notebook_page.dart';

/// Por que uma gravação do caderno falhou. Só [transient] merece nova tentativa;
/// as outras são **permanentes**: repetir o mesmo envio dá o mesmo erro.
enum NotebookErrorKind {
  /// Sem rede, timeout, 5xx… tentar de novo mais tarde pode funcionar.
  transient,

  /// A página passa do limite de 4 MB do servidor (CHECK 23514).
  pageTooLarge,

  /// A nota/o caderno não existe mais ou não é mais nosso (FK 23503, RLS 42501).
  noteGone,

  /// O dado do servidor está num formato que este app não entende (versão mais nova).
  newerFormat,
}

/// [RepositoryException] com a classificação do erro ([kind]) e o código do Postgres.
class NotebookRepositoryException extends RepositoryException {
  const NotebookRepositoryException(
    super.message, {
    this.kind = NotebookErrorKind.transient,
    this.code,
    super.duplicate,
  });

  final NotebookErrorKind kind;

  /// Código SQLSTATE do Postgres, quando houver.
  final String? code;

  /// Classifica um código SQLSTATE.
  static NotebookErrorKind kindOfCode(String? code) => switch (code) {
        '23514' => NotebookErrorKind.pageTooLarge,
        '23503' || '42501' => NotebookErrorKind.noteGone,
        _ => NotebookErrorKind.transient,
      };

  /// Permanente = não adianta repetir o mesmo envio.
  bool get permanent => kind != NotebookErrorKind.transient;
}

/// Páginas de um caderno (`note_pages`). Erros viram `RepositoryException`.
abstract interface class NotebookRepository {
  /// Páginas do caderno, por `idx`; emite a lista atual e cada mudança.
  Stream<List<NotebookPage>> watchPages(String noteId);

  Future<List<NotebookPage>> listPages(String noteId);

  /// Primeira página (menor idx), para a miniatura; `null` se não há páginas.
  Future<NotebookPage?> firstPage(String noteId);

  /// Texto reconhecido (fase 2) das páginas, junto por caderno: `noteId -> texto`.
  /// Só entram cadernos com algum texto; usado na busca de notas.
  Future<Map<String, String>> recognizedTextByNote();

  /// Cria uma página. [id] opcional (uuid gerado pelo cliente; se já existir,
  /// devolve a existente, o que torna a fila offline idempotente). Sem [at],
  /// vai para o fim; com [at], entra nessa posição e as seguintes descem.
  Future<NotebookPage> addPage(
    String noteId, {
    PageBackground background = PageBackground.lined,
    String? id,
    int? at,
  });

  /// Grava [page].data contra a versão otimista [page].version. **Não grava o
  /// fundo** (isso é só de [setBackground]); o `background` de [page] só vale
  /// quando a página precisa ser recriada. Se outro aparelho
  /// gravou antes, relê, mescla (`decode → merge → encode`) e grava de novo, até
  /// conseguir. Devolve a página como ficou no servidor (dados mesclados, versão nova);
  /// quem chamou deve adotar o resultado. Também "toca" `notes.updated_at`.
  /// Se a página foi apagada em outro aparelho, é recriada no fim (a tinta não se perde).
  Future<NotebookPage> savePage(NotebookPage page);

  Future<void> setBackground(String pageId, PageBackground background);

  /// Apaga a página e reindexa as seguintes.
  Future<void> deletePage(String pageId);

  /// Copia a página (mesma tinta e fundo, id novo) logo depois dela.
  Future<NotebookPage> duplicatePage(String pageId);

  /// [pageIds] é a nova ordem completa das páginas do caderno.
  Future<void> reorder(String noteId, List<String> pageIds);
}

/// Mescla os dados de duas versões da mesma página (união por id menos tombstones).
String mergePageData(String remote, String local) =>
    encodePage(decodePage(remote).merge(decodePage(local)));
