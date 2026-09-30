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
  // Último conteúdo confirmado (salvo no repositório, ou o valor do servidor
  // no momento em que a tela abriu). Usado para saber se há edições não
  // salvas (dirty) e para detectar mudanças remotas (I3).
  Note? _lastSaved;
  Timer? _debounce;
  bool _preview = false;
  String? _saveError;
  String? _remoteNotice;
  bool _saving = false;
  bool _saveAgain = false;
  bool _disposed = false;
  bool _deleted = false;

  @override
  void initState() {
    super.initState();
    _repo = ref.read(repositoryProvider);
    _drafts = ref.read(noteDraftsProvider);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _disposed = true;
    if (!_deleted && _dirty) unawaited(_flush());
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  /// Há alterações não refletidas em [_lastSaved]? Um rascunho recuperado
  /// que ainda não foi salvo também conta como dirty.
  bool get _dirty {
    final note = _note;
    if (note == null) return false;
    return _draftNote(note) != _lastSaved;
  }

  /// Nota com o texto atual dos campos. Se o título estiver vazio, mantém o
  /// último título salvo em vez de descartar o corpo editado.
  Note _draftNote(Note base) {
    final title = _title.text.trim();
    return base.copyWith(
      title: title.isEmpty ? (_lastSaved?.title ?? base.title) : title,
      body: _body.text,
    );
  }

  void _changed() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), _save);
  }

  Future<void> _save() async {
    if (_deleted) return;
    if (_title.text.trim().isEmpty) {
      if (!_disposed) setState(() => _saveError = 'O título não pode ficar vazio.');
      return;
    }
    await _flush();
  }

  /// Salva o conteúdo atual. Serializa com qualquer salvamento em andamento:
  /// se o texto mudar enquanto uma gravação está em voo, salva de novo ao
  /// final (nunca duas gravações em paralelo, então a mais recente sempre
  /// vence). Se a tela já foi fechada e a gravação falha, guarda o rascunho
  /// para recuperação na próxima abertura.
  Future<void> _flush() async {
    if (_deleted) return;
    if (_saving) {
      _saveAgain = true;
      return;
    }
    _saving = true;
    try {
      while (true) {
        _saveAgain = false;
        final note = _note;
        if (note == null || _deleted) break;
        final draft = _draftNote(note);
        if (draft == _lastSaved) break;
        try {
          await _repo.upsertNote(draft);
          _note = draft;
          _lastSaved = draft;
          if (!_disposed) {
            setState(() {
              _saveError = null;
              _remoteNotice = null;
            });
          }
        } on RepositoryException catch (e) {
          if (_deleted) {
            // Nota excluída durante a gravação: não guardar rascunho.
          } else if (_disposed) {
            _drafts.put(draft);
          } else {
            setState(() => _saveError = e.duplicate
                ? 'Já existe uma nota com esse título.'
                : 'Não foi possível salvar. Suas alterações continuam aqui.');
          }
        }
        if (!_saveAgain) break;
      }
    } finally {
      _saving = false;
    }
  }

  Future<void> _delete(BuildContext context) async {
    final note = _note;
    if (note == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Excluir “${note.title}”?'),
        content: const Text('Essa ação não pode ser desfeita.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Excluir')),
        ],
      ),
    );
    if (confirmed != true) return;
    _debounce?.cancel();
    _deleted = true;
    try {
      await _repo.deleteNote(note.id);
      _drafts.take(note.id);
      if (context.mounted) context.pop();
    } on RepositoryException {
      _deleted = false;
      if (context.mounted) showError(context, 'Não foi possível excluir a nota.');
    }
  }

  Future<void> _openLink(String? href, List<Note> notes) async {
    if (href == null || !href.startsWith('wiki:')) return;
    final target = Uri.decodeComponent(href.substring('wiki:'.length));
    final existing = resolveWikiLink(target, notes);
    if (existing != null) {
      context.push('/nota/${existing.id}');
      return;
    }
    final created = Note(id: newId(), title: target, spaceId: _note?.spaceId);
    try {
      await _repo.upsertNote(created);
      if (mounted) context.push('/nota/${created.id}');
    } on RepositoryException {
      if (mounted) setState(() => _saveError = 'Não foi possível criar a nota “$target”.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final notes = ref.watch(notesProvider);
    return asyncView(notes, (all) {
      final current = all.where((n) => n.id == widget.noteId).firstOrNull;
      if (current != null) {
        if (_note == null) {
          final draft = _drafts.take(current.id);
          _note = current;
          _lastSaved = current;
          final content = draft ?? current;
          _title.text = content.title;
          _body.text = content.body;
          if (draft != null) {
            _saveError =
                'Alterações não salvas foram recuperadas. Edite para tentar salvar de novo.';
          }
        } else if (current != _lastSaved) {
          // Uma versão mais nova chegou pelo stream (outro dispositivo/aba).
          if (_dirty) {
            _remoteNotice = 'Esta nota foi alterada em outro dispositivo; '
                'suas alterações vão substituí-la ao salvar.';
          } else {
            _note = current;
            _lastSaved = current;
            _title.text = current.title;
            _body.text = current.body;
            _remoteNotice = null;
          }
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
            IconButton(
              key: const Key('delete-note'),
              tooltip: 'Excluir nota',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _delete(context),
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
            if (_remoteNotice != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _remoteNotice!,
                  key: const Key('remote-notice'),
                  style: TextStyle(color: theme.colorScheme.tertiary),
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
                  onTap: () => context.push('/nota/${n.id}'),
                ),
            ],
          ],
        ),
      );
    });
  }
}
