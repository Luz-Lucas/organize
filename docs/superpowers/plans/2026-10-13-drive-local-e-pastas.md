# Abrir arquivos do Drive pelo aparelho + Cadernos em pastas por matéria — Plano

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:test-driven-development. Regras comuns do plano `2026-10-12-series-alarmes-github-drive.md` (pt-BR, sem commit, sem nuvem/VM, arquivos compartilhados com edição pequena e ancorada, `flutter analyze` limpo e suíte verde no fim).

**Aprovado no chat (2026-10-13).**

## Task A — Arquivos do Drive abertos localmente (com cache)

- **Cache persistente** (não o `cache/` do sistema, que o Android pode limpar): `<filesDir>/drive_cache/<fileId>/<nome seguro>` + índice `drive_cache/index.json` com `{fileId: {name, size, modifiedTime, md5, path, lastOpened}}`. No Linux: `~/.local/share/dev.organizacional.organizacional/drive_cache/`.
- **Abrir um arquivo** (de Documentos e das notas-link, inclusive "Editar no Samsung Notes"): obter metadados atuais (`modifiedTime`, `md5Checksum`, `size`) — a lista de Documentos já traz `modifiedTime`; acrescente `md5Checksum` à lista e/ou uma ação `meta {id}` na função `drive` (com teste Deno) — se o cache tem o arquivo com o mesmo `md5` (ou mesmo `modifiedTime`+`size` se não houver md5) → abre direto, **funciona offline** (sem rede: abre o que estiver no cache e avisa "pode estar desatualizado"); senão baixa (ação `download` existente) com progresso e cancelamento, grava no cache e abre.
- **Com que app abrir**: `.sdocx` → Samsung Notes (como hoje, mas a partir do cache persistente); demais (PDF, Word, imagens, txt…) → `ACTION_VIEW` com o mime correto via `FileProvider` (o seletor do sistema/app padrão); arquivos nativos do Google (Docs/Sheets) não baixam → abrem no navegador como hoje. Linux: `xdg-open` no arquivo baixado. "Abrir no Drive" continua disponível no menu.
- **Kotlin**: generalizar o `openFile` do `SamsungNotesChannel` (hoje restrito a `.sdocx` em `cache/samsung_open/`) para um canal de arquivos (`dev.organizacional/files`) com `openFile(path, mime, preferPackage?)` restrito à pasta `drive_cache/` (mesma checagem de caminho canônico; `SamsungOpenGuard` ou um guard novo testado em JUnit); `file_paths.xml` passa a expor também `files/drive_cache/`.
- **Ajustes → "Arquivos baixados"**: tamanho total, "Limpar" (com confirmação); limpeza automática dos menos usados acima de 1 GB.
- Testes: cache acerta/erra por md5, offline abre do cache, arquivo mudado no Drive baixa de novo, sdocx vai para o Samsung Notes, PDF vai para ACTION_VIEW com mime, limpar, limite de 1 GB (LRU), guard de caminho (JUnit), ação `meta` (Deno).
- Arquivos: `app/lib/features/documents/*`, `app/lib/features/samsung_notes/edit_in_samsung_notes.dart`, `app/lib/features/notes/note_screen.dart` (botões das notas-link), `app/lib/data/*drive*`, novos em `app/lib/files/`, `SamsungNotesChannel.kt`/novo `FilesChannel.kt`, `AndroidManifest.xml` e `res/xml/file_paths.xml`, `supabase/functions/drive/*`, Ajustes (cartão novo). **Não** tocar em `app/lib/notebook/`, `notes_tree.dart`, `notes_screen.dart`.

## Task B — Cadernos em pastas por matéria (estilo Samsung Notes)

- **Pastas = Espaços** (tabela `spaces`, que já tem `kind` — `materia` — e `color`). Sem migração nova se o campo `color` bastar; se precisar, a migração fica em `supabase/migrations/20261025000000_*.sql`.
- **Aba Notas** ganha um seletor no topo (`SegmentedButton`): **Notas | Cadernos** (`Key('notes-tab-notes')`, `Key('notes-tab-notebooks')`), lembrado por aparelho.
- **Cadernos**: lista de pastas — **Todos**, uma por espaço de **matéria** (com a cor; ordenadas por `position`/nome), depois os demais espaços, e **Sem pasta** — no celular como chips roláveis no topo, no tablet/desktop como coluna lateral; grade de cadernos (miniatura da 1ª página via `notebook_thumbnail.dart`, título, data "há 2 h"/"12 out"), ordenar por data ou nome, busca (título + `recognized_text`).
- **Novo caderno** (`Key('new-notebook')` mantida) já nasce na pasta aberta (`space_id`).
- **Segurar um caderno**: Mover para pasta (folha com as pastas), Renomear, Excluir (reaproveitar o que a Task 4 da fase 1 fez em `notes_tree.dart`).
- **Pastas**: "+ Pasta" cria um espaço `kind=materia` com cor (paleta do tema); segurar uma pasta → Renomear, Cor, Excluir (excluir espaço **não** apaga cadernos: mover para "Sem pasta" antes — confira o `on delete` de `notes.space_id`; hoje é `cascade`! então o app precisa zerar `space_id` dos cadernos/notas da pasta antes de excluir, com confirmação clara, ou bloquear excluir pasta com itens; escolha a opção segura e teste).
- Testes: alternar abas, filtrar por pasta, criar caderno na pasta, mover, renomear, criar/renomear/recolorir/excluir pasta sem perder cadernos, busca, 360 dp e 1,3x sem estourar, tablet com coluna lateral.
- Arquivos: `app/lib/features/notes/notes_screen.dart`, `notes_tree.dart` (só se necessário e com edição pequena), novos em `app/lib/features/notes/notebooks/`, repositório de espaços se faltar algo. **Não** tocar em `app/lib/notebook/ui/*`, `app/lib/features/documents/*`, `note_screen.dart`.
