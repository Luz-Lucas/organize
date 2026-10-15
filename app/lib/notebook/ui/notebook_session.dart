/// Contrato entre a tela do Caderno e a camada de dados.
///
/// A tela **não conhece** repositório, Supabase nem Riverpod: ela recebe um
/// [NotebookSession] e um [NotebookImageStore]. O `NotebookController`
/// implementa [NotebookSession]; os testes da tela usam implementações falsas.
///
/// ```dart
/// enum SaveStatus { saving, saved, offline, problem, noteDeleted }
/// enum PageNotice { none, nearLimit, tooLarge, newerVersion }
///
/// class NotebookPageState {            // uma página, como a UI a vê
///   final String id;                    // identidade estável da página
///   final int idx;                      // 0, 1, 2… (ordem na rolagem)
///   final PageBackground background;    // blank | lined | grid | dots
///   final PageDoc doc;                  // conteúdo (core/page_doc.dart)
///   final PageNotice notice;            // aviso da página (grande, versão nova…)
/// }
///
/// abstract class NotebookImageStore {
///   Future<String> upload(Uint8List bytes, String ext); // -> caminho no Storage
///   Future<ImageProvider> load(String path);            // caminho -> imagem
/// }
///
/// abstract class NotebookSession {
///   Stream<List<NotebookPageState>> get pages;   // ordenada por idx
///   SaveStatus get status;                       // valor atual
///   Stream<SaveStatus> get statusChanges;        // mudanças de [status]
///   NotebookImageStore get images;
///   void updatePage(String id, PageDoc doc);     // edição concluída
///   void addPage({PageBackground background, PageDoc? initial}); // acrescenta no fim
///   void deletePage(String id);
///   void duplicatePage(String id);               // cópia logo após a página
///   void setBackground(String id, PageBackground background);
/// }
/// ```
///
/// ## Regras que a implementação precisa honrar
///
/// * **Toda operação por página usa o id**, nunca o índice: a lista muda sob a
///   tela (duplicar, apagar, página inserida por outro aparelho) e um índice
///   guardado antes de um diálogo ou de um envio apontaria para outra página.
///   A tela junta o que chega de [NotebookSession.pages] ao que exibe **só entre
///   páginas de mesmo id**; a ordem vem da lista.
/// * [NotebookSession.pages] **repete o último valor** para quem começa a
///   escutar (ou emite o estado atual assim que a tela escuta) e emite de novo
///   após qualquer mudança de estrutura (`addPage`, `deletePage`,
///   `duplicatePage`, `setBackground`) e quando chegam páginas de outro
///   aparelho. Pode ser `Stream.multi`/`BehaviorSubject`-like; não precisa ser
///   broadcast se só a tela escuta, mas precisa suportar nova escuta.
/// * [NotebookSession.updatePage] é chamado **ao fim de cada gesto** (traço
///   solto, borracha levantada, mover/redimensionar do laço, texto confirmado,
///   imagem inserida, desfazer/refazer, colar…), não a cada ponto. A
///   implementação aplica o documento localmente na hora, agenda o salvamento
///   (debounce de 1,5 s, no máximo 10 s de espera) e atualiza
///   [NotebookSession.status]. Ela **não** precisa reemitir o próprio
///   `updatePage` em `pages` (a tela já exibe o que desenhou), mas pode: a tela
///   mescla o que chega com o que tem (`local.merge(remoto)`, união por id menos
///   tombstones), então eco atrasado é inofensivo. Id desconhecido é ignorado.
/// * `pages` pode trazer documentos **mais novos** de outro aparelho (já
///   mesclados pelo repositório): a tela os mescla ao que está exibindo.
/// * `deletePage` reindexa: as páginas seguintes sobem um índice. A tela
///   descarta o estado local da página apagada imediatamente e espera `pages`
///   com a nova lista.
/// * [NotebookPageState.notice] avisa a tela: [PageNotice.newerVersion] = página
///   gravada por um app mais novo (a tela a mostra só para leitura e **não**
///   chama `updatePage` nela); [PageNotice.tooLarge] = o servidor recusou por
///   passar do limite; [PageNotice.nearLimit] = perto do limite.
/// * [SaveStatus.problem] = alguma página não pôde ser salva (veja os avisos das
///   páginas); [SaveStatus.noteDeleted] = o caderno foi excluído em outro aparelho.
/// * [NotebookImageStore.upload] devolve o caminho que vai no `ImageBox.path`
///   (ex.: `<user_id>/<note_id>/<uuid>.png`); [NotebookImageStore.load] resolve
///   esse caminho para um [ImageProvider] (URL assinada com cache). Erros de
///   `load` mostram um quadro cinza no lugar da imagem, sem quebrar a página.
library;

import 'dart:typed_data';

import 'package:flutter/painting.dart' show ImageProvider;

import '../core/notebook_core.dart';

/// Estado de salvamento mostrado na barra da tela.
enum SaveStatus {
  /// Alterações ainda não confirmadas no servidor.
  saving,

  /// Tudo salvo.
  saved,

  /// Sem conexão: salvo só no aparelho (será enviado quando voltar).
  offline,

  /// Algo não pôde ser salvo e não adianta tentar de novo (ex.: página grande
  /// demais). O aviso está na página; o resto do caderno continua salvando.
  problem,

  /// O caderno foi excluído em outro aparelho: nada mais será gravado.
  noteDeleted,
}

/// Aviso sobre uma página.
enum PageNotice {
  none,

  /// Perto do limite de tamanho do servidor (≈ 3 MB de 4 MB).
  nearLimit,

  /// O servidor recusou a página por passar do limite; ela não é regravada
  /// enquanto não diminuir.
  tooLarge,

  /// Gravada por uma versão mais nova do app: só leitura.
  newerVersion,
}

/// Uma página do caderno, como a tela a enxerga.
class NotebookPageState {
  const NotebookPageState({
    required this.id,
    required this.idx,
    required this.background,
    required this.doc,
    this.notice = PageNotice.none,
  });

  /// Identidade estável da página (uuid); é a chave de todas as operações.
  final String id;
  final int idx;
  final PageBackground background;
  final PageDoc doc;
  final PageNotice notice;

  /// Página que a tela não deve editar.
  bool get readOnly => notice == PageNotice.newerVersion;

  NotebookPageState copyWith({
    String? id,
    int? idx,
    PageBackground? background,
    PageDoc? doc,
    PageNotice? notice,
  }) => NotebookPageState(
    id: id ?? this.id,
    idx: idx ?? this.idx,
    background: background ?? this.background,
    doc: doc ?? this.doc,
    notice: notice ?? this.notice,
  );

  @override
  bool operator ==(Object other) =>
      other is NotebookPageState &&
      other.id == id &&
      other.idx == idx &&
      other.background == background &&
      other.notice == notice &&
      identical(other.doc, doc);

  @override
  int get hashCode => Object.hash(id, idx, background, notice, identityHashCode(doc));
}

/// Armazenamento das imagens do caderno (Supabase Storage na Task 4).
abstract class NotebookImageStore {
  /// Envia [bytes] (extensão [ext] sem ponto, ex.: `png`) e devolve o caminho
  /// a gravar em `ImageBox.path`.
  Future<String> upload(Uint8List bytes, String ext);

  /// Resolve [path] (de um `ImageBox`) para uma imagem exibível.
  Future<ImageProvider> load(String path);
}

/// Tudo de que a [NotebookScreen] precisa do mundo exterior.
abstract class NotebookSession {
  /// Páginas ordenadas por `idx`. Repete o último valor a quem escuta.
  Stream<List<NotebookPageState>> get pages;

  /// Estado de salvamento atual.
  SaveStatus get status;

  /// Emite cada mudança de [status].
  Stream<SaveStatus> get statusChanges;

  NotebookImageStore get images;

  /// Um gesto terminou: [doc] é o novo conteúdo da página [id].
  void updatePage(String id, PageDoc doc);

  /// Nova página no fim do caderno. Com [initial], a página já nasce com esse
  /// conteúdo (ex.: a página de um PDF como fundo) e é salva como uma edição.
  void addPage({PageBackground background = PageBackground.lined, PageDoc? initial});

  void deletePage(String id);

  /// Duplica a página [id] (fundo e conteúdo) logo depois dela.
  void duplicatePage(String id);

  void setBackground(String id, PageBackground background);
}
