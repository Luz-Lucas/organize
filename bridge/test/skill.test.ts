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

const TZ = 'America/Sao_Paulo';
// terça-feira, 20/10/2026, 12:00 em São Paulo
const NOW = new Date('2026-10-20T15:00:00Z');

type NewTask = Parameters<SkillDeps['addTask']>[0];
type NewEvent = Parameters<SkillDeps['addEvent']>[0];

/** Agenda em memória: guarda o que a skill pediu para gravar. */
function fakeAgenda() {
  const tasks: NewTask[] = [];
  const events: NewEvent[] = [];
  const deps: Pick<SkillDeps, 'timeZone' | 'now' | 'addTask' | 'addEvent'> = {
    timeZone: TZ,
    now: () => NOW,
    async addTask(t) { tasks.push(t); },
    async addEvent(e) { events.push(e); },
  };
  return { deps, tasks, events };
}

async function ssml(skill: ReturnType<typeof buildSkill>, request: Record<string, unknown>, userId = USER) {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const res = await skill.invoke(envelope(request, userId) as any);
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return (res.response.outputSpeech as any)?.ssml as string;
}

describe('skill', () => {
  const logs: string[] = [];
  const skill = buildSkill({ allowedUserId: USER, briefingInput: async () => input, log: (m) => logs.push(m), ...fakeAgenda().deps });

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
    const open = buildSkill({ allowedUserId: null, briefingInput: async () => input, log: (m) => seen.push(m), ...fakeAgenda().deps });
    expect(await ssml(open, { type: 'LaunchRequest' })).toContain('ainda não configurada');
    expect(seen.join('\n')).toContain(USER);
  });

  it('erro ao ler a agenda vira mensagem amigável', async () => {
    const broken = buildSkill({ allowedUserId: USER, briefingInput: async () => { throw new Error('db fora'); }, log: () => {}, ...fakeAgenda().deps });
    expect(await ssml(broken, { type: 'LaunchRequest' })).toContain('Não consegui acessar sua agenda agora.');
  });

  it('parar se despede', async () => {
    expect(await ssml(skill, intent('AMAZON.StopIntent'))).toContain('Até mais!');
  });

  it('ajuda cita o dia, tarefas e eventos', async () => {
    expect(await ssml(skill, intent('AMAZON.HelpIntent'))).toContain(
      'Você pode dizer: qual é o meu dia; adicionar tarefa estudar para sexta; ou marcar reunião amanhã às 15h.',
    );
  });

  it('as compras saíram da skill', async () => {
    const help = await ssml(skill, intent('AMAZON.HelpIntent'));
    expect(help).not.toMatch(/leite|compra|lista/i);
  });

  describe('AdicionarTarefaIntent', () => {
    const build = () => {
      const f = fakeAgenda();
      return { ...f, skill: buildSkill({ allowedUserId: USER, briefingInput: async () => input, log: () => {}, ...f.deps }) };
    };
    const pedido = (v?: string) => intent('AdicionarTarefaIntent', v === undefined ? undefined : { pedido: v });

    it('título e sexta: grava com prazo até 23:59 e confirma', async () => {
      const { skill: s, tasks, events } = build();
      expect(await ssml(s, pedido('estudar cálculo para sexta'))).toContain('Anotei a tarefa estudar cálculo para sexta, 23 de outubro.');
      expect(tasks).toEqual([{ title: 'estudar cálculo', dueAt: new Date('2026-10-24T02:59:00Z') }]);
      expect(events).toEqual([]);
    });

    it('sem prazo', async () => {
      const { skill: s, tasks } = build();
      expect(await ssml(s, pedido('estudar cálculo'))).toContain('Anotei a tarefa estudar cálculo.');
      expect(tasks).toEqual([{ title: 'estudar cálculo', dueAt: null }]);
    });

    it('hoje, amanhã e com hora', async () => {
      const { skill: s, tasks } = build();
      expect(await ssml(s, pedido('pagar a luz hoje'))).toContain('Anotei a tarefa pagar a luz para hoje.');
      expect(await ssml(s, pedido('ligar pro João amanhã'))).toContain('Anotei a tarefa ligar pro João para amanhã, quarta.');
      expect(await ssml(s, pedido('enviar relatório dia 25 às 3 da tarde'))).toContain('Anotei a tarefa enviar relatório para domingo, 25 de outubro, às 15h.');
      expect(tasks.map((t) => t.dueAt?.toISOString())).toEqual([
        '2026-10-21T02:59:00.000Z', '2026-10-22T02:59:00.000Z', '2026-10-25T18:00:00.000Z',
      ]);
    });

    it('hora sem data vale para hoje', async () => {
      const { skill: s, tasks } = build();
      expect(await ssml(s, pedido('ligar para o João às 17h'))).toContain('Anotei a tarefa ligar para o João para hoje, às 17h.');
      expect(tasks).toEqual([{ title: 'ligar para o João', dueAt: new Date('2026-10-20T20:00:00Z') }]);
    });

    it('sem pedido pergunta qual é a tarefa e mantém a sessão', async () => {
      const { skill: s, tasks } = build();
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const res: any = await s.invoke(envelope(pedido()) as any);
      expect(res.response.outputSpeech.ssml).toContain('Qual é a tarefa?');
      expect(res.response.shouldEndSession).toBe(false);
      expect(res.response.reprompt.outputSpeech.ssml).toContain('Qual é a tarefa?');
      expect(res.response.directives).toEqual([
        expect.objectContaining({ type: 'Dialog.ElicitSlot', slotToElicit: 'pedido', updatedIntent: expect.objectContaining({ name: 'AdicionarTarefaIntent' }) }),
      ]);
      expect(tasks).toEqual([]);
    });

    it('só data, sem título, também pergunta de novo', async () => {
      const { skill: s, tasks } = build();
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const res: any = await s.invoke(envelope(pedido('para sexta')) as any);
      expect(res.response.outputSpeech.ssml).toContain('Qual é a tarefa?');
      expect(res.response.shouldEndSession).toBe(false);
      expect(tasks).toEqual([]);
    });

    it('título com caracteres de SSML é escapado na fala', async () => {
      const { skill: s } = build();
      expect(await ssml(s, pedido('revisar P&D <x>'))).toContain('P&amp;D &lt;x&gt;');
    });

    it('falha no banco vira mensagem amigável', async () => {
      const f = fakeAgenda();
      const broken = buildSkill({
        allowedUserId: USER, briefingInput: async () => input, log: () => {}, ...f.deps,
        addTask: async () => { throw new Error('db fora'); },
      });
      expect(await ssml(broken, pedido('estudar'))).toContain('Não consegui anotar a tarefa agora.');
    });
  });

  describe('CriarEventoIntent', () => {
    const build = () => {
      const f = fakeAgenda();
      return { ...f, skill: buildSkill({ allowedUserId: USER, briefingInput: async () => input, log: () => {}, ...f.deps }) };
    };
    const pedido = (v?: string) => intent('CriarEventoIntent', v === undefined ? undefined : { pedido: v });

    it('com hora: evento de 1 hora', async () => {
      const { skill: s, events, tasks } = build();
      expect(await ssml(s, pedido('reunião com o Pedro amanhã às 15h'))).toContain('Marquei reunião com o Pedro amanhã, quarta, das 15h às 16h.');
      expect(events).toEqual([{
        title: 'reunião com o Pedro', startsAt: new Date('2026-10-21T18:00:00Z'), endsAt: new Date('2026-10-21T19:00:00Z'), allDay: false,
      }]);
      expect(tasks).toEqual([]);
    });

    it('sem hora: dia inteiro', async () => {
      const { skill: s, events } = build();
      expect(await ssml(s, pedido('feriado na sexta'))).toContain('Marquei feriado na sexta, 23 de outubro, o dia todo.');
      expect(events).toEqual([{
        title: 'feriado', startsAt: new Date('2026-10-23T03:00:00Z'), endsAt: new Date('2026-10-24T03:00:00Z'), allDay: true,
      }]);
    });

    it('sem data, o padrão é hoje', async () => {
      const { skill: s, events } = build();
      expect(await ssml(s, pedido('dentista às 17h30'))).toContain('Marquei dentista hoje, das 17h30 às 18h30.');
      expect(events[0].startsAt).toEqual(new Date('2026-10-20T20:30:00Z'));
      expect(await ssml(s, pedido('almoço ao meio-dia'))).toContain('Marquei almoço hoje, do meio-dia às 13h.');
      expect(await ssml(s, pedido('feriado'))).toContain('Marquei feriado hoje, o dia todo.');
    });

    it('evento que atravessa a meia-noite', async () => {
      const { skill: s } = build();
      expect(await ssml(s, pedido('festa sábado às 23h'))).toContain('Marquei festa no sábado, 24 de outubro, das 23h à meia-noite.');
    });

    it('sem pedido ou sem título, pergunta e mantém a sessão', async () => {
      const { skill: s, events } = build();
      for (const v of [undefined, 'amanhã às 15h']) {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const res: any = await s.invoke(envelope(pedido(v)) as any);
        expect(res.response.outputSpeech.ssml).toContain('O que você quer marcar?');
        expect(res.response.shouldEndSession).toBe(false);
        expect(res.response.directives[0]).toMatchObject({ type: 'Dialog.ElicitSlot', slotToElicit: 'pedido' });
      }
      expect(events).toEqual([]);
    });

    it('falha no banco vira mensagem amigável', async () => {
      const f = fakeAgenda();
      const broken = buildSkill({
        allowedUserId: USER, briefingInput: async () => input, log: () => {}, ...f.deps,
        addEvent: async () => { throw new Error('db fora'); },
      });
      expect(await ssml(broken, pedido('dentista amanhã'))).toContain('Não consegui marcar o evento agora.');
    });
  });
});
