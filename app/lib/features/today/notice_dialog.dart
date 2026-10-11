import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../data/repository.dart';
import '../../domain/ids.dart';
import '../../domain/notice.dart';

/// Cria ou edita um aviso. Em caso de falha ao gravar, o diálogo continua
/// aberto com o que foi digitado.
class NoticeDialog extends ConsumerStatefulWidget {
  const NoticeDialog({super.key, this.existing});

  final Notice? existing;

  @override
  ConsumerState<NoticeDialog> createState() => _NoticeDialogState();
}

class _NoticeDialogState extends ConsumerState<NoticeDialog> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  late bool _pinned;
  late NoticePriority _priority;
  DateTime? _expires;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final n = widget.existing;
    _title = TextEditingController(text: n?.title ?? '');
    _body = TextEditingController(text: n?.body ?? '');
    _pinned = n?.pinned ?? false;
    _priority = n?.priority ?? NoticePriority.normal;
    _expires = n?.expiresAt;
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = ref.read(clockProvider)();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expires ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) {
      setState(() => _expires = DateTime(picked.year, picked.month, picked.day, 23, 59));
    }
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Dê um título ao aviso.');
      return;
    }
    final old = widget.existing;
    final notice = old == null
        ? Notice(
            id: newId(),
            title: title,
            body: _body.text.trim(),
            priority: _priority,
            pinned: _pinned,
            expiresAt: _expires,
            createdAt: ref.read(clockProvider)(),
          )
        : old.copyWith(
            title: title,
            body: _body.text.trim(),
            priority: _priority,
            pinned: _pinned,
            expiresAt: _expires,
            clearExpires: _expires == null,
          );
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(repositoryProvider).upsertNotice(notice);
      if (mounted) Navigator.of(context).pop();
    } on RepositoryException {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Não foi possível salvar o aviso.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final alta = _priority == NoticePriority.alta;
    return AlertDialog(
      title: Text(widget.existing == null ? 'Novo aviso' : 'Editar aviso'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const Key('notice-title'),
                controller: _title,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Título'),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('notice-body'),
                controller: _body,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Detalhes (opcional)'),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                key: const Key('notice-pinned'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Fixar no topo'),
                value: _pinned,
                onChanged: (v) => setState(() => _pinned = v),
              ),
              Row(
                children: [
                  Text('Prioridade', style: theme.textTheme.bodyMedium),
                  const SizedBox(width: 12),
                  ChoiceChip(
                    key: const Key('notice-priority-normal'),
                    label: const Text('Normal'),
                    selected: !alta,
                    onSelected: (_) => setState(() => _priority = NoticePriority.normal),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    key: const Key('notice-priority-alta'),
                    label: const Text('Alta'),
                    selected: alta,
                    onSelected: (_) => setState(() => _priority = NoticePriority.alta),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton.icon(
                    key: const Key('notice-expires'),
                    onPressed: _pickDate,
                    icon: const Icon(Icons.event_outlined, size: 18),
                    label: Text(_expires == null
                        ? 'Sem data de expiração'
                        : 'Expira em ${DateFormat('d MMM yyyy', 'pt_BR').format(_expires!)}'),
                  ),
                  if (_expires != null)
                    IconButton(
                      key: const Key('notice-clear-expires'),
                      tooltip: 'Remover expiração',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() => _expires = null),
                    ),
                ],
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('notice-save'),
          onPressed: _saving ? null : _save,
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}
