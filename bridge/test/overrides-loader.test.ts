import { describe, expect, it, vi } from 'vitest';
import { createOverridesLoader } from '../src/overrides-loader.js';
import type { WakeOverride } from '../src/scheduler.js';

const ovr = (over: Partial<WakeOverride> = {}): WakeOverride => ({
  planId: 'p1', runDate: '2026-10-13', skip: false, time: '06:30:00', ...over,
});

describe('createOverridesLoader', () => {
  it('lê a janela de -2 a +2 dias em torno de hoje, igual à dos runs', async () => {
    const load = vi.fn().mockResolvedValue([ovr()]);
    const loader = createOverridesLoader(load, () => {});
    expect(await loader('2026-10-12')).toEqual([ovr()]);
    expect(load).toHaveBeenCalledWith('2026-10-10', '2026-10-14');
  });

  it('janela cruza o mês corretamente', async () => {
    const load = vi.fn().mockResolvedValue([]);
    await createOverridesLoader(load, () => {})('2026-10-31');
    expect(load).toHaveBeenCalledWith('2026-10-29', '2026-11-02');
  });

  it('falha na leitura devolve o último resultado bom e registra no log sem dados sensíveis', async () => {
    const log = vi.fn();
    const load = vi.fn()
      .mockResolvedValueOnce([ovr()])
      .mockRejectedValueOnce(new Error('rede caiu'));
    const loader = createOverridesLoader(load, log);
    await loader('2026-10-12');
    const result = await loader('2026-10-12');
    expect(result).toEqual([ovr()]);
    expect(log).toHaveBeenCalledTimes(1);
    expect(log.mock.calls[0][0]).toContain('rede caiu');
    expect(log.mock.calls[0][0]).not.toContain('p1');
  });

  it('falha na primeira leitura devolve lista vazia sem lançar', async () => {
    const load = vi.fn().mockRejectedValue(new Error('timeout'));
    const log = vi.fn();
    await expect(createOverridesLoader(load, log)('2026-10-12')).resolves.toEqual([]);
    expect(log).toHaveBeenCalledTimes(1);
  });

  it('volta a usar o resultado novo depois que a leitura se recupera', async () => {
    const load = vi.fn()
      .mockRejectedValueOnce(new Error('x'))
      .mockResolvedValueOnce([ovr({ skip: true, time: null })]);
    const loader = createOverridesLoader(load, () => {});
    expect(await loader('2026-10-12')).toEqual([]);
    expect(await loader('2026-10-12')).toEqual([ovr({ skip: true, time: null })]);
  });
});
