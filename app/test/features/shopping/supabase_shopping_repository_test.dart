import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:organizacional/data/repository.dart';
import 'package:organizacional/data/supabase_shopping_repository.dart';
import 'package:organizacional/domain/shopping.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Sent {
  _Sent(this.method, this.url, this.body);
  final String method;
  final Uri url;
  final Object? body;
}

SupabaseClient _client(List<_Sent> sent, {int status = 201, String reply = '[]'}) {
  final mock = MockClient((http.Request req) async {
    sent.add(_Sent(req.method, req.url, req.body.isEmpty ? null : jsonDecode(req.body)));
    return http.Response(reply, status, request: req, headers: {'content-type': 'application/json'});
  });
  return SupabaseClient('http://localhost:54321', 'anon', httpClient: mock);
}

void main() {
  test('addItem sem seção não manda a coluna section (o gatilho decide)', () async {
    final sent = <_Sent>[];
    await SupabaseShoppingRepository(_client(sent)).addItem(listId: 'l1', name: ' Leite ', quantity: '2');
    expect(sent.single.method, 'POST');
    expect(sent.single.url.path, '/rest/v1/shopping_items');
    expect(sent.single.body, {'list_id': 'l1', 'name': 'Leite', 'quantity': '2'});
  });

  test('addItem com seção manda o nome da seção', () async {
    final sent = <_Sent>[];
    await SupabaseShoppingRepository(_client(sent))
        .addItem(listId: 'l1', name: 'Pão', section: ShopSection.padaria);
    expect((sent.single.body as Map)['section'], 'padaria');
  });

  test('updateItem sempre manda seção válida', () async {
    final sent = <_Sent>[];
    final item = ShoppingItem(id: 'i1', listId: 'l1', name: 'Leite', createdAt: DateTime(2026));
    await SupabaseShoppingRepository(_client(sent, status: 204))
        .updateItem(item.copyWith(section: ShopSection.frios, quantity: '1 L'));
    expect(sent.single.method, 'PATCH');
    expect(sent.single.url.queryParameters['id'], 'eq.i1');
    expect((sent.single.body as Map)['section'], 'frios');
    expect((sent.single.body as Map).containsKey('list_id'), isFalse);
  });

  test('finishShopping apaga só os marcados da lista e conta pela resposta', () async {
    final sent = <_Sent>[];
    final n = await SupabaseShoppingRepository(_client(sent, status: 200, reply: '[{"id":"a"},{"id":"b"}]'))
        .finishShopping('l1');
    expect(n, 2);
    expect(sent.single.method, 'DELETE');
    expect(sent.single.url.queryParameters['list_id'], 'eq.l1');
    expect(sent.single.url.queryParameters['checked'], 'eq.true');
  });

  test('ensureDefaultList devolve a existente sem criar', () async {
    final sent = <_Sent>[];
    final l = await SupabaseShoppingRepository(_client(sent,
            status: 200, reply: '[{"id":"l1","name":"Farmácia","position":0,"section_order":null}]'))
        .ensureDefaultList();
    expect(l.name, 'Farmácia');
    expect(sent.map((s) => s.method), ['GET']);
  });

  test('ensureDefaultList cria Mercado quando não há lista', () async {
    final sent = <_Sent>[];
    final mock = MockClient((req) async {
      sent.add(_Sent(req.method, req.url, req.body.isEmpty ? null : jsonDecode(req.body)));
      final body = req.method == 'GET'
          ? '[]'
          : '{"id":"l9","name":"Mercado","position":0,"section_order":null}';
      return http.Response(body, req.method == 'GET' ? 200 : 201,
          request: req, headers: {'content-type': 'application/json'});
    });
    final db = SupabaseClient('http://localhost:54321', 'anon', httpClient: mock);
    final l = await SupabaseShoppingRepository(db).ensureDefaultList();
    expect(l.id, 'l9');
    expect(sent.last.method, 'POST');
    expect((sent.last.body as Map)['name'], 'Mercado');
  });

  test('erro duplicado do Postgres vira RepositoryException.duplicate', () async {
    final sent = <_Sent>[];
    final repo = SupabaseShoppingRepository(_client(sent,
        status: 409, reply: '{"code":"23505","message":"duplicate key","details":null,"hint":null}'));
    await expectLater(
      repo.upsertList(const ShoppingList(id: 'x', name: 'Mercado')),
      throwsA(isA<RepositoryException>().having((e) => e.duplicate, 'duplicate', true)),
    );
  });
}
