import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/drive_repository.dart';
import '../../data/repository.dart';
import '../../domain/drive.dart';
import '../../ui/common.dart';
import '../../ui/org_theme.dart';

final _emailRe = RegExp(r'^[^\s@<>()",;:\\]{1,64}@[A-Za-z0-9.-]{1,255}\.[A-Za-z]{2,}$');

/// Folha "Compartilhar": link público liga/desliga (com copiar), convite por e-mail
/// com papel e lista de quem tem acesso (com remover).
class ShareFileSheet extends StatefulWidget {
  const ShareFileSheet({super.key, required this.repo, required this.item});

  final DriveRepository repo;
  final DriveItem item;

  @override
  State<ShareFileSheet> createState() => _ShareFileSheetState();
}

class _ShareFileSheetState extends State<ShareFileSheet> {
  final _email = TextEditingController();
  List<DrivePermission> _perms = const [];
  DriveRole _role = DriveRole.reader;
  String? _link;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _emailError;

  bool get _linkOn => _perms.any((p) => p.isAnyone);

  @override
  void initState() {
    super.initState();
    _link = widget.item.webViewLink;
    _refresh();
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final p = await widget.repo.permissions(widget.item.id);
      if (!mounted) return;
      setState(() {
        _perms = p;
        _loading = false;
        _error = null;
      });
    } on RepositoryException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  Future<void> _run(Future<void> Function() op, String fallback) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await op();
      await _refresh();
    } on RepositoryException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = fallback);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleLink(bool on) => _run(() async {
        final link = await widget.repo.setLinkSharing(widget.item.id, on);
        if (link != null) _link = link;
      }, 'Não foi possível alterar o link.');

  Future<void> _copy() async {
    final link = _link;
    if (link == null) return;
    await Clipboard.setData(ClipboardData(text: link));
    if (mounted) showError(context, 'Link copiado.');
  }

  Future<void> _invite() async {
    final email = _email.text.trim();
    if (!_emailRe.hasMatch(email)) {
      setState(() => _emailError = 'E-mail inválido.');
      return;
    }
    setState(() => _emailError = null);
    await _run(() async {
      await widget.repo.share(widget.item.id, email, _role);
      _email.clear();
    }, 'Não foi possível convidar.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final org = context.org;
    final people = _perms.where((p) => !p.isAnyone).toList();
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          key: const Key('doc-share-sheet'),
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Compartilhar', style: theme.textTheme.titleMedium),
            Text(widget.item.name, style: theme.textTheme.bodySmall?.copyWith(color: org.inkMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 12),
            if (_loading)
              const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
            else ...[
              SwitchListTile(
                key: const Key('doc-link-switch'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Qualquer pessoa com o link pode ver'),
                value: _linkOn,
                onChanged: _busy ? null : _toggleLink,
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: const Key('doc-link-copy'),
                  onPressed: _linkOn && _link != null ? _copy : null,
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copiar link'),
                ),
              ),
              const SizedBox(height: 16),
              Text('Convidar por e-mail', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              TextField(
                key: const Key('doc-share-email'),
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(labelText: 'E-mail', errorText: _emailError),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DropdownButton<DriveRole>(
                      key: const Key('doc-share-role'),
                      value: _role,
                      isExpanded: true,
                      items: [for (final r in DriveRole.values) DropdownMenuItem(value: r, child: Text(r.label))],
                      onChanged: (r) => setState(() => _role = r ?? _role),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(key: const Key('doc-share-invite'), onPressed: _busy ? null : _invite, child: const Text('Convidar')),
                ],
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!, key: const Key('doc-share-error'), style: TextStyle(color: theme.colorScheme.error)),
                ),
              if (people.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Quem tem acesso', style: theme.textTheme.titleSmall),
                for (final p in people)
                  ListTile(
                    key: Key('doc-perm-${p.id}'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(p.email ?? 'Pessoa'),
                    subtitle: Text(p.roleLabel),
                    trailing: p.isOwner
                        ? null
                        : IconButton(
                            key: Key('doc-perm-remove-${p.id}'),
                            tooltip: 'Remover acesso',
                            icon: const Icon(Icons.person_remove_outlined),
                            onPressed: _busy ? null : () => _run(() => widget.repo.unshare(widget.item.id, p.id), 'Não foi possível remover.'),
                          ),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
