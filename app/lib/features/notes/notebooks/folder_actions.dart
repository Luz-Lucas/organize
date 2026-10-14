import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../data/repository.dart';
import '../../../domain/ids.dart';
import '../../../domain/note.dart';
import '../../../domain/space.dart';
import '../../../ui/common.dart';
import 'notebook_actions.dart' show FolderDot;
import 'notebooks_logic.dart';

/// Dados do diálogo de pasta (só os campos pedidos vêm preenchidos de verdade).
class FolderForm {
  const FolderForm({required this.name, required this.color, required this.kind});

  final String name;
  final String color;
  final SpaceKind kind;
}

/// "+ Pasta": pede nome, cor e tipo (Pasta = espaço `geral`; Matéria = espaço `materia`) e cria.
/// Devolve a pasta criada, ou `null` se cancelou ou falhou.
Future<Space?> createFolder(BuildContext context, WidgetRef ref) async {
  final existing = ref.read(spacesProvider).value ?? const <Space>[];
  final form = await showDialog<FolderForm>(
    context: context,
    builder: (_) => FolderDialog(
      title: 'Nova pasta',
      initialColor: folderColorHex(folderPalette[existing.length % folderPalette.length]),
    ),
  );
  if (form == null) return null;
  final space = Space(
    id: newId(),
    name: form.name,
    kind: form.kind,
    position: existing.length,
    color: form.color,
  );
  try {
    await ref.read(repositoryProvider).upsertSpace(space);
    return space;
  } on RepositoryException {
    if (context.mounted) showError(context, 'Não foi possível criar a pasta.');
    return null;
  }
}

/// Segurar uma pasta: Renomear, Cor, Transformar em matéria/pasta e Excluir.
/// [onDeleted] é chamado depois que a pasta foi mesmo excluída.
Future<void> showFolderMenu(BuildContext context, WidgetRef ref, Space space, {VoidCallback? onDeleted}) async {
  final isMateria = space.kind == SpaceKind.materia;
  final action = await showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Row(children: [
        FolderDot(color: parseFolderColor(space.color)),
        const SizedBox(width: 10),
        Expanded(child: Text(space.name, maxLines: 2, overflow: TextOverflow.ellipsis)),
      ]),
      children: [
        SimpleDialogOption(
          key: const Key('folder-menu-rename'),
          onPressed: () => Navigator.of(ctx).pop('rename'),
          child: const Text('Renomear'),
        ),
        SimpleDialogOption(
          key: const Key('folder-menu-color'),
          onPressed: () => Navigator.of(ctx).pop('color'),
          child: const Text('Cor'),
        ),
        SimpleDialogOption(
          key: const Key('folder-menu-kind'),
          onPressed: () => Navigator.of(ctx).pop('kind'),
          child: Text(isMateria ? 'Transformar em pasta' : 'Transformar em matéria'),
        ),
        SimpleDialogOption(
          key: const Key('folder-menu-delete'),
          onPressed: () => Navigator.of(ctx).pop('delete'),
          child: const Text('Excluir'),
        ),
      ],
    ),
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case 'rename':
      final form = await showDialog<FolderForm>(
        context: context,
        builder: (_) => FolderDialog(
            title: 'Renomear pasta', askColor: false, askKind: false, initialName: space.name),
      );
      if (form != null && context.mounted && form.name != space.name) {
        await _save(context, ref, space.copyWith(name: form.name));
      }
    case 'color':
      final form = await showDialog<FolderForm>(
        context: context,
        builder: (_) => FolderDialog(
            title: 'Cor da pasta', askName: false, askKind: false, initialColor: space.color, initialName: space.name),
      );
      if (form != null && context.mounted && form.color != space.color) {
        await _save(context, ref, space.copyWith(color: form.color));
      }
    case 'kind':
      await _save(context, ref, space.copyWith(kind: isMateria ? SpaceKind.geral : SpaceKind.materia));
    case 'delete':
      if (await deleteFolder(context, ref, space)) onDeleted?.call();
  }
}

Future<void> _save(BuildContext context, WidgetRef ref, Space space) async {
  try {
    await ref.read(repositoryProvider).upsertSpace(space);
  } on RepositoryException {
    if (context.mounted) showError(context, 'Não foi possível salvar a pasta.');
  }
}

/// Excluir uma pasta **nunca apaga cadernos**.
///
/// `notes.space_id` é `on delete cascade`, então o app move os cadernos da pasta para
/// "Sem pasta" *antes* de excluir o espaço (e o gatilho `spaces_keep_notebooks` do banco
/// garante o mesmo, mesmo que outro aparelho crie um caderno ali no meio).
/// Pastas com notas de texto ou tarefas não são excluídas por aqui (o espaço levaria
/// esses itens junto): o app avisa e nada é apagado.
/// Devolve `true` se a pasta foi excluída.
Future<bool> deleteFolder(BuildContext context, WidgetRef ref, Space space) async {
  final repo = ref.read(repositoryProvider);
  final notes = ref.read(notesProvider).value;
  final tasks = ref.read(tasksProvider).value;
  if (notes == null || tasks == null) {
    showError(context, 'Aguarde carregar e tente de novo.');
    return false;
  }
  ({List<Note> notebooks, int texts, int tasks}) inFolder() {
    final ns = ref.read(notesProvider).value ?? notes;
    final ts = ref.read(tasksProvider).value ?? tasks;
    return (
      notebooks: [for (final n in ns) if (n.spaceId == space.id && n.isNotebook) n],
      texts: ns.where((n) => n.spaceId == space.id && !n.isNotebook).length,
      tasks: ts.where((t) => t.spaceId == space.id).length,
    );
  }

  Future<void> blocked(({List<Note> notebooks, int texts, int tasks}) c) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Não dá para excluir “${space.name}”', maxLines: 3, overflow: TextOverflow.ellipsis),
          content: Text(
            'Esta pasta tem ${[
              if (c.texts > 0) plural(c.texts, 'nota de texto', 'notas de texto'),
              if (c.tasks > 0) plural(c.tasks, 'tarefa', 'tarefas'),
            ].join(' e ')}, e excluí-la apagaria esses itens. '
            'Mova ou exclua essas notas e tarefas antes. Os cadernos nunca são apagados com a pasta.',
          ),
          actions: [
            FilledButton(
              key: const Key('folder-delete-blocked-ok'),
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Entendi'),
            ),
          ],
        ),
      );

  final first = inFolder();
  if (first.texts > 0 || first.tasks > 0) {
    await blocked(first);
    return false;
  }
  final n = first.notebooks.length;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Excluir a pasta “${space.name}”?', maxLines: 3, overflow: TextOverflow.ellipsis),
      content: Text(n == 0
          ? 'A pasta está vazia.'
          : 'Você tem ${plural(n, 'caderno', 'cadernos')} nesta pasta. Nenhum será apagado: '
              '${n == 1 ? 'ele vai' : 'eles vão'} para “Sem pasta”.'),
      actions: [
        TextButton(
          key: const Key('folder-delete-cancel'),
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('folder-delete-confirm'),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Excluir pasta'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;

  // Relê: algo pode ter chegado em outro aparelho enquanto o diálogo estava aberto.
  final latest = inFolder();
  if (latest.texts > 0 || latest.tasks > 0) {
    await blocked(latest);
    return false;
  }
  try {
    for (final nb in latest.notebooks) {
      await repo.upsertNote(nb.withSpace(null));
    }
  } on RepositoryException {
    if (context.mounted) showError(context, 'Não foi possível mover os cadernos. A pasta não foi excluída.');
    return false;
  }
  try {
    await repo.deleteSpace(space.id);
    return true;
  } on RepositoryException {
    if (context.mounted) showError(context, 'Não foi possível excluir a pasta.');
    return false;
  }
}

/// Diálogo de pasta: nome, cor (paleta) e tipo (Pasta | Matéria). Cada campo pode ser omitido.
class FolderDialog extends StatefulWidget {
  const FolderDialog({
    super.key,
    required this.title,
    this.askName = true,
    this.askColor = true,
    this.askKind = true,
    this.initialName = '',
    this.initialColor,
    this.initialKind = SpaceKind.geral,
  });

  final String title;
  final bool askName;
  final bool askColor;
  final bool askKind;
  final String initialName;
  final String? initialColor;
  final SpaceKind initialKind;

  @override
  State<FolderDialog> createState() => _FolderDialogState();
}

class _FolderDialogState extends State<FolderDialog> {
  late final _name = TextEditingController(text: widget.initialName);
  late String _color = widget.initialColor ?? folderColorHex(folderPalette.first);
  late SpaceKind _kind = widget.initialKind;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _valid => !widget.askName || _name.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return AlertDialog(
      title: Text(widget.title),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.askName)
            TextField(
              key: const Key('folder-name'),
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Nome'),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _valid ? _submit() : null,
            ),
          if (widget.askColor) ...[
            const SizedBox(height: 16),
            Text('Cor', style: muted),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in folderPalette)
                  PaletteSwatch(
                    key: Key('folder-color-${folderColorHex(c).substring(1)}'),
                    color: c,
                    selected: folderColorHex(c) == _color.toUpperCase(),
                    onTap: () => setState(() => _color = folderColorHex(c)),
                  ),
              ],
            ),
          ],
          if (widget.askKind) ...[
            const SizedBox(height: 16),
            Text('Tipo', style: muted),
            const SizedBox(height: 8),
            SegmentedButton<SpaceKind>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: SpaceKind.geral, label: Text('Pasta', key: Key('folder-kind-geral'))),
                ButtonSegment(value: SpaceKind.materia, label: Text('Matéria', key: Key('folder-kind-materia'))),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          key: const Key('folder-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('folder-ok'),
          onPressed: _valid ? _submit : null,
          child: const Text('Salvar'),
        ),
      ],
    );
  }

  void _submit() =>
      Navigator.of(context).pop(FolderForm(name: _name.text.trim(), color: _color.toUpperCase(), kind: _kind));
}

/// Bolinha de cor da paleta fixa (pastas e etiquetas): marcada com um check quando escolhida.
class PaletteSwatch extends StatelessWidget {
  const PaletteSwatch({super.key, required this.color, required this.selected, required this.onTap});

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        label: 'Cor ${folderColorHex(color)}',
        child: InkResponse(
          onTap: onTap,
          radius: 24,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? Theme.of(context).colorScheme.onSurface : Colors.transparent,
                width: 2.5,
              ),
            ),
            child: selected
                ? Icon(Icons.check,
                    size: 20,
                    color: ThemeData.estimateBrightnessForColor(color) == Brightness.dark ? Colors.white : Colors.black87)
                : null,
          ),
        ),
      );
}
