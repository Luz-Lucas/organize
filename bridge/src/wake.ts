import { chunkSpeech } from './briefing.js';
import { AlexaAuthError, type AlexaGateway } from './gateway.js';
import type { RunStatus, WakeAction, WakePlan } from './scheduler.js';

export interface WakeResult { ok: boolean; notes: string[] }

export interface WakeTexts { briefing: string; headlines: string }

/** Teto da espera da música no "Testar agora", para o teste não ser eterno. */
export const TEST_MAX_STOP_SEC = 60;

/** Plano usado por "Testar agora": sem atraso do resumo e com a parada da música limitada. */
export function testPlan(plan: WakePlan): WakePlan {
  return {
    ...plan,
    briefingDelayMin: 0,
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

  await attempt('volume', () => gateway.setVolume(plan.echoDeviceId, plan.volume));
  if (plan.musicFirst) {
    if (await music()) {
      if (plan.musicStopAfterSec !== null) await stopAfterWait(plan.musicStopAfterSec);
      else await sleep(plan.briefingDelayMin * 60_000);
    }
    // Mesmo que a música tenha falhado, o próximo passo roda: o usuário precisa acordar.
    if (plan.afterMusic === 'briefing') await speak(texts.briefing);
    else if (plan.afterMusic === 'headlines') await speak(texts.headlines);
  } else {
    await speak(texts.briefing);
    if ((await music()) && plan.musicStopAfterSec !== null) await stopAfterWait(plan.musicStopAfterSec);
  }
  return { ok: audio, notes };
}

export interface WakeStore {
  armRun(planId: string, runDate: string, plannedFor: Date, fallbackHandle: string): Promise<void>;
  setRunStatus(runId: string, status: RunStatus, note?: string | null): Promise<void>;
  claimRun(planId: string, runDate: string, plannedFor: Date): Promise<boolean>;
  finishRun(planId: string, runDate: string, status: 'done' | 'failed', note: string): Promise<void>;
}

export interface WakeDeps {
  gateway: AlexaGateway;
  store: WakeStore;
  briefing: () => Promise<WakeTexts>;
  sleep: (ms: number) => Promise<void>;
  log: (msg: string) => void;
}

type FireAction = Extract<WakeAction, { type: 'fire' }>;

async function fireWake(a: FireAction, deps: WakeDeps): Promise<void> {
  try {
    const result = await runWake(a.plan, await deps.briefing(), deps.gateway, deps.sleep);
    const handle = a.run?.fallbackHandle;
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
