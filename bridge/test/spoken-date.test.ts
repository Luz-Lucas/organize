import { describe, expect, it } from 'vitest';
import { parseSpokenRequest, taskDue } from '../src/spoken-date.js';

const TZ = 'America/Sao_Paulo';
// terça-feira, 20/10/2026, 12:00 em São Paulo
const NOW = new Date('2026-10-20T15:00:00Z');
const p = (text: string, now = NOW) => parseSpokenRequest(text, now, TZ);
const ymd = (y: number, m: number, d: number) => ({ y, m, d });

describe('parseSpokenRequest: datas', () => {
  it('sem data nem hora devolve só o título', () => {
    expect(p('estudar cálculo')).toEqual({ title: 'estudar cálculo', date: null, time: null });
  });

  it('hoje, amanhã e depois de amanhã', () => {
    expect(p('pagar a conta hoje').date).toEqual(ymd(2026, 10, 20));
    expect(p('pagar a conta amanhã').date).toEqual(ymd(2026, 10, 21));
    expect(p('pagar a conta amanha').date).toEqual(ymd(2026, 10, 21));
    expect(p('pagar a conta depois de amanhã').date).toEqual(ymd(2026, 10, 22));
    expect(p('pagar a conta depois de amanhã').title).toBe('pagar a conta');
  });

  it('usa o dia local do fuso, não o dia UTC', () => {
    const lateNight = new Date('2026-10-21T01:30:00Z'); // 22:30 de 20/10 em São Paulo
    expect(p('x hoje', lateNight).date).toEqual(ymd(2026, 10, 20));
    expect(p('x amanhã', lateNight).date).toEqual(ymd(2026, 10, 21));
  });

  it('virada de mês e de ano em hoje/amanhã', () => {
    const dec = new Date('2026-12-30T15:00:00Z');
    expect(p('x amanhã', dec).date).toEqual(ymd(2026, 12, 31));
    expect(p('x depois de amanhã', dec).date).toEqual(ymd(2027, 1, 1));
  });

  it('dias da semana: próxima ocorrência, nunca hoje', () => {
    expect(p('prova sexta').date).toEqual(ymd(2026, 10, 23));
    expect(p('prova na sexta').date).toEqual(ymd(2026, 10, 23));
    expect(p('prova sexta-feira').date).toEqual(ymd(2026, 10, 23));
    expect(p('prova na sexta-feira').date).toEqual(ymd(2026, 10, 23));
    expect(p('prova quarta').date).toEqual(ymd(2026, 10, 21));
    expect(p('prova sábado').date).toEqual(ymd(2026, 10, 24));
    expect(p('prova domingo').date).toEqual(ymd(2026, 10, 25));
    expect(p('prova segunda').date).toEqual(ymd(2026, 10, 26));
    expect(p('prova segunda que vem').date).toEqual(ymd(2026, 10, 26));
    expect(p('prova na próxima segunda').date).toEqual(ymd(2026, 10, 26));
    expect(p('prova terça-feira').date).toEqual(ymd(2026, 10, 27)); // hoje é terça: vai para a próxima
    expect(p('prova terça que vem').date).toEqual(ymd(2026, 10, 27));
    expect(p('prova terca').date).toEqual(ymd(2026, 10, 27));
    expect(p('prova quinta').date).toEqual(ymd(2026, 10, 22));
    expect(p('prova esta sexta').date).toEqual(ymd(2026, 10, 23));
  });

  it('o título perde o dia da semana e os complementos', () => {
    expect(p('prova de cálculo na sexta-feira').title).toBe('prova de cálculo');
    expect(p('prova de cálculo segunda que vem').title).toBe('prova de cálculo');
    expect(p('prova de cálculo na próxima segunda').title).toBe('prova de cálculo');
  });

  it('dia 25: neste mês se ainda não passou, senão no mês seguinte', () => {
    expect(p('boleto dia 25').date).toEqual(ymd(2026, 10, 25));
    expect(p('boleto dia 20').date).toEqual(ymd(2026, 10, 20)); // hoje conta
    expect(p('boleto dia 10').date).toEqual(ymd(2026, 11, 10));
    expect(p('boleto no dia 5').date).toEqual(ymd(2026, 11, 5));
    expect(p('boleto para o dia 25').date).toEqual(ymd(2026, 10, 25));
    expect(p('boleto para o dia 25').title).toBe('boleto');
  });

  it('dia 25 em dezembro passa para janeiro; dia inexistente no mês pula para um mês que o tenha', () => {
    const dec = new Date('2026-12-28T15:00:00Z');
    expect(p('x dia 3', dec).date).toEqual(ymd(2027, 1, 3));
    const feb = new Date('2026-02-15T15:00:00Z');
    expect(p('x dia 30', feb).date).toEqual(ymd(2026, 3, 30));
  });

  it('"25 de novembro" e "dia 3 de dezembro"', () => {
    expect(p('formatura 25 de novembro').date).toEqual(ymd(2026, 11, 25));
    expect(p('formatura 25 de novembro').title).toBe('formatura');
    expect(p('formatura dia 3 de dezembro').date).toEqual(ymd(2026, 12, 3));
    expect(p('formatura dia 3 de dezembro').title).toBe('formatura');
    expect(p('formatura em 1 de março').date).toEqual(ymd(2027, 3, 1)); // já passou: ano seguinte
    expect(p('formatura 20 de outubro').date).toEqual(ymd(2026, 10, 20)); // hoje conta
    expect(p('formatura 19 de outubro').date).toEqual(ymd(2027, 10, 19));
  });

  it('ano explícito, 29 de fevereiro e data numérica', () => {
    expect(p('x 25 de novembro de 2027').date).toEqual(ymd(2027, 11, 25));
    expect(p('x 25 de novembro de 2027').title).toBe('x');
    expect(p('aniversário 29 de fevereiro').date).toEqual(ymd(2028, 2, 29));
    expect(p('x dia 25/11').date).toEqual(ymd(2026, 11, 25));
  });

  it('data impossível não vira data', () => {
    expect(p('x 31 de fevereiro').date).toBeNull();
    expect(p('x 5/13').date).toBeNull();
  });

  it('não confunde palavras parecidas', () => {
    expect(p('ver amanhecer').date).toBeNull();
    expect(p('hojeriza').date).toBeNull();
    expect(p('comprar dois livros').date).toBeNull();
  });
});

describe('parseSpokenRequest: horas', () => {
  const time = (t: string) => p(t).time;

  it('"às 15h", "15h30", "15:30", "às 15 horas"', () => {
    expect(time('reunião às 15h')).toEqual({ h: 15, min: 0 });
    expect(time('reunião 15h')).toEqual({ h: 15, min: 0 });
    expect(time('reunião às 15h30')).toEqual({ h: 15, min: 30 });
    expect(time('reunião às 15:30')).toEqual({ h: 15, min: 30 });
    expect(time('reunião às 15 horas')).toEqual({ h: 15, min: 0 });
    expect(time('reunião às 15 horas e 30')).toEqual({ h: 15, min: 30 });
    expect(time('reunião às 15 horas e meia')).toEqual({ h: 15, min: 30 });
    expect(time('reunião 15 hs')).toEqual({ h: 15, min: 0 });
    expect(time('reunião às 1 hora')).toEqual({ h: 1, min: 0 });
  });

  it('"15 e 30" e "às 15 e 30"', () => {
    expect(time('reunião 15 e 30')).toEqual({ h: 15, min: 30 });
    expect(time('reunião às 15 e 45')).toEqual({ h: 15, min: 45 });
    expect(p('reunião às 15 e 30').title).toBe('reunião');
  });

  it('período: da tarde e da noite somam 12; da manhã não', () => {
    expect(time('dentista às 3 da tarde')).toEqual({ h: 15, min: 0 });
    expect(time('jantar às 8 da noite')).toEqual({ h: 20, min: 0 });
    expect(time('academia às 7 da manhã')).toEqual({ h: 7, min: 0 });
    expect(time('academia às 9 da manhã')).toEqual({ h: 9, min: 0 });
    expect(time('almoço às 12 da tarde')).toEqual({ h: 12, min: 0 });
    expect(time('x às 12 da noite')).toEqual({ h: 0, min: 0 });
    expect(time('x às 3 e meia da tarde')).toEqual({ h: 15, min: 30 });
    expect(time('x às 3h30 da tarde')).toEqual({ h: 15, min: 30 });
    expect(time('x às 3 e 15 da tarde')).toEqual({ h: 15, min: 15 });
    expect(time('x às 3 da madrugada')).toEqual({ h: 3, min: 0 });
    expect(time('x 8 da noite')).toEqual({ h: 20, min: 0 });
    expect(time('x às 3 de tarde')).toEqual({ h: 15, min: 0 });
    expect(time('x às 15h da tarde')).toEqual({ h: 15, min: 0 }); // 15 já é tarde: não soma de novo
  });

  it('meio-dia e meia-noite', () => {
    expect(time('almoço meio-dia')).toEqual({ h: 12, min: 0 });
    expect(time('almoço ao meio dia')).toEqual({ h: 12, min: 0 });
    expect(time('almoço ao meio-dia')).toEqual({ h: 12, min: 0 });
    expect(time('virada meia-noite')).toEqual({ h: 0, min: 0 });
    expect(time('virada à meia noite')).toEqual({ h: 0, min: 0 });
    expect(p('almoço ao meio-dia').title).toBe('almoço');
  });

  it('"às 9" sem período fica 9h', () => {
    expect(time('academia às 9')).toEqual({ h: 9, min: 0 });
    expect(time('academia às 18')).toEqual({ h: 18, min: 0 });
  });

  it('horas por extenso', () => {
    expect(time('x às três da tarde')).toEqual({ h: 15, min: 0 });
    expect(time('x às quinze horas')).toEqual({ h: 15, min: 0 });
    expect(time('x às dez horas')).toEqual({ h: 10, min: 0 });
    expect(time('x às vinte e uma horas')).toEqual({ h: 21, min: 0 });
    expect(time('x à uma hora')).toEqual({ h: 1, min: 0 });
  });

  it('número solto no título não é hora', () => {
    expect(p('estudar capítulo 3')).toEqual({ title: 'estudar capítulo 3', date: null, time: null });
    expect(p('comprar 2 livros')).toEqual({ title: 'comprar 2 livros', date: null, time: null });
    expect(p('ler 15 páginas').time).toBeNull();
    expect(p('x às 25').time).toBeNull();
    expect(p('x às 15h75').time).not.toEqual({ h: 15, min: 75 });
  });

  it('só período, sem hora, não define horário e fica no título', () => {
    expect(p('academia amanhã de manhã')).toEqual({ title: 'academia de manhã', date: ymd(2026, 10, 21), time: null });
  });
});

describe('parseSpokenRequest: título', () => {
  it('data e hora juntas, em qualquer ordem', () => {
    expect(p('reunião com o Pedro amanhã às 15h')).toEqual({ title: 'reunião com o Pedro', date: ymd(2026, 10, 21), time: { h: 15, min: 0 } });
    expect(p('reunião às 15h com o Pedro amanhã')).toEqual({ title: 'reunião com o Pedro', date: ymd(2026, 10, 21), time: { h: 15, min: 0 } });
    expect(p('amanhã às 15h reunião com o Pedro')).toEqual({ title: 'reunião com o Pedro', date: ymd(2026, 10, 21), time: { h: 15, min: 0 } });
    expect(p('dentista dia 25 às 3 da tarde')).toEqual({ title: 'dentista', date: ymd(2026, 10, 25), time: { h: 15, min: 0 } });
    expect(p('dentista na sexta às 9 da manhã')).toEqual({ title: 'dentista', date: ymd(2026, 10, 23), time: { h: 9, min: 0 } });
  });

  it('tira preposições das pontas, mas preserva as do meio', () => {
    expect(p('estudar cálculo para sexta').title).toBe('estudar cálculo');
    expect(p('estudar cálculo pra sexta').title).toBe('estudar cálculo');
    expect(p('estudar cálculo para a sexta').title).toBe('estudar cálculo');
    expect(p('estudar cálculo no sábado').title).toBe('estudar cálculo');
    expect(p('de estudar cálculo').title).toBe('estudar cálculo');
    expect(p('para sexta estudar cálculo').title).toBe('estudar cálculo');
    expect(p('prova de cálculo').title).toBe('prova de cálculo');
    expect(p('ligar para a vovó amanhã').title).toBe('ligar para a vovó');
  });

  it('mantém caixa e acentos originais e tira pontuação final', () => {
    expect(p('Reunião com a Júlia amanhã.').title).toBe('Reunião com a Júlia');
    expect(p('  Estudar   cálculo   ').title).toBe('Estudar cálculo');
  });

  it('título vazio quando só há data/hora/preposições', () => {
    expect(p('amanhã').title).toBe('');
    expect(p('para sexta às 15h').title).toBe('');
    expect(p('').title).toBe('');
    expect(p('   ').title).toBe('');
    expect(p('de').title).toBe('');
  });
});

describe('taskDue', () => {
  it('só data vale até 23:59 do dia local (como o create_task do MCP)', () => {
    expect(taskDue(ymd(2026, 10, 24), null, TZ).toISOString()).toBe('2026-10-25T02:59:00.000Z');
  });
  it('com hora usa a hora local', () => {
    expect(taskDue(ymd(2026, 10, 24), { h: 15, min: 30 }, TZ).toISOString()).toBe('2026-10-24T18:30:00.000Z');
  });
  it('respeita horário de verão do fuso', () => {
    expect(taskDue(ymd(2026, 7, 1), { h: 9, min: 0 }, 'America/New_York').toISOString()).toBe('2026-07-01T13:00:00.000Z');
    expect(taskDue(ymd(2026, 1, 15), { h: 9, min: 0 }, 'America/New_York').toISOString()).toBe('2026-01-15T14:00:00.000Z');
  });
});
