import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../data/repository.dart';
import '../../domain/ids.dart';
import '../../domain/note.dart';
import '../../domain/wikilinks.dart';
import '../../ui/common.dart';

class NoteScreen extends ConsumerStatefulWidget {
  const NoteScreen({super.key, required this.noteId});

  final String noteId;

  @override
  ConsumerState<NoteScreen> createState() => _NoteScreenState();
}

class _NoteScreenState extends ConsumerState<NoteScreen> {
  late final Repository _repo;
  late final NoteDrafts _drafts;
  final _title = TextEditingController();
  final _body = TextEditingController();
  Note? _note;
  Timer? _debounce;
  bool _preview = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _repo = ref.read(repositoryProvider);
    _drafts = ref.read(noteDraftsProvider);
  }

  @override
  void dispose() {
    if (_debounce?.isActive ?? false) {
      _debounce!.cancel();
      final pending = _edited();
      if (pending != null) {
        unawaited(_repo.upsertNote(pending).catchError((Object _) => _drafts.put(pending)));
      }
    }
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Note? _edited() {
    final note = _note;
    final title = _title.text.trim();
    if (note == null || title.isEmpty) return null;
    return note.copyWith(title: title, body: _body.text);
  }

  void _changed() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), _save);
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _saveError = 'O título não pode ficar vazio.');
      return;
    }
    final updated = _edited();
    if (updated == null) return;
    try {
      await _repo.upsertNote(updated);
      _note = updated;
      if (mounted) setState(() => _saveError = null);
    } on RepositoryException catch (e) {
      if (mounted) {
        setState(() => _saveError = e.duplicate
            ? 'Já existe uma nota com esse título.'
            : 'Não foi possível salvar. Suas alterações continuam aqui.');
      }
    }
  }

  Future<void> _openLink(String? href, List<Note> notes) async {
    if (href == null || !href.startsWith('wiki:')) return;
    final target = Uri.decodeComponent(href.substring('wiki:'.length));
    final existing = resolveWikiLink(target, notes);
    if (existing != null) {
      context.go('/nota/${existing.id}');
      return;
    }
    final created = Note(id: newId(), title: target, spaceId: _note?.spaceId);
    try {
      await _repo.upsertNote(created);
      if (mounted) context.go('/nota/${created.id}');
    } on RepositoryException {
      if (mounted) setState(() => _saveError = 'Não foi possível criar a nota “$target”.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final notes = ref.watch(notesProvider);
    return asyncView(notes, (all) {
      final current = all.where((n) => n.id == widget.noteId).firstOrNull;
      if (_note == null && current != null) {
        final draft = _drafts.take(current.id);
        _note = draft ?? current;
        _title.text = _note!.title;
        _body.text = _note!.body;
        if (draft != null) {
          _saveError = 'Alterações não salvas foram recuperadas. Edite para tentar salvar de novo.';
        }
      }
      final note = _note;
      if (note == null) {
        return Scaffold(
          appBar: AppBar(),
          body: const Center(child: EmptyHint('Nota não encontrada.')),
        );
      }
      final theme = Theme.of(context);
      final backlinks = backlinksFor(note.copyWith(title: _title.text), all);
      return Scaffold(
        appBar: AppBar(
          actions: [
            IconButton(
              key: const Key('toggle-preview'),
              tooltip: _preview ? 'Editar' : 'Visualizar',
              icon: Icon(_preview ? Icons.edit_outlined : Icons.visibility_outlined),
              onPressed: () => setState(() => _preview = !_preview),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 48),
          children: [
            TextField(
              key: const Key('note-title'),
              controller: _title,
              onChanged: (_) => _changed(),
              style: theme.textTheme.headlineSmall,
              decoration: const InputDecoration.collapsed(hintText: 'Título'),
            ),
            if (_saveError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _saveError!,
                  key: const Key('save-error'),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            const SizedBox(height: 16),
            if (_preview)
              MarkdownBody(
                data: wikiLinksToMarkdown(_body.text),
                onTapLink: (text, href, title) => _openLink(href, all),
              )
            else
              TextField(
                key: const Key('note-body'),
                controller: _body,
                onChanged: (_) => _changed(),
                maxLines: null,
                minLines: 12,
                keyboardType: TextInputType.multiline,
                decoration: const InputDecoration.collapsed(
                  hintText: 'Escreva em Markdown. Use [[Título]] para ligar notas.',
                ),
              ),
            if (backlinks.isNotEmpty) ...[
              const SectionHeader('Mencionada em'),
              for (final n in backlinks)
                ListTile(
                  leading: const Icon(Icons.link),
                  title: Text(n.title),
                  onTap: () => context.go('/nota/${n.id}'),
                ),
            ],
          ],
        ),
      );
    });
  }
}
