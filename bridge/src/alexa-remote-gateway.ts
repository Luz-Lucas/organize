import { readFile, writeFile } from 'node:fs/promises';
import AlexaRemote from 'alexa-remote2';
import {
  AlexaAuthError, type AlexaGateway, type DeviceAction, type EchoDevice, type Routine, type SmartDevice,
} from './gateway.js';

type Any = any; // eslint-disable-line @typescript-eslint/no-explicit-any

const KNOWN_OPERATIONS = ['turnOn', 'turnOff', 'setBrightness'];
const AUTH_HINT = /401|403|cookie|unauthori[sz]ed|login|csrf/i;

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

export function mapRoutines(raw: unknown): Routine[] {
  if (!Array.isArray(raw)) return [];
  return raw.flatMap((r: Any) => {
    if (typeof r?.automationId !== 'string') return [];
    const utterance = r.triggers?.[0]?.payload?.utterance;
    return [{ id: r.automationId, name: String(r.name ?? utterance ?? 'Rotina sem nome') }];
  });
}

export interface AlexaRemoteOptions {
  cookieFile: string;
  amazonPage: string;
  alexaServiceHost: string;
  language: string;
}

export class AlexaRemoteGateway implements AlexaGateway {
  private readonly alexa: Any = new AlexaRemote();

  static async connect(opts: AlexaRemoteOptions): Promise<AlexaRemoteGateway> {
    let saved: Any;
    try {
      saved = JSON.parse(await readFile(opts.cookieFile, 'utf8'));
    } catch {
      throw new AlexaAuthError(`sem login salvo em ${opts.cookieFile}; rode o login da ponte`);
    }
    const gw = new AlexaRemoteGateway();
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

  async createAlarm(echoDeviceId: string, at: Date, label: string): Promise<string> {
    const notification = this.alexa.createNotificationObject(echoDeviceId, 'Alarm', label, at, 'ON');
    const created = await this.call<Any>('createNotification', notification);
    return JSON.stringify(created && typeof created === 'object' && created.id ? created : notification);
  }

  async deleteAlarm(handle: string): Promise<void> {
    await this.call('deleteNotification', JSON.parse(handle));
  }
}
