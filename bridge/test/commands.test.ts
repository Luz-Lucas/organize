import { describe, expect, it } from 'vitest';
import { executeCommand, isExpired, type Command } from '../src/commands.js';
import { FakeGateway } from './fake-gateway.js';

const cmd = (kind: Command['kind'], payload: Record<string, unknown>, createdAt = new Date('2026-09-28T10:00:00Z')): Command =>
  ({ id: 'c1', kind, payload, createdAt });

function deps() {
  const gateway = new FakeGateway();
  let synced = 0;
  return {
    gateway,
    get synced() { return synced; },
    d: { gateway, sync: async () => { synced++; }, wakeTest: async (id: string) => `teste ${id}` },
  };
}

describe('executeCommand', () => {
  it('liga, desliga e ajusta brilho', async () => {
    const { gateway, d } = deps();
    await executeCommand(cmd('device', { entityId: 'luz1', action: 'turnOn' }), d);
    await executeCommand(cmd('device', { entityId: 'luz1', action: 'setBrightness', brightness: 40 }), d);
    expect(gateway.calls).toEqual(['deviceAction(luz1,turnOn)', 'deviceAction(luz1,setBrightness,40)']);
  });

  it('valida ação e brilho', async () => {
    const { d } = deps();
    await expect(executeCommand(cmd('device', { entityId: 'luz1', action: 'explodir' }), d)).rejects.toThrow('ação desconhecida: explodir');
    await expect(executeCommand(cmd('device', { entityId: 'luz1', action: 'setBrightness', brightness: 150 }), d)).rejects.toThrow('brilho deve ser de 0 a 100');
    await expect(executeCommand(cmd('routine', { routineId: 'r1' }), d)).rejects.toThrow('campo "echoDeviceId" ausente');
  });

  it('fala em blocos, roda rotina, toca Spotify, sincroniza e testa despertar', async () => {
    const h = deps();
    await executeCommand(cmd('speak', { echoDeviceId: 'ECHO', text: 'Olá. '.repeat(80) }), h.d);
    expect(h.gateway.calls.filter((c) => c.startsWith('speak')).length).toBeGreaterThan(1);
    await executeCommand(cmd('routine', { routineId: 'r1', echoDeviceId: 'ECHO' }), h.d);
    await executeCommand(cmd('music', { echoDeviceId: 'ECHO', query: 'lofi' }), h.d);
    await executeCommand(cmd('sync', {}), h.d);
    expect(await executeCommand(cmd('wake_test', { planId: 'p1' }), h.d)).toBe('teste p1');
    expect(h.gateway.calls).toContain('runRoutine(r1,ECHO)');
    expect(h.gateway.calls).toContain('playSpotify(ECHO,lofi)');
    expect(h.synced).toBe(1);
  });

  it('comando com mais de 120 s expira', () => {
    const c = cmd('speak', {}, new Date('2026-09-28T10:00:00Z'));
    expect(isExpired(c, new Date('2026-09-28T10:02:00Z'))).toBe(false);
    expect(isExpired(c, new Date('2026-09-28T10:02:01Z'))).toBe(true);
  });
});
