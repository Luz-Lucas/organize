@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/repository.dart';
import 'package:organizacional/data/supabase_repository.dart';
import 'package:organizacional/domain/ids.dart';
import 'package:organizacional/domain/note.dart';
import 'package:organizacional/domain/space.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  final url = Platform.environment['SUPABASE_URL'];
  final key = Platform.environment['SUPABASE_ANON_KEY'];
  final skip = url == null || key == null ? 'defina SUPABASE_URL e SUPABASE_ANON_KEY' : null;
  late SupabaseRepository repo;

  setUpAll(() async {
    if (skip != null) return;
    final client = SupabaseClient(
      url!,
      key!,
      authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
    );
    await client.auth.signUp(
      email: 'teste-${DateTime.now().microsecondsSinceEpoch}@local.test',
      password: 'senha-de-teste-123',
    );
    repo = SupabaseRepository(client);
  });

  test('espaço criado chega pelo stream realtime', () async {
    final space = Space(id: newId(), name: 'Integração', kind: SpaceKind.materia);
    await repo.upsertSpace(space);
    final list = await repo
        .watchSpaces()
        .firstWhere((l) => l.any((s) => s.id == space.id))
        .timeout(const Duration(seconds: 10));
    expect(list.firstWhere((s) => s.id == space.id), space);
  }, skip: skip);

  test('título duplicado vira RepositoryException(duplicate: true)', () async {
    final title = 'Duplicada ${newId()}';
    await repo.upsertNote(Note(id: newId(), title: title));
    await expectLater(
      repo.upsertNote(Note(id: newId(), title: title.toUpperCase())),
      throwsA(isA<RepositoryException>().having((e) => e.duplicate, 'duplicate', isTrue)),
    );
  }, skip: skip);
}
