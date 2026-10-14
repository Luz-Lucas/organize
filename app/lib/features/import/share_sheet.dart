import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/drive_repository.dart';
import '../../data/repository.dart';
import '../../data/share_intent_service.dart';
import '../../domain/drive.dart';
import '../../domain/space.dart';
import '../../app/providers.dart';
import '../../ui/org_theme.dart';
import 'importer.dart';

/// Abre a folha "Salvar no Organizacional" para o [content] recebido.
Future<void> showShareSheet(BuildContext context, SharedContent content, {required bool signedIn}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useRootNavigator: true,
      builder: (_) => ShareSheet(content: content, signedIn: signedIn),
    );

/// Texto -> nota; arquivos -> Drive (Organizacional/Importados) + nota com o link.
class ShareSheet extends ConsumerStatefulWidget {
  const ShareSheet({super.key, required this.content, required this.signedIn});

  final SharedContent content;
  final bool signedIn;

  @override
  ConsumerState<ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends ConsumerState<ShareSheet> {
  String? _spaceId; // null = "Importadas"
  bool _saving = false;
  String? _error;

  SharedContent get _c => widget.content;

  Future<void> _save() async {
    final driveState = ref.read(driveStateProvider).value;
    final importer = Importer(repo: ref.read(repositoryProvider), drive: ref.read(driveRepositoryProvider), driveState: driveState);
    final router = GoRouter.maybeOf(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    final summary = ImportSummary();
    String? openId;
    String? textNoteTitle;
    final usable = [for (final f in _c.files) if (importer.driveReady || f.becomesNote) f];
    try {
      if (_c.hasText) {
        final note = await importer.saveText(_c.text!, spaceId: _spaceId);
        summary
          ..notes += 1
          ..noteIds.add(note.id);
        openId = note.id;
        textNoteTitle = note.title;
      }
      if (usable.isNotEmpty) {
        final s = await importer.importFiles(usable, spaceId: _spaceId);
        summary
          ..notes += s.notes
          ..files += s.files
          ..errors.addAll(s.errors)
          ..noteIds.addAll(s.noteIds);
        openId ??= s.noteIds.firstOrNull;
      }
    } on RepositoryException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Não foi possível salvar. Tente de novo.');
    }
    if (!mounted) return;
    if (summary.notes == 0 && summary.files == 0) {
      setState(() {
        _saving = false;
        _error ??= summary.errors.isNotEmpty ? summary.errors.join('\n') : 'Não foi possível salvar. Tente de novo.';
      });
      return;
    }
    final id = openId;
    navigator.pop();
    messenger
      ?..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(usable.isEmpty && textNoteTitle != null ? 'Nota "$textNoteTitle" criada.' : summary.text),
        action: id == null || router == null ? null : SnackBarAction(label: 'Abrir', onPressed: () => router.push('/nota/$id')),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final org = context.org;
    final driveState = ref.watch(driveStateProvider).value;
    final driveReady = driveState?.status == DriveStatus.ok && (driveState?.rootFolderId ?? '').isNotEmpty;
    final spaces = ref.watch(spacesProvider).value ?? const <Space>[];
    final needDrive = _c.files.any((f) => !f.becomesNote);
    final driveMissing = needDrive && !driveReady;
    final canSave = widget.signedIn && (_c.hasText || _c.files.any((f) => f.becomesNote) || (needDrive && driveReady));

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          key: const Key('share-sheet'),
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Salvar no Organize', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            if (_c.hasText)
              Container(
                key: const Key('share-preview'),
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: org.surfaceRaised, borderRadius: BorderRadius.circular(org.radiusSm), border: Border.all(color: org.line)),
                child: Text(_c.text!.trim(), maxLines: 6, overflow: TextOverflow.ellipsis),
              ),
            for (final f in _c.files)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(f.becomesNote ? Icons.article_outlined : Icons.insert_drive_file_outlined, color: org.inkMuted),
                title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(formatBytes(f.size)),
              ),
            const SizedBox(height: 8),
            if (_c.hasText)
              Text('Vira uma nota (título = primeira linha).', style: theme.textTheme.bodySmall?.copyWith(color: org.inkMuted)),
            if (needDrive && driveReady)
              Text(
                'Os arquivos vão para o Drive em Organizacional/Importados e cada um ganha uma nota com o link.',
                style: theme.textTheme.bodySmall?.copyWith(color: org.inkMuted),
              ),
            if (!widget.signedIn)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Entre na sua conta do Organize para salvar.', key: const Key('share-signin-required'), style: TextStyle(color: theme.colorScheme.error)),
              )
            else ...[
              if (driveMissing)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _c.hasText
                            ? 'O Google Drive não está conectado: só o texto será salvo, os arquivos ficam de fora.'
                            : 'Para guardar arquivos, conecte o Google Drive em Ajustes.',
                        key: const Key('share-drive-missing'),
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        key: const Key('share-open-settings'),
                        onPressed: () {
                          final router = GoRouter.maybeOf(context);
                          Navigator.of(context).pop();
                          router?.go('/ajustes');
                        },
                        child: const Text('Abrir Ajustes'),
                      ),
                    ],
                  ),
                ),
              if (canSave) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text('Espaço:', style: theme.textTheme.bodyMedium),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButton<String?>(
                        key: const Key('share-space'),
                        isExpanded: true,
                        value: _spaceId,
                        items: [
                          const DropdownMenuItem<String?>(value: null, child: Text(importSpaceName)),
                          for (final s in spaces)
                            if (s.name != importSpaceName) DropdownMenuItem<String?>(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: _saving ? null : (v) => setState(() => _spaceId = v),
                      ),
                    ),
                  ],
                ),
              ],
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, key: const Key('share-error'), style: TextStyle(color: theme.colorScheme.error)),
              ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('Cancelar')),
                if (canSave) ...[
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const Key('share-save'),
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Salvar'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
