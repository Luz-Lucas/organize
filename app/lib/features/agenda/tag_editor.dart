import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/repository.dart';
import '../../domain/calendar_event.dart';
import '../../domain/event_tag.dart';
import '../../domain/ids.dart';
import '../../ui/common.dart';
import '../../ui/org_theme.dart';
import '../notes/notebooks/folder_actions.dart' show PaletteSwatch;
import '../notes/notebooks/notebooks_logic.dart';
import 'tag_style.dart';

/// Tamanho máximo do nome de uma etiqueta.
const int kTagNameMax = 40;

const _msgNameEmpty = 'Dê um nome à etiqueta.';
const _msgNameLong = 'O nome pode ter até $kTagNameMax caracteres.';
const _msgNameDuplicate = 'Já existe uma etiqueta com esse nome.';
const _msgHexInvalid = 'Use o formato #RRGGBB, como #3E63DD.';

/// Mensagem de erro para o [raw] digitado como nome, ou `null` se estiver bom: de 1 a [kTagNameMax]
/// caracteres e único (sem diferenciar maiúsculas) entre [others]; [editingId] é a etiqueta em edição,
/// que não conta como repetida de si mesma.
String? validateTagName(String raw, Iterable<EventTag> others, {String? editingId}) {
  final name = raw.trim();
  if (name.isEmpty) return _msgNameEmpty;
  if (name.length > kTagNameMax) return _msgNameLong;
  final key = name.toLowerCase();
  final clash = others.any((t) => t.id != editingId && t.name.trim().toLowerCase() == key);
  return clash ? _msgNameDuplicate : null;
}

/// `#RRGGBB` (o `#` é opcional) -> cor, ou `null` se não for um hex de 6 dígitos.
Color? parseTagHex(String text) => parseFolderColor(text);

/// Primeira cor da paleta que nenhuma etiqueta usa ainda (ou, esgotada a paleta, uma pela posição).
String suggestTagColor(List<EventTag> tags) {
  final used = {for (final t in tags) t.color.toUpperCase()};
  for (final c in folderPalette) {
    if (!used.contains(folderColorHex(c))) return folderColorHex(c);
  }
  return folderColorHex(folderPalette[tags.length % folderPalette.length]);
}

/// Abre o diálogo de criar (ou, com [existing], editar) etiqueta e grava no repositório. Devolve a
/// etiqueta salva, ou `null` se o usuário cancelou (ou excluiu, no caso de edição).
Future<EventTag?> showTagEditor(BuildContext context, WidgetRef ref, {EventTag? existing}) {
  final repo = ref.read(repositoryProvider);
  final tags = ref.read(eventTagsProvider).value ?? const <EventTag>[];
  final nextPosition = tags.isEmpty ? 0 : tags.map((t) => t.position).reduce(math.max) + 1;
  return showDialog<EventTag>(
    context: context,
    builder: (_) => TagEditorDialog(
      existing: existing,
      existingTags: tags,
      initialColor: suggestTagColor(tags),
      newPosition: nextPosition,
      onSave: (draft) async {
        try {
          await repo.upsertTag(draft);
          return null;
        } on RepositoryException catch (e) {
          return e.duplicate ? _msgNameDuplicate : 'Não foi possível salvar a etiqueta.';
        }
      },
      onDelete: existing == null
          ? null
          : () async {
              try {
                await repo.deleteTag(existing.id);
                return null;
              } on RepositoryException {
                return 'Não foi possível excluir a etiqueta.';
              }
            },
    ),
  );
}

/// Pergunta antes de excluir [tag]; `true` se o usuário confirmou.
Future<bool> confirmDeleteTag(BuildContext context, EventTag tag) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Excluir a etiqueta “${tag.name}”?', maxLines: 3, overflow: TextOverflow.ellipsis),
      content: const Text('Os eventos com essa etiqueta ficarão sem etiqueta. Eles não são apagados.'),
      actions: [
        TextButton(
          key: const Key('tag-delete-cancel'),
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('tag-delete-confirm'),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Excluir etiqueta'),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// Confirma e exclui [tag] (os eventos ficam, sem etiqueta). Erro de gravação vira aviso.
Future<void> deleteTagWithConfirm(BuildContext context, WidgetRef ref, EventTag tag) async {
  final repo = ref.read(repositoryProvider);
  if (!await confirmDeleteTag(context, tag) || !context.mounted) return;
  try {
    await repo.deleteTag(tag.id);
  } on RepositoryException {
    if (context.mounted) showError(context, 'Não foi possível excluir a etiqueta.');
  }
}

/// Editor de uma etiqueta: nome, cor (paleta ou cor livre), papel opcional e prévia ao vivo.
///
/// [onSave] e [onDelete] devolvem `null` em caso de sucesso (o diálogo fecha, devolvendo a etiqueta
/// salva) ou a mensagem de erro (o diálogo continua aberto, sem perder o que foi digitado).
class TagEditorDialog extends StatefulWidget {
  const TagEditorDialog({
    super.key,
    required this.onSave,
    required this.initialColor,
    this.existingTags = const [],
    this.newPosition = 0,
    this.existing,
    this.onDelete,
  });

  final Future<String?> Function(EventTag draft) onSave;
  final Future<String?> Function()? onDelete;
  final EventTag? existing;

  /// Etiquetas que já existem, para a checagem de nome repetido.
  final List<EventTag> existingTags;

  /// Posição de uma etiqueta nova (o fim da lista).
  final int newPosition;

  /// Cor sugerida para etiqueta nova.
  final String initialColor;

  @override
  State<TagEditorDialog> createState() => _TagEditorDialogState();
}

class _TagEditorDialogState extends State<TagEditorDialog> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late String _color = (widget.existing?.color ?? widget.initialColor).toUpperCase();
  late HSVColor _hsv = HSVColor.fromColor(parseTagHex(_color) ?? folderPalette.first);
  late final _hex = TextEditingController(text: _color);
  late bool _custom = !folderPalette.any((c) => folderColorHex(c) == _color);
  late EventTagRole _role = widget.existing?.role ?? EventTagRole.normal;
  bool _hexError = false;
  bool _busy = false;
  String? _error;

  bool get _editing => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    _hex.dispose();
    super.dispose();
  }

  String? get _nameProblem =>
      validateTagName(_name.text, widget.existingTags, editingId: widget.existing?.id);

  void _pickPalette(Color c) => setState(() {
        _color = folderColorHex(c);
        _hsv = HSVColor.fromColor(c);
        _hex.text = _color;
        _hexError = false;
      });

  void _pickHsv(HSVColor v) => setState(() {
        _hsv = v;
        _color = folderColorHex(v.toColor());
        _hex.text = _color;
        _hexError = false;
      });

  void _typeHex(String text) {
    final c = parseTagHex(text);
    setState(() {
      if (c == null) {
        _hexError = true;
      } else {
        _hexError = false;
        _color = folderColorHex(c);
        _hsv = HSVColor.fromColor(c);
      }
    });
  }

  void _toggleCustom() => setState(() {
        _custom = !_custom;
        if (!_custom) {
          // Fechando a cor livre, o que estava digitado errado volta para a cor valendo.
          _hex.text = _color;
          _hexError = false;
        }
      });

  Future<void> _save() async {
    final problem = _nameProblem;
    if (problem != null) {
      // Repetido/comprido já aparece no campo; o vazio só é cobrado aqui.
      setState(() => _error = _name.text.trim().isEmpty ? problem : null);
      return;
    }
    if (_hexError) return; // o erro já está visível sob o campo da cor
    setState(() {
      _busy = true;
      _error = null;
    });
    final old = widget.existing;
    final draft = EventTag(
      id: old?.id ?? newId(),
      name: _name.text.trim(),
      color: _color,
      role: _role,
      position: old?.position ?? widget.newPosition,
    );
    final failure = await widget.onSave(draft);
    if (!mounted) return;
    if (failure != null) {
      setState(() {
        _busy = false;
        _error = failure;
      });
      return;
    }
    Navigator.of(context).pop(draft);
  }

  Future<void> _delete() async {
    if (!await confirmDeleteTag(context, widget.existing!) || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final failure = await widget.onDelete!();
    if (!mounted) return;
    if (failure != null) {
      setState(() {
        _busy = false;
        _error = failure;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final org = context.org;
    final muted = theme.textTheme.labelMedium?.copyWith(color: org.inkMuted);
    final nameProblem = _name.text.trim().isEmpty ? null : _nameProblem;
    return AlertDialog(
      title: Text(_editing ? 'Editar etiqueta' : 'Nova etiqueta'),
      scrollable: true,
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('tag-name'),
              controller: _name,
              autofocus: !_editing,
              maxLength: kTagNameMax,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: 'Nome', counterText: '', errorText: nameProblem),
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) => _busy ? null : _save(),
            ),
            const SizedBox(height: 16),
            Text('Cor', style: muted),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in folderPalette)
                  PaletteSwatch(
                    key: Key('tag-color-${folderColorHex(c).substring(1)}'),
                    color: c,
                    selected: folderColorHex(c) == _color,
                    onTap: () => _pickPalette(c),
                  ),
                _CustomColorSwatch(
                  key: const Key('tag-color-custom'),
                  open: _custom,
                  color: parseTagHex(_color) ?? folderPalette.first,
                  usingCustom: !folderPalette.any((c) => folderColorHex(c) == _color),
                  onTap: _toggleCustom,
                ),
              ],
            ),
            if (_custom) ...[
              const SizedBox(height: 12),
              Text('Cor livre', style: muted),
              const SizedBox(height: 8),
              _SaturationValueBox(
                key: const Key('tag-sv'),
                hsv: _hsv,
                onChanged: _pickHsv,
              ),
              const SizedBox(height: 12),
              _HueStrip(
                key: const Key('tag-hue'),
                hsv: _hsv,
                onChanged: _pickHsv,
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('tag-hex'),
                controller: _hex,
                maxLength: 7,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[#0-9a-fA-F]'))],
                decoration: InputDecoration(
                  labelText: 'Cor em hexadecimal',
                  hintText: '#3E63DD',
                  counterText: '',
                  errorText: _hexError ? _msgHexInvalid : null,
                ),
                onChanged: _typeHex,
              ),
            ],
            const SizedBox(height: 16),
            Text('Papel no calendário (opcional)', style: muted),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in EventTagRole.values)
                  ChoiceChip(
                    key: Key('tag-role-${r.name}'),
                    label: Text(r.label),
                    selected: _role == r,
                    onSelected: (_) => setState(() => _role = r),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(_roleHelp(_role), style: theme.textTheme.bodySmall?.copyWith(color: org.inkMuted)),
            const SizedBox(height: 16),
            Text('Prévia', style: muted),
            const SizedBox(height: 8),
            _TagPreview(name: _name.text.trim(), color: _color, role: _role),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ),
          ],
        ),
      ),
      actions: [
        if (_editing)
          TextButton(
            key: const Key('tag-delete'),
            onPressed: _busy ? null : _delete,
            child: Text('Excluir', style: TextStyle(color: theme.colorScheme.error)),
          ),
        TextButton(
          key: const Key('tag-cancel'),
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(key: const Key('tag-save'), onPressed: _busy ? null : _save, child: const Text('Salvar')),
      ],
    );
  }
}

String _roleHelp(EventTagRole r) => switch (r) {
      EventTagRole.main => 'Destaque: título em negrito e fundo mais forte (ex.: aulas).',
      EventTagRole.secondary => 'Discreta: fundo mais claro, para não competir com o principal (ex.: academia).',
      EventTagRole.seasonal => 'Eventos de época do ano, como viagens e feriados.',
      EventTagRole.meeting => 'Reuniões, em horários variados.',
      EventTagRole.normal => 'Sem peso especial.',
    };

/// Como um evento com essa etiqueta aparece no calendário (usa o mesmo estilo da agenda).
class _TagPreview extends StatelessWidget {
  const _TagPreview({required this.name, required this.color, required this.role});

  final String name;
  final String color;
  final EventTagRole role;

  @override
  Widget build(BuildContext context) {
    final org = context.org;
    final theme = Theme.of(context);
    final tag = EventTag(id: _sampleEvent.tagId!, name: name, color: color, role: role);
    final look = eventLook(org, _sampleEvent, {tag.id: tag});
    final title = name.isEmpty ? 'Nome da etiqueta' : name;
    return Semantics(
      container: true,
      label: 'Prévia de um evento com a etiqueta $title',
      child: ExcludeSemantics(
        child: Container(
          key: const Key('tag-preview'),
          decoration: BoxDecoration(color: org.surface, borderRadius: BorderRadius.circular(8)),
          child: EventSurface(
            look: look,
            radius: 8,
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            barKey: const Key('tag-preview-bar'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  key: const Key('tag-preview-title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(color: look.text, fontWeight: look.titleWeight),
                ),
                Text(
                  '09:00 – 10:00 · evento de exemplo',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: look.text.withValues(alpha: 0.75)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Evento fictício da prévia (só a etiqueta importa para o visual).
final _sampleEvent = CalendarEvent(
  id: 'tag-preview',
  title: 'Exemplo',
  startsAt: DateTime(2026, 1, 1, 9),
  endsAt: DateTime(2026, 1, 1, 10),
  tagId: 'tag-preview',
);

/// Bolinha "cor livre" ao lado da paleta: arco-íris; marcada quando a cor atual não é da paleta.
class _CustomColorSwatch extends StatelessWidget {
  const _CustomColorSwatch({
    super.key,
    required this.open,
    required this.color,
    required this.usingCustom,
    required this.onTap,
  });

  final bool open;
  final Color color;
  final bool usingCustom;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Semantics(
      button: true,
      selected: open || usingCustom,
      label: 'Cor livre',
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const SweepGradient(colors: [
              Color(0xFFFF0000),
              Color(0xFFFFFF00),
              Color(0xFF00FF00),
              Color(0xFF00FFFF),
              Color(0xFF0000FF),
              Color(0xFFFF00FF),
              Color(0xFFFF0000),
            ]),
            border: Border.all(color: open || usingCustom ? onSurface : Colors.transparent, width: 2.5),
          ),
          child: Icon(
            usingCustom ? Icons.check : Icons.colorize,
            size: 20,
            color: Colors.white,
            shadows: const [Shadow(blurRadius: 3, color: Colors.black54)],
          ),
        ),
      ),
    );
  }
}

const _handleSize = 20.0;

/// Quadrado de saturação (horizontal) e brilho (vertical, topo = mais claro) para o matiz atual.
///
/// Não usa `LayoutBuilder` (o `AlertDialog` rolável mede dimensões intrínsecas); a largura vem do próprio
/// render object na hora do gesto.
class _SaturationValueBox extends StatelessWidget {
  const _SaturationValueBox({super.key, required this.hsv, required this.onChanged});

  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  static const _height = 150.0;

  @override
  Widget build(BuildContext context) {
    void update(Offset p) {
      final w = (context.findRenderObject() as RenderBox).size.width;
      onChanged(hsv.withSaturation((p.dx / w).clamp(0.0, 1.0)).withValue((1 - p.dy / _height).clamp(0.0, 1.0)));
    }

    return Semantics(
      label: 'Saturação e brilho',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => update(d.localPosition),
        onPanStart: (d) => update(d.localPosition),
        onPanUpdate: (d) => update(d.localPosition),
        child: SizedBox(
          width: double.infinity,
          height: _height,
          child: CustomPaint(painter: _SvPainter(hsv)),
        ),
      ),
    );
  }
}

class _SvPainter extends CustomPainter {
  _SvPainter(this.hsv);

  final HSVColor hsv;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(8));
    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(colors: [Colors.white, HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor()])
            .createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), Colors.black],
        ).createShader(rect),
    );
    canvas.restore();
    _paintHandle(canvas, Offset(hsv.saturation * size.width, (1 - hsv.value) * size.height), hsv.toColor());
  }

  @override
  bool shouldRepaint(_SvPainter old) => old.hsv != hsv;
}

void _paintHandle(Canvas canvas, Offset c, Color fill) {
  canvas.drawCircle(c, _handleSize / 2, Paint()..color = fill);
  canvas.drawCircle(
    c,
    _handleSize / 2,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.white,
  );
  canvas.drawCircle(
    c,
    _handleSize / 2 + 1,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.black45,
  );
}

/// Faixa de matiz (0–360°).
class _HueStrip extends StatelessWidget {
  const _HueStrip({super.key, required this.hsv, required this.onChanged});

  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  @override
  Widget build(BuildContext context) {
    void update(Offset p) {
      final w = (context.findRenderObject() as RenderBox).size.width;
      onChanged(hsv.withHue((p.dx / w).clamp(0.0, 1.0) * 359.999));
    }

    return Semantics(
      label: 'Matiz',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => update(d.localPosition),
        onHorizontalDragStart: (d) => update(d.localPosition),
        onHorizontalDragUpdate: (d) => update(d.localPosition),
        child: SizedBox(
          width: double.infinity,
          height: 28,
          child: CustomPaint(painter: _HuePainter(hsv.hue)),
        ),
      ),
    );
  }
}

class _HuePainter extends CustomPainter {
  _HuePainter(this.hue);

  final double hue;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(14)),
      Paint()
        ..shader = LinearGradient(colors: [
          for (var i = 0; i <= 6; i++) HSVColor.fromAHSV(1, i * 60.0, 1, 1).toColor(),
        ]).createShader(rect),
    );
    final x = (hue / 360).clamp(0.0, 1.0) * size.width;
    _paintHandle(canvas, Offset(x, size.height / 2), HSVColor.fromAHSV(1, hue, 1, 1).toColor());
  }

  @override
  bool shouldRepaint(_HuePainter old) => old.hue != hue;
}
