import 'package:flutter/material.dart';

import '../../data/drive_repository.dart';
import '../../data/repository.dart';
import '../../domain/drive.dart';
import '../../ui/org_theme.dart';

/// Pede um texto (nome de pasta/arquivo). Devolve o valor sem espaços nas pontas, ou null se cancelou.
Future<String?> askText(
  BuildContext context, {
  required String title,
  required String label,
  required Key fieldKey,
  required Key okKey,
  required String okLabel,
  String initial = '',
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _AskTextDialog(title: title, label: label, fieldKey: fieldKey, okKey: okKey, okLabel: okLabel, initial: initial),
    );

class _AskTextDialog extends StatefulWidget {
  const _AskTextDialog({
    required this.title,
    required this.label,
    required this.fieldKey,
    required this.okKey,
    required this.okLabel,
    required this.initial,
  });

  final String title;
  final String label;
  final Key fieldKey;
  final Key okKey;
  final String okLabel;
  final String initial;

  @override
  State<_AskTextDialog> createState() => _AskTextDialogState();
}

class _AskTextDialogState extends State<_AskTextDialog> {
  late final _ctrl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _ctrl.text.trim();
    if (v.isNotEmpty) Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: TextField(
          key: widget.fieldKey,
          controller: _ctrl,
          autofocus: true,
          maxLength: 255,
          decoration: InputDecoration(labelText: widget.label),
          onSubmitted: (_) => _submit(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(key: widget.okKey, onPressed: _submit, child: Text(widget.okLabel)),
        ],
      );
}

/// Seletor de pasta do Drive. Devolve o id da pasta escolhida, ou null se cancelou.
Future<String?> pickDriveFolder(
  BuildContext context, {
  required DriveRepository repo,
  String? startFolderId,
  String? excludeId,
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _FolderPicker(repo: repo, startFolderId: startFolderId, excludeId: excludeId),
    );

class _FolderPicker extends StatefulWidget {
  const _FolderPicker({required this.repo, this.startFolderId, this.excludeId});

  final DriveRepository repo;
  final String? startFolderId;
  final String? excludeId;

  @override
  State<_FolderPicker> createState() => _FolderPickerState();
}

class _FolderPickerState extends State<_FolderPicker> {
  DriveFolder? _folder;
  List<DriveItem> _folders = const [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _go(widget.startFolderId);
  }

  Future<void> _go(String? id) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final l = await widget.repo.list(folderId: id);
      if (!mounted) return;
      setState(() {
        _folder = l.folder;
        _folders = [for (final i in l.items) if (i.isFolder && i.id != widget.excludeId) i];
        _loading = false;
      });
    } on RepositoryException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final folder = _folder;
    final org = context.org;
    return AlertDialog(
      key: const Key('doc-move-dialog'),
      title: const Text('Mover para…'),
      content: SizedBox(
        width: 360,
        height: 320,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (folder != null && folder.parents.isNotEmpty)
                            IconButton(
                              key: const Key('picker-up'),
                              tooltip: 'Pasta acima',
                              icon: const Icon(Icons.arrow_upward, size: 20),
                              onPressed: () => _go(folder.parents.first),
                            ),
                          Expanded(
                            child: Text(folder?.name ?? '', style: Theme.of(context).textTheme.titleSmall, overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: _folders.isEmpty
                            ? Center(child: Text('Sem subpastas.', style: TextStyle(color: org.inkMuted)))
                            : ListView(
                                children: [
                                  for (final f in _folders)
                                    ListTile(
                                      key: Key('picker-folder-${f.id}'),
                                      dense: true,
                                      leading: Icon(Icons.folder_outlined, color: org.accentText),
                                      title: Text(f.name, overflow: TextOverflow.ellipsis),
                                      onTap: () => _go(f.id),
                                    ),
                                ],
                              ),
                      ),
                    ],
                  ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          key: const Key('doc-move-here'),
          onPressed: folder == null ? null : () => Navigator.pop(context, folder.id),
          child: const Text('Mover para aqui'),
        ),
      ],
    );
  }
}
