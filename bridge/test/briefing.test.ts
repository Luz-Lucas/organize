import { describe, expect, it } from 'vitest';
import { buildBriefing, chunkSpeech, escapeSsml, headlinesText, splitTasks, type BriefingInput } from '../src/briefing.js';

const SP = 'America/Sao_Paulo';
const now = new Date('2026-09-28T10:00:00Z'); // 07:00 em SP, segunda

const input = (over: Partial<BriefingInput> = {}): BriefingInput => ({
  now, timeZone: SP, events: [], overdue: [], dueToday: [], news: [], ...over,
});

describe('buildBriefing', () => {
  it('dia completo', () => {
    const text = buildBriefing(input({
      events: [
        { title: 'Cálculo I', startsAt: new Date('2026-09-28T11:00:00Z'), endsAt: new Date('2026-09-28T12:40:00Z'), allDay: false, location: 'Sala 12' },
        { title: 'Feriado acadêmico', startsAt: new Date('2026-09-28T03:00:00Z'), endsAt: new Date('2026-09-29T03:00:00Z'), allDay: true, location: null },
      ],
      dueToday: [{ title: 'Lista 3.' }],
      overdue: [{ title: 'Resumo' }, { title: 'Relatório' }],
      news: [{ source: 'G1', title: 'Chuva forte em BH.' }],
    }));
    expect(text).toBe(
      'Bom dia! Hoje é segunda-feira, 28 de setembro. ' +
      'Você tem 2 compromissos: às 08:00, Cálculo I, em Sala 12; o dia todo, Feriado acadêmico. ' +
      'Para hoje: Lista 3. ' +
      'Atenção, há 2 tarefas atrasadas: Resumo e Relatório. ' +
      'Manchetes: G1: Chuva forte em BH.',
    );
  });

  it('dia livre', () => {
    expect(buildBriefing(input())).toBe(
      'Bom dia! Hoje é segunda-feira, 28 de setembro. Sua agenda de hoje está livre. Nenhuma tarefa com prazo para hoje.',
    );
  });

  it('saudação segue o horário local, não o UTC', () => {
    expect(buildBriefing(input({ now: new Date('2026-09-28T17:00:00Z') }))).toMatch(/^Boa tarde!/);
    expect(buildBriefing(input({ now: new Date('2026-09-29T00:30:00Z') }))).toMatch(/^Boa noite! Hoje é segunda-feira/);
  });

  it('limita a quantidade de eventos e tarefas', () => {
    const ev = (i: number) => ({ title: `E${i}`, startsAt: new Date(`2026-09-28T1${i}:00:00Z`), endsAt: new Date(`2026-09-28T1${i}:30:00Z`), allDay: false, location: null });
    const text = buildBriefing(input({
      events: [0, 1, 2, 3, 4, 5, 6, 7].map(ev),
      dueToday: ['a', 'b', 'c', 'd', 'e', 'f', 'g'].map((title) => ({ title })),
    }));
    expect(text).toContain('Você tem 8 compromissos:');
    expect(text).toContain('; e mais 2.');
    expect(text).toContain('Para hoje: a, b, c, d e e, e mais 2.');
  });
});

describe('auxiliares', () => {
  it('headlinesText sem manchetes', () => {
    expect(headlinesText([])).toBe('Não encontrei manchetes das suas fontes agora.');
  });

  it('splitTasks separa atrasadas de hoje', () => {
    const start = new Date('2026-09-28T03:00:00Z');
    const r = splitTasks([
      { title: 'velha', dueAt: new Date('2026-09-28T02:59:00Z') },
      { title: 'hoje', dueAt: new Date('2026-09-28T03:00:00Z') },
    ], start);
    expect(r.overdue.map((t) => t.title)).toEqual(['velha']);
    expect(r.dueToday.map((t) => t.title)).toEqual(['hoje']);
  });

  it('chunkSpeech respeita o limite e não corta palavras', () => {
    const text = 'Frase um. ' + 'palavra '.repeat(60) + 'fim.';
    const chunks = chunkSpeech(text, 100);
    expect(chunks.every((c) => c.length <= 100)).toBe(true);
    expect(chunks.join(' ').replace(/\s+/g, ' ')).toBe(text.replace(/\s+/g, ' ').trim());
    expect(chunkSpeech('curto')).toEqual(['curto']);
  });

  it('escapeSsml', () => {
    expect(escapeSsml(`P&D <Lab> "x" 'y'`)).toBe('P&amp;D &lt;Lab&gt; &quot;x&quot; &apos;y&apos;');
  });
});
