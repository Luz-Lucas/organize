import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { buildSkill, type SkillDeps } from '../src/skill.js';

const USER = 'amzn1.ask.account.EU';
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

const TZ = 'America/Sao_Paulo';
// terça-feira, 20/10/2026, 12:00 em São Paulo
const NOW = new Date('2026-10-20T15:00:00Z');

type NewTask = Parameters<SkillDeps['addTask']>[0];

/** Agenda em memória: guarda o que a skill pediu para gravar. */
function fakeAgenda() {
  const tasks: NewTask[] = [];
  const deps: Pick<SkillDeps, 'timeZone' | 'now' | 'addTask'> = {
    timeZone: TZ,
    now: () => NOW,
    async addTask(t) { tasks.push(t); },
  };
  return { deps, tasks };
}

async function ssml(skill: ReturnType<typeof buildSkill>, request: Record<string, unknown>, userId = USER) {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const res = await skill.invoke(envelope(request, userId) as any);
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return (res.response.outputSpeech as any)?.ssml as string;
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
async function raw(skill: ReturnType<typeof buildSkill>, request: Record<string, unknown>): Promise<any> {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return (await skill.invoke(envelope(request) as any)).response;
}

/** Resposta que pergunta a tarefa e mantém a sessão aberta, com a próxima fala indo para o campo `pedido`. */
function expectAsksTask(res: any, question = 'Qual é a tarefa?') {
  expect(res.outputSpeech.ssml).toContain(question);
  expect(res.shouldEndSession).toBe(false);
  expect(res.reprompt.outputSpeech.ssml).toContain('Qual é a tarefa?');
  expect(res.directives).toEqual([{
    type: 'Dialog.ElicitSlot',
    slotToElicit: 'pedido',
    updatedIntent: {
      name: 'AdicionarTarefaIntent',
      confirmationStatus: 'NONE',
      slots: { pedido: { name: 'pedido', confirmationStatus: 'NONE' } },
    },
  }]);
}

describe('skill', () => {
  const logs: string[] = [];
  const build = () => {
    const f = fakeAgenda();
    return { ...f, skill: buildSkill({ allowedUserId: USER, log: (m) => logs.push(m), ...f.deps }) };
  };
  const { skill } = build();

  it('abrir a skill pergunta a tarefa e mantém a sessão para a próxima fala virar o pedido', async () => {
    expectAsksTask(await raw(skill, { type: 'LaunchRequest' }));
  });

  it('abrir a skill não fala resumo nem agenda', async () => {
    const out = await ssml(skill, { type: 'LaunchRequest' });
    expect(out).not.toMatch(/bom dia|compromisso|manchete|agenda/i);
  });

  it('outra conta Amazon recebe recusa', async () => {
    expect(await ssml(skill, { type: 'LaunchRequest' }, 'amzn1.ask.account.OUTRO')).toContain('Esta skill é privada.');
  });

  it('sem ALEXA_ALLOWED_USER_ID configurado, loga o id da conta', async () => {
    const seen: string[] = [];
    const open = buildSkill({ allowedUserId: null, log: (m) => seen.push(m), ...fakeAgenda().deps });
    expect(await ssml(open, { type: 'LaunchRequest' })).toContain('ainda não configurada');
    expect(seen.join('\n')).toContain(USER);
  });

  it('parar e cancelar se despedem', async () => {
    expect(await ssml(skill, intent('AMAZON.StopIntent'))).toContain('Até mais!');
    expect(await ssml(skill, intent('AMAZON.CancelIntent'))).toContain('Até mais!');
  });

  it('ajuda dá um exemplo de tarefa e continua esperando a tarefa', async () => {
    const res = await raw(skill, intent('AMAZON.HelpIntent'));
    expect(res.outputSpeech.ssml).toContain('Diga a tarefa, por exemplo: adicionar estudar cálculo para sexta.');
    expect(res.shouldEndSession).toBe(false);
    expect(res.directives[0]).toMatchObject({ type: 'Dialog.ElicitSlot', slotToElicit: 'pedido' });
  });

  it('não entendeu (Fallback): pergunta qual é a tarefa e mantém a sessão', async () => {
    expectAsksTask(await raw(skill, intent('AMAZON.FallbackIntent')));
  });

  it('as compras saíram da skill', async () => {
    const help = await ssml(skill, intent('AMAZON.HelpIntent'));
    expect(help).not.toMatch(/leite|compra|lista/i);
  });

  describe('AdicionarTarefaIntent', () => {
    const pedido = (v?: string) => intent('AdicionarTarefaIntent', v === undefined ? undefined : { pedido: v });

    it('título e sexta: grava com prazo até 23:59, prioridade alta, e confirma sem citar prioridade', async () => {
      const { skill: s, tasks } = build();
      const out = await ssml(s, pedido('estudar cálculo para sexta'));
      expect(out).toContain('Anotei a tarefa estudar cálculo para sexta, 23 de outubro.');
      expect(out).not.toMatch(/prioridade|alta/i);
      expect(tasks).toEqual([{ title: 'estudar cálculo', dueAt: new Date('2026-10-24T02:59:00Z'), priority: 'alta' }]);
    });

    it('mandar mensagem para a Joana amanhã', async () => {
      const { skill: s, tasks } = build();
      expect(await ssml(s, pedido('mandar mensagem para a Joana amanhã'))).toContain(
        'Anotei a tarefa mandar mensagem para a Joana para amanhã, quarta, 21 de outubro.',
      );
      expect(tasks).toEqual([{ title: 'mandar mensagem para a Joana', dueAt: new Date('2026-10-22T02:59:00Z'), priority: 'alta' }]);
    });

    it('"cancelar", "nada", "deixa pra lá" depois de "Qual é a tarefa?" encerram sem anotar', async () => {
      const { skill: s, tasks } = build();
      for (const v of ['cancelar', 'Nada.', 'deixa pra lá', 'parar', 'não']) {
        expect(await ssml(s, pedido(v))).toContain('Tudo bem, não anotei nada.');
      }
      expect(tasks).toEqual([]);
      // Palavras de cancelar dentro de uma tarefa de verdade continuam valendo.
      expect(await ssml(s, pedido('cancelar a assinatura da academia'))).toContain('Anotei a tarefa cancelar a assinatura da academia.');
    });

    it('sem prazo, também com prioridade alta', async () => {
      const { skill: s, tasks } = build();
      expect(await ssml(s, pedido('mandar mensagem para a Joana'))).toContain('Anotei a tarefa mandar mensagem para a Joana.');
      expect(tasks).toEqual([{ title: 'mandar mensagem para a Joana', dueAt: null, priority: 'alta' }]);
    });

    it('hoje, depois de amanhã e com hora', async () => {
      const { skill: s, tasks } = build();
      expect(await ssml(s, pedido('pagar a luz hoje'))).toContain('Anotei a tarefa pagar a luz para hoje.');
      expect(await ssml(s, pedido('enviar relatório dia 25 às 3 da tarde'))).toContain('Anotei a tarefa enviar relatório para domingo, 25 de outubro, às 15h.');
      expect(tasks.map((t) => [t.dueAt?.toISOString(), t.priority])).toEqual([
        ['2026-10-21T02:59:00.000Z', 'alta'], ['2026-10-25T18:00:00.000Z', 'alta'],
      ]);
    });

    it('depois de amanhã também leva o dia e a data', async () => {
      const { skill: s } = build();
      expect(await ssml(s, pedido('ligar pro João depois de amanhã'))).toContain('Anotei a tarefa ligar pro João para depois de amanhã, quinta, 22 de outubro.');
    });

    it('hora sem data vale para hoje', async () => {
      const { skill: s, tasks } = build();
      expect(await ssml(s, pedido('ligar para o João às 17h'))).toContain('Anotei a tarefa ligar para o João para hoje, às 17h.');
      expect(tasks).toEqual([{ title: 'ligar para o João', dueAt: new Date('2026-10-20T20:00:00Z'), priority: 'alta' }]);
    });

    it('sem pedido ("adicionar tarefa" sozinho) pergunta qual é a tarefa e mantém a sessão', async () => {
      const { skill: s, tasks } = build();
      expectAsksTask(await raw(s, pedido()));
      expect(tasks).toEqual([]);
    });

    it('só data, sem título, também pergunta de novo', async () => {
      const { skill: s, tasks } = build();
      expectAsksTask(await raw(s, pedido('para sexta')));
      expect(tasks).toEqual([]);
    });

    it('título com caracteres de SSML é escapado na fala', async () => {
      const { skill: s } = build();
      expect(await ssml(s, pedido('revisar P&D <x>'))).toContain('P&amp;D &lt;x&gt;');
    });

    it('falha no banco vira mensagem amigável', async () => {
      const f = fakeAgenda();
      const broken = buildSkill({
        allowedUserId: USER, log: () => {}, ...f.deps,
        addTask: async () => { throw new Error('db fora'); },
      });
      expect(await ssml(broken, pedido('estudar'))).toContain('Não consegui anotar a tarefa agora.');
    });
  });

  it('erro inesperado vira mensagem amigável', async () => {
    const f = fakeAgenda();
    const broken = buildSkill({ allowedUserId: USER, log: () => {}, ...f.deps, now: () => { throw new Error('relógio'); } });
    expect(await ssml(broken, intent('AdicionarTarefaIntent', { pedido: 'estudar' }))).toContain('Tente de novo em instantes.');
  });
});

describe('modelo de interação pt-BR', () => {
  const model = JSON.parse(readFileSync(new URL('../skill/interaction-model.pt-BR.json', import.meta.url), 'utf8')).interactionModel;
  const intents: Array<{ name: string; samples: string[]; slots?: Array<{ name: string; type: string; samples?: string[] }> }> = model.languageModel.intents;
  const byName = (n: string) => intents.find((i) => i.name === n)!;

  it('invocationName continua organize', () => {
    expect(model.languageModel.invocationName).toBe('organize');
  });

  it('só tarefas: sem resumo, notícias nem evento', () => {
    expect(intents.map((i) => i.name).sort()).toEqual([
      'AMAZON.CancelIntent', 'AMAZON.FallbackIntent', 'AMAZON.HelpIntent', 'AMAZON.NavigateHomeIntent', 'AMAZON.StopIntent', 'AdicionarTarefaIntent',
    ]);
  });

  it('muitas frases de entrada, todas com {pedido}', () => {
    const { samples } = byName('AdicionarTarefaIntent');
    for (const s of ['adicionar tarefa', 'adicionar a tarefa', 'adicionar', 'adiciona', 'anotar', 'anota', 'nova tarefa', 'criar tarefa',
      'tarefa', 'me lembra de', 'lembrar de', 'lembrete', 'preciso', 'eu preciso', 'tenho que', 'colocar']) {
      expect(samples, s).toContain(`${s} {pedido}`);
    }
    for (const s of samples) expect(s).toContain('{pedido}');
    expect(new Set(samples).size).toBe(samples.length);
  });

  it('o slot pedido é SearchQuery e tem frase de elicitação só com {pedido}', () => {
    const slot = byName('AdicionarTarefaIntent').slots!.find((x) => x.name === 'pedido')!;
    expect(slot.type).toBe('AMAZON.SearchQuery');
    expect(slot.samples).toEqual(['{pedido}']);
  });

  it('dialog model exige a elicitação de pedido, com a skill controlando a conversa', () => {
    expect(model.dialog.delegationStrategy).toBe('SKILL_RESPONSE');
    const d = model.dialog.intents.find((i: { name: string }) => i.name === 'AdicionarTarefaIntent');
    const slot = d.slots.find((x: { name: string }) => x.name === 'pedido');
    expect(slot).toMatchObject({ type: 'AMAZON.SearchQuery', elicitationRequired: true, confirmationRequired: false });
    const prompt = model.prompts.find((p: { id: string }) => p.id === slot.prompts.elicitation);
    expect(prompt.variations).toEqual([{ type: 'PlainText', value: 'Qual é a tarefa?' }]);
  });
});
