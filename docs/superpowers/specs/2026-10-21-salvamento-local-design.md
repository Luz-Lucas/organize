# Salvamento local primeiro (offline-first) — Design

Pedido do usuário (2026-10-21): "salvar alterações localmente e só depois atualizar o servidor … para todas as features, removendo a
necessidade imediata de conexão, fazendo salvamento imediato, depois sincronizando com o servidor e banco". Gatilho: marcar uma série
do treino deu erro — a gravação funcionou, mas a tela só mudava quando o realtime devolvia a linha; sem isso, cada novo toque gravava a
mesma série de novo e o banco recusava (`set_logs_session_id_exercise_id_set_index_key`, 5 vezes em segundos nos logs).

## Intenção
O app nunca deve esperar o servidor para mostrar ou guardar algo. Toda alteração aparece na hora, sobrevive a fechar o app e sem
internet, e chega à nuvem sozinha quando der. Erro só quando o servidor **recusar** a alteração de vez.

## Decisões do usuário
- **Conflito: vale a alteração mais recente** (último a alterar ganha), comparando o momento em que cada aparelho fez a alteração.

## Escopo
- **Dentro:** espaços, notas, tarefas, eventos (e séries), etiquetas, Academia (fichas, exercícios, sessões, séries), Compras (listas,
  itens; frequentes só leitura), ajustes do usuário (`user_settings`), planos de despertar e exceções (`wake_plans`, `wake_overrides`).
- **Fora (precisam de internet por natureza):** Gmail, Drive, GitHub, Notícias, dispositivos/rotinas da Alexa, atualização do app.
- **Cadernos:** já gravam páginas localmente com fila própria e merge por traço (`notebook/`); continuam como estão. A **nota** do
  caderno (linha de `notes`) entra no esquema novo.

## Como funciona (decisões técnicas — minhas)
1. **Banco local** no aparelho (SQLite via pacote `sqlite3` + `sqlite3_flutter_libs`, funciona em Android, Linux e Windows), com
   duas tabelas genéricas: `rows(tbl, id, data_json, client_updated_at)` — espelho das tabelas da nuvem da conta logada — e
   `outbox(seq, tbl, op upsert|delete, id, data_json, client_updated_at, attempts, last_error)`.
2. **Escrita:** os repositórios gravam em `rows` + `outbox` numa transação e a tela atualiza na hora (os streams leem do banco local).
   Cada alteração carimba `client_updated_at = agora` (relógio do aparelho).
3. **Envio:** um sincronizador manda a fila em ordem para o Supabase quando há conexão (ao abrir o app, ao voltar a conexão, a cada
   escrita e periodicamente), com novas tentativas e espera crescente. Recusa permanente do servidor (ex.: violação de regra) tira o item
   da fila, desfaz a cópia local (relê da nuvem) e mostra um aviso único "Não foi possível salvar X".
4. **Recebimento:** carga inicial de cada tabela + realtime; cada linha que chega substitui a local **exceto** se houver alteração
   pendente mais nova dessa linha na fila. Ao reconectar, recarrega para não perder mudanças feitas enquanto estava fora.
5. **Último ganha no servidor:** coluna `client_updated_at timestamptz` em todas as tabelas sincronizadas; gatilho `before update`
   ignora a atualização se o `client_updated_at` recebido for **mais antigo** que o gravado (o mais recente prevalece mesmo que chegue
   depois). Escritas da ponte/Alexa e do MCP (sem o campo) recebem `now()`.
6. **Apagar:** apagar vale na hora e ganha de uma edição feita antes em outro aparelho (sem "lixeira" no servidor). Edição posterior a um
   apagamento em outro aparelho que ainda não sincronizou é descartada. (Minha decisão: lixeira exigiria mudar MCP, ponte e todas as
   consultas.)
7. **Itens derivados pelo servidor** (seção do item de compra, frequentes, classificação de etiqueta): aparecem provisórios no aparelho
   ("Outros"/sem etiqueta) e se corrigem quando a nuvem devolve a linha.
8. **Indicador:** a faixa "Sem conexão" vira um indicador discreto "N alterações aguardando envio" (só quando há fila e ela não anda há
   alguns segundos); os avisos "Não foi possível salvar…" de queda de conexão somem.
9. **Conta:** ao sair da conta, o banco local é apagado; cada conta tem o seu.
10. **Segundo plano:** o workmanager periódico também envia a fila (o widget e os lembretes passam a ler do banco local).

## Não-objetivos
- Edição colaborativa campo a campo em notas (é a linha inteira que vence).
- Funcionar sem internet no primeiro login (precisa baixar uma vez).

## Anti-objetivos (seria falha mesmo funcionando)
- Perder uma alteração local sem avisar.
- Duplicar itens ao reenviar (o envio é idempotente pelo `id`).
- Deixar o app mais lento para abrir.

## Correção imediata incluída
`set_logs`: além do esquema novo, gravar a série de forma idempotente (upsert pela chave `session_id, exercise_id, set_index`).
