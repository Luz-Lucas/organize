# Caderno com S Pen — Fase 1 (caneta e caderno) — Plano

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:test-driven-development. Spec: `docs/superpowers/specs/2026-10-13-caderno-spen-design.md` (leia antes). Regras comuns do plano `2026-10-12-series-alarmes-github-drive.md` (pt-BR, banco só local, sem commit, sem nuvem/VM, arquivos compartilhados com edição pequena e ancorada; `flutter analyze` limpo e `TZ=America/Sao_Paulo flutter test --exclude-tags integration` verde no fim).

Ondas: **Onda 1** = Tasks 1 e 2 em paralelo. **Onda 2** = Tasks 3 e 4 em paralelo (dependem da API da Task 2, definida abaixo).

## API fixa do núcleo (Task 2 implementa; Tasks 3 e 4 usam)

Pasta `app/lib/notebook/core/` (Dart puro, sem Flutter widgets; pode usar `dart:ui` só para `Offset/Rect/Color` se preciso):
- `enum PenTool { fountain, pen, pencil, highlighter }`, `enum PageBackground { blank, lined, grid, dots }`.
- `class InkPoint { final double x, y, p; }` (unidades de página 1000×1414; `p` 0–1).
- `class Stroke { final String id; final PenTool tool; final int argb; final double width; final List<InkPoint> points; Rect get bounds; }`
- `class TextBox { id, x, y, w, text, size, argb }`, `class ImageBox { id, x, y, w, h, path }`.
- `class PageDoc { final List<Stroke> strokes; final List<TextBox> texts; final List<ImageBox> images; final Set<String> deleted; PageDoc merge(PageDoc other); PageDoc withStroke(...)/without(ids)/... (imutável) }`.
- `String encodePage(PageDoc)` / `PageDoc decodePage(String)` (JSON v1 → gzip → base64; `''` decodifica para página vazia; versão desconhecida → erro claro).
- Geometria: `List<String> hitStrokes(PageDoc, Offset center, double radius)` (borracha por traço), `PageDoc erasePartial(PageDoc, List<Offset> path, double radius, String Function() newId)` (parte traços em pedaços), `Set<String> lassoSelect(PageDoc, List<Offset> polygon)` (≥ 50 % dos pontos dentro), `PageDoc transformItems(PageDoc, Set<String> ids, Matrix2x3 / (scale, dx, dy))`, `PageDoc recolor(...)`.
- `class History` (desfazer/refazer de `PageDoc` por página, limite 100).
- `const pageWidth = 1000.0, pageHeight = 1414.0`.

## Task 1 — Banco, Storage e MCP (Onda 1)
Migração `supabase/migrations/20261023000000_notebooks.sql` conforme a spec (notes.kind, note_pages, RLS, realtime, checks, bucket `notebook-images` + policies de storage do dono por prefixo `<user_id>/`). pgTAP `supabase/tests/database/notebooks_test.sql` (RLS de páginas e do bucket, kind inválido, unique (note_id, idx), tamanho). MCP (`mcp/src/tools/notes.ts`): `search_notes` passa a buscar também em `note_pages.recognized_text` e indica `kind`; criar nota pelo MCP continua `kind='text'`. Testes vitest. Não toque em `app/`.

## Task 2 — Núcleo de tinta (Onda 1)
Implementar a API acima com testes extensivos em `app/test/notebook/core/` (codificação ida-e-volta, tamanho razoável — 2.000 traços × 100 pontos < 1,5 MB codificado —, merge com tombstones/comutatividade/idempotência, borracha por traço e parcial, laço, transformações, histórico). Nada de UI. Não toque em outros diretórios.

## Task 3 — Tela do Caderno (Onda 2)
`app/lib/notebook/ui/`: `NotebookScreen` (rota `/caderno/:id`), `InkPageView` (uma página: fundo desenhado, traços prontos em cache, traço atual numa camada separada, seleção do laço), `NotebookToolbar`. Entrada por `Listener` (não GestureDetector) — `PointerDeviceKind.stylus` desenha; `invertedStylus` ou botão lateral (`kPrimaryStylusButton`/`kSecondaryStylusButton`) apaga; `touch` rola/zoom salvo se "Desenhar com o dedo"; `mouse` desenha no Linux. Pressão de `event.pressure` normalizada por `pressureMin/Max`. Traço suave: `perfect_freehand` (se o pacote estiver disponível e compatível; senão implementação própria de contorno variável). Zoom/rolagem: `InteractiveViewer` com `panEnabled` só para toque. Ferramentas da spec (canetas, cores do tema + seletor, 5 espessuras, borracha por traço/parcial, laço com alças de redimensionar e menu Copiar/Colar/Cor/Apagar, texto, imagem via `file_picker`/galeria, desfazer/refazer, fundos, + página, apagar/duplicar página). Imagens: interface `NotebookImageStore` (upload/URL assinada) — a Task 4 entrega as implementações; aqui use uma falsa. Testes de widget com eventos sintéticos de stylus/touch/mouse (pressão, borracha pelo botão, palm rejection, laço move, desfazer), e um teste de desempenho simples (montar página com 5.000 traços sem estourar o tempo de frame no teste de layout). Arquivos só em `app/lib/notebook/ui/` e testes.

## Task 4 — Dados, sincronização e integração (Onda 2)
`Note.kind` no domínio (fromMap/toMap; padrão `text`); `NotebookRepository` (Memory + Supabase): `watchPages(noteId)`, `savePage(page)` com versão otimista e mescla (`decode → merge → encode`) em conflito, `addPage/deletePage/duplicatePage/reorder`; `NotebookImageStore` Supabase Storage (upload, URL assinada com cache, limite 10 MB). `NotebookController` (Riverpod) com salvamento automático 1,5 s após o último traço e ao sair/pausar, indicador "Salvando…/Salvo/Sem conexão (salvo no aparelho)" e fila local quando offline (`shared_preferences` já é dependência). Integração: rota `/caderno/:id` no `router.dart`; "Novo caderno" (`Key('new-notebook')`) na lista/árvore de notas e no FAB/ações rápidas da Início se houver "Nota"; ícone de caderno e miniatura da 1ª página na lista; abrir nota `kind=notebook` vai para `/caderno/:id`; busca de notas inclui `recognized_text`; voltar (`BackHandler`) funciona. Testes: repositório (conflito mescla sem perder traços dos dois aparelhos), controller (debounce, offline→online), navegação e lista. Arquivos compartilhados com edição pequena: `router.dart`, `notes_tree.dart`, `notes_screen.dart`, `note.dart`, `main.dart`, `helpers.dart`, `today_screen.dart` (só se adicionar ação rápida).

## Coordenador (depois)
Suíte completa, revisão independente (desempenho, conflito, RLS do Storage), migração na nuvem, MCP na VM, APK + Linux; o usuário testa no tablet com a S Pen (latência, palm rejection, borracha pelo botão) antes da Fase 2.
