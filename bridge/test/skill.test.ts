import { describe, expect, it } from 'vitest';
import type { BriefingInput } from '../src/briefing.js';
import { buildSkill, type SkillDeps } from '../src/skill.js';

const USER = 'amzn1.ask.account.EU';
const input: BriefingInput = {
  now: new Date('2026-09-28T10:00:00Z'),
  timeZone: 'America/Sao_Paulo',
  events: [{ title: 'P&D <Lab>', startsAt: new Date('2026-09-28T11:00:00Z'), endsAt: new Date('2026-09-28T12:00:00Z'), allDay: false, location: null }],
  overdue: [],
  dueToday: [],
  news: [{ source: 'G1', title: 'Chuva forte' }],
};

function envelope(request: Record<string, unknown>, userId = USER) {
  return {
    version: '1.0',
    session: { new: true, sessionId: 's', application: { applicationId: 'app' }, user: { userId } },
    context: { System: { application: { applicationId: 'app' }, user: { userId }, apiEndpoint: 'https://api.amazonalexa.com' } },
    request: { requestId: 'r', timestamp: new Date().toISOString(), locale: 'pt-BR', ...request },
  };
}

const intent = (name: string, slots?: Record<string, string>) => ({
  type: 'IntentRequest',
  intent: {
    name, confirmationStatus: 'NONE',
    ...(slots ? { slots: Object.fromEntries(Object.entries(slots).map(([k, v]) => [k, { name: k, value: v, confirmationStatus: 'NONE' }])) } : {}),
  },
});

/** Compras em memória: lista Mercado e Farmácia; repetidos (sem acento) são "já estava". */
function fakeShopping(initial: Record<string, string[]> = { Mercado: [], 'Farmácia': [] }) {
  const lists = new Map(Object.entries(initial).map(([k, v]) => [k, [...v]]));
  const fold = (s: string) => s.normalize('NFD').replace(/\p{M}/gu, '').toLowerCase();
  const calls: Array<{ items: string[]; list: string | null }> = [];
  const deps: Pick<SkillDeps, 'addShopping' | 'shoppingSummary'> = {
    async addShopping(items, list) {
      calls.push({ items, list });
      const name = list ?? 'Mercado';
      const cur = lists.get(name) ?? [];
      lists.set(name, cur);
      const added: string[] = [];
      const skipped: string[] = [];
      for (const i of items) {
        if (cur.some((c) => fold(c) === fold(i))) skipped.push(i);
        else { cur.push(i); added.push(i); }
      }
      return { added, skipped, list: name };
    },
    async shoppingSummary() { return [...lists].map(([list, items]) => ({ list, items })); },
  };
  return { deps, calls };
}

async function ssml(skill: ReturnType<typeof buildSkill>, request: Record<string, unknown>, userId = USER) {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const res = await skill.invoke(envelope(request, userId) as any);
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return (res.response.outputSpeech as any)?.ssml as string;
}

describe('skill', () => {
  const logs: string[] = [];
  const skill = buildSkill({ allowedUserId: USER, briefingInput: async () => input, log: (m) => logs.push(m), ...fakeShopping().deps });

  it('abrir a skill fala o resumo com SSML escapado', async () => {
    const out = await ssml(skill, { type: 'LaunchRequest' });
    expect(out).toContain('Bom dia! Hoje é segunda-feira, 28 de setembro.');
    expect(out).toContain('P&amp;D &lt;Lab&gt;');
    expect(out).not.toContain('<Lab>');
  });

  it('ResumoDoDiaIntent e NoticiasIntent', async () => {
    expect(await ssml(skill, intent('ResumoDoDiaIntent'))).toContain('Você tem 1 compromisso');
    expect(await ssml(skill, intent('NoticiasIntent'))).toContain('Manchetes: G1: Chuva forte.');
  });

  it('outra conta Amazon recebe recusa', async () => {
    expect(await ssml(skill, { type: 'LaunchRequest' }, 'amzn1.ask.account.OUTRO')).toContain('Esta skill é privada.');
  });

  it('sem ALEXA_ALLOWED_USER_ID configurado, loga o id da conta', async () => {
    const seen: string[] = [];
    const open = buildSkill({ allowedUserId: null, briefingInput: async () => input, log: (m) => seen.push(m), ...fakeShopping().deps });
    expect(await ssml(open, { type: 'LaunchRequest' })).toContain('ainda não configurada');
    expect(seen.join('\n')).toContain(USER);
  });

  it('erro ao ler a agenda vira mensagem amigável', async () => {
    const broken = buildSkill({ allowedUserId: USER, briefingInput: async () => { throw new Error('db fora'); }, log: () => {}, ...fakeShopping().deps });
    expect(await ssml(broken, { type: 'LaunchRequest' })).toContain('Não consegui acessar sua agenda agora.');
  });

  it('parar se despede', async () => {
    expect(await ssml(skill, intent('AMAZON.StopIntent'))).toContain('Até mais!');
  });

  it('ajuda cita adicionar leite', async () => {
    expect(await ssml(skill, intent('AMAZON.HelpIntent'))).toContain('adicionar leite');
  });

  describe('compras', () => {
    const build = (initial?: Record<string, string[]>) => {
      const f = fakeShopping(initial);
      return { ...f, skill: buildSkill({ allowedUserId: USER, briefingInput: async () => input, log: () => {}, ...f.deps }) };
    };

    it('adicionar itens na lista padrão', async () => {
      const { skill: s, calls } = build();
      const out = await ssml(s, intent('AdicionarCompraIntent', { item: 'leite e pão' }));
      expect(out).toContain('Anotei leite e pão na lista Mercado.');
      expect(calls).toEqual([{ items: ['leite', 'pão'], list: null }]);
    });

    it('"na farmácia" vai para a lista com esse nome', async () => {
      const { skill: s, calls } = build();
      const out = await ssml(s, intent('AdicionarCompraIntent', { item: 'dipirona na farmacia' }));
      expect(out).toContain('Anotei dipirona na lista Farmácia.');
      expect(calls).toEqual([{ items: ['dipirona'], list: 'Farmácia' }]);
    });

    it('repetido avisa que já estava na lista', async () => {
      const { skill: s } = build({ Mercado: ['Leite'] });
      expect(await ssml(s, intent('AdicionarCompraIntent', { item: 'leite' }))).toContain('Leite já estava na lista.');
      const mix = await ssml(s, intent('AdicionarCompraIntent', { item: 'leite e ovos' }));
      expect(mix).toContain('Anotei ovos na lista Mercado.');
      expect(mix).toContain('Leite já estava na lista.');
    });

    it('vários repetidos usam o plural', async () => {
      const { skill: s } = build({ Mercado: ['leite', 'pão'] });
      expect(await ssml(s, intent('AdicionarCompraIntent', { item: 'leite e pão' }))).toContain('Leite e pão já estavam na lista.');
    });

    it('sem item pergunta o que adicionar e mantém a sessão', async () => {
      const { skill: s, calls } = build();
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const res = await s.invoke(envelope(intent('AdicionarCompraIntent')) as any);
      expect((res.response.outputSpeech as any)?.ssml).toContain('O que você quer adicionar?');
      expect(res.response.shouldEndSession).toBe(false);
      expect(calls).toEqual([]);
    });

    it('item com caracteres de SSML é escapado', async () => {
      const { skill: s } = build();
      const out = await ssml(s, intent('AdicionarCompraIntent', { item: 'P&D <x>' }));
      expect(out).toContain('P&amp;D &lt;x&gt;');
    });

    it('ler a lista: poucos itens', async () => {
      const { skill: s } = build({ Mercado: ['leite', 'pão', 'ovos'], 'Farmácia': [] });
      expect(await ssml(s, intent('ListaDeComprasIntent'))).toContain('Na lista Mercado: leite, pão e ovos.');
    });

    it('ler a lista: resume além de três itens', async () => {
      const { skill: s } = build({ Mercado: ['leite', 'pão', 'ovos', 'arroz', 'feijão', 'sal'] });
      expect(await ssml(s, intent('ListaDeComprasIntent'))).toContain('Na lista Mercado: leite, pão, ovos e 3 outros.');
      const um = build({ Mercado: ['leite', 'pão', 'ovos', 'sal'] }).skill;
      expect(await ssml(um, intent('ListaDeComprasIntent'))).toContain('leite, pão, ovos e 1 outro.');
    });

    it('ler a lista: várias listas e lista vazia', async () => {
      const { skill: s } = build({ Mercado: ['leite'], 'Farmácia': ['dipirona'] });
      const out = await ssml(s, intent('ListaDeComprasIntent'));
      expect(out).toContain('Na lista Mercado: leite.');
      expect(out).toContain('Na lista Farmácia: dipirona.');
      expect(await ssml(build().skill, intent('ListaDeComprasIntent'))).toContain('Sua lista está vazia.');
    });

    it('falha no banco vira mensagem amigável', async () => {
      const f = fakeShopping();
      const broken = buildSkill({
        allowedUserId: USER, briefingInput: async () => input, log: () => {},
        addShopping: async () => { throw new Error('db fora'); }, shoppingSummary: f.deps.shoppingSummary,
      });
      expect(await ssml(broken, intent('AdicionarCompraIntent', { item: 'leite' }))).toContain('Não consegui acessar sua lista de compras');
    });
  });
});
