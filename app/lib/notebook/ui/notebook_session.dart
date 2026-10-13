/// Contrato entre a tela do Caderno (Task 3) e a camada de dados (Task 4).
///
/// A tela **não conhece** repositório, Supabase nem Riverpod: ela recebe um
/// [NotebookSession] e um [NotebookImageStore]. O `NotebookController` da Task 4
/// implementa [NotebookSession]; os testes da tela usam implementações falsas.
///
/// ```dart
/// enum SaveStatus { saving, saved, offline }
///
/// class NotebookPageState {            // uma página, como a UI a vê
///   final int idx;                      // 0, 1, 2… (ordem na rolagem)
///   final PageBackground background;    // blank | lined | grid | dots
///   final PageDoc doc;                  // conteúdo (core/page_doc.dart)
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
///   void updatePage(int idx, PageDoc doc);       // edição concluída
///   void addPage({PageBackground background});   // acrescenta no fim
///   void deletePage(int idx);
///   void duplicatePage(int idx);                 // cópia logo após idx
///   void setBackground(int idx, PageBackground background);
/// }
/// ```
///
/// ## Regras que a implementação (Task 4) precisa honrar
///
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
///   (debounce de 1,5 s) e atualiza [NotebookSession.status]. Ela **não** precisa
///   reemitir o próprio `updatePage` em `pages` (a tela já exibe o que desenhou),
///   mas pode: a tela mescla o que chega com o que tem (`local.merge(remoto)`,
///   união por id menos tombstones), então eco atrasado é inofensivo.
/// * `pages` pode trazer documentos **mais novos** de outro aparelho (já
///   mesclados pelo repositório): a tela os mescla ao que está exibindo.
/// * `deletePage` reindexa: as páginas seguintes sobem um índice. A tela
///   descarta o estado local da página apagada imediatamente e espera `pages`
///   com a nova lista.
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
}

/// Uma página do caderno, como a tela a enxerga.
class NotebookPageState {
  const NotebookPageState({
    required this.idx,
    required this.background,
    required this.doc,
  });

  final int idx;
  final PageBackground background;
  final PageDoc doc;

  NotebookPageState copyWith({
    int? idx,
    PageBackground? background,
    PageDoc? doc,
  }) => NotebookPageState(
    idx: idx ?? this.idx,
    background: background ?? this.background,
    doc: doc ?? this.doc,
  );

  @override
  bool operator ==(Object other) =>
      other is NotebookPageState &&
      other.idx == idx &&
      other.background == background &&
      identical(other.doc, doc);

  @override
  int get hashCode => Object.hash(idx, background, identityHashCode(doc));
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

  /// Um gesto terminou: [doc] é o novo conteúdo da página [idx].
  void updatePage(int idx, PageDoc doc);

  /// Nova página no fim do caderno.
  void addPage({PageBackground background = PageBackground.lined});

  void deletePage(int idx);

  /// Duplica a página [idx] (fundo e conteúdo) logo depois dela.
  void duplicatePage(int idx);

  void setBackground(int idx, PageBackground background);
}
