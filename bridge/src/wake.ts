import { chunkSpeech } from './briefing.js';
import { AlexaAuthError, type AlexaGateway } from './gateway.js';
import { evaluatePresence, type GeoPoint, type PresenceInput } from './presence.js';
import type { RunStatus, WakeAction, WakeDeviceAction, WakePlan } from './scheduler.js';

export interface WakeResult { ok: boolean; notes: string[] }

export interface WakeTexts { briefing: string; headlines: string }

/** Teto da espera da música no "Testar agora", para o teste não ser eterno. */
export const TEST_MAX_STOP_SEC = 60;

/** Teto da espera entre a música e o resumo no "Testar agora" (o teste espelha a experiência real, sem esperar minutos). */
export const TEST_MAX_BRIEFING_WAIT_SEC = 10;

/** Espera, em segundos, entre o início da música e o resumo (quando a música não é parada). */
export const briefingWaitSec = (plan: WakePlan): number => plan.briefingDelaySec ?? plan.briefingDelayMin * 60;

/** Plano usado por "Testar agora": espera do resumo limitada a 10 s e parada da música limitada. */
export function testPlan(plan: WakePlan): WakePlan {
  return {
    ...plan,
    briefingDelayMin: 0,
    briefingDelaySec: Math.min(briefingWaitSec(plan), TEST_MAX_BRIEFING_WAIT_SEC),
    musicStopAfterSec: plan.musicStopAfterSec === null ? null : Math.min(plan.musicStopAfterSec, TEST_MAX_STOP_SEC),
  };
}

export async function runWake(
  plan: WakePlan,
  texts: WakeTexts,
  gateway: AlexaGateway,
  sleep: (ms: number) => Promise<void>,
): Promise<WakeResult> {
  const notes: string[] = [];
  let audio = false;
  let authError: AlexaAuthError | null = null;
  const attempt = async (label: string, fn: () => Promise<void>): Promise<boolean> => {
    try {
      await fn();
      return true;
    } catch (e) {
      if (e instanceof AlexaAuthError) throw e;
      notes.push(`${label}: ${(e as Error).message}`);
      return false;
    }
  };
  const music = async () => {
    const query = plan.spotifyQuery?.trim();
    if (!query) return false;
    const played = await attempt('spotify', () => gateway.playSpotify(plan.echoDeviceId, query));
    audio ||= played;
    return played;
  };
  const speak = async (text: string) => {
    for (const chunk of chunkSpeech(text)) {
      if (!(await attempt('fala', () => gateway.speak(plan.echoDeviceId, chunk)))) return;
      audio = true;
    }
  };
  /** Espera e para a música; falha vira nota e não impede o próximo passo. */
  const stopAfterWait = async (sec: number) => {
    await sleep(sec * 1000);
    await attempt('parar música', () => gateway.stopMusic(plan.echoDeviceId));
  };

  /** Uma ação de dispositivo: espera o atraso e executa; falha vira nota e não afeta as outras. */
  const deviceTask = async (d: WakeDeviceAction) => {
    try {
      if (d.delayMin > 0) await sleep(d.delayMin * 60_000);
      await attempt(`dispositivo ${d.name}`, () => gateway.deviceAction(d.entityId, d.action, d.brightness));
    } catch (e) {
      if (e instanceof AlexaAuthError) authError ??= e;
      else notes.push(`dispositivo ${d.name}: ${(e as Error).message}`);
    }
  };
  // Em paralelo com a música e a fala (não as atrasam); nunca rejeitam, para não deixar rejeição solta.
  const devices = plan.deviceActions.map((d) => deviceTask(d));

  await attempt('volume', () => gateway.setVolume(plan.echoDeviceId, plan.volume));
  if (plan.musicFirst) {
    if (await music()) {
      if (plan.musicStopAfterSec !== null) await stopAfterWait(plan.musicStopAfterSec);
      else if (briefingWaitSec(plan) > 0) await sleep(briefingWaitSec(plan) * 1000);
    }
    // Mesmo que a música tenha falhado, o próximo passo roda: o usuário precisa acordar.
    if (plan.afterMusic === 'briefing') await speak(texts.briefing);
    else if (plan.afterMusic === 'headlines') await speak(texts.headlines);
  } else {
    await speak(texts.briefing);
    if ((await music()) && plan.musicStopAfterSec !== null) await stopAfterWait(plan.musicStopAfterSec);
  }
  await Promise.all(devices); // espera as ações pendentes (atrasadas) terminarem
  if (authError) throw authError;
  return { ok: audio, notes };
}

/** Local do clima: última localização do celular (até 3 h), senão a casa, senão nenhum. */
export const WEATHER_MAX_FIX_AGE_MIN = 180;

export type PresenceSource = Omit<PresenceInput, 'now' | 'maxAgeMin'>;

export function weatherLocation(src: PresenceSource | null, now: Date): GeoPoint | null {
  if (!src) return null;
  const loc = src.location;
  if (loc && now.getTime() - loc.reportedAt.getTime() <= WEATHER_MAX_FIX_AGE_MIN * 60_000) {
    return { lat: loc.lat, lon: loc.lon };
  }
  return src.home ? { lat: src.home.lat, lon: src.home.lon } : null;
}

export interface WakeStore {
  armRun(planId: string, runDate: string, plannedFor: Date, fallbackHandle: string): Promise<void>;
  setRunStatus(runId: string, status: RunStatus, note?: string | null): Promise<void>;
  claimRun(planId: string, runDate: string, plannedFor: Date): Promise<boolean>;
  finishRun(planId: string, runDate: string, status: 'done' | 'failed' | 'skipped', note: string): Promise<void>;
}

export interface WakeDeps {
  gateway: AlexaGateway;
  store: WakeStore;
  /** Monta os textos; `weather` (já falável) entra logo depois da data, quando houver. */
  briefing: (weather: string | null) => Promise<WakeTexts>;
  sleep: (ms: number) => Promise<void>;
  log: (msg: string) => void;
  /** Casa e última localização do celular. Sem isso, a presença não é verificada. */
  presence?: () => Promise<PresenceSource>;
  /** Texto falado do clima para o ponto; null quando indisponível. */
  weather?: (at: GeoPoint) => Promise<string | null>;
  now?: () => Date;
}

/** Texto do clima para o despertar; qualquer falha apenas o omite (nunca registra coordenadas). */
export async function weatherSpeech(
  plan: WakePlan,
  src: PresenceSource | null,
  deps: Pick<WakeDeps, 'weather' | 'now' | 'log'>,
): Promise<string | null> {
  if (!plan.includeWeather || !deps.weather) return null;
  try {
    const at = weatherLocation(src, (deps.now ?? (() => new Date()))());
    return at ? await deps.weather(at) : null;
  } catch {
    deps.log('clima indisponível; seguindo sem ele');
    return null;
  }
}

type FireAction = Extract<WakeAction, { type: 'fire' }>;

async function fireWake(a: FireAction, deps: WakeDeps): Promise<void> {
  try {
    const handle = a.run?.fallbackHandle;
    // Presença primeiro, antes de qualquer efeito. Sem dados ou com erro: toca (só pula com certeza).
    let source: PresenceSource | null = null;
    if (deps.presence) {
      try {
        source = await deps.presence();
      } catch (e) {
        deps.log(`presença indisponível; tocando mesmo assim: ${(e as Error).message}`);
      }
    }
    if (source) {
      const presence = evaluatePresence({ ...source, now: (deps.now ?? (() => new Date()))() });
      if (presence.state === 'away') {
        if (handle) await deps.gateway.deleteAlarm(handle).catch((e: Error) => deps.log(`não apagou o alarme reserva: ${e.message}`));
        await deps.store.finishRun(a.plan.id, a.runDate, 'skipped', `fora de casa (a ${Math.round(presence.distanceM ?? 0)} m)`);
        return;
      }
    }
    const weather = await weatherSpeech(a.plan, source, deps);
    const result = await runWake(a.plan, await deps.briefing(weather), deps.gateway, deps.sleep);
    if (result.ok && handle) {
      await deps.gateway.deleteAlarm(handle).catch((e: Error) => deps.log(`não apagou o alarme reserva: ${e.message}`));
    }
    await deps.store.finishRun(a.plan.id, a.runDate, result.ok ? 'done' : 'failed', result.notes.join('; '));
  } catch (e) {
    deps.log(`despertar ${a.plan.label} falhou: ${(e as Error).message}`);
    await deps.store.finishRun(a.plan.id, a.runDate, 'failed', (e as Error).message).catch(() => {});
    if (e instanceof AlexaAuthError) throw e;
  }
}

export async function applyWakeActions(
  actions: WakeAction[],
  deps: WakeDeps,
  inFlight: Set<string>,
): Promise<Promise<void>[]> {
  const running: Promise<void>[] = [];
  for (const a of actions) {
    try {
      switch (a.type) {
        case 'arm': {
          const handle = await deps.gateway.createAlarm(a.plan.echoDeviceId, a.fallbackAt, `${a.plan.label} (reserva)`);
          await deps.store.armRun(a.plan.id, a.runDate, a.plannedFor, handle);
          break;
        }
        case 'rearm': {
          if (a.run.fallbackHandle) await deps.gateway.deleteAlarm(a.run.fallbackHandle).catch(() => {});
          const handle = await deps.gateway.createAlarm(a.plan.echoDeviceId, a.fallbackAt, `${a.plan.label} (reserva)`);
          await deps.store.armRun(a.plan.id, a.run.runDate, a.plannedFor, handle);
          break;
        }
        case 'cancel':
          if (a.run.fallbackHandle) {
            await deps.gateway.deleteAlarm(a.run.fallbackHandle).catch((e: Error) => deps.log(`não apagou alarme: ${e.message}`));
          }
          await deps.store.setRunStatus(a.run.id, 'cancelled');
          break;
        case 'miss':
          await deps.store.setRunStatus(a.run.id, 'missed', 'a ponte não disparou no horário; o alarme reserva tocou');
          break;
        case 'fire': {
          const key = `${a.plan.id}:${a.runDate}`;
          if (inFlight.has(key)) break;
          if (!(await deps.store.claimRun(a.plan.id, a.runDate, a.plannedFor))) break;
          inFlight.add(key);
          running.push(fireWake(a, deps).finally(() => inFlight.delete(key)));
          break;
        }
      }
    } catch (e) {
      if (e instanceof AlexaAuthError) throw e;
      deps.log(`falha em ${a.type}: ${(e as Error).message}`);
    }
  }
  return running;
}
