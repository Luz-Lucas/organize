import { describe, expect, it } from 'vitest';
import { AlexaAuthError } from '../src/gateway.js';
import type { WakePlan, WakeRun } from '../src/scheduler.js';
import { applyWakeActions, runWake, testPlan, type WakeStore } from '../src/wake.js';
import { FakeGateway } from './fake-gateway.js';

const plan = (over: Partial<WakePlan> = {}): WakePlan => ({
  id: 'p1', label: 'Aula', days: [1], time: '07:00', echoDeviceId: 'ECHO', spotifyQuery: 'lofi',
  musicFirst: true, briefingDelayMin: 3, musicStopAfterSec: null, afterMusic: 'briefing',
  volume: 30, fallbackAlarm: true, enabled: true, ...over,
});

class MemoryWakeStore implements WakeStore {
  log: string[] = [];
  claimed = new Set<string>();
  async armRun(planId: string, runDate: string, plannedFor: Date, handle: string) { this.log.push(`arm ${planId} ${runDate} ${plannedFor.toISOString()} ${handle}`); }
  async setRunStatus(runId: string, status: string) { this.log.push(`status ${runId} ${status}`); }
  async claimRun(planId: string, runDate: string) {
    const key = `${planId}:${runDate}`;
    if (this.claimed.has(key)) return false;
    this.claimed.add(key);
    return true;
  }
  async finishRun(planId: string, runDate: string, status: string, note: string) { this.log.push(`finish ${planId} ${runDate} ${status} ${note}`); }
}

const noSleep = async () => {};
const texts = { briefing: 'Bom dia!', headlines: 'Manchetes: A.' };

/** Espera falsa que registra a pausa na mesma linha do tempo das chamadas ao gateway. */
const timeline = (gw: FakeGateway) => async (ms: number) => { gw.calls.push(`sleep(${ms})`); };

describe('runWake', () => {
  it('música antes: volume → Spotify → espera → fala', async () => {
    const gw = new FakeGateway();
    const waits: number[] = [];
    const r = await runWake(plan(), texts, gw, async (ms) => { waits.push(ms); });
    expect(r).toEqual({ ok: true, notes: [] });
    expect(gw.calls).toEqual(['setVolume(ECHO,30)', 'playSpotify(ECHO,lofi)', 'speak(ECHO,Bom dia!)']);
    expect(waits).toEqual([180_000]);
  });

  it('Spotify falhando: ainda fala o resumo e conta como sucesso', async () => {
    const gw = new FakeGateway();
    gw.failOn.add('playSpotify');
    const r = await runWake(plan(), texts, gw, noSleep);
    expect(r.ok).toBe(true);
    expect(r.notes).toEqual(['spotify: playSpotify falhou']);
    expect(gw.calls).toContain('speak(ECHO,Bom dia!)');
  });

  it('nada tocou: ok=false', async () => {
    const gw = new FakeGateway();
    gw.failOn.add('playSpotify');
    gw.failOn.add('speak');
    expect((await runWake(plan(), texts, gw, noSleep)).ok).toBe(false);
  });

  it('resumo primeiro quando musicFirst=false', async () => {
    const gw = new FakeGateway();
    await runWake(plan({ musicFirst: false }), { briefing: 'Oi.', headlines: 'H.' }, gw, noSleep);
    expect(gw.calls).toEqual(['setVolume(ECHO,30)', 'speak(ECHO,Oi.)', 'playSpotify(ECHO,lofi)']);
  });

  it('erro de login é propagado', async () => {
    const gw = new FakeGateway();
    gw.setVolume = async () => { throw new AlexaAuthError('cookie expirado'); };
    await expect(runWake(plan(), texts, gw, noSleep)).rejects.toBeInstanceOf(AlexaAuthError);
  });
});

describe('runWake: parar a música', () => {
  it('música → espera 30 s → stop → resumo', async () => {
    const gw = new FakeGateway();
    const r = await runWake(plan({ musicStopAfterSec: 30 }), texts, gw, timeline(gw));
    expect(r).toEqual({ ok: true, notes: [] });
    expect(gw.calls).toEqual([
      'setVolume(ECHO,30)', 'playSpotify(ECHO,lofi)', 'sleep(30000)', 'stopMusic(ECHO)', 'speak(ECHO,Bom dia!)',
    ]);
    expect(gw.stopped).toEqual(['ECHO']);
  });

  it('musicStopAfterSec ignora o atraso do resumo (briefingDelayMin)', async () => {
    const gw = new FakeGateway();
    await runWake(plan({ musicStopAfterSec: 45, briefingDelayMin: 10 }), texts, gw, timeline(gw));
    expect(gw.calls.filter((c) => c.startsWith('sleep'))).toEqual(['sleep(45000)']);
  });

  it('afterMusic=end: para a música e não fala nada', async () => {
    const gw = new FakeGateway();
    const r = await runWake(plan({ musicStopAfterSec: 30, afterMusic: 'end' }), texts, gw, timeline(gw));
    expect(r).toEqual({ ok: true, notes: [] });
    expect(gw.calls).toEqual(['setVolume(ECHO,30)', 'playSpotify(ECHO,lofi)', 'sleep(30000)', 'stopMusic(ECHO)']);
  });

  it('afterMusic=headlines: fala só as manchetes', async () => {
    const gw = new FakeGateway();
    await runWake(plan({ musicStopAfterSec: 30, afterMusic: 'headlines' }), texts, gw, timeline(gw));
    expect(gw.calls).toEqual([
      'setVolume(ECHO,30)', 'playSpotify(ECHO,lofi)', 'sleep(30000)', 'stopMusic(ECHO)', 'speak(ECHO,Manchetes: A.)',
    ]);
  });

  it('afterMusic também vale sem musicStopAfterSec (espera briefingDelayMin, sem stop)', async () => {
    const gw = new FakeGateway();
    await runWake(plan({ afterMusic: 'headlines' }), texts, gw, timeline(gw));
    expect(gw.calls).toEqual(['setVolume(ECHO,30)', 'playSpotify(ECHO,lofi)', 'sleep(180000)', 'speak(ECHO,Manchetes: A.)']);
    expect(gw.stopped).toEqual([]);
  });

  it('sem musicStopAfterSec mantém o comportamento antigo: espera o atraso em minutos e não para', async () => {
    const gw = new FakeGateway();
    await runWake(plan(), texts, gw, timeline(gw));
    expect(gw.calls).toEqual(['setVolume(ECHO,30)', 'playSpotify(ECHO,lofi)', 'sleep(180000)', 'speak(ECHO,Bom dia!)']);
    expect(gw.stopped).toEqual([]);
  });

  it('musicFirst=false: fala → música → espera → stop (afterMusic ignorado)', async () => {
    const gw = new FakeGateway();
    await runWake(plan({ musicFirst: false, musicStopAfterSec: 20, afterMusic: 'end' }), texts, gw, timeline(gw));
    expect(gw.calls).toEqual([
      'setVolume(ECHO,30)', 'speak(ECHO,Bom dia!)', 'playSpotify(ECHO,lofi)', 'sleep(20000)', 'stopMusic(ECHO)',
    ]);
  });

  it('musicFirst=false sem musicStopAfterSec: não espera nem para', async () => {
    const gw = new FakeGateway();
    await runWake(plan({ musicFirst: false }), texts, gw, timeline(gw));
    expect(gw.calls).toEqual(['setVolume(ECHO,30)', 'speak(ECHO,Bom dia!)', 'playSpotify(ECHO,lofi)']);
  });

  it('música que falha ao iniciar: não espera nem para, mas ainda executa afterMusic', async () => {
    const gw = new FakeGateway();
    gw.failOn.add('playSpotify');
    const r = await runWake(plan({ musicStopAfterSec: 30, afterMusic: 'headlines' }), texts, gw, timeline(gw));
    expect(r.ok).toBe(true);
    expect(r.notes).toEqual(['spotify: playSpotify falhou']);
    expect(gw.calls).toEqual(['setVolume(ECHO,30)', 'playSpotify(ECHO,lofi)', 'speak(ECHO,Manchetes: A.)']);
  });

  it('música que falha com afterMusic=end: nada falado, ok=false', async () => {
    const gw = new FakeGateway();
    gw.failOn.add('playSpotify');
    const r = await runWake(plan({ musicStopAfterSec: 30, afterMusic: 'end' }), texts, gw, timeline(gw));
    expect(r.ok).toBe(false);
    expect(gw.calls).toEqual(['setVolume(ECHO,30)', 'playSpotify(ECHO,lofi)']);
  });

  it('sem busca do Spotify não espera nem para', async () => {
    const gw = new FakeGateway();
    await runWake(plan({ spotifyQuery: null, musicStopAfterSec: 30 }), texts, gw, timeline(gw));
    expect(gw.calls).toEqual(['setVolume(ECHO,30)', 'speak(ECHO,Bom dia!)']);
  });

  it('stopMusic lançando erro vira nota e o próximo passo roda', async () => {
    const gw = new FakeGateway();
    gw.failOn.add('stopMusic');
    const r = await runWake(plan({ musicStopAfterSec: 30 }), texts, gw, timeline(gw));
    expect(r.ok).toBe(true);
    expect(r.notes).toEqual(['parar música: stopMusic falhou']);
    expect(gw.calls.at(-1)).toBe('speak(ECHO,Bom dia!)');
  });

  it('AlexaAuthError no stopMusic continua propagando', async () => {
    const gw = new FakeGateway();
    gw.stopMusic = async () => { throw new AlexaAuthError('cookie expirado'); };
    await expect(runWake(plan({ musicStopAfterSec: 30 }), texts, gw, noSleep)).rejects.toBeInstanceOf(AlexaAuthError);
  });
});

describe('testPlan (Testar agora)', () => {
  it('zera o atraso do resumo e mantém "não parar"', () => {
    expect(testPlan(plan({ briefingDelayMin: 5 }))).toMatchObject({ briefingDelayMin: 0, musicStopAfterSec: null });
  });

  it('respeita musicStopAfterSec, limitando a 60 s', () => {
    expect(testPlan(plan({ musicStopAfterSec: 30 })).musicStopAfterSec).toBe(30);
    expect(testPlan(plan({ musicStopAfterSec: 60 })).musicStopAfterSec).toBe(60);
    expect(testPlan(plan({ musicStopAfterSec: 300 })).musicStopAfterSec).toBe(60);
  });
});

describe('applyWakeActions', () => {
  const deps = (gw: FakeGateway, store: MemoryWakeStore) =>
    ({ gateway: gw, store, briefing: async () => texts, sleep: noSleep, log: () => {} });

  it('arma: cria alarme reserva e grava o run', async () => {
    const gw = new FakeGateway();
    const store = new MemoryWakeStore();
    await applyWakeActions([{
      type: 'arm', plan: plan(), runDate: '2026-09-28',
      plannedFor: new Date('2026-09-28T10:00:00Z'), fallbackAt: new Date('2026-09-28T10:10:00Z'),
    }], deps(gw, store), new Set());
    expect(gw.calls).toEqual(['createAlarm(ECHO,2026-09-28T10:10:00.000Z,Aula (reserva))']);
    expect(store.log).toEqual(['arm p1 2026-09-28 2026-09-28T10:00:00.000Z alarme-1']);
  });

  it('dispara uma vez e apaga o alarme reserva quando deu certo', async () => {
    const gw = new FakeGateway();
    const store = new MemoryWakeStore();
    const armed: WakeRun = { id: 'r1', planId: 'p1', runDate: '2026-09-28', plannedFor: new Date('2026-09-28T10:00:00Z'), status: 'armed', fallbackHandle: 'reserva-1' };
    const fire = { type: 'fire' as const, plan: plan(), runDate: '2026-09-28', plannedFor: armed.plannedFor, run: armed };
    const inFlight = new Set<string>();
    const first = await applyWakeActions([fire], deps(gw, store), inFlight);
    const second = await applyWakeActions([fire], deps(gw, store), inFlight);
    await Promise.all([...first, ...second]);
    expect(gw.calls.filter((c) => c.startsWith('playSpotify'))).toHaveLength(1);
    expect(gw.calls).toContain('deleteAlarm(reserva-1)');
    expect(store.log).toEqual(['finish p1 2026-09-28 done ']);
  });

  it('se nada tocou, mantém o alarme reserva e marca failed', async () => {
    const gw = new FakeGateway();
    gw.failOn.add('playSpotify');
    gw.failOn.add('speak');
    const store = new MemoryWakeStore();
    const armed: WakeRun = { id: 'r1', planId: 'p1', runDate: '2026-09-28', plannedFor: new Date(), status: 'armed', fallbackHandle: 'reserva-1' };
    const pending = await applyWakeActions([{ type: 'fire', plan: plan(), runDate: '2026-09-28', plannedFor: armed.plannedFor, run: armed }], deps(gw, store), new Set());
    await Promise.all(pending);
    expect(gw.calls).not.toContain('deleteAlarm(reserva-1)');
    expect(store.log[0]).toMatch(/^finish p1 2026-09-28 failed spotify: playSpotify falhou; fala: speak falhou/);
  });

  it('cancelar apaga o alarme e marca cancelled; miss só marca', async () => {
    const gw = new FakeGateway();
    const store = new MemoryWakeStore();
    const armed: WakeRun = { id: 'r1', planId: null, runDate: '2026-09-28', plannedFor: new Date(), status: 'armed', fallbackHandle: 'reserva-1' };
    await applyWakeActions([{ type: 'cancel', run: armed }, { type: 'miss', run: { ...armed, id: 'r2' } }], deps(gw, store), new Set());
    expect(gw.calls).toEqual(['deleteAlarm(reserva-1)']);
    expect(store.log).toEqual(['status r1 cancelled', 'status r2 missed']);
  });
});
