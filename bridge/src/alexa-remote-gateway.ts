import { readFile, writeFile } from 'node:fs/promises';
import AlexaRemote from 'alexa-remote2';
import {
  AlexaAuthError, type AlexaGateway, type DeviceAction, type EchoDevice, type Routine, type SmartDevice,
} from './gateway.js';

type Any = any; // eslint-disable-line @typescript-eslint/no-explicit-any

const KNOWN_OPERATIONS = ['turnOn', 'turnOff', 'setBrightness'];
const AUTH_HINT = /\b(?:401|403)\b|unauthori[sz]ed|forbidden|invalid cookie|cookie (?:expired|invalid)|no cookie|login (?:required|failed)|csrf|not logged in/i;

const asError = (err: unknown): Error => {
  const message = String((err as Error)?.message ?? err);
  return AUTH_HINT.test(message) ? new AlexaAuthError(message) : new Error(message);
};

export function mapSmartEntities(raw: unknown): SmartDevice[] {
  if (!Array.isArray(raw)) return [];
  return raw.flatMap((e: Any) => {
    const ops = Array.isArray(e?.supportedOperations)
      ? KNOWN_OPERATIONS.filter((op) => e.supportedOperations.includes(op))
      : [];
    if (typeof e?.id !== 'string' || ops.length === 0) return [];
    return [{ id: e.id, name: String(e.displayName ?? e.id), operations: ops }];
  });
}

/** Procura, em qualquer nível do JSON de getSmarthomeDevices, o applianceId do objeto com o entityId dado. */
export function findApplianceId(raw: unknown, entityId: string): string | null {
  const seen = new Set<object>();
  const walk = (node: unknown): string | null => {
    if (!node || typeof node !== 'object' || seen.has(node)) return null;
    seen.add(node);
    const o = node as Any;
    if (o.entityId === entityId && typeof o.applianceId === 'string') return o.applianceId;
    for (const v of Object.values(o)) {
      const found = walk(v);
      if (found) return found;
    }
    return null;
  };
  return walk(raw);
}

export function mapRoutines(raw: unknown): Routine[] {
  if (!Array.isArray(raw)) return [];
  return raw.flatMap((r: Any) => {
    if (typeof r?.automationId !== 'string') return [];
    const utterance = r.triggers?.[0]?.payload?.utterance;
    return [{ id: r.automationId, name: String(r.name ?? utterance ?? 'Rotina sem nome') }];
  });
}

/** Alarme reserva: handle normalizado, gravado em wake_runs.fallback_handle. */
export interface AlarmHandle {
  v: 2;
  /** Identificador da API nova (/v1/alerts/alarms/{notificationIndex}). */
  notificationIndex?: string;
  /** Identificador da API antiga (/api/notifications/{id}). */
  id?: string;
  deviceSerialNumber: string;
  /** Horário do alarme em ms desde a época. */
  alarmTime: number;
  label: string | null;
}

/** Tolerância ao casar o horário de um alarme da lista com o do handle. */
export const ALARM_MATCH_WINDOW_MS = 90_000;

const nonEmpty = (v: unknown): string | undefined => (typeof v === 'string' && v.trim() !== '' ? v : undefined);

const SCHEDULED = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2}))?/;
const localMs = (y: string, mo: string, d: string, h: string, mi: string, sec?: string): number =>
  new Date(Number(y), Number(mo) - 1, Number(d), Number(h), Number(mi), Number(sec ?? 0)).getTime();

/** Horário (ms) de um alarme: `alarmTime` da lista; senão `trigger.scheduledTime` (formato novo) ou originalDate + originalTime (hora local da ponte). */
export function alarmTimeMs(n: Any): number | undefined {
  if (typeof n?.alarmTime === 'number' && Number.isFinite(n.alarmTime) && n.alarmTime > 0) return n.alarmTime;
  const sched = SCHEDULED.exec(String(n?.trigger?.scheduledTime ?? ''));
  if (sched) return localMs(sched[1]!, sched[2]!, sched[3]!, sched[4]!, sched[5]!, sched[6]);
  const date = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(n?.originalDate ?? ''));
  const time = /^(\d{2}):(\d{2})(?::(\d{2}))?/.exec(String(n?.originalTime ?? ''));
  if (date && time) return localMs(date[1]!, date[2]!, date[3]!, time[1]!, time[2]!, time[3]);
  return undefined;
}

/**
 * Lê um handle em qualquer dos três formatos: o novo ({v:2,...}), o antigo com `id` e o legado sem id
 * (o próprio pedido do POST: trigger/extensions/endpointId). Erro se não der para identificar o alarme.
 */
export function parseAlarmHandle(handle: string): AlarmHandle {
  let o: Any;
  try {
    o = JSON.parse(handle);
  } catch {
    o = null;
  }
  if (!o || typeof o !== 'object') throw new Error('handle do alarme reserva ilegível');
  const deviceSerialNumber = nonEmpty(o.deviceSerialNumber) ?? nonEmpty(String(o.endpointId ?? '').split('@')[0]);
  const alarmTime = alarmTimeMs(o);
  const notificationIndex = nonEmpty(o.notificationIndex);
  const id = nonEmpty(o.id);
  if (!(deviceSerialNumber && alarmTime !== undefined) && !notificationIndex && !id) {
    throw new Error('handle do alarme reserva sem dispositivo, horário ou identificador');
  }
  return {
    v: 2,
    ...(notificationIndex ? { notificationIndex } : {}),
    ...(id ? { id } : {}),
    deviceSerialNumber: deviceSerialNumber ?? '',
    alarmTime: alarmTime ?? 0,
    label: nonEmpty(o.label) ?? nonEmpty(o.reminderLabel) ?? null,
  };
}

const ID_CONTAINERS = ['alarm', 'alert', 'notification', 'data', 'payload', 'result', 'response', 'alarms', 'notifications'];

/** Identificador na resposta do POST (topo ou dentro de alarm/alert/notification/data/...; nunca em sound/assets/trigger). */
export function extractAlarmIds(created: unknown): { notificationIndex?: string; id?: string } {
  const find = (keys: string[]): string | undefined => {
    const queue: { node: unknown; depth: number }[] = [{ node: created, depth: 0 }];
    while (queue.length > 0) {
      const { node, depth } = queue.shift()!;
      if (Array.isArray(node)) {
        if (depth < 3) for (const item of node) queue.push({ node: item, depth: depth + 1 });
        continue;
      }
      if (!node || typeof node !== 'object') continue;
      const o = node as Any;
      for (const k of keys) {
        const v = nonEmpty(o[k]);
        if (v) return v;
      }
      if (depth < 3) for (const k of ID_CONTAINERS) if (o[k] && typeof o[k] === 'object') queue.push({ node: o[k], depth: depth + 1 });
    }
    return undefined;
  };
  const notificationIndex = find(['notificationIndex', 'alarmId']);
  const id = find(['id']);
  return { ...(notificationIndex ? { notificationIndex } : {}), ...(id ? { id } : {}) };
}

/** Só as chaves (até 2 níveis) de um objeto, para diagnóstico; nunca valores. */
export function keyShape(v: unknown): string[] {
  const out: string[] = [];
  const walk = (node: unknown, prefix: string, depth: number) => {
    if (!node || typeof node !== 'object') return;
    const target = Array.isArray(node) ? (node[0] as unknown) : node;
    if (!target || typeof target !== 'object' || Array.isArray(target)) return;
    for (const k of Object.keys(target)) {
      if (out.length >= 40) return;
      out.push(`${prefix}${k}`);
      if (depth < 1) walk((target as Any)[k], `${prefix}${k}.`, depth + 1);
    }
  };
  walk(v, '', 0);
  return out;
}

const matchesIdentifier = (n: Any, h: AlarmHandle): boolean => {
  const idx = h.notificationIndex;
  if (idx && (n.notificationIndex === idx || n.id === idx || (typeof n.id === 'string' && n.id.endsWith(`-${idx}`)))) return true;
  return Boolean(h.id && (n.id === h.id || n.notificationIndex === h.id));
};

/** Alarmes da lista que batem com dispositivo, tipo Alarm, horário (±90 s) e rótulo; os de rótulo igual vêm primeiro, depois os mais próximos. */
export function findByTime(list: Any[], h: AlarmHandle): Any[] {
  if (!h.deviceSerialNumber || !h.alarmTime) return [];
  const scored = list.flatMap((n) => {
    if (n?.deviceSerialNumber !== h.deviceSerialNumber || n?.type !== 'Alarm') return [];
    const t = alarmTimeMs(n);
    if (t === undefined || Math.abs(t - h.alarmTime) > ALARM_MATCH_WINDOW_MS) return [];
    const label = nonEmpty(n.reminderLabel);
    // Um alarme do usuário com outro rótulo no mesmo horário nunca é o reserva.
    if (label && (h.label ? label !== h.label : !/\(reserva\)\s*$/.test(label))) return [];
    return [{ n, exact: h.label !== null && label === h.label, diff: Math.abs(t - h.alarmTime) }];
  });
  scored.sort((a, b) => Number(b.exact) - Number(a.exact) || a.diff - b.diff);
  return scored.map((x) => x.n);
}

/** Alarmes da lista a que o handle se refere: por identificador; sem ele (ou se ele não aparece), por dispositivo + horário + rótulo. */
export function findTargets(list: Any[], h: AlarmHandle): Any[] {
  const byId = list.filter((n) => matchesIdentifier(n, h));
  if (byId.length > 0) return byId;
  const byTime = findByTime(list, h);
  const exact = byTime.filter((n) => h.label !== null && nonEmpty(n.reminderLabel) === h.label);
  return exact.length > 0 ? exact : byTime;
}

const isActive = (n: Any): boolean => n.status !== 'OFF' && n.status !== 'INSTANCE_CANCELED';

export interface AlexaRemoteOptions {
  cookieFile: string;
  amazonPage: string;
  alexaServiceHost: string;
  language: string;
  /** Diagnóstico da ponte (nunca recebe tokens, ids ou nomes; só formas e contagens). */
  log?: (msg: string) => void;
}

export class AlexaRemoteGateway implements AlexaGateway {
  private readonly alexa: Any;
  private readonly log: (msg: string) => void;
  private loggedCreateShape = false;

  /** `alexa` e `log` existem para os testes e para a ponte injetar o log; o padrão é a alexa-remote2 real. */
  constructor(alexa?: Any, log?: (msg: string) => void) {
    this.alexa = alexa ?? new AlexaRemote();
    this.log = log ?? (() => {});
  }

  static async connect(opts: AlexaRemoteOptions): Promise<AlexaRemoteGateway> {
    let saved: Any;
    try {
      saved = JSON.parse(await readFile(opts.cookieFile, 'utf8'));
    } catch {
      throw new AlexaAuthError(`sem login salvo em ${opts.cookieFile}; rode o login da ponte`);
    }
    const gw = new AlexaRemoteGateway(undefined, opts.log);
    gw.alexa.on('cookie', () => {
      void writeFile(opts.cookieFile, JSON.stringify(gw.alexa.cookieData)).catch(() => {});
    });
    await new Promise<void>((resolve, reject) => {
      gw.alexa.init({
        cookie: saved,
        formerRegistrationData: saved,
        amazonPage: opts.amazonPage,
        alexaServiceHost: opts.alexaServiceHost,
        acceptLanguage: opts.language,
        useWsMqtt: false,
        cookieRefreshInterval: 4 * 24 * 60 * 60 * 1000,
        logger: () => {},
      }, (err: unknown) => (err ? reject(asError(err)) : resolve()));
    });
    return gw;
  }

  private call<T>(method: string, ...args: unknown[]): Promise<T> {
    return new Promise((resolve, reject) => {
      this.alexa[method](...args, (err: unknown, res: T) => (err ? reject(asError(err)) : resolve(res)));
    });
  }

  async listEchos(): Promise<EchoDevice[]> {
    const res = await this.call<Any>('getDevices');
    return (res?.devices ?? [])
      .filter((d: Any) => Array.isArray(d.capabilities) && d.capabilities.includes('VOLUME_SETTING'))
      .map((d: Any) => ({ id: String(d.serialNumber), name: String(d.accountName), online: Boolean(d.online) }));
  }

  async listSmartDevices(): Promise<SmartDevice[]> {
    return mapSmartEntities(await this.call<unknown>('getSmarthomeEntities'));
  }

  async deleteSmartDevice(entityId: string): Promise<void> {
    const raw = await this.call<unknown>('getSmarthomeDevices');
    const applianceId = findApplianceId(raw, entityId);
    if (applianceId === null) throw new Error('dispositivo não encontrado na Alexa');
    await this.call('deleteSmarthomeDevice', applianceId);
  }

  async listRoutines(): Promise<Routine[]> {
    return mapRoutines(await this.call<unknown>('getAutomationRoutines'));
  }

  async runRoutine(routineId: string, echoDeviceId: string): Promise<void> {
    const all = await this.call<Any[]>('getAutomationRoutines');
    const routine = (all ?? []).find((r: Any) => r.automationId === routineId);
    if (!routine) throw new Error('rotina não encontrada; sincronize de novo');
    await this.call('executeAutomationRoutine', echoDeviceId, routine);
  }

  async deviceAction(entityId: string, action: DeviceAction, brightness?: number): Promise<void> {
    const parameters: Record<string, unknown> = { action };
    if (action === 'setBrightness') parameters.brightness = brightness;
    await this.call('executeSmarthomeDeviceAction', [entityId], parameters, 'APPLIANCE');
  }

  async speak(echoDeviceId: string, text: string): Promise<void> {
    await this.call('sendSequenceCommand', echoDeviceId, 'speak', text);
  }

  async setVolume(echoDeviceId: string, volume: number): Promise<void> {
    await this.call('sendSequenceCommand', echoDeviceId, 'volume', volume);
  }

  async playSpotify(echoDeviceId: string, query: string): Promise<void> {
    // Falha (busca sem resultado, Spotify não vinculado, pedido inválido) precisa virar erro:
    // assim o runWake registra a falha, mas ainda fala o resumo.
    let res: Any;
    try {
      res = await this.call<Any>('playMusicProvider', echoDeviceId, 'SPOTIFY', query);
    } catch (e) {
      throw new Error(`Spotify não tocou "${query}": ${(e as Error).message}`);
    }
    const failed = res && typeof res === 'object'
      && ((typeof res.result === 'string' && res.result !== 'VALID') || (Array.isArray(res.errors) && res.errors.length > 0));
    if (failed) throw new Error(`Spotify não encontrou ou não tocou "${query}"`);
  }

  async stopMusic(echoDeviceId: string): Promise<void> {
    // sendCommand(serialOrName, command, value, callback): 'pause' ignora o valor.
    await this.call('sendCommand', echoDeviceId, 'pause', null);
  }

  private async listAlarms(): Promise<Any[]> {
    const res = await this.call<Any>('getNotifications', false); // false = sem cache
    // Formato inesperado não pode virar "lista vazia": isso faria o alarme parecer apagado.
    if (!Array.isArray(res?.notifications)) throw new Error('lista de alarmes da Alexa em formato inesperado');
    return res.notifications;
  }

  /** DELETE na API nova; a lib não tem método próprio, então vai direto por httpsGetAuthApi. */
  private deleteAlarmV2(notificationIndex: string): Promise<void> {
    return new Promise((resolve, reject) => {
      this.alexa.httpsGetAuthApi(
        `/v1/alerts/alarms/${encodeURIComponent(notificationIndex)}`,
        (err: unknown) => (err ? reject(asError(err)) : resolve()),
        { method: 'DELETE' },
      );
    });
  }

  async createAlarm(echoDeviceId: string, at: Date, label: string): Promise<string> {
    const notification = this.alexa.createNotificationObject(echoDeviceId, 'Alarm', label, at, 'ON');
    if (!notification) throw new Error('Echo não encontrado na Alexa; sincronize de novo');
    const created = await this.call<Any>('createNotification', notification);
    if (!this.loggedCreateShape) { // uma vez, só chaves: para saber o que a API devolve
      this.loggedCreateShape = true;
      this.log(`alarme reserva: chaves da resposta do POST = [${keyShape(created).join(', ')}]`);
    }
    const handle: AlarmHandle = { v: 2, deviceSerialNumber: echoDeviceId, alarmTime: at.getTime(), label };
    const ids = extractAlarmIds(created);
    if (!ids.notificationIndex && !ids.id) {
      try {
        const found = findByTime(await this.listAlarms(), handle)[0];
        if (found) {
          ids.notificationIndex = nonEmpty(found.notificationIndex);
          ids.id = nonEmpty(found.id);
        } else {
          this.log('alarme reserva: o alarme recém-criado não apareceu na lista; handle sem identificador');
        }
      } catch (e) {
        this.log(`alarme reserva: não consegui listar para achar o identificador (${(e as Error).message})`);
      }
    }
    if (ids.notificationIndex) handle.notificationIndex = ids.notificationIndex;
    if (ids.id) handle.id = ids.id;
    return JSON.stringify(handle);
  }

  async deleteAlarm(handle: string): Promise<void> {
    const h = parseAlarmHandle(handle);
    const activeTargets = async () => findTargets(await this.listAlarms(), h).filter(isActive);
    let targets = await activeTargets();
    if (targets.length === 0) return; // não está na lista (já tocou ou foi removido) ou já está desativado

    const errors: string[] = [];
    const steps: { name: string; applies: (n: Any) => boolean; run: (n: Any) => Promise<unknown> }[] = [
      { name: 'DELETE v2', applies: (n) => !!nonEmpty(n.notificationIndex), run: (n) => this.deleteAlarmV2(n.notificationIndex) },
      { name: 'cancel v2', applies: (n) => !!nonEmpty(n.notificationIndex), run: (n) => this.call('deactivateNotificationV2', n.notificationIndex) },
      { name: 'delete antigo', applies: (n) => !!nonEmpty(n.id), run: (n) => this.call('deleteNotification', n) },
    ];
    for (const step of steps) {
      const todo = targets.filter(step.applies);
      if (todo.length === 0) continue;
      for (const n of todo) {
        try {
          await step.run(n);
        } catch (e) {
          errors.push(`${step.name}: ${(e as Error).message}`);
        }
      }
      targets = await activeTargets(); // confere de verdade; a resposta da API sozinha não prova nada
      if (targets.length === 0) return;
    }
    throw new Error(`o alarme reserva continua ativo na Alexa depois de tentar apagar (${errors.join('; ') || 'a API não devolveu erro'})`);
  }
}
