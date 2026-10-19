/** Remove acentos e caixa (comparação de nomes falados). */
export function fold(s: string): string {
  return s.normalize('NFD').replace(/\p{M}/gu, '').toLowerCase();
}

export interface ShoppingUtterance { list: string | null; items: string[] }

const esc = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

/**
 * Interpreta o que a pessoa disse depois de "adicionar": tira o "na lista (de compras|do X)",
 * escolhe a lista quando X é uma das existentes (o nome devolvido é o cadastrado) e separa os itens
 * por vírgula e " e ". Um "na X" com X desconhecido continua sendo parte do item.
 */
export function parseShoppingUtterance(text: string, listNames: string[]): ShoppingUtterance {
  // NFC mantém o texto original e a versão sem acento com o mesmo tamanho (cortamos pelo índice).
  let rest = text.normalize('NFC').trim().replace(/[.!?;:\s]+$/, '');
  let list: string | null = null;
  const byFold = new Map(listNames.map((n) => [fold(n), n]));

  // " na lista", " na lista de compras", " na lista do/da X" (X existente escolhe a lista)
  const lista = /\s+(?:n[ao]|para a|pra)\s+lista(?:\s+(?:de\s+compras|d[oa]s?\s+(.+?)))?$/.exec(fold(rest));
  if (lista || fold(rest).replace(/\s+/g, ' ') === 'na lista') {
    if (lista) {
      if (lista[1]) list = byFold.get(lista[1].trim()) ?? null;
      rest = rest.slice(0, lista.index);
    } else {
      rest = '';
    }
  } else {
    // " na X" / " no X" com X uma lista existente
    for (const [key, name] of byFold) {
      const m = new RegExp(`(?:^|\\s)n[ao]\\s+${esc(key)}$`).exec(fold(rest));
      if (m) {
        list = name;
        rest = rest.slice(0, m.index);
        break;
      }
    }
  }

  const seen = new Set<string>();
  const items: string[] = [];
  for (const part of rest.split(/\s*,\s*|\s+e\s+/i)) {
    const item = part.trim().replace(/[.!?;:]+$/, '').trim();
    if (!item || seen.has(fold(item))) continue;
    seen.add(fold(item));
    items.push(item);
  }
  return { list, items };
}

const joinList = (items: string[]) =>
  items.length <= 1 ? items.join('') : `${items.slice(0, -1).join(', ')} e ${items[items.length - 1]}`;

const capitalize = (s: string) => s.charAt(0).toUpperCase() + s.slice(1);

/** "Anotei leite e pão na lista Mercado." / "Leite já estava na lista." (as duas, se houver). */
export function addedText(r: { added: string[]; skipped: string[]; list: string }): string {
  const parts: string[] = [];
  if (r.added.length) parts.push(`Anotei ${joinList(r.added)} na lista ${r.list}.`);
  if (r.skipped.length) {
    parts.push(`${capitalize(joinList(r.skipped))} ${r.skipped.length === 1 ? 'já estava' : 'já estavam'} na lista.`);
  }
  return parts.join(' ');
}

const SHOWN = 3;

/** "Na lista Mercado: leite, pão e 3 outros." — só as listas com itens; nenhuma → "Sua lista está vazia.". */
export function listSummaryText(lists: { list: string; items: string[] }[]): string {
  const parts = lists.filter((l) => l.items.length > 0).map((l) => {
    const rest = l.items.length - SHOWN;
    const shown = rest > 0
      ? `${l.items.slice(0, SHOWN).join(', ')} e ${rest} ${rest === 1 ? 'outro' : 'outros'}`
      : joinList(l.items);
    return `Na lista ${l.list}: ${shown}.`;
  });
  return parts.length ? parts.join(' ') : 'Sua lista está vazia.';
}
