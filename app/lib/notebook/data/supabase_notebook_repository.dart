import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/repository.dart';
import '../../domain/ids.dart';
import '../core/notebook_core.dart';
import 'notebook_page.dart';
import 'notebook_repository.dart';

/// `note_pages` no Supabase.
///
/// Regras do banco que moldam este código:
/// * `unique (note_id, idx)` é **deferrable**, então não serve de alvo de `on conflict`:
///   nada aqui usa `upsert`; é sempre insert ou update separados.
/// * `version` não tem trigger: a versão otimista é do cliente
///   (`update … set version = v + 1 where id = … and version = v`).
/// * Cada requisição do PostgREST é uma transação; por isso a reindexação
///   (reordenar, apagar, inserir no meio) escolhe uma ordem de updates que nunca colide.
class SupabaseNotebookRepository implements NotebookRepository {
  SupabaseNotebookRepository(
    this._db, {
    DateTime Function()? now,
    this.touchInterval = const Duration(seconds: 60),
  }) : _now = now ?? DateTime.now;

  final SupabaseClient _db;
  final DateTime Function() _now;

  /// Intervalo mínimo entre dois "toques" em `notes.updated_at` do mesmo caderno.
  /// Cada toque vira um evento de realtime da tabela `notes` para **todas** as telas
  /// que listam notas (e para a rota do caderno), então tocar a cada save (1,5 s)
  /// reconstruía o app inteiro durante a escrita.
  final Duration touchInterval;

  final _lastTouch = <String, DateTime>{};
  final _touchSkipped = <String>{};

  static const _maxSaveAttempts = 12;
  static const _parkBase = 1000000;

  Future<T> _guard<T>(Future<T> Function() op) async {
    try {
      return await op();
    } on PostgrestException catch (e) {
      throw NotebookRepositoryException(
        e.message,
        kind: NotebookRepositoryException.kindOfCode(e.code),
        code: e.code,
        duplicate: e.code == '23505',
      );
    } on RepositoryException {
      rethrow;
    } on PageDecodeException catch (e) {
      // Ao mesclar num conflito, o dado do servidor é de uma versão mais nova do app.
      throw NotebookRepositoryException(e.message, kind: NotebookErrorKind.newerFormat);
    } catch (e) {
      throw NotebookRepositoryException('Falha de conexão: $e');
    }
  }

  SupabaseQueryBuilder get _pages => _db.from('note_pages');

  List<NotebookPage> _rows(List<Map<String, dynamic>> rows) => [for (final r in rows) NotebookPage.fromMap(r)];

  @override
  Stream<List<NotebookPage>> watchPages(String noteId) => _db
      .from('note_pages')
      .stream(primaryKey: ['id'])
      .eq('note_id', noteId)
      .order('idx', ascending: true)
      .map(_rows);

  @override
  Future<List<NotebookPage>> listPages(String noteId) => _guard(() async =>
      _rows(await _pages.select().eq('note_id', noteId).order('idx', ascending: true)));

  @override
  Future<NotebookPage?> firstPage(String noteId) => _guard(() async {
        final rows = _rows(await _pages.select().eq('note_id', noteId).order('idx', ascending: true).limit(1));
        return rows.firstOrNull;
      });

  @override
  Future<Map<String, String>> recognizedTextByNote() => _guard(() async {
        final rows = await _pages.select('note_id,idx,recognized_text').neq('recognized_text', '').order('idx', ascending: true);
        final out = <String, List<String>>{};
        for (final r in rows) {
          out.putIfAbsent(r['note_id'] as String, () => []).add(r['recognized_text'] as String);
        }
        return {for (final e in out.entries) e.key: e.value.join('\n')};
      });

  Future<NotebookPage?> _byId(String id) async {
    final rows = _rows(await _pages.select().eq('id', id).limit(1));
    return rows.firstOrNull;
  }

  Future<int> _nextIdx(String noteId) async {
    final rows = await _pages.select('idx').eq('note_id', noteId).order('idx', ascending: false).limit(1);
    return rows.isEmpty ? 0 : (rows.first['idx'] as num).toInt() + 1;
  }

  /// Insere no fim; se outro aparelho tomou o idx no meio tempo (23505), tenta de novo.
  Future<NotebookPage> _insertAtEnd(NotebookPage page) async {
    for (var attempt = 0; attempt < _maxSaveAttempts; attempt++) {
      final row = page.copyWith(idx: await _nextIdx(page.noteId));
      try {
        final rows = await _pages.insert(row.toInsertMap()).select();
        return NotebookPage.fromMap(rows.first);
      } on PostgrestException catch (e) {
        if (e.code != '23505') rethrow;
        final existing = await _byId(page.id);
        if (existing != null) return existing; // outra tentativa nossa já gravou
      }
    }
    throw const RepositoryException('Não foi possível criar a página (conflito de posição).');
  }

  @override
  Future<NotebookPage> addPage(
    String noteId, {
    PageBackground background = PageBackground.lined,
    String? id,
    int? at,
  }) =>
      _guard(() async {
        final pageId = id ?? newId();
        final existing = await _byId(pageId);
        if (existing != null) return existing;
        final created = await _insertAtEnd(NotebookPage(id: pageId, noteId: noteId, idx: 0, background: background));
        if (at == null) return created;
        final order = [for (final p in await _list(noteId)) p.id]..remove(pageId);
        order.insert(at.clamp(0, order.length), pageId);
        await _reindex(noteId, order);
        return (await _byId(pageId)) ?? created;
      });

  Future<List<NotebookPage>> _list(String noteId) async =>
      _rows(await _pages.select('id,note_id,idx').eq('note_id', noteId).order('idx', ascending: true));

  @override
  Future<NotebookPage> savePage(NotebookPage page) => _guard(() async {
        var local = page;
        for (var attempt = 0; attempt < _maxSaveAttempts; attempt++) {
          final updated = await _pages
              // O fundo não entra aqui: quem troca o fundo é o setBackground.
              .update({
                'data': local.data,
                if (local.withRecognizedText) 'recognized_text': local.recognizedText,
                'version': local.version + 1,
              })
              .eq('id', local.id)
              .eq('version', local.version)
              .select();
          if (updated.isNotEmpty) {
            await _touchNote(local.noteId);
            return NotebookPage.fromMap(updated.first);
          }
          final remote = await _byId(local.id);
          if (remote == null) {
            // Apagada em outro aparelho: recria no fim para não perder a tinta.
            final created = await _insertAtEnd(local.copyWith(version: 1));
            await _touchNote(local.noteId);
            return created;
          }
          // Em conflito que acrescentou tinta de outro aparelho, o texto reconhecido deste
          // aparelho não vale para o documento mesclado: não é gravado (o aparelho transcreve
          // de novo e envia no save seguinte). Se nada foi acrescentado, ele continua valendo.
          final merged = mergePageData(remote.data, local.data);
          local = local.copyWith(
            version: remote.version,
            data: merged,
            withRecognizedText: local.withRecognizedText && merged == local.data,
          );
        }
        throw const RepositoryException('Muitos conflitos ao salvar a página; tente de novo.');
      });

  /// Sobe a nota na lista, no máximo uma vez por [touchInterval] por caderno (o
  /// toque adiado fica anotado e [touchNote] o faz ao sair). Falha aqui não pode
  /// perder o salvamento da página, e um toque que falhou não conta como feito.
  Future<void> _touchNote(String noteId, {bool force = false}) async {
    final t = _now();
    final last = _lastTouch[noteId];
    if (!force && last != null && t.difference(last) < touchInterval) {
      _touchSkipped.add(noteId);
      return;
    }
    try {
      await _db.from('notes').update({'updated_at': t.toUtc().toIso8601String()}).eq('id', noteId);
      _lastTouch[noteId] = t;
      _touchSkipped.remove(noteId);
    } catch (_) {}
  }

  @override
  Future<void> touchNote(String noteId) async {
    if (_touchSkipped.contains(noteId)) await _touchNote(noteId, force: true);
  }

  @override
  Future<void> setBackground(String pageId, PageBackground background) =>
      _guard(() async => await _pages.update({'background': background.name}).eq('id', pageId));

  @override
  Future<void> deletePage(String pageId) => _guard(() async {
        final page = await _byId(pageId);
        if (page == null) return;
        // Apagar imagens órfãs do Storage é feito só quando o usuário apaga a imagem/nota (API do Storage).
        await _pages.delete().eq('id', pageId);
        final rest = await _list(page.noteId);
        await _reindex(page.noteId, [for (final p in rest) p.id]);
      });

  @override
  Future<NotebookPage> duplicatePage(String pageId) => _guard(() async {
        final src = await _byId(pageId);
        if (src == null) throw const RepositoryException('Página não encontrada.');
        final copy = await _insertAtEnd(NotebookPage(
          id: newId(),
          noteId: src.noteId,
          idx: 0,
          background: src.background,
          data: src.data,
          recognizedText: src.recognizedText,
        ));
        final order = [for (final p in await _list(src.noteId)) p.id]..remove(copy.id);
        order.insert((order.indexOf(src.id) + 1).clamp(0, order.length), copy.id);
        await _reindex(src.noteId, order);
        return (await _byId(copy.id)) ?? copy;
      });

  @override
  Future<void> reorder(String noteId, List<String> pageIds) => _guard(() async {
        final current = {for (final p in await _list(noteId)) p.id};
        if (pageIds.length != current.length || !current.containsAll(pageIds) || pageIds.toSet().length != pageIds.length) {
          throw const RepositoryException('A nova ordem não corresponde às páginas do caderno.');
        }
        await _reindex(noteId, pageIds);
      });

  /// Leva cada página de [order] para o idx = posição, mexendo só nas que mudam.
  /// Cada update é uma transação e a unique é conferida no fim dela, então a
  /// ordem importa: deslocamentos só para a esquerda andam de cima para baixo,
  /// só para a direita de baixo para cima; trocas mistas "estacionam" as páginas
  /// em idx altos primeiro.
  Future<void> _reindex(String noteId, List<String> order) async {
    final now = {for (final p in await _list(noteId)) p.id: p.idx};
    final changed = <(String, int, int)>[
      for (var i = 0; i < order.length; i++)
        if (now[order[i]] != null && now[order[i]] != i) (order[i], now[order[i]]!, i),
    ];
    if (changed.isEmpty) return;
    Future<void> setIdx(String id, int idx) async => await _pages.update({'idx': idx}).eq('id', id);
    if (changed.every((c) => c.$3 < c.$2)) {
      for (final c in [...changed]..sort((a, b) => a.$3.compareTo(b.$3))) {
        await setIdx(c.$1, c.$3);
      }
    } else if (changed.every((c) => c.$3 > c.$2)) {
      for (final c in [...changed]..sort((a, b) => b.$3.compareTo(a.$3))) {
        await setIdx(c.$1, c.$3);
      }
    } else {
      for (final c in changed) {
        await setIdx(c.$1, _parkBase + c.$3);
      }
      for (final c in changed) {
        await setIdx(c.$1, c.$3);
      }
    }
  }
}
