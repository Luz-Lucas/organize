import { describe, expect, it } from 'vitest';
import { AlexaRemoteGateway } from '../src/alexa-remote-gateway.js';
import type { WakePlan, WakeRun } from '../src/scheduler.js';
import { applyWakeActions, type WakeStore } from '../src/wake.js';

type Any = any; // eslint-disable-line @typescript-eslint/no-explicit-any

const SERIAL = 'G090LF09643202VS';
const TYPE = 'A3S5BH2HU6VAYF';
const AT = new Date('2026-09-28T10:10:00Z');
const pad = (n: number) => String(n).padStart(2, '0');
const localIso = (d: Date) =>
  `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;

interface ServerAlarm {
  id: string; notificationIndex?: string; deviceSerialNumber: string; type: string;
  alarmTime: number; originalTime: string; reminderLabel: string | null; status: string;
}

/** Imita o trecho da alexa-remote2 8.1.1 que o gateway usa para alarmes (formato novo: POST /v1/alerts/alarms). */
class FakeAlexa {
  alarms: ServerAlarm[] = [];
  calls: string[] = [];
  /** O que o POST devolve. A API real devolve corpo sem id (a lib converte corpo vazio em {success:true}). */
  postResponse: (created: ServerAlarm) => unknown = () => ({ success: true });
  listFails = false;
  deleteV2Fails = false;
  /** O DELETE responde sucesso, mas não apaga nada. */
  deleteV2Noop = false;
  cancelFails = false;
  cancelNoop = false;
  oldDeleteNoop = false;
  private seq = 0;

  /** Cria direto no "servidor", como se o usuário ou outro cliente tivesse criado. */
  seed(over: Partial<ServerAlarm> & { at?: Date } = {}): ServerAlarm {
    const n = ++this.seq;
    const at = over.at ?? AT;
    const uuid = `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
    const alarm: ServerAlarm = {
      id: `${TYPE}-${SERIAL}-${uuid}`, notificationIndex: uuid, deviceSerialNumber: SERIAL, type: 'Alarm',
      alarmTime: at.getTime(), originalTime: localIso(at).slice(11) + '.000', reminderLabel: null, status: 'ON',
      ...over,
    };
    delete (alarm as Any).at;
    this.alarms.push(alarm);
    return alarm;
  }

  active(): ServerAlarm[] { return this.alarms.filter((a) => a.status === 'ON'); }

  createNotificationObject(serial: string, type: string, _label: string, value: Date) {
    // Como na lib real: formato novo, sem rótulo, com endpointId.
    return { trigger: { scheduledTime: localIso(value) }, extensions: [], endpointId: `${serial}@${TYPE}`, _type: type };
  }

  createNotification(n: Any, cb: (e: unknown, r?: unknown) => void) {
    this.calls.push('POST /v1/alerts/alarms');
    const at = new Date(n.trigger.scheduledTime);
    const created = this.seed({ at, deviceSerialNumber: String(n.endpointId).split('@')[0] });
    cb(null, this.postResponse(created));
  }

  getNotifications(cached: boolean, cb: (e: unknown, r?: unknown) => void) {
    this.calls.push(`GET /api/notifications cached=${cached}`);
    if (this.listFails) return cb(new Error('lista indisponível'));
    cb(null, { notifications: this.alarms.map((a) => ({ ...a })) });
  }

  httpsGetAuthApi(path: string, cb: (e: unknown, r?: unknown) => void, flags: Any = {}) {
    this.calls.push(`${flags.method ?? 'GET'} ${path}`);
    const m = /^\/v1\/alerts\/alarms\/([^/]+)$/.exec(path);
    if (flags.method === 'DELETE' && m) {
      if (this.deleteV2Fails) return cb(new Error('no body'));
      if (!this.deleteV2Noop) this.alarms = this.alarms.filter((a) => a.notificationIndex !== m[1]);
      return cb(null, { success: true });
    }
    cb(new Error(`rota inesperada ${path}`));
  }

  deactivateNotificationV2(idx: string, cb: (e: unknown, r?: unknown) => void) {
    this.calls.push(`PUT /v1/alerts/alarms/${idx}/cancel`);
    if (this.cancelFails) return cb(new Error('cancel falhou'));
    if (!this.cancelNoop) for (const a of this.alarms) if (a.notificationIndex === idx) a.status = 'OFF';
    cb(null, { success: true });
  }

  deleteNotification(n: Any, cb: (e: unknown, r?: unknown) => void) {
    this.calls.push(`DELETE /api/notifications/${n.id}`);
    if (!this.oldDeleteNoop) this.alarms = this.alarms.filter((a) => a.id !== n.id);
    cb(null, { Message: null });
  }
}

const setup = () => {
  const alexa = new FakeAlexa();
  const logs: string[] = [];
  const gw = new AlexaRemoteGateway(alexa, (m: string) => logs.push(m));
  return { alexa, gw, logs };
};

const mutating = (alexa: FakeAlexa) => alexa.calls.filter((c) => /^(DELETE|PUT) /.test(c));

describe('AlexaRemoteGateway.createAlarm', () => {
  it('resposta do POST sem id: acha o alarme na lista e grava o handle com notificationIndex', async () => {
    const { alexa, gw } = setup();
    const handle = JSON.parse(await gw.createAlarm(SERIAL, AT, 'Aula (reserva)'));
    const created = alexa.alarms[0]!;
    expect(handle).toEqual({
      v: 2, notificationIndex: created.notificationIndex, id: created.id,
      deviceSerialNumber: SERIAL, alarmTime: AT.getTime(), label: 'Aula (reserva)',
    });
    expect(alexa.calls).toEqual(['POST /v1/alerts/alarms', 'GET /api/notifications cached=false']);
  });

  it('resposta do POST com identificador: usa o da resposta, sem listar', async () => {
    const { alexa, gw } = setup();
    alexa.postResponse = (c) => ({ notificationIndex: c.notificationIndex });
    const handle = JSON.parse(await gw.createAlarm(SERIAL, AT, 'Aula (reserva)'));
    expect(handle.notificationIndex).toBe(alexa.alarms[0]!.notificationIndex);
    expect(handle.deviceSerialNumber).toBe(SERIAL);
    expect(alexa.calls).toEqual(['POST /v1/alerts/alarms']);
  });

  it('identificador aninhado na resposta também vale, mas o id do som não', async () => {
    const { alexa, gw } = setup();
    alexa.postResponse = (c) => ({ sound: { id: 'system_alerts_repetitive_04' }, alarm: { notificationIndex: c.notificationIndex } });
    const handle = JSON.parse(await gw.createAlarm(SERIAL, AT, 'Aula (reserva)'));
    expect(handle.notificationIndex).toBe(alexa.alarms[0]!.notificationIndex);
    expect(handle.id).toBeUndefined();
  });

  it('ignora alarmes de outro Echo, de outro tipo e fora de ±90 s', async () => {
    const { alexa, gw } = setup();
    alexa.seed({ deviceSerialNumber: 'OUTRO' });
    alexa.seed({ type: 'Reminder' });
    alexa.seed({ at: new Date(AT.getTime() + 120_000) });
    const handle = JSON.parse(await gw.createAlarm(SERIAL, AT, 'Aula (reserva)'));
    const mine = alexa.alarms.at(-1)!;
    expect(handle.notificationIndex).toBe(mine.notificationIndex);
  });

  it('lista indisponível: não falha, grava o handle só com dispositivo, horário e label', async () => {
    const { alexa, gw, logs } = setup();
    alexa.listFails = true;
    const handle = JSON.parse(await gw.createAlarm(SERIAL, AT, 'Aula (reserva)'));
    expect(handle).toEqual({ v: 2, deviceSerialNumber: SERIAL, alarmTime: AT.getTime(), label: 'Aula (reserva)' });
    expect(logs.some((m) => m.includes('lista indisponível') || m.includes('listar'))).toBe(true);
  });

  it('registra só as chaves da resposta, uma única vez, nunca valores', async () => {
    const { alexa, gw, logs } = setup();
    alexa.postResponse = (c) => ({ notificationIndex: c.notificationIndex, secret: 'valor-secreto-123' });
    await gw.createAlarm(SERIAL, AT, 'Aula (reserva)');
    await gw.createAlarm(SERIAL, new Date(AT.getTime() + 3_600_000), 'Aula (reserva)');
    const shape = logs.filter((m) => m.includes('chaves'));
    expect(shape).toHaveLength(1);
    expect(shape[0]).toContain('notificationIndex');
    expect(shape[0]).toContain('secret');
    const all = logs.join('\n');
    expect(all).not.toContain('valor-secreto-123');
    expect(all).not.toContain(alexa.alarms[0]!.notificationIndex!);
    expect(all).not.toContain(SERIAL);
  });
});

describe('AlexaRemoteGateway.deleteAlarm', () => {
  it('handle novo: apaga pela rota V2 (DELETE) e confirma na lista', async () => {
    const { alexa, gw } = setup();
    const handle = await gw.createAlarm(SERIAL, AT, 'Aula (reserva)');
    alexa.calls.length = 0;
    await gw.deleteAlarm(handle);
    expect(alexa.alarms).toEqual([]);
    expect(mutating(alexa)).toHaveLength(1);
    expect(mutating(alexa)[0]).toMatch(/^DELETE \/v1\/alerts\/alarms\/[0-9a-f-]+$/);
  });

  it('DELETE V2 falha: o fallback /cancel resolve', async () => {
    const { alexa, gw } = setup();
    const handle = await gw.createAlarm(SERIAL, AT, 'Aula (reserva)');
    const idx = alexa.alarms[0]!.notificationIndex;
    alexa.deleteV2Fails = true;
    await gw.deleteAlarm(handle);
    expect(alexa.active()).toEqual([]);
    expect(mutating(alexa)).toEqual([`DELETE /v1/alerts/alarms/${idx}`, `PUT /v1/alerts/alarms/${idx}/cancel`]);
  });

  it('DELETE V2 "funciona" mas o alarme continua ON: tenta /cancel em seguida', async () => {
    const { alexa, gw } = setup();
    const handle = await gw.createAlarm(SERIAL, AT, 'Aula (reserva)');
    alexa.deleteV2Noop = true;
    await gw.deleteAlarm(handle);
    expect(alexa.active()).toEqual([]);
  });

  it('handle legado sem id (trigger/extensions/endpointId): acha pelo horário e pelo dispositivo e apaga', async () => {
    const { alexa, gw } = setup();
    const mine = alexa.seed();
    const user = alexa.seed({ at: new Date(AT.getTime() + 3_600_000), reminderLabel: 'Trabalho' });
    const legacy = JSON.stringify({ trigger: { scheduledTime: localIso(AT) }, extensions: [], endpointId: `${SERIAL}@${TYPE}` });
    await gw.deleteAlarm(legacy);
    expect(alexa.alarms.map((a) => a.id)).toEqual([user.id]);
    expect(alexa.alarms.some((a) => a.id === mine.id)).toBe(false);
  });

  it('handle legado: não mexe em alarme de outro Echo nem em alarme com outro rótulo no mesmo horário', async () => {
    const { alexa, gw } = setup();
    alexa.seed({ deviceSerialNumber: 'OUTRO' });
    alexa.seed({ reminderLabel: 'Remédio' });
    const mine = alexa.seed({ reminderLabel: 'Aula (reserva)' });
    const legacy = JSON.stringify({ trigger: { scheduledTime: localIso(AT) }, extensions: [], endpointId: `${SERIAL}@${TYPE}` });
    await gw.deleteAlarm(legacy);
    expect(alexa.alarms.some((a) => a.id === mine.id)).toBe(false);
    expect(alexa.alarms).toHaveLength(2);
    expect(alexa.active()).toHaveLength(2);
  });

  it('handle novo sem notificationIndex (lista indisponível na criação): acha por dispositivo, horário e label', async () => {
    const { alexa, gw } = setup();
    alexa.listFails = true;
    const handle = await gw.createAlarm(SERIAL, AT, 'Aula (reserva)');
    alexa.listFails = false;
    await gw.deleteAlarm(handle);
    expect(alexa.alarms).toEqual([]);
  });

  it('o alarme ainda está ON depois de tentar apagar: lança erro claro', async () => {
    const { alexa, gw } = setup();
    const handle = await gw.createAlarm(SERIAL, AT, 'Aula (reserva)');
    alexa.deleteV2Noop = true;
    alexa.cancelNoop = true;
    alexa.oldDeleteNoop = true;
    await expect(gw.deleteAlarm(handle)).rejects.toThrow(/continua ativo/);
  });

  it('todas as rotas falham e o alarme segue ON: o erro traz o motivo, sem dados pessoais', async () => {
    const { alexa, gw } = setup();
    const handle = await gw.createAlarm(SERIAL, AT, 'Aula (reserva)');
    alexa.deleteV2Fails = true;
    alexa.cancelFails = true;
    alexa.oldDeleteNoop = true;
    const err = await gw.deleteAlarm(handle).catch((e: Error) => e);
    expect((err as Error).message).toMatch(/continua ativo/);
    expect((err as Error).message).toContain('cancel falhou');
    expect((err as Error).message).not.toContain(SERIAL);
  });

  it('alarme sumido da lista conta como apagado (já tocou ou foi removido)', async () => {
    const { alexa, gw } = setup();
    const handle = await gw.createAlarm(SERIAL, AT, 'Aula (reserva)');
    alexa.alarms = [];
    alexa.calls.length = 0;
    await expect(gw.deleteAlarm(handle)).resolves.toBeUndefined();
    expect(mutating(alexa)).toEqual([]);
  });

  it('alarme já desativado (status OFF) não precisa de nova chamada', async () => {
    const { alexa, gw } = setup();
    const handle = await gw.createAlarm(SERIAL, AT, 'Aula (reserva)');
    alexa.alarms[0]!.status = 'OFF';
    alexa.calls.length = 0;
    await gw.deleteAlarm(handle);
    expect(mutating(alexa)).toEqual([]);
  });

  it('handle antigo com id (sem notificationIndex): usa deleteNotification', async () => {
    const { alexa, gw } = setup();
    const old = alexa.seed({ notificationIndex: undefined });
    delete (old as Any).notificationIndex;
    const handle = JSON.stringify({ id: old.id, deviceSerialNumber: SERIAL, alarmTime: AT.getTime(), type: 'Alarm' });
    await gw.deleteAlarm(handle);
    expect(alexa.alarms).toEqual([]);
    expect(mutating(alexa)).toEqual([`DELETE /api/notifications/${old.id}`]);
  });

  it('handle que não é JSON: erro claro, nada é apagado', async () => {
    const { alexa, gw } = setup();
    alexa.seed();
    await expect(gw.deleteAlarm('alarme-1')).rejects.toThrow(/handle/);
    expect(alexa.alarms).toHaveLength(1);
  });

  it('lista indisponível ao apagar: o erro sobe (não finge que apagou)', async () => {
    const { alexa, gw } = setup();
    const handle = await gw.createAlarm(SERIAL, AT, 'Aula (reserva)');
    alexa.listFails = true;
    await expect(gw.deleteAlarm(handle)).rejects.toThrow(/lista/);
  });
});

describe('despertar com o gateway real sobre a Alexa falsa', () => {
  const plan: WakePlan = {
    id: 'p1', label: 'Aula', days: [1], time: '07:00', echoDeviceId: SERIAL, spotifyQuery: null,
    musicFirst: false, briefingDelayMin: 0, briefingDelaySec: null, musicStopAfterSec: null, afterMusic: 'briefing',
    volume: 30, fallbackAlarm: true, enabled: true, includeWeather: false, deviceActions: [], phoneAlarm: 'fallback',
  };
  const store = (log: string[]): WakeStore => ({
    armRun: async (_p, _d, _f, handle) => { log.push(`arm ${handle}`); },
    setRunStatus: async (id, s) => { log.push(`status ${id} ${s}`); },
    claimRun: async () => true,
    finishRun: async (_p, _d, status) => { log.push(`finish ${status}`); },
  });

  /** Gateway real (sem Alexa de verdade): alarmes na FakeAlexa, falas no-op. */
  const build = () => {
    const { alexa, gw, logs } = setup();
    const real = gw as Any;
    real.speak = async () => {};
    real.setVolume = async () => {};
    return { alexa, gw: real as AlexaRemoteGateway, logs };
  };

  it('fireWake: depois do áudio confirmado o reserva sai de verdade e não sobra alarme ON', async () => {
    const { alexa, gw, logs } = build();
    const handle = await gw.createAlarm(SERIAL, AT, 'Aula (reserva)');
    expect(alexa.active()).toHaveLength(1);
    const run: WakeRun = { id: 'r1', planId: 'p1', runDate: '2026-09-28', plannedFor: new Date('2026-09-28T10:00:00Z'), status: 'armed', fallbackHandle: handle };
    const out: string[] = [];
    const pending = await applyWakeActions(
      [{ type: 'fire', plan, runDate: '2026-09-28', plannedFor: run.plannedFor, run }],
      { gateway: gw, store: store(out), briefing: async () => ({ briefing: 'Bom dia!', headlines: 'H.' }), sleep: async () => {}, log: (m) => logs.push(m) },
      new Set(),
    );
    await Promise.all(pending);
    expect(out).toEqual(['finish done']);
    expect(alexa.active()).toEqual([]);
    expect(logs.some((m) => m.includes('não apagou o alarme reserva'))).toBe(false);
  });

  it('fireWake com alarme que não dá para apagar: registra "não apagou o alarme reserva" e termina done', async () => {
    const { alexa, gw, logs } = build();
    const handle = await gw.createAlarm(SERIAL, AT, 'Aula (reserva)');
    alexa.deleteV2Noop = true; alexa.cancelNoop = true; alexa.oldDeleteNoop = true;
    const run: WakeRun = { id: 'r1', planId: 'p1', runDate: '2026-09-28', plannedFor: new Date('2026-09-28T10:00:00Z'), status: 'armed', fallbackHandle: handle };
    const out: string[] = [];
    const pending = await applyWakeActions(
      [{ type: 'fire', plan, runDate: '2026-09-28', plannedFor: run.plannedFor, run }],
      { gateway: gw, store: store(out), briefing: async () => ({ briefing: 'Bom dia!', headlines: 'H.' }), sleep: async () => {}, log: (m) => logs.push(m) },
      new Set(),
    );
    await Promise.all(pending);
    expect(out).toEqual(['finish done']);
    expect(logs.some((m) => m.includes('não apagou o alarme reserva'))).toBe(true);
  });

  it('rearm: apaga o reserva antigo de verdade e arma um novo', async () => {
    const { alexa, gw, logs } = build();
    const old = await gw.createAlarm(SERIAL, AT, 'Aula (reserva)');
    const run: WakeRun = { id: 'r1', planId: 'p1', runDate: '2026-09-28', plannedFor: new Date('2026-09-28T10:00:00Z'), status: 'armed', fallbackHandle: old };
    const later = new Date(AT.getTime() + 3_600_000);
    const out: string[] = [];
    await applyWakeActions(
      [{ type: 'rearm', plan, run, plannedFor: new Date('2026-09-28T11:00:00Z'), fallbackAt: later }],
      { gateway: gw, store: store(out), briefing: async () => ({ briefing: 'x', headlines: 'y' }), sleep: async () => {}, log: (m) => logs.push(m) },
      new Set(),
    );
    expect(alexa.active()).toHaveLength(1);
    expect(alexa.active()[0]!.alarmTime).toBe(later.getTime());
    expect(out).toHaveLength(1);
  });

  it('cancel: apaga o reserva de verdade', async () => {
    const { alexa, gw, logs } = build();
    const handle = await gw.createAlarm(SERIAL, AT, 'Aula (reserva)');
    const run: WakeRun = { id: 'r1', planId: 'p1', runDate: '2026-09-28', plannedFor: new Date('2026-09-28T10:00:00Z'), status: 'armed', fallbackHandle: handle };
    const out: string[] = [];
    await applyWakeActions([{ type: 'cancel', run }],
      { gateway: gw, store: store(out), briefing: async () => ({ briefing: 'x', headlines: 'y' }), sleep: async () => {}, log: (m) => logs.push(m) },
      new Set());
    expect(alexa.active()).toEqual([]);
    expect(out).toEqual(['status r1 cancelled']);
  });
});
