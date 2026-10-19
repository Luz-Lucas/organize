import { describe, expect, it } from 'vitest';
import { parseShoppingUtterance } from '../src/shopping.js';

const lists = ['Mercado', 'Farmácia'];

describe('parseShoppingUtterance', () => {
  it('item simples vai sem lista', () => {
    expect(parseShoppingUtterance('leite', lists)).toEqual({ list: null, items: ['leite'] });
  });

  it('remove "na lista" e "na lista de compras"', () => {
    expect(parseShoppingUtterance('leite na lista', lists)).toEqual({ list: null, items: ['leite'] });
    expect(parseShoppingUtterance('leite na lista de compras', lists)).toEqual({ list: null, items: ['leite'] });
    expect(parseShoppingUtterance('leite na lista do mercado', lists)).toEqual({ list: 'Mercado', items: ['leite'] });
  });

  it('lista existente por "na/no X", sem acento nem caixa', () => {
    expect(parseShoppingUtterance('dipirona na farmacia', lists)).toEqual({ list: 'Farmácia', items: ['dipirona'] });
    expect(parseShoppingUtterance('Pão no Mercado', lists)).toEqual({ list: 'Mercado', items: ['Pão'] });
    expect(parseShoppingUtterance('shampoo na lista da farmácia', lists)).toEqual({ list: 'Farmácia', items: ['shampoo'] });
  });

  it('"na X" com X desconhecido continua sendo parte do item', () => {
    expect(parseShoppingUtterance('bolo na caixa', lists)).toEqual({ list: null, items: ['bolo na caixa'] });
  });

  it('"lista do X" desconhecida é descartada (cai na lista padrão)', () => {
    expect(parseShoppingUtterance('tomate na lista da feira', lists)).toEqual({ list: null, items: ['tomate'] });
  });

  it('separa vários itens por vírgula e "e"', () => {
    expect(parseShoppingUtterance('leite, pão e ovos', lists)).toEqual({ list: null, items: ['leite', 'pão', 'ovos'] });
    expect(parseShoppingUtterance('leite e pão na farmácia', lists)).toEqual({ list: 'Farmácia', items: ['leite', 'pão'] });
  });

  it('não separa "e" dentro de palavras e ignora repetidos e vazios', () => {
    expect(parseShoppingUtterance('peixe, , Peixe', lists)).toEqual({ list: null, items: ['peixe'] });
  });

  it('texto vazio não gera itens', () => {
    expect(parseShoppingUtterance('  ', lists)).toEqual({ list: null, items: [] });
    expect(parseShoppingUtterance('na lista', lists)).toEqual({ list: null, items: [] });
  });
});
