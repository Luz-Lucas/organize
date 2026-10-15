import 'package:flutter/material.dart';

import '../../domain/calendar_event.dart';
import '../../domain/event_tag.dart';
import '../../ui/org_theme.dart';
import '../notes/notebooks/notebooks_logic.dart' show parseFolderColor;
import 'calendar_common.dart';

/// Etiquetas indexadas por id (a agenda consulta uma por evento).
Map<String, EventTag> tagMap(Iterable<EventTag> tags) => {for (final t in tags) t.id: t};

/// Opacidade da cor da etiqueta no fundo do evento, por papel. `main` pesa mais; `secondary` some mais.
double tagFillAlpha(EventTagRole role) => switch (role) {
      EventTagRole.main => 0.42,
      EventTagRole.secondary => 0.14,
      _ => 0.28,
    };

/// Peso do título do evento, por papel.
FontWeight tagTitleWeight(EventTagRole role) => switch (role) {
      EventTagRole.main => FontWeight.w700,
      EventTagRole.secondary => FontWeight.w500,
      _ => FontWeight.w600,
    };

/// Como um evento é desenhado: sem etiqueta, o visual de sempre (cor por espaço, texto `onAccent`);
/// com etiqueta, barra lateral na cor dela, fundo suave dessa cor sobre a superfície do tema e texto `ink`.
class EventLook {
  const EventLook({
    required this.tagged,
    required this.accent,
    required this.fill,
    required this.fillAlpha,
    required this.text,
    required this.titleWeight,
  });

  final bool tagged;

  /// Barra lateral (só desenhada quando [tagged]).
  final Color accent;
  final Color fill;
  final double fillAlpha;
  final Color text;
  final FontWeight titleWeight;

  /// Peso do título nas telas que, sem etiqueta, usam o estilo padrão do tema.
  FontWeight? get taggedWeight => tagged ? titleWeight : null;
}

EventLook eventLook(OrgThemeSpec org, CalendarEvent e, Map<String, EventTag> tags) {
  final tag = e.tagId == null ? null : tags[e.tagId];
  final color = parseFolderColor(tag?.color);
  if (tag == null || color == null) {
    final base = eventColor(org, e.spaceId);
    return EventLook(
      tagged: false,
      accent: base,
      fill: base,
      fillAlpha: 1,
      text: org.onAccent,
      titleWeight: FontWeight.w600,
    );
  }
  final alpha = tagFillAlpha(tag.role);
  return EventLook(
    tagged: true,
    accent: color,
    fill: Color.alphaBlend(color.withValues(alpha: alpha), org.surface),
    fillAlpha: alpha,
    text: org.ink,
    titleWeight: tagTitleWeight(tag.role),
  );
}

const double tagBarWidth = 4;

/// Fundo do evento: cor cheia sem etiqueta; com etiqueta, fundo suave e barra lateral colorida
/// (a barra leva [barKey]). O [child] recebe o [padding] já descontada a barra.
class EventSurface extends StatelessWidget {
  const EventSurface({
    super.key,
    required this.look,
    required this.radius,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.barKey,
  });

  final EventLook look;
  final double radius;
  final Widget child;
  final EdgeInsets padding;
  final Key? barKey;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    if (!look.tagged) {
      return Container(
        padding: padding,
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(color: look.fill, borderRadius: shape),
        child: child,
      );
    }
    return ClipRRect(
      borderRadius: shape,
      child: Stack(
        children: [
          Positioned.fill(child: ColoredBox(color: look.fill)),
          Padding(padding: padding + const EdgeInsets.only(left: tagBarWidth), child: child),
          Positioned(left: 0, top: 0, bottom: 0, width: tagBarWidth, child: ColoredBox(key: barKey, color: look.accent)),
        ],
      ),
    );
  }
}
