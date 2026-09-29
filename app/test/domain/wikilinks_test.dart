import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/domain/note.dart';
import 'package:organizacional/domain/wikilinks.dart';

void main() {
  test('parse encontra links simples e com apelido', () {
    final links = parseWikiLinks('Ver [[Cálculo I]] e [[Álgebra Linear|álgebra]].');
    expect(links.map((l) => l.target), ['Cálculo I', 'Álgebra Linear']);
    expect(links.map((l) => l.label), ['Cálculo I', 'álgebra']);
  });

  test('ignora colchetes vazios', () {
    expect(parseWikiLinks('[[ ]] e [[]]'), isEmpty);
  });

  test('resolve ignorando caixa e espaços extras', () {
    const notes = [Note(id: 'n1', title: 'Cálculo I')];
    expect(resolveWikiLink('  cálculo   i ', notes)?.id, 'n1');
  });

  test('link sem nota correspondente resolve para null', () {
    const notes = [Note(id: 'n1', title: 'Cálculo I')];
    expect(resolveWikiLink('Física', notes), isNull);
  });

  test('backlinks lista quem menciona a nota, sem ela mesma', () {
    const target = Note(id: 'n1', title: 'Limites', body: 'ver [[Limites]]');
    const notes = [
      target,
      Note(id: 'n2', title: 'Derivadas', body: 'usa [[limites]]'),
      Note(id: 'n3', title: 'Física', body: 'nada aqui'),
    ];
    expect(backlinksFor(target, notes).map((n) => n.id), ['n2']);
  });

  test('wikiLinksToMarkdown gera link wiki: codificado', () {
    expect(wikiLinksToMarkdown('[[Cálculo I|calc]] e [[Física]]'),
        '[calc](wiki:C%C3%A1lculo%20I) e [Física](wiki:F%C3%ADsica)');
  });

  test('uniqueTitle numera títulos repetidos', () {
    const notes = [Note(id: 'a', title: 'Sem título'), Note(id: 'b', title: 'sem título 2')];
    expect(uniqueTitle('Sem título', notes), 'Sem título 3');
    expect(uniqueTitle('Nova', notes), 'Nova');
  });
}
