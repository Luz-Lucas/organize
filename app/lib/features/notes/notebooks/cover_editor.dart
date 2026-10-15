import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../data/repository.dart';
import '../../../domain/note.dart';
import '../../../domain/notebook_cover.dart';
import '../../../notebook/core/notebook_core.dart' show pageHeight, pageWidth;
import '../../../notebook/notebook_cover_view.dart';
import '../../../notebook/state/notebook_providers.dart';
import '../../../notebook/ui/notebook_screen.dart' show PickedImage, kMaxImageBytes, pickImageFromSystem;
import '../../../ui/common.dart';
import '../../../ui/org_theme.dart';

/// Seletor de imagem da capa (os testes trocam).
final coverImagePickerProvider = Provider<Future<PickedImage?> Function()>((ref) => pickImageFromSystem);

/// Abre o editor de capa do caderno [note] e grava o resultado.
Future<void> editNotebookCover(BuildContext context, WidgetRef ref, Note note) async {
  final result = await showModalBottomSheet<_CoverResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _CoverEditor(note: note),
  );
  if (result == null || !context.mounted) return;
  try {
    var cover = result.cover;
    if (cover != null && result.newImage != null) {
      final store = ref.read(notebookImageStoreFactoryProvider)(note.id);
      final path = await store.upload(result.newImage!.bytes, result.newImage!.ext);
      cover = cover.copyWith(imagePath: path);
    }
    await ref.read(repositoryProvider).upsertNote(note.withCover(cover));
  } catch (e) {
    if (context.mounted) {
      showError(
        context,
        e is RepositoryException ? 'Não foi possível salvar a capa.' : 'Não foi possível enviar a imagem.',
      );
    }
  }
}

class _CoverResult {
  const _CoverResult(this.cover, {this.newImage});

  /// `null` = tirar a capa.
  final NotebookCover? cover;

  /// Imagem escolhida agora (ainda não enviada).
  final PickedImage? newImage;
}

class _CoverEditor extends ConsumerStatefulWidget {
  const _CoverEditor({required this.note});

  final Note note;

  @override
  ConsumerState<_CoverEditor> createState() => _CoverEditorState();
}

class _CoverEditorState extends ConsumerState<_CoverEditor> {
  late NotebookCover _cover;
  late final bool _hadCover;
  late final TextEditingController _text;
  late final TextEditingController _emoji;
  PickedImage? _picked;

  @override
  void initState() {
    super.initState();
    final existing = widget.note.cover;
    _hadCover = existing != null;
    _cover = existing ?? NotebookCover(kind: CoverKind.text, text: widget.note.title);
    _text = TextEditingController(text: _cover.kind == CoverKind.text ? _cover.text : widget.note.title);
    _emoji = TextEditingController(text: _cover.emoji);
  }

  @override
  void dispose() {
    _text.dispose();
    _emoji.dispose();
    super.dispose();
  }

  bool get _canSave => switch (_cover.kind) {
    CoverKind.text => _text.text.trim().isNotEmpty,
    CoverKind.emoji => _emoji.text.trim().isNotEmpty,
    CoverKind.image => _picked != null || (_cover.imagePath ?? '').isNotEmpty,
  };

  NotebookCover get _current =>
      _cover.copyWith(text: _text.text.trim(), emoji: _emoji.text.trim().characters.take(1).toString());

  Future<void> _pickImage() async {
    final picked = await ref.read(coverImagePickerProvider)();
    if (picked == null || !mounted) return;
    if (picked.bytes.length > kMaxImageBytes) {
      showError(context, 'A imagem passa de 10 MB.');
      return;
    }
    setState(() {
      _picked = picked;
      _cover = _cover.copyWith(kind: CoverKind.image);
    });
  }

  void _save() {
    final cover = _current;
    Navigator.of(context).pop(
      _CoverResult(
        cover.kind == CoverKind.image && _picked == null && (cover.imagePath ?? '').isEmpty ? null : cover,
        newImage: cover.kind == CoverKind.image ? _picked : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final org = context.org;
    final kind = _cover.kind;
    final showColor = kind != CoverKind.image || _cover.fit == CoverFit.fit;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Capa de “${widget.note.title}”',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Center(
                child: SizedBox(
                  width: 120,
                  height: 120 * pageHeight / pageWidth,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: org.line),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: _preview(),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SegmentedButton<CoverKind>(
                key: const Key('cover-kind'),
                segments: const [
                  ButtonSegment(value: CoverKind.text, icon: Icon(Icons.title), label: Text('Texto')),
                  ButtonSegment(
                    value: CoverKind.emoji,
                    icon: Icon(Icons.emoji_emotions_outlined),
                    label: Text('Emoji'),
                  ),
                  ButtonSegment(value: CoverKind.image, icon: Icon(Icons.image_outlined), label: Text('Imagem')),
                ],
                selected: {kind},
                onSelectionChanged: (s) => setState(() => _cover = _cover.copyWith(kind: s.first)),
              ),
              const SizedBox(height: 12),
              if (kind == CoverKind.text)
                TextField(
                  key: const Key('cover-text'),
                  controller: _text,
                  maxLines: 3,
                  minLines: 1,
                  maxLength: 60,
                  decoration: const InputDecoration(labelText: 'Texto da capa'),
                  onChanged: (_) => setState(() {}),
                ),
              if (kind == CoverKind.emoji)
                TextField(
                  key: const Key('cover-emoji'),
                  controller: _emoji,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 32),
                  decoration: const InputDecoration(labelText: 'Emoji (abra o teclado de emojis)'),
                  onChanged: (v) {
                    // Fica só o último emoji digitado.
                    final chars = v.trim().characters;
                    final last = chars.isEmpty ? '' : chars.last;
                    if (last != v) {
                      _emoji.value = TextEditingValue(
                        text: last,
                        selection: TextSelection.collapsed(offset: last.length),
                      );
                    }
                    setState(() {});
                  },
                ),
              if (kind == CoverKind.image) ...[
                OutlinedButton.icon(
                  key: const Key('cover-pick-image'),
                  onPressed: _pickImage,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text(
                    _picked != null || (_cover.imagePath ?? '').isNotEmpty ? 'Trocar imagem' : 'Escolher imagem',
                  ),
                ),
                const SizedBox(height: 12),
                SegmentedButton<CoverFit>(
                  key: const Key('cover-fit'),
                  segments: const [
                    ButtonSegment(value: CoverFit.fill, label: Text('Preencher (corta)')),
                    ButtonSegment(value: CoverFit.fit, label: Text('Inteira (com fundo)')),
                  ],
                  selected: {_cover.fit},
                  onSelectionChanged: (s) => setState(() => _cover = _cover.copyWith(fit: s.first)),
                ),
              ],
              if (showColor) ...[
                const SizedBox(height: 12),
                Text(kind == CoverKind.image ? 'Cor do fundo' : 'Cor da capa', style: theme.textTheme.labelLarge),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in kCoverColors)
                      _ColorDot(
                        key: ValueKey('cover-color-$c'),
                        color: Color(c),
                        selected: _cover.color == c,
                        onTap: () => setState(() => _cover = _cover.copyWith(color: c)),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              OverflowBar(
                alignment: MainAxisAlignment.end,
                overflowAlignment: OverflowBarAlignment.end,
                spacing: 8,
                children: [
                  if (_hadCover)
                    TextButton(
                      key: const Key('cover-remove'),
                      onPressed: () => Navigator.of(context).pop(const _CoverResult(null)),
                      child: const Text('Tirar capa'),
                    ),
                  TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
                  FilledButton(
                    key: const Key('cover-save'),
                    onPressed: _canSave ? _save : null,
                    child: const Text('Salvar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _preview() {
    final cover = _current;
    final picked = _picked;
    if (cover.kind == CoverKind.image && picked != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: ColoredBox(
          color: Color(cover.color),
          child: Image.memory(
            Uint8List.fromList(picked.bytes),
            fit: cover.fit == CoverFit.fill ? BoxFit.cover : BoxFit.contain,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (_, _, _) => const Center(child: Icon(Icons.broken_image_outlined)),
          ),
        ),
      );
    }
    if (!cover.isValid) {
      return Center(child: Icon(Icons.menu_book_outlined, color: context.org.inkMuted));
    }
    return NotebookCoverView(noteId: widget.note.id, cover: cover, radius: 3);
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({super.key, required this.color, required this.selected, required this.onTap});

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkResponse(
    onTap: onTap,
    radius: 22,
    child: Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: selected ? context.org.accentText : context.org.line, width: selected ? 3 : 1),
      ),
      child: selected ? Icon(Icons.check, size: 18, color: coverInkOn(color)) : null,
    ),
  );
}
