import 'dart:async';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../data/repository.dart';
import '../../domain/ids.dart';
import '../../domain/note.dart';
import '../../domain/space.dart';
import '../../domain/wikilinks.dart';
import '../../ui/common.dart';
import '../../ui/org_theme.dart';
import '../import/importer.dart' show driveFileIdFromLink, driveLinkFileName, driveLinkInBody;
import '../samsung_notes/edit_in_samsung_notes.dart';
import '../samsung_notes/folder_sync.dart' show samsungSpaceName;
import '../samsung_notes/samsung_platform.dart';
import 'markdown_bridge.dart';
import 'rich_note_editor.dart';
import '../../app/back_navigation.dart';

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
  // Mostra o Markdown cru (TextField) em vez do editor rico.
  bool _markdownMode = false;
  // A nota tem conteúdo que o editor visual não preserva (tabela, HTML…).
  bool _richUnsafe = false;
  // Muda para recriar o editor rico a partir de `_body` (volta do modo
  // Markdown ou atualização remota).
  int _editorEpoch = 0;
  String? _saveError;
  String? _remoteNotice;
  bool _saving = false;
  bool _saveAgain = false;
  bool _disposed = false;
  bool _deleted = false;
  // Nota recém-criada ("Sem título…" e vazia): foca o título com tudo selecionado.
  bool _focusTitle = false;
  // "Editar no Samsung Notes": baixando; erro do download; ou o aviso de que nenhum app abriu o arquivo.
  bool _editing = false;
  String? _editError;
  bool _editNotOpened = false;

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
    final messenger = ScaffoldMessenger.maybeOf(context);
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
    final restore = _draftNote(note);
    _deleted = true;
    try {
      await _repo.deleteNote(note.id);
      _drafts.take(note.id);
      if (context.mounted) context.popOrGo('/notas');
      showUndo(messenger, 'Nota excluída', () => _repo.upsertNote(restore));
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

  /// Link do Drive quando a nota é uma nota-link criada pela sincronização do Samsung Notes.
  String? _samsungDriveLink(Note note) {
    final spaces = ref.watch(spacesProvider).value ?? const <Space>[];
    final space = spaces.where((s) => s.id == note.spaceId).firstOrNull;
    if (space == null || normalizeTitle(space.name) != normalizeTitle(samsungSpaceName)) return null;
    return driveLinkInBody(note.body);
  }

  bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Baixa o `.sdocx` do Drive e o entrega ao Samsung Notes (que o importa como nota editável).
  Future<void> _editInSamsungNotes(String fileId, String fileName) async {
    if (_editing) return;
    setState(() {
      _editing = true;
      _editError = null;
      _editNotOpened = false;
    });
    final result = await ref.read(samsungEditorProvider).edit(fileId: fileId, fileName: fileName);
    if (!mounted) return;
    setState(() {
      _editing = false;
      _editError = result.outcome == EditOutcome.failed ? result.message : null;
      _editNotOpened = result.outcome == EditOutcome.notOpened;
    });
  }

  Widget _samsungActions(String link, String body) {
    final installed = ref.watch(samsungNotesInstalledProvider).value ?? false;
    final fileName = driveLinkFileName(body);
    final fileId = driveFileIdFromLink(link);
    final canEdit =
        installed && _isAndroid && fileId != null && fileName != null && fileName.toLowerCase().endsWith('.sdocx');
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const Key('samsung-open-drive'),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Abrir no Drive'),
                onPressed: () => ref.read(linkOpenerProvider)(Uri.parse(link)),
              ),
              if (installed)
                OutlinedButton.icon(
                  key: const Key('samsung-open-app'),
                  icon: const Icon(Icons.edit_note, size: 18),
                  label: const Text('Abrir Samsung Notes'),
                  onPressed: () => ref.read(samsungNotesPlatformProvider).open(),
                ),
              if (canEdit)
                OutlinedButton.icon(
                  key: const Key('edit-in-samsung-notes'),
                  icon: _editing
                      ? const SizedBox(
                          key: Key('edit-in-samsung-progress'),
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.edit, size: 18),
                  label: Text(_editing ? 'Baixando…' : 'Editar no Samsung Notes'),
                  onPressed: _editing ? null : () => _editInSamsungNotes(fileId, fileName),
                ),
            ],
          ),
          if (_editError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_editError!, key: const Key('edit-in-samsung-error'), style: TextStyle(color: theme.colorScheme.error)),
            ),
          if (_editNotOpened)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Não encontrei um app para abrir este arquivo.',
                    key: const Key('edit-in-samsung-notice'),
                    style: theme.textTheme.bodySmall,
                  ),
                  TextButton(
                    key: const Key('edit-in-samsung-open-drive'),
                    onPressed: () => ref.read(linkOpenerProvider)(Uri.parse(link)),
                    child: const Text('Abrir no Drive'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody(
      BuildContext context, ThemeData theme, List<Note> all, List<Note> backlinks) {
    final samsungLink = _note == null ? null : _samsungDriveLink(_note!);
    final header = <Widget>[
      TextField(
        key: const Key('note-title'),
        controller: _title,
        autofocus: _focusTitle,
        textCapitalization: TextCapitalization.sentences,
        onChanged: (_) => _changed(),
        style: theme.textTheme.headlineMedium,
        decoration: const InputDecoration.collapsed(hintText: 'Título'),
      ),
      if (samsungLink != null) _samsungActions(samsungLink, _note!.body),
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
            style: TextStyle(color: context.org.accentText),
          ),
        ),
      if (_richUnsafe && _markdownMode)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Esta nota tem formatação que o editor visual não preserva (tabelas, HTML…); ela é editada como Markdown.',
            key: const Key('rich-unsafe-notice'),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      const SizedBox(height: 16),
    ];
    final backlinkTiles = <Widget>[
      if (backlinks.isNotEmpty) ...[
        const SectionHeader('Mencionada em'),
        for (final n in backlinks)
          ListTile(
            leading: const Icon(Icons.link),
            title: Text(n.title),
            onTap: () => context.push('/nota/${n.id}'),
          ),
      ],
    ];

    if (!_preview && !_markdownMode) {
      // O editor rico precisa de altura limitada (ele rola por conta própria),
      // então fica num Expanded; os backlinks vão no rodapé dele.
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...header,
            Expanded(
              child: KeyedSubtree(
                key: ValueKey(_editorEpoch),
                child: RichNoteEditor(
                  key: const Key('rich-editor'),
                  initialMarkdown: _body.text,
                  onChanged: (md) {
                    _body.text = md;
                    _changed();
                  },
                  onWikiLink: (title) =>
                      _openLink('wiki:${encodeWikiTarget(title)}', all),
                  footer: backlinkTiles.isEmpty
                      ? const SizedBox(height: 48)
                      : Column(children: [...backlinkTiles, const SizedBox(height: 48)]),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 48),
      children: [
        ...header,
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
        ...backlinkTiles,
      ],
    );
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
          if (draft == null && content.title.startsWith('Sem título') && content.body.isEmpty) {
            _focusTitle = true;
            _title.selection = TextSelection(baseOffset: 0, extentOffset: content.title.length);
          }
          _richUnsafe = !canRoundTripMarkdown(content.body);
          _markdownMode = _richUnsafe;
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
            _richUnsafe = !canRoundTripMarkdown(current.body);
            if (_richUnsafe) _markdownMode = true;
            _editorEpoch++;
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
              key: const Key('toggle-markdown'),
              tooltip: _markdownMode ? 'Ver editor' : 'Ver como Markdown',
              icon: Icon(_markdownMode ? Icons.edit_note : Icons.code),
              onPressed: () {
                if (_markdownMode && !canRoundTripMarkdown(_body.text)) {
                  showError(context,
                      'Esta nota tem formatação (como tabelas ou HTML) que o editor visual não preserva. Edite como Markdown.');
                  return;
                }
                setState(() {
                if (_markdownMode) _editorEpoch++;
                _markdownMode = !_markdownMode;
                _preview = false;
              });
              },
            ),
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
        body: _buildBody(context, theme, all, backlinks),
      );
    });
  }
}
