import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/domain/calendar_event.dart';
import 'package:organizacional/domain/event_tag.dart';
import 'package:organizacional/features/agenda/calendar_common.dart';
import 'package:organizacional/features/agenda/tag_style.dart';
import 'package:organizacional/ui/themes.dart';

final _org = orgThemeById('violeta');

CalendarEvent _ev({String? tagId, String? spaceId}) => CalendarEvent(
      id: 'e1',
      title: 'Aula',
      startsAt: DateTime(2026, 10, 12, 10),
      endsAt: DateTime(2026, 10, 12, 11),
      tagId: tagId,
      spaceId: spaceId,
    );

EventTag _tag(String id, EventTagRole role, {String color = '#3E63DD'}) =>
    EventTag(id: id, name: id, color: color, role: role);

void main() {
  test('sem etiqueta (ou etiqueta desconhecida) mantém o visual antigo, por espaço', () {
    for (final e in [_ev(spaceId: 's1'), _ev(tagId: 'apagada', spaceId: 's1')]) {
      final look = eventLook(_org, e, const {});
      expect(look.tagged, isFalse);
      expect(look.fill, eventColor(_org, 's1'));
      expect(look.text, _org.onAccent);
      expect(look.titleWeight, FontWeight.w600);
    }
  });

  test('cor da etiqueta inválida cai no visual antigo', () {
    final look = eventLook(_org, _ev(tagId: 't'), {'t': _tag('t', EventTagRole.normal, color: 'azul')});
    expect(look.tagged, isFalse);
  });

  test('com etiqueta: barra na cor dela, fundo suave misturado à superfície e texto do tema', () {
    final look = eventLook(_org, _ev(tagId: 't'), {'t': _tag('t', EventTagRole.normal)});
    expect(look.tagged, isTrue);
    expect(look.accent, const Color(0xFF3E63DD));
    expect(look.fill, Color.alphaBlend(look.accent.withValues(alpha: look.fillAlpha), _org.surface));
    expect(look.fill, isNot(look.accent));
    expect(look.text, _org.ink);
  });

  test('main tem mais destaque (negrito e fundo mais forte); secondary é mais discreto', () {
    final main = eventLook(_org, _ev(tagId: 't'), {'t': _tag('t', EventTagRole.main)});
    final normal = eventLook(_org, _ev(tagId: 't'), {'t': _tag('t', EventTagRole.normal)});
    final secondary = eventLook(_org, _ev(tagId: 't'), {'t': _tag('t', EventTagRole.secondary)});
    expect(main.titleWeight, FontWeight.w700);
    expect(main.fillAlpha, greaterThan(normal.fillAlpha));
    expect(secondary.fillAlpha, lessThan(normal.fillAlpha));
    expect(secondary.titleWeight.value, lessThan(normal.titleWeight.value));
    for (final r in [EventTagRole.seasonal, EventTagRole.meeting]) {
      final l = eventLook(_org, _ev(tagId: 't'), {'t': _tag('t', r)});
      expect(l.fillAlpha, normal.fillAlpha);
      expect(l.titleWeight, normal.titleWeight);
    }
  });

  test('tagMap indexa as etiquetas por id', () {
    final m = tagMap([_tag('a', EventTagRole.main), _tag('b', EventTagRole.normal)]);
    expect(m.keys, ['a', 'b']);
  });
}
