import { describe, expect, it } from 'vitest';
import { AlexaAuthError } from '../src/gateway.js';
import type { WakePlan, WakeRun } from '../src/scheduler.js';
import { applyWakeActions, runWake, testPlan, weatherLocation, type PresenceSource, type WakeDeps, type WakeStore } from '../src/wake.js';
import { FakeGateway } from './fake-gateway.js';

const plan = (over: Partial<WakePlan> = {}): WakePlan => ({
  id: 'p1', label: 'Aula', days: [1], time: '07:00', echoDeviceId: 'ECHO', spotifyQuery: 'lofi',
  musicFirst: true, briefingDelayMin: 3, briefingDelaySec: null, musicStopAfterSec: null, afterMusic: 'briefing',
  volume: 30, fallbackAlarm: true, enabled: true, includeWeather: true, deviceActions: [], phoneAlarm: 'fallback', ...over,
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

describe('runWake: espera do resumo em segundos', () => {
  it('briefingDelaySec=10: sleep(10000) entre a música e a fala', async () => {
    const gw = new FakeGateway();
    await runWake(plan({ briefingDelaySec: 10 }), texts, gw, timeline(gw));
    expect(gw.calls).toEqual(['setVolume(ECHO,30)', 'playSpotify(ECHO,lofi)', 'sleep(10000)', 'speak(ECHO,Bom dia!)']);
  });

  it('briefingDelaySec nulo mantém a espera em minutos', async () => {
    const gw = new FakeGateway();
    await runWake(plan({ briefingDelaySec: null, briefingDelayMin: 2 }), texts, gw, timeline(gw));
    expect(gw.calls).toContain('sleep(120000)');
  });

  it('briefingDelaySec=0 não espera (mesmo com minutos > 0)', async () => {
    const gw = new FakeGateway();
    await runWake(plan({ briefingDelaySec: 0, briefingDelayMin: 5 }), texts, gw, timeline(gw));
    expect(gw.calls).toEqual(['setVolume(ECHO,30)', 'playSpotify(ECHO,lofi)', 'speak(ECHO,Bom dia!)']);
  });

  it('briefingDelaySec vale também com afterMusic=headlines', async () => {
    const gw = new FakeGateway();
    await runWake(plan({ briefingDelaySec: 10, afterMusic: 'headlines' }), texts, gw, timeline(gw));
    expect(gw.calls).toEqual(['setVolume(ECHO,30)', 'playSpotify(ECHO,lofi)', 'sleep(10000)', 'speak(ECHO,Manchetes: A.)']);
  });

  it('musicStopAfterSec continua mandando: briefingDelaySec é ignorado', async () => {
    const gw = new FakeGateway();
    await runWake(plan({ briefingDelaySec: 10, musicStopAfterSec: 30 }), texts, gw, timeline(gw));
    expect(gw.calls.filter((c) => c.startsWith('sleep'))).toEqual(['sleep(30000)']);
  });
});

describe('runWake: ações de dispositivos', () => {
  const acts = (...a: Partial<WakePlan['deviceActions'][number]>[]) =>
    a.map((x, i) => ({ entityId: `luz${i + 1}`, name: `Luz ${i + 1}`, action: 'turnOn' as const, delayMin: 0, ...x }));

  it('atraso 0 roda já, junto da música; atrasada espera sua pausa; tudo termina antes de retornar', async () => {
    const gw = new FakeGateway();
    const r = await runWake(
      plan({ deviceActions: acts({}, { action: 'setBrightness', brightness: 40, delayMin: 5 }, { action: 'turnOff', delayMin: 1 }) }),
      texts, gw, timeline(gw),
    );
    expect(r).toEqual({ ok: true, notes: [] });
    const c = gw.calls;
    expect(c[0]).toBe('deviceAction(luz1,turnOn)');
    expect(c.indexOf('sleep(300000)')).toBeLessThan(c.indexOf('deviceAction(luz2,setBrightness,40)'));
    expect(c.indexOf('sleep(60000)')).toBeLessThan(c.indexOf('deviceAction(luz3,turnOff)'));
    expect(c).toContain('playSpotify(ECHO,lofi)');
    expect(c).toContain('speak(ECHO,Bom dia!)');
  });

  it('não atrasa a música nem a fala: a pausa longa da ação não bloqueia o resto', async () => {
    const gw = new FakeGateway();
    let release!: () => void;
    const gate = new Promise<void>((res) => { release = res; });
    const sleep = async (ms: number) => { if (ms === 1_800_000) await gate; };
    const p = runWake(plan({ deviceActions: acts({ delayMin: 30 }), briefingDelayMin: 0 }), texts, gw, sleep);
    let done = false;
    void p.then(() => { done = true; });
    await new Promise((r) => setTimeout(r, 10));
    expect(gw.calls).toContain('speak(ECHO,Bom dia!)');
    expect(gw.calls).not.toContain('deviceAction(luz1,turnOn)');
    expect(done).toBe(false); // espera a pendente
    release();
    const r = await p;
    expect(gw.calls.at(-1)).toBe('deviceAction(luz1,turnOn)');
    expect(r.ok).toBe(true);
  });

  it('falha de uma ação vira nota e não impede as outras', async () => {
    const gw = new FakeGateway();
    const orig = gw.deviceAction.bind(gw);
    gw.deviceAction = async (id, action, b) => { if (id === 'luz1') throw new Error('offline'); return orig(id, action, b); };
    const r = await runWake(plan({ deviceActions: acts({}, { action: 'turnOff' }) }), texts, gw, noSleep);
    expect(r.ok).toBe(true);
    expect(r.notes).toEqual(['dispositivo Luz 1: offline']);
    expect(gw.calls).toContain('deviceAction(luz2,turnOff)');
    expect(gw.calls).toContain('speak(ECHO,Bom dia!)');
  });

  it('só as ações não contam como áudio: sem som, ok=false', async () => {
    const gw = new FakeGateway();
    gw.failOn.add('playSpotify');
    gw.failOn.add('speak');
    const r = await runWake(plan({ deviceActions: acts({}) }), texts, gw, noSleep);
    expect(r.ok).toBe(false);
    expect(gw.calls).toContain('deviceAction(luz1,turnOn)');
  });

  it('AlexaAuthError numa ação é propagado no final', async () => {
    const gw = new FakeGateway();
    gw.deviceAction = async () => { throw new AlexaAuthError('cookie expirado'); };
    await expect(runWake(plan({ deviceActions: acts({}) }), texts, gw, noSleep)).rejects.toBeInstanceOf(AlexaAuthError);
  });
});

describe('testPlan (Testar agora)', () => {
  it('zera o atraso em minutos e mantém "não parar"', () => {
    expect(testPlan(plan({ briefingDelayMin: 5 }))).toMatchObject({ briefingDelayMin: 0, musicStopAfterSec: null });
  });

  it('limita a espera do resumo a 10 s (não a zero)', () => {
    expect(testPlan(plan({ briefingDelayMin: 5 })).briefingDelaySec).toBe(10);
    expect(testPlan(plan({ briefingDelaySec: 300 })).briefingDelaySec).toBe(10);
    expect(testPlan(plan({ briefingDelaySec: 10 })).briefingDelaySec).toBe(10);
    expect(testPlan(plan({ briefingDelaySec: 4 })).briefingDelaySec).toBe(4);
    expect(testPlan(plan({ briefingDelaySec: 0 })).briefingDelaySec).toBe(0);
    expect(testPlan(plan({ briefingDelayMin: 0 })).briefingDelaySec).toBe(0);
  });

  it('mantém as ações de dispositivos e o clima', () => {
    const p = plan({ includeWeather: false, deviceActions: [{ entityId: 'x', name: 'X', action: 'turnOn', delayMin: 1 }] });
    expect(testPlan(p)).toMatchObject({ includeWeather: false, deviceActions: p.deviceActions });
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

describe('fireWake: presença e clima', () => {
  const NOW = new Date('2026-09-28T10:00:20Z');
  const HOME = { lat: -19.9167, lon: -43.9345, radiusM: 50 };
  const atHome = { lat: -19.9167, lon: -43.9345, accuracyM: 10, reportedAt: new Date('2026-09-28T09:50:00Z') };
  const sp = { lat: -23.55, lon: -46.63, accuracyM: 10, reportedAt: new Date('2026-09-28T09:50:00Z') };
  const armed: WakeRun = { id: 'r1', planId: 'p1', runDate: '2026-09-28', plannedFor: new Date('2026-09-28T10:00:00Z'), status: 'armed', fallbackHandle: 'reserva-1' };
  const fire = (p: WakePlan, run: WakeRun | null = armed) =>
    ({ type: 'fire' as const, plan: p, runDate: '2026-09-28', plannedFor: armed.plannedFor, run });

  const run = async (
    src: PresenceSource | Error | undefined,
    over: Partial<WakePlan> = {},
    extra: Partial<WakeDeps> = {},
    runInfo: WakeRun | null = armed,
  ) => {
    const gw = new FakeGateway();
    const store = new MemoryWakeStore();
    const weatherCalls: { lat: number; lon: number }[] = [];
    const briefingArgs: (string | null)[] = [];
    const deps: WakeDeps = {
      gateway: gw, store, sleep: noSleep, log: () => {}, now: () => NOW,
      briefing: async (w) => { briefingArgs.push(w); return { briefing: w ? `Bom dia! ${w} Agenda.` : 'Bom dia! Agenda.', headlines: 'H.' }; },
      weather: async (at) => { weatherCalls.push(at); return 'Faz 22 graus.'; },
      ...(src === undefined ? {} : { presence: async () => { if (src instanceof Error) throw src; return src; } }),
      ...extra,
    };
    const pending = await applyWakeActions([fire(plan(over), runInfo)], deps, new Set());
    await Promise.all(pending);
    return { gw, store, weatherCalls, briefingArgs };
  };

  it('fora de casa: só apaga o alarme reserva e termina "skipped"; nenhum outro efeito', async () => {
    const { gw, store, weatherCalls, briefingArgs } = await run(
      { home: HOME, requireHome: true, location: sp },
      { deviceActions: [{ entityId: 'luz1', name: 'Luz', action: 'turnOn', delayMin: 0 }] },
    );
    expect(gw.calls).toEqual(['deleteAlarm(reserva-1)']);
    expect(store.log).toHaveLength(1);
    expect(store.log[0]).toMatch(/^finish p1 2026-09-28 skipped fora de casa \(a \d+ m\)$/);
    expect(weatherCalls).toEqual([]);
    expect(briefingArgs).toEqual([]);
  });

  it('fora de casa sem alarme reserva: nada no gateway', async () => {
    const { gw, store } = await run({ home: HOME, requireHome: true, location: sp }, {}, {}, null);
    expect(gw.calls).toEqual([]);
    expect(store.log[0]).toContain('skipped');
  });

  it('em casa: toca normalmente e apaga o reserva', async () => {
    const { gw, store } = await run({ home: HOME, requireHome: true, location: atHome });
    expect(gw.calls).toContain('playSpotify(ECHO,lofi)');
    expect(gw.calls).toContain('deleteAlarm(reserva-1)');
    expect(store.log[0]).toMatch(/ done /);
  });

  it('localização desconhecida (antiga ou ausente): toca mesmo assim', async () => {
    const old = { ...sp, reportedAt: new Date('2026-09-28T09:00:00Z') };
    for (const location of [null, old]) {
      const { gw, store } = await run({ home: HOME, requireHome: true, location });
      expect(gw.calls).toContain('playSpotify(ECHO,lofi)');
      expect(store.log[0]).toMatch(/ done /);
    }
  });

  it('presença não exigida (sem casa ou require_home=false): toca mesmo estando longe', async () => {
    for (const src of [{ home: null, requireHome: true, location: sp }, { home: HOME, requireHome: false, location: sp }]) {
      const { gw } = await run(src);
      expect(gw.calls).toContain('playSpotify(ECHO,lofi)');
    }
  });

  it('erro ao ler a presença: toca mesmo assim', async () => {
    const { gw } = await run(new Error('db fora'));
    expect(gw.calls).toContain('playSpotify(ECHO,lofi)');
  });

  it('sem fonte de presença configurada: toca', async () => {
    const { gw } = await run(undefined);
    expect(gw.calls).toContain('playSpotify(ECHO,lofi)');
  });

  it('clima entra no resumo falado, com a localização do celular (até 3 h)', async () => {
    const fix = { ...sp, reportedAt: new Date('2026-09-28T07:30:00Z') }; // 2h30
    const { gw, weatherCalls } = await run({ home: HOME, requireHome: false, location: fix });
    expect(weatherCalls).toEqual([{ lat: sp.lat, lon: sp.lon }]);
    expect(gw.calls).toContain('speak(ECHO,Bom dia! Faz 22 graus. Agenda.)');
  });

  it('localização com mais de 3 h: usa a casa', async () => {
    const stale = { ...sp, reportedAt: new Date('2026-09-28T06:00:00Z') };
    const { weatherCalls } = await run({ home: HOME, requireHome: false, location: stale });
    expect(weatherCalls).toEqual([{ lat: HOME.lat, lon: HOME.lon }]);
  });

  it('sem casa e sem localização recente: sem clima', async () => {
    const { gw, weatherCalls, briefingArgs } = await run({ home: null, requireHome: true, location: null });
    expect(weatherCalls).toEqual([]);
    expect(briefingArgs).toEqual([null]);
    expect(gw.calls).toContain('speak(ECHO,Bom dia! Agenda.)');
  });

  it('includeWeather=false não busca o clima', async () => {
    const { weatherCalls, briefingArgs } = await run({ home: HOME, requireHome: true, location: atHome }, { includeWeather: false });
    expect(weatherCalls).toEqual([]);
    expect(briefingArgs).toEqual([null]);
  });

  it('falha do clima (exceção ou null) só omite o clima; o despertar segue', async () => {
    for (const weather of [async () => { throw new Error('rede'); }, async () => null]) {
      const { gw, briefingArgs, store } = await run({ home: HOME, requireHome: true, location: atHome }, {}, { weather });
      expect(briefingArgs).toEqual([null]);
      expect(gw.calls).toContain('speak(ECHO,Bom dia! Agenda.)');
      expect(store.log[0]).toMatch(/ done /);
    }
  });

  it('sem dependência de clima configurada: segue sem clima', async () => {
    const { briefingArgs } = await run({ home: HOME, requireHome: true, location: atHome }, {}, { weather: undefined });
    expect(briefingArgs).toEqual([null]);
  });

  it('não registra coordenadas nos logs', async () => {
    const logs: string[] = [];
    await run({ home: HOME, requireHome: true, location: atHome }, {}, {
      log: (m) => logs.push(m), weather: async () => { throw new Error('boom'); },
    });
    await run({ home: HOME, requireHome: true, location: sp }, {}, { log: (m) => logs.push(m) });
    expect(logs.join(' ')).not.toMatch(/-?\d+\.\d{3}/);
  });
});

describe('weatherLocation', () => {
  const now = new Date('2026-09-28T10:00:00Z');
  const home = { lat: 1, lon: 2, radiusM: 50 };
  it('celular recente > casa > nada', () => {
    const loc = { lat: 3, lon: 4, accuracyM: null, reportedAt: new Date('2026-09-28T07:00:00Z') };
    expect(weatherLocation({ home, requireHome: true, location: loc }, now)).toEqual({ lat: 3, lon: 4 }); // 3 h exatas
    expect(weatherLocation({ home, requireHome: true, location: { ...loc, reportedAt: new Date('2026-09-28T06:59:00Z') } }, now)).toEqual({ lat: 1, lon: 2 });
    expect(weatherLocation({ home: null, requireHome: true, location: null }, now)).toBeNull();
    expect(weatherLocation(null, now)).toBeNull();
  });
});
