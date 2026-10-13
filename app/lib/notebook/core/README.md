# Núcleo de tinta do Caderno (`app/lib/notebook/core/`)

Dart puro (só `dart:ui` para `Offset`/`Rect`, `dart:io` para gzip). Sem widgets.
Importe tudo por `package:organizacional/notebook/core/notebook_core.dart`.

## Ajustes e acréscimos à "API fixa" do plano (nada foi removido)

1. **`TextBox` colide com o `TextBox` do `dart:ui`/Flutter.** Nome mantido como no
   plano. Em arquivos que importam `flutter/material.dart` (ou `dart:ui`) use
   `import 'package:flutter/material.dart' hide TextBox;`. Também existe o alias
   `typedef InkText = TextBox;`.
2. **Formato dos pontos no JSON v1.** O gzip quase não comprime `pts` absolutos
   (`[x,y,p,...]` em decimal: 2.000 traços × 100 pontos = 1,56 MB). O `encodePage`
   grava os pontos de cada traço como `"q"`: inteiros (x e y em décimos, pressão em
   centésimos), 1º ponto absoluto e os demais em delta (= 0,70 MB, 2,2× menor). O
   `decodePage` lê **as duas** formas (`q` e `pts` literal da spec). Mesma
   quantização da spec (0,1 / 0,01). Quem ler o JSON fora do Dart precisa conhecer `q`.
3. **Edição = apagar + criar com id novo.** `transformItems`, `recolor`,
   `erasePartial` e `History` nunca alteram um item: tombstonam o antigo e criam
   outro (id de `newId`, padrão `newInkId()`). Por isso existem as variantes
   `*Mapped` que devolvem `EditResult(doc, idMap)` (`idMap`: id antigo → novo) para
   a UI manter a seleção do laço.
4. **Ids e ordem de empilhamento.** `String newInkId()` gera ids únicos e
   estritamente crescentes (17 chars: tempo + sequência + aleatório). `merge`
   ordena os itens por id, então a ordem de empilhamento canônica = ordem de
   criação, igual nos dois aparelhos. **Use `newInkId()` para ids de traços,
   textos e imagens novos.** Itens editados/pedaços/revividos vão para o topo.
5. **`History` é imutável e guarda diferenças**, não cópias. Assinatura final:
   `History({limit = 100})`, `record(before, after) → History`,
   `undo(current, {newId}) → HistoryStep?`, `redo(current, {newId}) → HistoryStep?`
   (`HistoryStep{history, doc, idMap}`), `canUndo/canRedo/undoCount/redoCount`.
   Desfazer é uma **nova edição** sobre o documento atual (itens apagados voltam
   como cópias com id novo; itens criados são tombstonados). Motivo: voltar a um
   snapshot antigo seria desfeito pelo `merge` com o servidor (o tombstone vence) e
   apagaria traços vindos de outro aparelho. Passos sem efeito (outro aparelho já
   apagou) são pulados. Chame `record(antes, depois)` a cada gesto concluído.
6. **`encodePage(PageDoc.empty) == ''`** (página sem itens nem tombstones). Página só
   com tombstones NÃO é vazia (precisa propagar a exclusão).
7. **`PageDoc.withoutEphemeralTombstones(before)`** descarta os tombstones de ids que
   não existiam em `before`: itens que nasceram e morreram no mesmo gesto (a borracha
   parcial refaz o documento a cada movimento; 30 linhas apagadas deixavam 4.440
   tombstones). A tela chama isso ao fechar cada gesto; os tombstones de itens que já
   existiam continuam, para a exclusão se propagar no merge.

## API final

```dart
const double pageWidth = 1000.0, pageHeight = 1414.0;
enum PenTool { fountain, pen, pencil, highlighter }
enum PageBackground { blank, lined, grid, dots }

class InkPoint { final double x, y, p; Offset get offset; InkPoint quantized(); }
class Stroke {            // imutável; points não vazia
  final String id; final PenTool tool; final int argb; final double width;
  final List<InkPoint> points;      // imutável
  late final Rect bounds;           // pontos + meia espessura
  Stroke copyWith({...}); Stroke quantized();
}
class TextBox  { id, x, y, w, text, size, argb;  Rect get bounds /*altura estimada*/; copyWith; quantized }
class ImageBox { id, x, y, w, h, path;           Rect get bounds; copyWith; quantized }

class PageDoc {            // imutável
  factory PageDoc({strokes, texts, images, deleted});   // normaliza
  static final PageDoc empty;
  final List<Stroke> strokes; final List<TextBox> texts; final List<ImageBox> images;
  final Set<String> deleted;                             // tombstones
  bool get isEmpty;  int get itemCount;
  Stroke? strokeById(id); TextBox? textById(id); ImageBox? imageById(id); bool contains(id);
  PageDoc withStroke(Stroke) / withStrokes(Iterable<Stroke>) / withText(TextBox) / withImage(ImageBox);
  PageDoc without(Iterable<String> ids);                 // remove + tombstone
  PageDoc merge(PageDoc other);   // união por id − tombstones; comutativa, associativa, idempotente
}
// with*: quantizam o item; id tombstoned ou id repetido com conteúdo diferente => ArgumentError.

String encodePage(PageDoc);   PageDoc decodePage(String);   // JSON v1 -> gzip -> base64
// decodePage('') => PageDoc.empty. Erros: PageDecodeException (FormatException);
// versão desconhecida: UnsupportedPageVersionException(version) com mensagem pt-BR.
const int pageFormatVersion = 1;

// Geometria (unidades de página)
List<String> hitStrokes(PageDoc, Offset center, double radius, {Offset? from});
List<String> hitItems(PageDoc, Offset center, double radius, {Offset? from});  // + textos e imagens
PageDoc erasePartial(PageDoc, List<Offset> path, double radius, String Function() newId,
    {double minPieceLength = 0.5});
Set<String> lassoSelect(PageDoc, List<Offset> polygon);       // >= 50 % dos pontos dentro
Rect? itemsBounds(PageDoc, Set<String> ids);
PageDoc transformItems(PageDoc, Set<String> ids, Matrix2x3 m, {String Function()? newId});
PageDoc recolor(PageDoc, Set<String> ids, int argb, {String Function()? newId});
PageDoc extractItems(PageDoc, Set<String> ids);               // "copiar" (clipboard)
PageDoc pasteDoc(PageDoc target, PageDoc clip, {double dx = 0, double dy = 0, String Function()? newId});
EditResult transformItemsMapped(...); EditResult recolorMapped(...); EditResult pasteDocMapped(...);
class EditResult { final PageDoc doc; final Map<String,String> idMap; }

class Matrix2x3 { // x' = a·x + c·y + tx ; y' = b·x + d·y + ty
  const Matrix2x3(a, b, c, d, tx, ty); static const identity;
  Matrix2x3.translation(dx, dy); Matrix2x3.scaling(sx, {sy, anchor}); Matrix2x3.rotation(rad, {anchor});
  Matrix2x3 operator *(Matrix2x3 o);  // aplica o primeiro
  Offset apply(Offset); double get xScale, yScale, uniformScale;
}

String newInkId();
class History { ... }   // ver item 5
```

## Semântica que a UI precisa saber

* **Borracha por traço**: `hitStrokes(doc, centro, raio, from: pontoAnterior)` (o raio
  soma a meia espessura de cada traço); depois `doc.without(ids)`. `from` evita
  "pular" traços quando a caneta anda rápido entre duas amostras.
* **Borracha parcial**: chame `erasePartial(doc, [ponto anterior, ponto atual], raio, newInkId)`
  a cada evento (ou com o caminho acumulado). Cortes exatos na borda da borracha
  (interpola x, y, pressão); nunca sobra pedaço de um ponto só; traço de um ponto
  (pingo) é apagado inteiro ou fica. Sem contato devolve o mesmo `doc` (`identical`).
* **Laço**: `lassoSelect` com o polígono do laço (fechado implicitamente). Traços:
  ≥ 50 % dos pontos dentro; textos/imagens: ≥ 50 % de uma grade 3×3 sobre a caixa.
* **Mover/redimensionar/girar**: `transformItemsMapped(doc, ids, m)`. Texto e imagem
  só translam/escalam (a caixa não gira). Espessura e fonte escalam por `uniformScale`.
* **Cor**: `recolor` troca só o RGB e mantém o alfa (marca-texto segue translúcido);
  imagens são ignoradas.
* **Copiar/colar**: `extractItems(doc, ids)` → guarde o `PageDoc`; `pasteDocMapped(destino, clip, dx:, dy:)`
  gera ids novos (funciona entre páginas).
* **Quantização na memória**: `with*`, `erasePartial`, `transformItems` etc. já
  quantizam (coordenadas 0,1; pressão e espessura 0,01), então `decodePage(encodePage(d)) == d`.
  Não use `withStroke` para "atualizar" um traço (ids são imutáveis).
* **Traço em andamento**: não vai para o `PageDoc` até o gesto terminar; ao soltar,
  `doc.withStroke(Stroke(id: newInkId(), ...))` e `history.record(antes, depois)`.
* **Salvar**: `encodePage(doc)`; conflito (versão otimista): `decodePage(remoto).merge(local)`.
* **Tombstones** nunca são podados (sem saber quais aparelhos ainda têm o item não
  é seguro); custam ~20 bytes por id apagado.

## Medidas (JIT/debug, 2.000 traços × 100 pontos = 200 mil pontos)

Veja os números no relatório da tarefa e rode `flutter test test/notebook/core/perf_test.dart`
para reproduzir (imprime linhas `PERF ...`).
