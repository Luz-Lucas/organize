import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/back_navigation.dart';
import '../../app/providers.dart';
import '../../data/drive_repository.dart';
import '../../data/file_picker_service.dart';
import '../../data/repository.dart';
import '../../domain/drive.dart';
import '../../ui/common.dart';
import '../../ui/org_theme.dart';
import '../../ui/org_widgets.dart';
import 'drive_dialogs.dart';
import 'share_file_sheet.dart';

IconData iconForDriveItem(DriveItem item) {
  if (item.isFolder) return Icons.folder_outlined;
  final m = item.mimeType;
  if (m == 'application/pdf') return Icons.picture_as_pdf_outlined;
  if (m.startsWith('image/')) return Icons.image_outlined;
  if (m.startsWith('video/')) return Icons.movie_outlined;
  if (m.startsWith('audio/')) return Icons.audiotrack_outlined;
  if (m.contains('spreadsheet') || m.contains('excel')) return Icons.table_chart_outlined;
  if (m.contains('presentation') || m.contains('powerpoint')) return Icons.slideshow_outlined;
  if (m.contains('word') || m.contains('document') || m == 'application/msword') return Icons.description_outlined;
  if (m.startsWith('text/')) return Icons.article_outlined;
  return Icons.insert_drive_file_outlined;
}

/// `/documentos`: navegação pelas pastas do Google Drive (Organizacional ou Meu Drive).
class DocumentsScreen extends ConsumerStatefulWidget {
  const DocumentsScreen({super.key});

  @override
  ConsumerState<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends ConsumerState<DocumentsScreen> {
  final _searchCtrl = TextEditingController();

  bool _myDrive = false;
  List<DriveFolder> _trail = const [];
  List<DriveItem> _items = const [];
  bool _loading = false;
  Object? _error;
  bool _loadedOnce = false;

  String _query = '';
  List<DriveItem>? _results;

  String? _uploadName;
  double? _uploadFraction;

  DriveRepository get _repo => ref.read(driveRepositoryProvider);
  bool get _searching => _results != null;
  bool get _atRoot => _trail.length <= 1;

  @override
  void initState() {
    super.initState();
    ref.listenManual(driveStateProvider, (prev, next) {
      final ok = next.value?.status == DriveStatus.ok;
      if (ok && !_loadedOnce) {
        _loadedOnce = true;
        _load(null);
      }
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load(String? folderId, {List<DriveFolder>? keepTrail}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final listing = await _repo.list(folderId: folderId);
      if (!mounted) return;
      setState(() {
        _items = listing.items;
        _trail = [...?keepTrail, listing.folder];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _reload() async {
    if (_trail.isEmpty) return _load(_myDrive ? 'root' : null);
    await _load(_trail.last.id, keepTrail: _trail.sublist(0, _trail.length - 1));
    if (_searching && _query.isNotEmpty) await _runSearch(_query);
  }

  void _enter(DriveItem folder) => _load(folder.id, keepTrail: _trail);

  void _goTo(int index) => _load(_trail[index].id, keepTrail: _trail.sublist(0, index));

  void _switchRoot(bool myDrive) {
    if (myDrive == _myDrive) return;
    _clearSearch();
    setState(() => _myDrive = myDrive);
    _load(myDrive ? 'root' : null);
  }

  void _clearSearch() {
    _searchCtrl.clear();
    setState(() {
      _query = '';
      _results = null;
    });
  }

  Future<void> _runSearch(String q) async {
    final text = q.trim();
    if (text.isEmpty) return _clearSearch();
    setState(() {
      _query = text;
      _loading = true;
      _error = null;
    });
    try {
      final r = await _repo.search(text);
      if (!mounted) return;
      setState(() {
        _results = r;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _back() {
    if (_searching) {
      _clearSearch();
    } else if (!_atRoot) {
      _goTo(_trail.length - 2);
    } else {
      context.popOrGo('/mais');
    }
  }

  void _fail(Object e, String fallback) {
    if (!mounted) return;
    showError(context, e is RepositoryException ? e.message : fallback);
  }

  Future<void> _open(DriveItem item) async {
    if (item.isFolder) {
      if (_searching) _clearSearch();
      return _enter(item);
    }
    final link = item.webViewLink;
    final uri = link == null ? null : Uri.tryParse(link);
    if (uri == null) return showError(context, 'Este arquivo não tem link para abrir.');
    final opened = await ref.read(linkOpenerProvider)(uri);
    if (!opened && mounted) showError(context, 'Não consegui abrir o arquivo.');
  }

  Future<void> _newFolder() async {
    final name = await askText(
      context,
      title: 'Nova pasta',
      label: 'Nome da pasta',
      fieldKey: const Key('doc-folder-field'),
      okKey: const Key('doc-folder-ok'),
      okLabel: 'Criar',
    );
    if (name == null) return;
    try {
      await _repo.createFolder(_trail.last.id, name);
      await _reload();
    } catch (e) {
      _fail(e, 'Não foi possível criar a pasta.');
    }
  }

  Future<void> _rename(DriveItem item) async {
    final name = await askText(
      context,
      title: 'Renomear',
      label: 'Novo nome',
      initial: item.name,
      fieldKey: const Key('doc-rename-field'),
      okKey: const Key('doc-rename-ok'),
      okLabel: 'Renomear',
    );
    if (name == null || name == item.name) return;
    try {
      await _repo.rename(item.id, name);
      await _reload();
    } catch (e) {
      _fail(e, 'Não foi possível renomear.');
    }
  }

  Future<void> _move(DriveItem item) async {
    final dest = await pickDriveFolder(context, repo: _repo, startFolderId: _trail.isEmpty ? null : _trail.last.id, excludeId: item.id);
    if (dest == null) return;
    try {
      await _repo.move(item.id, dest);
      await _reload();
    } catch (e) {
      _fail(e, 'Não foi possível mover.');
    }
  }

  Future<void> _trash(DriveItem item) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await _repo.trash(item.id);
      await _reload();
    } catch (e) {
      return _fail(e, 'Não foi possível mover para a lixeira.');
    }
    showUndo(messenger, '"${item.name}" foi para a lixeira', () async {
      try {
        await _repo.restore(item.id);
      } finally {
        if (mounted) await _reload();
      }
    });
  }

  Future<void> _share(DriveItem item) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ShareFileSheet(repo: _repo, item: item),
    );
    if (mounted) await _reload();
  }

  Future<void> _showActions(DriveItem item) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          key: const Key('doc-actions'),
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis), dense: true),
            ListTile(
              key: const Key('doc-act-open'),
              leading: const Icon(Icons.open_in_new),
              title: Text(item.isFolder ? 'Abrir pasta' : 'Abrir no Drive'),
              onTap: () => Navigator.pop(ctx, 'open'),
            ),
            ListTile(
              key: const Key('doc-act-rename'),
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('Renomear'),
              onTap: () => Navigator.pop(ctx, 'rename'),
            ),
            ListTile(
              key: const Key('doc-act-move'),
              leading: const Icon(Icons.drive_file_move_outline),
              title: const Text('Mover para…'),
              onTap: () => Navigator.pop(ctx, 'move'),
            ),
            ListTile(
              key: const Key('doc-act-share'),
              leading: const Icon(Icons.person_add_alt_outlined),
              title: const Text('Compartilhar'),
              onTap: () => Navigator.pop(ctx, 'share'),
            ),
            ListTile(
              key: const Key('doc-act-trash'),
              leading: Icon(Icons.delete_outline, color: Theme.of(ctx).colorScheme.error),
              title: const Text('Mover para a lixeira'),
              onTap: () => Navigator.pop(ctx, 'trash'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'open':
        return _open(item);
      case 'rename':
        return _rename(item);
      case 'move':
        return _move(item);
      case 'share':
        return _share(item);
      case 'trash':
        return _trash(item);
    }
  }

  Future<void> _showAdd() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          key: const Key('docs-add-sheet'),
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('docs-new-folder'),
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('Nova pasta'),
              onTap: () => Navigator.pop(ctx, 'folder'),
            ),
            ListTile(
              key: const Key('docs-upload'),
              leading: const Icon(Icons.upload_file_outlined),
              title: const Text('Enviar arquivo'),
              onTap: () => Navigator.pop(ctx, 'upload'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'folder') return _newFolder();
    if (action == 'upload') return _upload();
  }

  Future<void> _upload() async {
    final picked = await ref.read(filePickerProvider).pickFiles();
    if (!mounted || picked.isEmpty) return;
    final big = picked.where((f) => f.size > driveWarnUploadBytes).toList();
    if (big.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          key: const Key('docs-big-dialog'),
          title: const Text('Arquivo grande'),
          content: Text(
            '${big.map((f) => '${f.name} (${formatBytes(f.size)})').join('\n')}\n\n'
            'Arquivos acima de 100 MB demoram e gastam dados. Enviar mesmo assim?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(key: const Key('docs-big-confirm'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Enviar')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    final parent = _trail.last.id;
    var sentFiles = 0;
    final messenger = ScaffoldMessenger.maybeOf(context);
    String? failure;
    for (final f in picked) {
      setState(() {
        _uploadName = f.name;
        _uploadFraction = 0;
      });
      try {
        await _repo.upload(
          parentId: parent,
          name: f.name,
          mimeType: f.mimeType,
          size: f.size,
          data: f.openRead(),
          onProgress: (sent, total) {
            if (mounted) setState(() => _uploadFraction = total == 0 ? 1 : sent / total);
          },
        );
        sentFiles++;
      } on RepositoryException catch (e) {
        failure = e.message;
        break;
      } catch (_) {
        failure = 'Não foi possível enviar ${f.name}.';
        break;
      }
    }
    if (!mounted) return;
    setState(() {
      _uploadName = null;
      _uploadFraction = null;
    });
    await _reload();
    if (!mounted) return;
    messenger
      ?..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(failure ?? '${plural(sentFiles, 'arquivo enviado', 'arquivos enviados')}.'),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(driveStateProvider).value;
    final status = state?.status ?? DriveStatus.notConnected;
    final theme = Theme.of(context);
    final org = context.org;

    Widget body;
    if (status == DriveStatus.notConnected) {
      body = _Notice(
        cardKey: const Key('docs-not-connected'),
        icon: Icons.folder_off_outlined,
        text: 'O Google Drive ainda não está conectado. Conecte em Ajustes para ver e organizar seus documentos aqui.',
        buttonKey: const Key('docs-open-settings'),
        buttonLabel: 'Abrir Ajustes',
        onPressed: () => context.go('/ajustes'),
      );
    } else if (status == DriveStatus.authRequired) {
      body = _Notice(
        cardKey: const Key('docs-auth-required'),
        icon: Icons.lock_reset_outlined,
        text: 'O acesso ao Google Drive expirou. Reconecte em Ajustes.',
        buttonKey: const Key('docs-reconnect'),
        buttonLabel: 'Reconectar',
        onPressed: () => context.go('/ajustes'),
      );
    } else {
      body = _buildBrowser(context, theme, org);
    }

    return PopScope(
      canPop: _atRoot && !_searching,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            key: const Key('docs-back'),
            tooltip: 'Voltar',
            icon: const Icon(Icons.arrow_back),
            onPressed: _back,
          ),
          title: const Text('Documentos'),
        ),
        floatingActionButton: status == DriveStatus.ok && _trail.isNotEmpty
            ? FloatingActionButton(
                key: const Key('docs-fab'),
                tooltip: 'Adicionar',
                onPressed: _showAdd,
                child: const Icon(Icons.add),
              )
            : null,
        body: SafeArea(child: body),
      ),
    );
  }

  Widget _buildBrowser(BuildContext context, ThemeData theme, OrgThemeSpec org) {
    final list = _results ?? _items;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: Text('Organizacional', key: Key('docs-root-org'))),
              ButtonSegment(value: true, label: Text('Meu Drive', key: Key('docs-root-my'))),
            ],
            selected: {_myDrive},
            onSelectionChanged: (s) => _switchRoot(s.first),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            key: const Key('docs-search'),
            controller: _searchCtrl,
            textInputAction: TextInputAction.search,
            onSubmitted: _runSearch,
            decoration: InputDecoration(
              hintText: 'Buscar pelo nome',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searching || _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      key: const Key('docs-search-clear'),
                      tooltip: 'Limpar busca',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: _clearSearch,
                    )
                  : null,
            ),
          ),
        ),
        if (!_searching && _trail.isNotEmpty) _Breadcrumb(trail: _trail, onTap: _goTo),
        if (_uploadFraction != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Enviando $_uploadName…', style: theme.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                LinearProgressIndicator(key: const Key('docs-progress'), value: _uploadFraction),
              ],
            ),
          ),
        if (_loading && _items.isEmpty && _results == null)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (_error != null)
          Expanded(child: _ErrorView(error: _error!, onRetry: _reload))
        else if (list.isEmpty)
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _searching ? 'Nada encontrado.' : 'Esta pasta está vazia.',
                  key: const Key('docs-empty'),
                  style: theme.textTheme.bodyMedium?.copyWith(color: org.inkMuted),
                ),
              ),
            ),
          )
        else
          Expanded(
            child: RefreshIndicator(
              onRefresh: _reload,
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 88),
                itemCount: list.length,
                itemBuilder: (context, i) => _ItemTile(
                  item: list[i],
                  onOpen: () => _open(list[i]),
                  onActions: () => _showActions(list[i]),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({required this.trail, required this.onTap});

  final List<DriveFolder> trail;
  final void Function(int index) onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final org = context.org;
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        reverse: true,
        children: [
          Row(
            children: [
              for (var i = 0; i < trail.length; i++) ...[
                if (i > 0) Icon(Icons.chevron_right, size: 18, color: org.inkMuted),
                TextButton(
                  key: Key('docs-crumb-$i'),
                  onPressed: i == trail.length - 1 ? null : () => onTap(i),
                  style: TextButton.styleFrom(minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 8)),
                  child: Text(
                    trail[i].name,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: i == trail.length - 1 ? FontWeight.w700 : FontWeight.w500,
                      color: i == trail.length - 1 ? org.ink : org.accentText,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item, required this.onOpen, required this.onActions});

  final DriveItem item;
  final VoidCallback onOpen;
  final VoidCallback onActions;

  @override
  Widget build(BuildContext context) {
    final org = context.org;
    final date = item.modifiedTime == null ? null : DateFormat('dd/MM/yyyy', 'pt_BR').format(item.modifiedTime!);
    final parts = [
      if (!item.isFolder && item.size != null) formatBytes(item.size!),
      ?date,
    ];
    return ListTile(
      key: Key('doc-${item.id}'),
      leading: Icon(iconForDriveItem(item), color: item.isFolder ? org.accentText : org.inkMuted),
      title: Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: parts.isEmpty ? null : Text(parts.join(' · ')),
      onTap: onOpen,
      onLongPress: onActions,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (item.shared) Icon(Icons.people_outline, size: 18, color: org.inkMuted),
          IconButton(
            key: Key('doc-menu-${item.id}'),
            tooltip: 'Mais ações',
            icon: const Icon(Icons.more_vert),
            onPressed: onActions,
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.cardKey,
    required this.icon,
    required this.text,
    required this.buttonKey,
    required this.buttonLabel,
    required this.onPressed,
  });

  final Key cardKey;
  final IconData icon;
  final String text;
  final Key buttonKey;
  final String buttonLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final org = context.org;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: OrgCard(
        key: cardKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: org.accentText),
            const SizedBox(height: 8),
            Text(text, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 12),
            FilledButton(key: buttonKey, onPressed: onPressed, child: Text(buttonLabel)),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reconnect = error is DriveException && (error as DriveException).needsReconnect;
    final message = error is RepositoryException ? (error as RepositoryException).message : 'Não foi possível carregar os documentos.';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, key: const Key('docs-error'), textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.error)),
            const SizedBox(height: 12),
            if (reconnect)
              FilledButton(key: const Key('docs-reconnect'), onPressed: () => context.go('/ajustes'), child: const Text('Reconectar'))
            else
              OutlinedButton(key: const Key('docs-retry'), onPressed: onRetry, child: const Text('Tentar de novo')),
          ],
        ),
      ),
    );
  }
}
