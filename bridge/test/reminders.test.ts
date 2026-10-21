import { describe, expect, it } from 'vitest';
import {
  reminderFires, reminderSpeech, runReminders,
  type ReminderData, type ReminderDeps, type ReminderEvent, type ReminderSettings, type ReminderTask,
} from '../src/reminders.js';
import { AlexaAuthError } from '../src/gateway.js';
import { FakeGateway } from './fake-gateway.js';

const SP = 'America/Sao_Paulo';
// 2026-10-21 é quarta; São Paulo = UTC-3. Hora local -> instante:
const at = (date: string, hhmm: string) => new Date(`${date}T${hhmm}:00-03:00`);

const settings = (over: Partial<ReminderSettings> = {}): ReminderSettings => ({
  dndEnabled: true, dndStart: '23:00', dndEnd: '10:00', ...over,
});
const event = (over: Partial<ReminderEvent> = {}): ReminderEvent => ({
  id: 'e1', title: 'Reunião', startsAt: at('2026-10-22', '15:00'), allDay: false, reminders: [30], ...over,
});
const task = (over: Partial<ReminderTask> = {}): ReminderTask => ({
  id: 't1', title: 'Pagar a luz', dueAt: at('2026-10-22', '18:00'), status: 'todo', priority: 'media', reminders: [60], ...over,
});
const NOW = at('2026-10-21', '08:00');
const fires = (items: { tasks?: ReminderTask[]; events?: ReminderEvent[] }, s = settings(), now = NOW) =>
  reminderFires({ tasks: items.tasks ?? [], events: items.events ?? [] }, s, now, SP);
const iso = (d: Date) => d.toISOString();

describe('reminderFires: eventos', () => {
  it('evento 15:00 com {30} avisa às 14:30', () => {
    const [f] = fires({ events: [event()] });
    expect(f).toMatchObject({ kind: 'event', itemId: 'e1', title: 'Reunião', dateOnly: false });
    expect(iso(f.fireAt)).toBe(iso(at('2026-10-22', '14:30')));
    expect(iso(f.itemAt)).toBe(iso(at('2026-10-22', '15:00')));
  });

  it('evento 08:30 com {30}: 08:00 cai no não perturbe, 10:00 passa do horário e é descartado', () => {
    expect(fires({ events: [event({ startsAt: at('2026-10-22', '08:30') })] })).toEqual([]);
  });

  it('evento 11:00 com {1440} avisa na véspera às 11:00', () => {
    const [f] = fires({ events: [event({ startsAt: at('2026-10-22', '11:00'), reminders: [1440] })] });
    expect(iso(f.fireAt)).toBe(iso(at('2026-10-21', '11:00')));
  });

  it('evento 10:20 com {60,30}: 09:20 e 09:50 viram um único 10:00', () => {
    const r = fires({ events: [event({ startsAt: at('2026-10-22', '10:20'), reminders: [60, 30] })] });
    expect(r.map((f) => iso(f.fireAt))).toEqual([iso(at('2026-10-22', '10:00'))]);
  });

  it('não perturbe desligado mantém 08:00', () => {
    const r = fires({ events: [event({ startsAt: at('2026-10-22', '08:30') })] }, settings({ dndEnabled: false }));
    expect(r.map((f) => iso(f.fireAt))).toEqual([iso(at('2026-10-22', '08:00'))]);
  });

  it('não perturbe 22:00 -> 07:00 com aviso às 23:30 vai para 07:00 do dia seguinte', () => {
    // evento às 23:30 do dia 23 com {1440}: aviso às 23:30 do dia 22, dentro do intervalo que atravessa a meia-noite
    const r = fires({ events: [event({ startsAt: at('2026-10-23', '23:30'), reminders: [1440] })] },
      settings({ dndStart: '22:00', dndEnd: '07:00' }));
    expect(r.map((f) => iso(f.fireAt))).toEqual([iso(at('2026-10-23', '07:00'))]);
  });

  it('aviso de madrugada sobe para o fim do intervalo do mesmo dia, se ainda for antes do item', () => {
    // 03:00 do dia 23 (parte pós-meia-noite do intervalo) seria 07:00 >= 03:30: descartado;
    // 03:30 do dia 22 (1440) vai para 07:00 do dia 22, antes do item
    const r = fires({ events: [event({ startsAt: at('2026-10-23', '03:30'), reminders: [30, 1440] })] },
      settings({ dndStart: '22:00', dndEnd: '07:00' }));
    expect(r.map((f) => iso(f.fireAt))).toEqual([iso(at('2026-10-22', '07:00'))]);
    const r2 = fires({ events: [event({ startsAt: at('2026-10-23', '09:00'), reminders: [1440] })] },
      settings({ dndStart: '22:00', dndEnd: '07:00' }));
    expect(r2.map((f) => iso(f.fireAt))).toEqual([iso(at('2026-10-22', '09:00'))]);
  });

  it('dia inteiro não avisa', () => {
    expect(fires({ events: [event({ allDay: true })] })).toEqual([]);
  });

  it('remove avisos que já passaram', () => {
    const r = fires({ events: [event({ startsAt: at('2026-10-21', '12:00'), reminders: [30, 15, 1440] })] },
      settings(), at('2026-10-21', '11:40'));
    expect(r.map((f) => iso(f.fireAt))).toEqual([iso(at('2026-10-21', '11:45'))]);
  });
});

describe('reminderFires: tarefas', () => {
  it('tarefa com hora avisa dueAt - m', () => {
    const [f] = fires({ tasks: [task()] });
    expect(f).toMatchObject({ kind: 'task', itemId: 't1', dateOnly: false });
    expect(iso(f.fireAt)).toBe(iso(at('2026-10-22', '17:00')));
  });

  it('tarefa só com data e prioridade alta avisa às 10:00 do dia do prazo', () => {
    const [f] = fires({ tasks: [task({ dueAt: at('2026-10-22', '23:59'), priority: 'alta' })] });
    expect(f.dateOnly).toBe(true);
    expect(iso(f.fireAt)).toBe(iso(at('2026-10-22', '10:00')));
    expect(iso(f.itemAt)).toBe(iso(at('2026-10-22', '23:59')));
  });

  it('tarefa só com data e prioridade média não avisa', () => {
    expect(fires({ tasks: [task({ dueAt: at('2026-10-22', '23:59'), priority: 'media' })] })).toEqual([]);
  });

  it('tarefa concluída ou sem prazo não avisa', () => {
    expect(fires({ tasks: [task({ status: 'done' }), task({ id: 't2', dueAt: null })] })).toEqual([]);
  });

  it('tarefa só com data alta, mesmo com o não perturbe cobrindo 10:00, sobe para o fim do intervalo', () => {
    const [f] = fires({ tasks: [task({ dueAt: at('2026-10-22', '23:59'), priority: 'alta' })] },
      settings({ dndStart: '08:00', dndEnd: '12:00' }));
    expect(iso(f.fireAt)).toBe(iso(at('2026-10-22', '12:00')));
  });
});

describe('reminderSpeech', () => {
  const base = { fireAt: at('2026-10-22', '14:30') };
  it('evento no mesmo dia', () => {
    const f = { kind: 'event' as const, itemId: 'e', title: 'reunião com o Pedro', ...base, itemAt: at('2026-10-22', '15:00'), dateOnly: false };
    expect(reminderSpeech(f, SP)).toBe('Lembrete: reunião com o Pedro às 15 horas.');
  });
  it('evento com minutos', () => {
    const f = { kind: 'event' as const, itemId: 'e', title: 'dentista', ...base, itemAt: at('2026-10-22', '15:30'), dateOnly: false };
    expect(reminderSpeech(f, SP)).toBe('Lembrete: dentista às 15 e 30.');
  });
  it('evento no dia seguinte', () => {
    const f = { kind: 'event' as const, itemId: 'e', title: 'reunião', fireAt: at('2026-10-21', '11:00'), itemAt: at('2026-10-22', '11:00'), dateOnly: false };
    expect(reminderSpeech(f, SP)).toBe('Lembrete: amanhã, reunião às 11 horas.');
  });
  it('tarefa só com data', () => {
    const f = { kind: 'task' as const, itemId: 't', title: 'pagar a luz.', fireAt: at('2026-10-22', '10:00'), itemAt: at('2026-10-22', '23:59'), dateOnly: true };
    expect(reminderSpeech(f, SP)).toBe('Lembrete: hoje vence a tarefa pagar a luz.');
  });
  it('tarefa com hora', () => {
    const f = { kind: 'task' as const, itemId: 't', title: 'pagar a luz', fireAt: at('2026-10-22', '17:00'), itemAt: at('2026-10-22', '18:00'), dateOnly: false };
    expect(reminderSpeech(f, SP)).toBe('Lembrete: a tarefa pagar a luz vence às 18 horas.');
  });
  it('uma hora e meio-dia', () => {
    const f = { kind: 'event' as const, itemId: 'e', title: 'almoço', fireAt: at('2026-10-22', '11:30'), itemAt: at('2026-10-22', '12:00'), dateOnly: false };
    expect(reminderSpeech(f, SP)).toBe('Lembrete: almoço ao meio-dia.');
    expect(reminderSpeech({ ...f, itemAt: at('2026-10-22', '01:00') }, SP)).toBe('Lembrete: almoço à 1 hora.');
  });
});

describe('runReminders', () => {
  const NOWRUN = at('2026-10-22', '14:30');
  const makeDeps = (over: Partial<ReminderData> = {}, depsOver: Partial<ReminderDeps> = {}) => {
    const gateway = new FakeGateway();
    const claimed = new Set<string>();
    const logs: string[] = [];
    const data: ReminderData = {
      tasks: [], events: [event()],
      settings: { ...settings(), remindersAlexa: true, reminderEcho: 'ECHO' },
      ...over,
    };
    const deps: ReminderDeps = {
      gateway, timeZone: SP, now: () => NOWRUN, log: (m) => logs.push(m),
      load: async () => data,
      presence: async () => 'home',
      claim: async (f) => {
        const k = `${f.kind}:${f.itemId}:${f.fireAt.toISOString()}`;
        if (claimed.has(k)) return false;
        claimed.add(k);
        return true;
      },
      ...depsOver,
    };
    return { gateway, deps, logs };
  };

  it('fala no Echo escolhido quando o aviso está na janela', async () => {
    const { gateway, deps } = makeDeps();
    expect(await runReminders(deps)).toBe(1);
    expect(gateway.calls).toEqual(['speak(ECHO,Lembrete: Reunião às 15 horas.)']);
  });

  it('não repete o mesmo aviso no próximo ciclo', async () => {
    const { gateway, deps } = makeDeps();
    await runReminders(deps);
    await runReminders({ ...deps, now: () => new Date(NOWRUN.getTime() + 60_000) });
    expect(gateway.calls).toHaveLength(1);
  });

  it('avisos com mais de 5 minutos de atraso e futuros não falam', async () => {
    const { gateway, deps } = makeDeps();
    await runReminders({ ...deps, now: () => new Date(NOWRUN.getTime() + 5 * 60_000) });
    await runReminders({ ...deps, now: () => new Date(NOWRUN.getTime() - 1000) });
    expect(gateway.calls).toEqual([]);
  });

  it('dentro dos 5 minutos de atraso ainda fala', async () => {
    const { gateway, deps } = makeDeps();
    await runReminders({ ...deps, now: () => new Date(NOWRUN.getTime() + 4 * 60_000) });
    expect(gateway.calls).toHaveLength(1);
  });

  it('chave Alexa desligada, sem Echo ou presença away: não fala nem registra', async () => {
    const claims: string[] = [];
    const claim = async (f: { itemId: string }) => { claims.push(f.itemId); return true; };
    const off = makeDeps({ settings: { ...settings(), remindersAlexa: false, reminderEcho: 'ECHO' } }, { claim });
    const noEcho = makeDeps({ settings: { ...settings(), remindersAlexa: true, reminderEcho: null } }, { claim });
    const away = makeDeps({}, { claim, presence: async () => 'away' });
    for (const m of [off, noEcho, away]) {
      await runReminders(m.deps);
      expect(m.gateway.calls).toEqual([]);
    }
    expect(claims).toEqual([]);
  });

  it('presença desconhecida ou com erro: fala mesmo assim', async () => {
    const unknown = makeDeps({}, { presence: async () => 'unknown' });
    await runReminders(unknown.deps);
    expect(unknown.gateway.calls).toHaveLength(1);
    const boom = makeDeps({}, { presence: async () => { throw new Error('sem dados'); } });
    await runReminders(boom.deps);
    expect(boom.gateway.calls).toHaveLength(1);
  });

  it('falha ao falar não derruba o laço e as outras mensagens seguem', async () => {
    const { gateway, deps, logs } = makeDeps({
      events: [event(), event({ id: 'e2', title: 'Dentista' })],
    });
    gateway.failOn.add('speak');
    expect(await runReminders(deps)).toBe(0);
    expect(logs.some((l) => l.includes('lembrete'))).toBe(true);
  });

  it('login expirado da Alexa sobe para o chamador tratar', async () => {
    const { gateway, deps } = makeDeps();
    gateway.speak = async () => { throw new AlexaAuthError('login expirou'); };
    await expect(runReminders(deps)).rejects.toBeInstanceOf(AlexaAuthError);
  });

  it('texto longo é dividido em pedaços', async () => {
    const { gateway, deps } = makeDeps({ events: [event({ title: 'palavra '.repeat(60).trim() })] });
    await runReminders(deps);
    expect(gateway.calls.length).toBeGreaterThan(1);
  });
});
