# Despertar: parar a música depois de N segundos e seguir para o próximo tópico — Design e Plano

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development ou executing-plans. Steps com checkbox.

**Pedido do usuário (2026-10-12):** "parar a música depois de certo tempo tocando (ex.: 30 s) e ir direto para o próximo tópico (encerrar, resumo ou etc.)".

## Comportamento

Dois campos novos em cada despertar (`wake_plans`):

| Campo (banco) | Tipo | Significado |
|---|---|---|
| `music_stop_after_sec` | `integer null`, `check (music_stop_after_sec between 5 and 600)` | Se preenchido e o despertar tem busca do Spotify: depois de a música começar, espera N segundos e **para a música** (comando `pause` no Echo). `null` = não para (comportamento atual). |
| `after_music` | `text not null default 'briefing'`, `check in ('briefing','headlines','end')` | O que vem **depois da música** (só vale com `music_first = true`): `briefing` = resumo do dia falado; `headlines` = só as manchetes; `end` = encerrar o despertar sem falar nada. |

Fluxo em `runWake` (bridge):
1. `volume` como hoje.
2. **`musicFirst = true`:** toca a música (se há `spotifyQuery`). Se tocou: com `musicStopAfterSec` → espera N s e chama `gateway.stopMusic(echo)`; **sem** ele → espera `briefingDelayMin` minutos como hoje (e não para). Depois executa `afterMusic`: `briefing` fala o resumo, `headlines` fala só as manchetes, `end` não fala. Se a música **não** tocou (falha), pula a espera e o stop e executa `afterMusic` mesmo assim (o usuário precisa acordar).
3. **`musicFirst = false`:** fala o resumo primeiro (como hoje); depois toca a música; se `musicStopAfterSec` → espera N s e para. (`afterMusic` é ignorado.)
4. `briefingDelayMin` é ignorado quando `musicStopAfterSec` está preenchido.
5. Falha do `stopMusic` vira nota ("parar música: …") mas **não** impede o próximo passo. `ok` continua significando "algo tocou ou foi falado" (o alarme reserva do Echo é apagado como hoje).
6. "Testar agora" (`wake_test`) usa o mesmo fluxo; hoje ele zera `briefingDelayMin`, mantenha isso, mas **respeite** `musicStopAfterSec` (para o teste não ser eterno, limite a espera do teste a no máximo 60 s).

## Ponte (bridge/)

- `WakePlan` (`scheduler.ts`) ganha `musicStopAfterSec: number | null` e `afterMusic: 'briefing' | 'headlines' | 'end'`; `supabase-store.ts` (`toPlan`) mapeia `music_stop_after_sec` / `after_music` (`after_music` desconhecido → `'briefing'`).
- `AlexaGateway.stopMusic(echoDeviceId: string): Promise<void>` (`gateway.ts`); implementação em `alexa-remote-gateway.ts` com o comando `pause` do alexa-remote2 (`sendCommand(serialOrName, 'pause', …)`; **leia** a fonte em `bridge/node_modules/alexa-remote2/alexa-remote.js` para a assinatura real e como `playSpotify`/`speak` chamam `this.call`); `FakeGateway` (`test/fake-gateway.ts`) registra `stopped: string[]`.
- `WakeDeps.briefing` passa de `() => Promise<string>` para `() => Promise<{ briefing: string; headlines: string }>` (`headlines` = `headlinesText(news)` de `briefing.ts`, a mesma que a skill usa); atualize `main.ts` (`wakeTick` e `wakeTest`) e `runWake(plan, text, gateway, sleep)` para receber `{briefing, headlines}`.
- Testes em `bridge/test/wake.test.ts` (use o `FakeGateway` e um `sleep` falso que registra as esperas): música→espera 30 s→stop→resumo; música→stop→`end` (nada falado); música→stop→manchetes; `musicFirst=false` (fala→música→espera→stop); sem `musicStopAfterSec` mantém o comportamento antigo (espera `briefingDelayMin` min, sem stop); música que falha ao iniciar não espera nem para e ainda executa `afterMusic`; `stopMusic` lançando erro vira nota e o próximo passo roda; `AlexaAuthError` continua propagando.

## Banco (supabase/)

Migração `supabase/migrations/20261012000000_wake_music_stop.sql` (apenas `alter table public.wake_plans add column …` com os checks acima, nomeados) e `supabase/tests/database/wake_music_stop_test.sql` (pgTAP no padrão dos outros): defaults, `music_stop_after_sec = 3` e `= 700` falham (check_violation), `after_music = 'x'` falha, valores válidos passam. Aplicar **só no Supabase local** (`npx supabase migration up --local`; `npx supabase test db`); **não** tocar na nuvem.

## App (app/)

- `WakePlan` (`lib/domain/alexa.dart`): `int? musicStopAfterSec`, `AfterMusic afterMusic` (enum `briefing, headlines, end` com `label`: "Resumo do dia", "Só as manchetes", "Encerrar"); `fromMap`/`toMap`/`copyWith`/`==`/`hashCode`; `toMap` grava `music_stop_after_sec` (null quando não parar) e `after_music`; `fromMap` tolera ausência (null / `briefing`). `copyWith` precisa conseguir **limpar** `musicStopAfterSec` (ex.: parâmetro `clearMusicStop`). `validateWakePlan`: se `musicStopAfterSec != null`, exige 5–600 e `spotifyQuery` não vazio ("Para parar a música, escolha uma busca do Spotify."). `wakeSummary` acrescenta "(para após 30 s)" depois do Spotify quando houver.
- Tela do despertar (`lib/features/home/wake_plan_screen.dart`): quando há busca do Spotify, um seletor **"Parar a música após"** com as opções *Não parar*, *15 s*, *30 s*, *1 min*, *2 min*, *5 min* (valores 15, 30, 60, 120, 300); quando "Música primeiro" está ligada, um seletor segmentado **"Depois da música"** com os três `AfterMusic`; quando um tempo de parada está escolhido, o campo de "atraso do resumo" (minutos) fica oculto/desabilitado com a nota "O resumo começa assim que a música parar." Mantenha todas as `Key`s existentes; novas: `music-stop-<segundos|none>` (ex.: `Key('music-stop-30')`) e `after-music-<briefing|headlines|end>`.
- Testes: domínio (`test/domain/alexa_test.dart`: ida e volta, validação, resumo), tela (`test/features/home_test.dart`: escolher 30 s e "Só as manchetes" e salvar grava os campos no `MemoryAlexaRepository`; sem busca do Spotify o seletor de parada não aparece; com "Música primeiro" desligada o seletor "Depois da música" some).

## Constraints

- pt-BR; `export PATH="$HOME/development/flutter/bin:$PATH"`; app: `flutter analyze` limpo + `TZ=America/Sao_Paulo flutter test --exclude-tags integration` verde; bridge: `cd bridge && npx vitest run` e `npx tsc -p tsconfig.typecheck.json`. 
- **Dois agentes em paralelo:** o agente "bridge+banco" mexe só em `bridge/` e `supabase/`; o agente "app" mexe só em `app/lib/domain/alexa.dart`, `app/lib/features/home/wake_plan_screen.dart`, `app/test/domain/alexa_test.dart`, `app/test/features/home_test.dart`. Há outros dois agentes mexendo em manifest/Kotlin/widgets/Ajustes do app: **não** toque em `app/android/`, `main.dart`, `app.dart`, `settings_screen.dart`, `lib/widgets/`, `lib/app_icon/`; **não** rode builds Android. Ninguém faz `git commit`/`stash`; ninguém toca a nuvem, a VM ou `mcp/`.
