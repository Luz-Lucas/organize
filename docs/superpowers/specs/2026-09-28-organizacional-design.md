# Organizacional — Design

**Data:** 2026-09-28
**Usuário:** uso pessoal (um único usuário), estudante universitário.

## Visão

Um só lugar para organizar aulas, matérias de estudo, trabalhos da faculdade e hobbies. A estrutura segue o Notion (espaços, páginas, tarefas) e as notas ligadas seguem o Obsidian (`[[links]]` e backlinks). O visual é minimalista e intuitivo, e o foco é produtividade: abrir o app e ver em segundos o que tem hoje.

## Decisões

| Tema | Decisão | Motivo |
|---|---|---|
| Cliente | **Flutter** (Linux/Windows desktop + Android) | Escolha do usuário: um código só, nativo nas duas plataformas |
| Dados | **Supabase** (Postgres + Auth + Realtime + Storage) | Escala sem migrar, sync em tempo real entre PC e celular, plano gratuito serve |
| Claude | **Servidor MCP** próprio (TypeScript) sobre o mesmo banco | O Claude Code/Desktop cria tarefas, planos e notas sem chave de API dentro do app |
| Google Agenda | Importação automática (Edge Function + cron) | As aulas chegam sozinhas, mapeadas para o espaço da matéria |
| GitHub | Issues → tarefas, repos → notas de projeto, notas → Markdown num repo | Trabalhos (GitHub Classroom), projetos e backup/versionamento estilo Obsidian |
| Notícias | RSS de fontes confiáveis (catálogo + feeds próprios), coletado por Edge Function + pg_cron; filtro por interesses/bloqueios em SQL (`news_feed`) | Uma regra só, usada pelo app, pela Alexa e pelo Claude |
| Alexa | **Híbrido** numa **VPS** (Docker + Caddy): skill oficial "Organizacional" (resumo do dia, estável) + ponte com API não oficial `alexa-remote2` (despertar com Spotify + resumo falado, rotinas, dispositivos, fala) | A Amazon não tem API oficial para alarmes, rotinas e dispositivos; a parte oficial continua funcionando se a não oficial quebrar |

## Modelo de dados (núcleo)

- `spaces`: matéria, trabalho, hobby ou geral. Organiza todo o resto.
- `notes`: página em Markdown com `[[links]]`. O título é único por usuário, sem diferenciar maiúsculas nem espaços extras.
- `tasks`: status, prazo, espaço e nota opcionais. `source` + `external_id` guardam a origem dos itens importados.
- `events`: agenda. `source` + `external_id` guardam a origem dos itens importados (Google).
- Toda tabela tem `user_id` com RLS `user_id = auth.uid()`.
- Excluir um espaço apaga suas notas e tarefas. Os eventos continuam na agenda, sem espaço.
- Notícias: `news_sources` (catálogo com `user_id` nulo + feeds próprios), `news_subscriptions`, `news_prefs` (interesses, bloqueios, janela, manchetes no resumo), `news_items`.
- Alexa: `wake_plans` (despertares definidos no app), `wake_runs` (execução idempotente + alarme reserva), `alexa_commands` (fila app → ponte), `alexa_devices`, `alexa_routines`, `alexa_bridge_status`.

## Roteiro (um plano por fase; cada fase entrega software funcionando)

1. **Fundação**: schema + RLS, app Flutter com login, Hoje, Agenda (eventos manuais), Tarefas, Espaços, notas Markdown com `[[links]]`/backlinks, builds Linux + APK.
2. **Notícias**: catálogo (G1, Folha, Estadão, O Globo, CNN Brasil, BBC Brasil, Agência Brasil) + feeds próprios validados; interesses destacam, bloqueios escondem (palavra inteira, sem acento); aba Notícias + manchetes em Hoje.
3. **Alexa**: despertar configurado no app (dias, hora, Echo, busca no Spotify, volume, resumo falado de eventos/tarefas/manchetes) com alarme reserva nativo; executar rotinas; ligar/desligar/brilho de dispositivos; falar texto no Echo; skill "Alexa, abre organizacional" para o resumo sob demanda.
4. **Claude via MCP**: servidor MCP com ferramentas `list_agenda`, `list_tasks`, `create_task`, `update_task`, `create_note`, `append_to_note`, `search_notes`, `create_study_plan` (cria uma nota de plano + série de tarefas com prazos), `list_news` + `create_news_digest` (nota diária com o resumo das manchetes) e `alexa_speak`, `alexa_run_routine`, `upsert_wake_plan` (via `alexa_commands`/`wake_plans`).
5. **Google Agenda**: OAuth do Google, escolha das agendas → espaço, importação periódica (`singleEvents=true` expande as aulas recorrentes), upsert por `external_id`.
6. **GitHub**: token fine-grained; issues atribuídas → tarefas; repos → notas de projeto ligadas a um espaço; exportar/sincronizar notas como Markdown num repositório.
7. **Anexos e mídia**: tabela `attachments` + Supabase Storage; player do YouTube embutido; visualizador/anotação de PDF; edição de `.docx`.
8. **Expansões** (a pedido): visões de banco estilo Notion (tabela/kanban), busca global, grafo de notas, cache offline, chat com o Claude dentro do app.

## Riscos conhecidos (resolver no plano da fase correspondente)

- **YouTube no Linux desktop**: os players baseados em WebView não suportam Linux. Alternativa: `media_kit` + extração do stream, ou abrir no navegador só no Linux.
- **Edição de .docx em Flutter**: não há editor maduro. Opções: converter docx ↔ rich text (com perdas), ou abrir no editor externo (LibreOffice/Word) e reenviar ao salvar.
- **Offline**: a Fase 1 exige conexão; um erro de gravação nunca pode apagar o texto do usuário.
- **Alexa não oficial**: login por cookie pode expirar ou quebrar com mudanças da Amazon → status `auth_required` visível no app, skill oficial segue funcionando e todo despertar tem alarme reserva nativo criado com antecedência.
- **Feeds RSS**: URLs mudam e alguns vêm em ISO-8859-1 → verificação do catálogo antes do deploy, decodificação por charset e feeds próprios validados antes de salvar.

## Fora de escopo

Multiusuário, colaboração, publicação web, app iOS/macOS.
