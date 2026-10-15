# Sub-projeto A — Visual novo, Kanban, Calendário, Editor e Avisos

**Data:** 2026-10-11 · **Base:** `docs/superpowers/specs/2026-09-28-organizacional-design.md`
**Fora deste sub-projeto:** Documentos + Google Drive (conta `sua-conta@gmail.com`) e Google Agenda (conta `seu-contato@gmail.com`) → sub-projeto **B+C** (uma conexão Google por conta, escopos mínimos). Central de notificações (celular + Alexa) → sub-projeto **D**.

## Decisões (aprovadas no brainstorming)

| Tema | Decisão |
|---|---|
| Estilo | Escuro único, estilo Obsidian. **10 sistemas de design** dos PDFs do usuário (Violeta, Safira, Musgo, Lunar, Índigo, Grafite, Coral, Cobalto, Cacto, Bronze), só a variante **escura**. Padrão: **Violeta**. |
| Troca de tema | Ajustes → grade com os 10; salvo em `user_settings.theme` (vale no PC e no celular). |
| Fontes | `google_fonts`. Embutidas: Sora + Fira Code (Violeta) + Inter (reserva). As demais baixam na 1ª escolha e ficam em cache; sem rede, usa a reserva. |
| Navegação | Computador (≥720px): barra lateral recolhível — Início, Agenda, Tarefas, Notas (árvore Espaços → notas + busca), Notícias, Casa, Ajustes. Celular: barra inferior Início, Agenda, Tarefas, Notas, **Mais** (Notícias, Casa, Ajustes). |
| Tarefas | **Kanban** A fazer / Fazendo / Feito (já são os 3 status do banco). Computador: 3 colunas, arrastar entre colunas. Celular: **abas**; segurar o cartão → "Mover para…". |
| Agenda | **Calendário**. Computador abre na **Semana** (grade de horários; tocar/arrastar em horário vazio cria evento), alterna com **Mês**. Celular: mês compacto + lista do dia. |
| Evento atravessando a meia-noite | Diálogo ganha **data de término**; se o fim (mesmo dia) for antes do início, o término vai sozinho para o dia seguinte. Evento aparece em todos os dias que toca. |
| Notas | Editor **WYSIWYG estilo Notion** com `appflowy_editor`. Banco continua em **Markdown** (fonte da verdade). `[[links]]` preservados. Botão **"Ver como Markdown"** como saída de emergência. Testes de ida e volta. |
| Quadro de avisos | Na Home. **Avisos do usuário** (tabela `notices`: título, texto, prioridade, fixado, expira em, arquivado) **+ avisos do sistema** (calculados no app: tarefas atrasadas, ponte/login da Alexa, próximo despertar em 24h), visualmente distintos e não editáveis. |
| Dispositivos Alexa | Por dispositivo: **Ocultar do app** (lista em `user_settings.hidden_alexa_devices`, reversível) e, para dispositivos de casa inteligente, **Remover da Alexa** (comando `delete_device` na ponte; confirmação explícita; irreversível pelo app). Echos: só ocultar. |

## Sistema de temas

Fonte dos dados: os 10 PDFs (`~/Downloads/*.pdf`), extraídos para `app/lib/ui/themes.dart` (código gerado, sem leitura de PDF em runtime). Cada `OrgThemeSpec` tem:

- `id`, `name`, `tagline`
- 13 tokens de cor (tema escuro): `surface`, `surfaceRaised`, `line`, `ink`, `inkMuted`, `accent`, `accentDeep`, `onAccent`, `accentText`, `accentSoft`, `secondary`, `secondarySoft`, `link`
- fontes `display` / `sans` / `mono`; `radiusSm/Md/Lg`; `glyph`; `motif`

Regras dos PDFs aplicadas: `accent` puro nunca como cor de texto (texto/link = `accentText`); botão principal = `accentDeep` com `onAccent`; `secondary` só decorativo. Mapeamento para Material 3: `surface→surface`, `surfaceRaised→surfaceContainer*`, `line→outline/outlineVariant`, `ink→onSurface`, `inkMuted→onSurfaceVariant`, `accentDeep→primary`, `onAccent→onPrimary`, `accentSoft→primaryContainer`, `accentText→onPrimaryContainer`, `secondary→secondary`, `secondarySoft→secondaryContainer`, `accent→tertiary`. Os tokens crus + glifo + motivo + radii também ficam numa `ThemeExtension<OrgTokens>` para widgets próprios. Motivos (`diagonal-stripes`, `wiregrid`, `leaf-rings`, `orbit-rings`, `ornament-dots`, `scanlines`, `wave-lines`, `dot-grid`, `brick-texture`, `cross-hatch`) desenhados por um `CustomPainter` em baixa opacidade, só no topo da Home e cabeçalhos — nunca atrás de texto longo.

Tabela de referência (tema escuro; `link` = `accentText`). Dados completos, incluindo o tema claro não usado, em `docs/superpowers/specs/assets/themes-10.json`:

| id | surface | raised | line | ink | inkMuted | accent | accentDeep | onAccent | accentText | accentSoft | secondary | secondarySoft | fontes (display/sans/mono) | radius sm/md/lg | glifo | motivo |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| violeta | #160F1E | #251E2D | #413B49 | #EFE9F7 | #9B8FAE | #8B5CF6 | #6633CC | #FFFFFF | #C0A9FF | #291B41 | #F472B6 | #3A1F36 | Sora / Sora / Fira Code | 6/13/24 | ✦ | diagonal-stripes |
| safira | #081826 | #172735 | #324250 | #DCEBF7 | #7195AC | #0EA5E9 | #0972A8 | #FFFFFF | #6FCBF3 | #092F45 | #22D3EE | #0C3646 | Outfit / Outfit / Roboto Mono | 4/9/16 | ◆ | wire- |
| musgo | #141912 | #232720 | #3F423A | #EBE8DA | #9AA08D | #5F7A3D | #3E5527 | #FFFFFF | #9CB679 | #202919 | #B08D2E | #2D2C16 | Libre Baskerville / Source Sans 3 / IBM Plex Mono | 8/14/20 | ❧ | leaf-rings |
| lunar | #0A0A0D | #1A1A1D | #37373A | #EAEAEE | #84858C | #7DF9FF | #2FB8C2 | #101014 | #B4FCFF | #1C3034 | #C084FC | #271E33 | Unbounded / Inter / JetBrains Mono | 8/14/20 | ○ | orbit-rings |
| indigo | #0F1330 | #1F223E | #3B3E58 | #EDEAF8 | #8D8AB0 | #C9A227 | #9C7C12 | #101014 | #E4C866 | #2D2A2F | #5A4FCF | #1B1D49 | Cormorant Garamond / Karla / JetBrains Mono | 2/4/2 | ✧ | ornament-dots |
| grafite | #111213 | #202122 | #3D3E3E | #EDEDEC | #8A8B8C | #B8B9BB | #8A8B8C | #101014 | #D7D8D9 | #2C2D2E | #3DDC97 | #183228 | IBM Plex Mono / IBM Plex Sans / IBM Plex Mono | 2/4/4 | › | scanlines |
| coral | #241512 | #332420 | #4E3F3B | #F7E9E1 | #B08D80 | #FF6F59 | #D14B36 | #FFFFFF | #FF9C89 | #47231D | #FFC24B | #47311B | Fraunces / Nunito Sans / JetBrains Mono | 10/22/40 | ~. | wave-lines |
| cobalto | #0B1220 | #1A212F | #373E4B | #E7ECF5 | #8792A6 | #2F6FED | #1D4FBF | #FFFFFF | #7FA6FF | #112141 | #00C2A8 | #092E36 | Space Grotesk / Inter / JetBrains Mono | 3/7/12 | ▪ | dot-grid |
| cacto | #1D1712 | #2C2620 | #47413A | #F0E9D8 | #A99A7C | #5C8A5C | #3D6640 | #FFFFFF | #8FBE8B | #27291E | #C1662F | #372417 | DM Serif Display / DM Sans / JetBrains Mono | 2/4/6 | ◧ | brick-texture |
| bronze | #1B1512 | #2A2320 | #463E39 | #F0E4D5 | #AB9885 | #B8692F | #8C4B1E | #FFFFFF | #E0A268 | #342217 | #7A8B6F | #2A2821 | Bitter / Barlow / JetBrains Mono | 2/6/10 | † | cross-hatch |

## Dados (migração `20261011000000_ui_redesign.sql`)

- `user_settings(user_id pk → auth.users, theme text not null default 'violeta' check in os 10 ids, hidden_alexa_devices text[] not null default '{}', updated_at)`; RLS dono.
- `notices(id uuid pk, user_id, title text not empty, body text default '', priority text check in ('normal','alta') default 'normal', pinned bool default false, expires_at timestamptz null, archived_at timestamptz null, created_at, updated_at)`; RLS dono; índice `(user_id, archived_at)`.
- `alexa_commands.kind` passa a aceitar `'delete_device'`.
- pgTAP: RLS das duas tabelas novas (outro usuário não lê nem altera) e o check de `theme`.

App: `Repository` ganha `watchNotices/upsertNotice/deleteNotice`; novo `SettingsRepository` (`watchSettings/saveSettings`) com versões em memória (testes) e Supabase.

## Regras de domínio (puras, testadas)

- `activeNotices(notices, now)`: exclui arquivados e expirados; ordena fixados → prioridade alta → mais recentes.
- `systemNotices(now, tasks, bridgeStatus, wakePlans)`: "N tarefa(s) atrasada(s)"; aviso da ponte (reaproveita `bridgeWarning`); "Despertar <rótulo> amanhã/hoje às HH:MM" se houver despertar ativo nas próximas 24h.
- `resolveEventEnd(start, endDay, endTime)`: se `endDay == dia de start` e `endTime <= hora de start`, término = dia seguinte; `validateEventTimes` continua exigindo fim > início.
- `eventsOnDay` já trata eventos de vários dias; testes novos cobrem 22:00→02:00.
- `moveTask(task, status, now)`: troca status; `done` define `completedAt = now`, sair de `done` limpa.
- Markdown ↔ editor: `[[Título]]` ↔ link `wiki:Título`; checklists, títulos, listas, citações, código, negrito/itálico, links. Teste de ida e volta garante `markdown == encode(decode(markdown))` para o corpus de teste.

## Ponte (bridge)

- `CommandKind` + `'delete_device'` (payload `entityId`). `AlexaGateway.deleteSmartDevice(entityId)`: resolve o `applianceId` correspondente via `getSmarthomeDevices` e chama `deleteSmarthomeDevice`; erro claro se não achar. Depois do sucesso, a ponte ressincroniza (a linha some de `alexa_devices`).
- Testes com o gateway falso; não há teste automático contra a Alexa real.

## Telas

Início (saudação + motivo, quadro de avisos, hoje, tarefas do dia, manchetes) · Agenda (semana/mês/celular) · Tarefas (Kanban) · Notas (árvore + editor) · Notícias · Casa (com ocultar/remover) · Ajustes (tema, conta, sair) · Mais (celular).

## Erros

Mesma política atual: falha de gravação mostra mensagem e **nunca** apaga o que o usuário digitou (nota, aviso, tarefa). Tema inválido/ausente no banco → Violeta. Fonte que não baixou → reserva, sem travar a tela. Remover da Alexa falhou → mensagem com o motivo; o dispositivo continua listado.

## Testes e entrega

`flutter analyze` limpo; testes de unidade e de widget atualizados para o novo layout; pgTAP; vitest da ponte. Entrega: `db push`, imagem nova da ponte na VM Oracle, build Linux instalado + APKs, push na `main`.
