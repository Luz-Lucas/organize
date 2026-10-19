# Academia, Lista de compras e Início "Para hoje" — Design

Aprovado pelo usuário em 2026-10-19 (respostas: Academia = "Treinos + registro"; Compras = quantidade e
categoria, itens frequentes, Alexa/Claude, várias listas; Para hoje = "Só tarefas urgentes").

## 1. Academia (Mais → Academia, rota `/academia`; cartão na Início)
- **Fichas**: Treino A, B, C… com exercícios em ordem (nome, séries, repetições como texto "8–12",
  carga planejada em kg opcional, descanso em segundos, observação). Criar, editar, reordenar, duplicar, apagar.
- **Treino do dia**: rodízio pela ordem das fichas — a sugerida é a seguinte à do último treino feito
  (a primeira, se nunca treinou); dá para trocar. Aparece nos dias com evento de academia na agenda;
  nos outros dias "Descanso" com "Treinar mesmo assim".
- **Durante o treino**: marcar cada série (repetições e carga já preenchidas com a última vez daquele
  exercício, senão com o planejado); ao marcar, cronômetro de descanso na tela. Desmarcar desfaz.
  "Finalizar treino" fecha a sessão.
- **Histórico**: sessões passadas; por exercício, a evolução da carga (data, maior carga, reps).
- **Cartão na Início**: "Hoje: Treino B — 6 exercícios" + Começar / progresso "8/18 séries" + Continuar /
  "Feito ✓" / "Descanso".

## 2. Compras (Mais → Compras, rota `/compras`; cartão na Início)
- **Várias listas** (padrão "Mercado", criada sozinha), sincronizadas (realtime).
- **Item**: nome, quantidade livre ("2 kg"), **seção**: Hortifrúti, Padaria, Açougue, Frios e laticínios,
  Mercearia, Bebidas, Limpeza, Higiene, Congelados, Outros. Seção escolhida sozinha pelo nome (no banco:
  primeiro a seção que o usuário já usou para aquele nome, senão palavras-chave, senão Outros); corrigir a
  seção de um item faz o app lembrar. Ordem das seções por lista, arrastável.
- **Frequentes**: sugestões ao digitar; faixa "Comprar de novo" (frequentes que não estão na lista) com
  um toque para recolocar.
- **No mercado**: marcar leva para "No carrinho" (fim da lista); "Finalizar compra" apaga os marcados.
- **Alexa**: "Alexa, peça ao organize para adicionar leite" (lista Mercado; "… na farmácia" vai para a
  lista com esse nome) e "Alexa, pergunte ao organize o que tem na lista".
- **Claude (MCP)**: ver listas e itens, adicionar, marcar/editar, remover, finalizar.

## 3. Início
Cabeçalho (saudação, data, botão Casa) → faixa de status → ações rápidas → **Para hoje** → **Academia**
→ **Compras** → **Despertares** → **E-mail**. Em tela larga: Para hoje à esquerda; os demais à direita.
- **Para hoje** = eventos de hoje que importam (fora: academia, etiqueta de papel `secondary`, e séries que
  se repetem ≥ 5 vezes nos próximos 7 dias) com horário, local, "agora" destacado, provas marcadas,
  já terminados esmaecidos; + tarefas não concluídas com prazo hoje ou atrasadas (até 5, "+N" leva a
  Tarefas). Vazio: "Dia livre".
- **Saem** da Início: Notícias (cartão e botão do cabeçalho), "Agora e a seguir", lista de tarefas,
  "Próxima prova". Notícias continua em Mais/barra lateral e no resumo da Alexa.
