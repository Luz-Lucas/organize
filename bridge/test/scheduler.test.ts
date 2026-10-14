import { describe, expect, it } from 'vitest';
import { DEFAULT_OPTIONS, occurrence, planWakeActions, type WakeOverride, type WakePlan, type WakeRun } from '../src/scheduler.js';

const SP = 'America/Sao_Paulo';
const plan = (over: Partial<WakePlan> = {}): WakePlan => ({
  id: 'p1', label: 'Aula', days: [1, 2, 3, 4, 5], time: '07:00:00', echoDeviceId: 'ECHO',
  spotifyQuery: 'lofi', musicFirst: true, briefingDelayMin: 3, briefingDelaySec: null, musicStopAfterSec: null, afterMusic: 'briefing', volume: 30,
  fallbackAlarm: true, enabled: true, includeWeather: true, deviceActions: [], phoneAlarm: 'fallback', ...over,
});
const run = (over: Partial<WakeRun> = {}): WakeRun => ({
  id: 'r1', planId: 'p1', runDate: '2026-09-28', plannedFor: new Date('2026-09-28T10:00:00Z'),
  status: 'armed', fallbackHandle: 'h1', ...over,
});
const ovr = (over: Partial<WakeOverride> = {}): WakeOverride => ({
  planId: 'p1', runDate: '2026-09-28', skip: false, time: '06:30:00', ...over,
});
const at = (iso: string) => new Date(iso);
const types = (actions: { type: string }[]) => actions.map((a) => a.type);

describe('planWakeActions', () => {
  it('antes do horário arma o alarme reserva para 10 min depois', () => {
    const actions = planWakeActions([plan()], [], at('2026-09-28T09:59:30Z'), SP);
    expect(actions).toEqual([{
      type: 'arm', plan: plan(), runDate: '2026-09-28',
      plannedFor: at('2026-09-28T10:00:00Z'), fallbackAt: at('2026-09-28T10:10:00Z'),
    }]);
  });

  it('não arma de novo o que já está armado', () => {
    expect(planWakeActions([plan()], [run()], at('2026-09-28T09:59:30Z'), SP)).toEqual([]);
  });

  it('no horário dispara (com ou sem run armado) e já arma o reserva de amanhã', () => {
    const now = at('2026-09-28T10:00:20Z');
    const actions = planWakeActions([plan()], [run()], now, SP);
    expect(types(actions)).toEqual(['fire', 'arm']);
    expect(actions[0]).toEqual(
      { type: 'fire', plan: plan(), runDate: '2026-09-28', plannedFor: at('2026-09-28T10:00:00Z'), run: run() },
    );
    expect(actions[1]).toMatchObject({ type: 'arm', runDate: '2026-09-29' });
    const noFallback = plan({ fallbackAlarm: false });
    expect(types(planWakeActions([noFallback], [], now, SP))).toEqual(['fire']);
  });

  it('não dispara duas vezes (run já rodando ou concluído)', () => {
    const now = at('2026-09-28T10:05:00Z');
    expect(types(planWakeActions([plan()], [run({ status: 'running' })], now, SP))).not.toContain('fire');
    expect(types(planWakeActions([plan()], [run({ status: 'done' })], now, SP))).not.toContain('fire');
  });

  it('passada a janela de 15 min, run armado vira "miss" e nada dispara (só arma amanhã)', () => {
    const actions = planWakeActions([plan()], [run()], at('2026-09-28T10:16:00Z'), SP);
    expect(types(actions)).toEqual(['miss', 'arm']);
  });

  it('fim de semana não dispara plano de dias úteis', () => {
    expect(planWakeActions([plan({ fallbackAlarm: false })], [], at('2026-10-03T10:00:30Z'), SP)).toEqual([]);
  });

  it('plano desativado cancela o alarme reserva armado', () => {
    expect(types(planWakeActions([plan({ enabled: false })], [run()], at('2026-09-28T08:00:00Z'), SP))).toEqual(['cancel']);
  });

  it('plano apagado (planId nulo) cancela o alarme reserva', () => {
    expect(types(planWakeActions([], [run({ planId: null })], at('2026-09-28T08:00:00Z'), SP))).toEqual(['cancel']);
  });

  it('mudança de horário rearma o alarme reserva', () => {
    const actions = planWakeActions([plan({ time: '06:30' })], [run()], at('2026-09-28T08:00:00Z'), SP);
    expect(actions).toEqual([{
      type: 'rearm', run: run(), plan: plan({ time: '06:30' }),
      plannedFor: at('2026-09-28T09:30:00Z'), fallbackAt: at('2026-09-28T09:40:00Z'),
    }]);
  });

  it('fronteira UTC: 22:30 de Brasília dispara na data local certa', () => {
    const p = plan({ time: '22:30', fallbackAlarm: false });
    const actions = planWakeActions([p], [], at('2026-09-29T01:30:30Z'), SP);
    expect(actions).toEqual([{ type: 'fire', plan: p, runDate: '2026-09-28', plannedFor: at('2026-09-29T01:30:00Z'), run: null }]);
  });

  it('plano às 23:55 ainda dispara depois da meia-noite, dentro da janela', () => {
    const p = plan({ time: '23:55', days: [1], fallbackAlarm: false });
    const actions = planWakeActions([p], [], at('2026-09-29T03:05:00Z'), SP); // terça 00:05 local
    expect(actions).toEqual([{ type: 'fire', plan: p, runDate: '2026-09-28', plannedFor: at('2026-09-29T02:55:00Z'), run: null }]);
  });

  it('execução pulada (fora de casa) é final: não dispara, não rearma e não conta como armada', () => {
    const skipped = run({ status: 'skipped', fallbackHandle: null });
    expect(planWakeActions([plan()], [skipped], at('2026-09-28T10:01:00Z'), SP).map((a) => `${a.type}:${'runDate' in a ? a.runDate : ''}`))
      .toEqual(['arm:2026-09-29']); // só o reserva de amanhã; nada para 2026-09-28
    expect(planWakeActions([plan()], [skipped], at('2026-09-28T09:00:00Z'), SP)).toEqual([]);
    expect(planWakeActions([plan()], [skipped], at('2026-09-28T10:20:00Z'), SP).filter((a) => a.type !== 'arm')).toEqual([]);
  });

  it('run cancelado pode ser rearmado e disparado', () => {
    const cancelled = run({ status: 'cancelled', fallbackHandle: null });
    expect(types(planWakeActions([plan()], [cancelled], at('2026-09-28T09:00:00Z'), SP))).toEqual(['arm']);
    expect(types(planWakeActions([plan()], [cancelled], at('2026-09-28T10:01:00Z'), SP))).toEqual(['fire', 'arm']);
  });
});

describe('overrides por data ("só amanhã")', () => {
  const NOW = at('2026-09-28T08:00:00Z'); // segunda 05:00 local

  it('occurrence: sem override segue a regra de dias e horário', () => {
    expect(occurrence(plan(), '2026-09-28', SP)).toEqual(at('2026-09-28T10:00:00Z'));
    expect(occurrence(plan(), '2026-10-03', SP)).toBeNull(); // sábado
  });

  it('occurrence: skip ⇒ null; horário novo substitui o do plano', () => {
    expect(occurrence(plan(), '2026-09-28', SP, [ovr({ skip: true, time: null })])).toBeNull();
    expect(occurrence(plan(), '2026-09-28', SP, [ovr()])).toEqual(at('2026-09-28T09:30:00Z'));
  });

  it('occurrence: override de outro plano ou de outra data é ignorado', () => {
    expect(occurrence(plan(), '2026-09-28', SP, [ovr({ planId: 'outro' })])).toEqual(at('2026-09-28T10:00:00Z'));
    expect(occurrence(plan(), '2026-09-28', SP, [ovr({ runDate: '2026-09-29' })])).toEqual(at('2026-09-28T10:00:00Z'));
  });

  it('occurrence: override em dia fora de `days` toca (dia extra)', () => {
    expect(occurrence(plan(), '2026-10-03', SP, [ovr({ runDate: '2026-10-03', time: '09:15' })]))
      .toEqual(at('2026-10-03T12:15:00Z'));
  });

  it('skip cancela o alarme reserva armado', () => {
    const actions = planWakeActions([plan()], [run()], NOW, SP, undefined, [ovr({ skip: true, time: null })]);
    expect(actions.filter((a) => a.type === 'cancel')).toEqual([{ type: 'cancel', run: run() }]);
    expect(actions.some((a) => a.type === 'arm' && a.runDate === '2026-09-28')).toBe(false);
  });

  it('skip não arma o reserva do dia pulado, só dos outros', () => {
    const actions = planWakeActions([plan()], [], at('2026-09-28T09:30:00Z'), SP, { ...DEFAULT_OPTIONS, armAheadHours: 36 }, [ovr({ skip: true, time: null })]);
    expect(actions.map((a) => `${a.type}:${'runDate' in a ? a.runDate : ''}`)).toEqual(['arm:2026-09-29']);
  });

  it('skip no horário do despertar não dispara', () => {
    const now = at('2026-09-28T10:00:20Z');
    const actions = planWakeActions([plan({ fallbackAlarm: false })], [], now, SP, undefined, [ovr({ skip: true, time: null })]);
    expect(actions).toEqual([]);
  });

  it('mudar o horário só desse dia rearma o reserva', () => {
    const actions = planWakeActions([plan()], [run()], NOW, SP, undefined, [ovr({ time: '06:30' })]);
    expect(actions).toEqual([{
      type: 'rearm', run: run(), plan: plan(),
      plannedFor: at('2026-09-28T09:30:00Z'), fallbackAt: at('2026-09-28T09:40:00Z'),
    }]);
  });

  it('override em dia fora de `days` arma e dispara', () => {
    const sat = ovr({ runDate: '2026-10-03', time: '09:00' });
    const arm = planWakeActions([plan()], [], at('2026-10-03T05:00:00Z'), SP, undefined, [sat]);
    expect(arm).toEqual([{
      type: 'arm', plan: plan(), runDate: '2026-10-03',
      plannedFor: at('2026-10-03T12:00:00Z'), fallbackAt: at('2026-10-03T12:10:00Z'),
    }]);
    const fire = planWakeActions([plan({ fallbackAlarm: false })], [], at('2026-10-03T12:00:30Z'), SP, undefined, [sat]);
    expect(fire).toEqual([{ type: 'fire', plan: plan({ fallbackAlarm: false }), runDate: '2026-10-03', plannedFor: at('2026-10-03T12:00:00Z'), run: null }]);
  });

  it('sem overrides nada muda', () => {
    expect(planWakeActions([plan()], [run()], at('2026-09-28T09:59:30Z'), SP, undefined, []))
      .toEqual(planWakeActions([plan()], [run()], at('2026-09-28T09:59:30Z'), SP));
  });
});
