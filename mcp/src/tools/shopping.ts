import { z } from 'zod';
import type { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import type { ToolContext } from './index.js';
import { DESTRUCTIVE, READ, UserError, WRITE, check, fold, ok, okData, safe } from './util.js';

type Row = Record<string, any>; // eslint-disable-line @typescript-eslint/no-explicit-any

const SECTIONS = [
  'hortifruti', 'padaria', 'acougue', 'frios', 'mercearia', 'bebidas', 'limpeza', 'higiene', 'congelados', 'outros',
] as const;
const section = z.enum(SECTIONS).describe(
  'Seção do mercado: hortifruti, padaria, acougue (Açougue), frios (Frios e laticínios), mercearia, bebidas, limpeza, higiene, congelados, outros',
);
const itemName = z.string().trim().min(1).max(80);
const quantity = z.string().trim().max(30);
const listName = z.string().trim().min(1).max(40);

const DEFAULT_LIST = 'Mercado';

export function itemOut(r: Row) {
  return { id: r.id, listId: r.list_id, name: r.name, quantity: r.quantity, section: r.section, checked: r.checked };
}

async function userLists(ctx: ToolContext): Promise<Row[]> {
  return check(await ctx.db.from('shopping_lists').select('id, name, position, section_order, created_at')
    .eq('user_id', ctx.userId).order('position').order('created_at')) as Row[];
}

/** Lista pelo nome (sem acento/caixa), ou a padrão "Mercado". `create` cria a que faltar. */
async function resolveList(ctx: ToolContext, name: string | undefined, create: boolean): Promise<Row> {
  const lists = await userLists(ctx);
  const wanted = name ?? DEFAULT_LIST;
  const found = lists.find((l) => fold(l.name) === fold(wanted));
  if (found) return found;
  if (!create) {
    throw new UserError(`Lista "${wanted}" não encontrada. Listas existentes: ${lists.map((l) => l.name).join(', ') || 'nenhuma'}.`);
  }
  return check(await ctx.db.from('shopping_lists')
    .insert({ user_id: ctx.userId, name: wanted, position: lists.length })
    .select('id, name').single()) as Row;
}

export function registerShopping(server: McpServer, ctx: ToolContext): void {
  server.registerTool('list_shopping', {
    title: 'Listar compras',
    description:
      'Lista as listas de compras com os itens por fazer (`pending`) e os já no carrinho (`checked`). ' +
      '`list` filtra pelo nome da lista (sem diferenciar acento/caixa). Não cria nada.',
    inputSchema: { list: listName.optional() },
    annotations: READ,
  }, safe(async (a) => {
    let lists = await userLists(ctx);
    if (a.list) {
      lists = lists.filter((l) => fold(l.name) === fold(a.list!));
      if (lists.length === 0) throw new UserError(`Lista "${a.list}" não encontrada.`);
    }
    const rows = lists.length === 0 ? [] : check(await ctx.db.from('shopping_items')
      .select('id, list_id, name, quantity, section, checked, position, created_at')
      .eq('user_id', ctx.userId).in('list_id', lists.map((l) => l.id))
      .order('position').order('created_at')) as Row[];
    return okData({
      lists: lists.map((l) => {
        const mine = rows.filter((r) => r.list_id === l.id).map(itemOut);
        return {
          id: l.id, name: l.name, sectionOrder: l.section_order ?? null,
          pending: mine.filter((i) => !i.checked), checked: mine.filter((i) => i.checked),
        };
      }),
    });
  }));

  server.registerTool('add_shopping_items', {
    title: 'Adicionar à lista de compras',
    description:
      'Adiciona itens a uma lista de compras. Sem `list` usa "Mercado" (criada se não existir); com `list` usa a lista de ' +
      'mesmo nome ou cria uma nova. O que já está na lista sem marcar é ignorado e devolvido em `skipped`. ' +
      '`section` é opcional: sem ela o app escolhe pelo nome (e lembra correções).',
    inputSchema: {
      list: listName.optional(),
      items: z.array(z.object({ name: itemName, quantity: quantity.optional(), section: section.optional() })).min(1).max(50),
    },
    annotations: { ...WRITE, idempotentHint: false },
  }, safe(async (a) => {
    const list = await resolveList(ctx, a.list, true);
    const pending = check(await ctx.db.from('shopping_items').select('name')
      .eq('user_id', ctx.userId).eq('list_id', list.id).eq('checked', false)) as Row[];
    const have = new Set(pending.map((r) => fold(String(r.name))));
    const skipped: string[] = [];
    const rows: Row[] = [];
    for (const it of a.items) {
      if (have.has(fold(it.name))) { skipped.push(it.name); continue; }
      have.add(fold(it.name));
      // quantity sempre explícita e section nula: o gatilho do banco escolhe a seção.
      rows.push({ user_id: ctx.userId, list_id: list.id, name: it.name, quantity: it.quantity ?? '', section: it.section ?? null });
    }
    const added = rows.length === 0 ? [] : check(await ctx.db.from('shopping_items').insert(rows)
      .select('id, list_id, name, quantity, section, checked')) as Row[];
    return ok({ list: { id: list.id, name: list.name }, added: added.map(itemOut), skipped });
  }));

  server.registerTool('update_shopping_item', {
    title: 'Editar item de compras',
    description: 'Marca/desmarca (`checked`, vai para o carrinho), muda `quantity`, `section` ou `name` de um item da lista.',
    inputSchema: {
      id: z.string().uuid(), checked: z.boolean().optional(), quantity: quantity.optional(),
      section: section.optional(), name: itemName.optional(),
    },
    annotations: { ...WRITE, idempotentHint: true },
  }, safe(async (a) => {
    const patch: Row = {};
    if (a.checked !== undefined) patch.checked = a.checked;
    if (a.quantity !== undefined) patch.quantity = a.quantity;
    if (a.section !== undefined) patch.section = a.section;
    if (a.name !== undefined) patch.name = a.name;
    if (Object.keys(patch).length === 0) throw new UserError('Nada para alterar: informe ao menos um campo.');
    const rows = check(await ctx.db.from('shopping_items').update(patch)
      .eq('id', a.id).eq('user_id', ctx.userId).select('id, list_id, name, quantity, section, checked')) as Row[];
    if (rows.length === 0) throw new UserError('Item não encontrado.');
    return ok({ item: itemOut(rows[0]) });
  }));

  server.registerTool('remove_shopping_item', {
    title: 'Remover item de compras',
    description: 'Remove um item da lista de compras pelo id. Irreversível.',
    inputSchema: { id: z.string().uuid() },
    annotations: DESTRUCTIVE,
  }, safe(async (a) => {
    const rows = check(await ctx.db.from('shopping_items').delete().eq('id', a.id).eq('user_id', ctx.userId).select('id')) as Row[];
    if (rows.length === 0) throw new UserError('Item não encontrado.');
    return ok({ deleted: a.id });
  }));

  server.registerTool('finish_shopping', {
    title: 'Finalizar compra',
    description:
      'Finaliza a compra: apaga da lista todos os itens já marcados (no carrinho) e devolve quantos. ' +
      'Sem `list` usa "Mercado". Irreversível; confirme com o usuário.',
    inputSchema: { list: listName.optional() },
    annotations: DESTRUCTIVE,
  }, safe(async (a) => {
    const list = await resolveList(ctx, a.list, false);
    const rows = check(await ctx.db.from('shopping_items').delete()
      .eq('user_id', ctx.userId).eq('list_id', list.id).eq('checked', true).select('id')) as Row[];
    return ok({ list: list.name, removed: rows.length });
  }));
}
