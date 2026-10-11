import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_alexa_repository.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/data/memory_settings_repository.dart';
import 'package:organizacional/domain/alexa.dart';
import 'package:organizacional/domain/user_settings.dart';

import '../helpers.dart';

const _tall = Size(1000, 3200);
final _now = DateTime(2026, 9, 28, 10);
const _plan = WakePlan(
  id: 'p1', label: 'Aula cedo', days: [1, 2, 3, 4, 5], hour: 7, minute: 0,
  echoDeviceId: 'ECHO', spotifyQuery: 'lofi',
);

MemoryAlexaRepository _alexa({List<WakePlan> plans = const [_plan], bool withSmart = true}) => MemoryAlexaRepository(
      status: BridgeStatus(state: BridgeState.ok, lastSeen: _now),
      devices: [
        const AlexaDevice(id: 'ECHO', name: 'Echo do quarto', kind: 'echo'),
        if (withSmart) ...const [
          AlexaDevice(id: 'luz1', name: 'Luz do quarto', kind: 'smart', operations: ['turnOn', 'turnOff', 'setBrightness']),
          AlexaDevice(id: 'tomada', name: 'Cafeteira', kind: 'smart', operations: ['turnOn', 'turnOff']),
          AlexaDevice(id: 'luz-oculta', name: 'Luz escondida', kind: 'smart', operations: ['turnOn']),
        ],
      ],
      plans: plans,
    );

Future<void> _open(WidgetTester tester, MemoryAlexaRepository alexa,
    {String id = 'p1', MemorySettingsRepository? settings}) =>
    pumpApp(tester, MemoryRepository(),
        location: '/casa/despertar/$id', now: _now, alexa: alexa, size: _tall, settings: settings);

Future<WakePlan> _save(WidgetTester tester, MemoryAlexaRepository alexa) async {
  await tester.ensureVisible(find.byKey(const Key('wake-save')));
  await tester.tap(find.byKey(const Key('wake-save')));
  await tester.pumpAndSettle();
  return (await alexa.watchWakePlans().first).single;
}

Future<void> _addDevice(WidgetTester tester, String id) async {
  await tester.ensureVisible(find.byKey(const Key('device-action-add')));
  await tester.tap(find.byKey(const Key('device-action-add')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('device-pick-$id')));
  await tester.pumpAndSettle();
}

void main() {
  group('clima', () {
    testWidgets('despertar novo vem com "Falar o clima" ligado; desligar salva include_weather false', (tester) async {
      final alexa = _alexa(plans: const []);
      await _open(tester, alexa, id: 'novo');
      expect(find.text('Falar o clima'), findsOneWidget);
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('weather-switch'))).value, isTrue);
      await tester.tap(find.byKey(const Key('weather-switch')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('wake-spotify')));
      await tester.enterText(find.byKey(const Key('wake-spotify')), 'rock');
      final saved = await _save(tester, alexa);
      expect(saved.includeWeather, isFalse);
    });

    testWidgets('despertar novo salvo sem mexer mantém o clima ligado', (tester) async {
      final alexa = _alexa(plans: const []);
      await _open(tester, alexa, id: 'novo');
      final saved = await _save(tester, alexa);
      expect(saved.includeWeather, isTrue);
      expect(saved.deviceActions, isEmpty);
      expect(saved.phoneAlarm, PhoneAlarm.fallback);
    });

    testWidgets('plano antigo: chave ligada e nada muda ao salvar', (tester) async {
      final alexa = _alexa();
      await _open(tester, alexa);
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('weather-switch'))).value, isTrue);
      final saved = await _save(tester, alexa);
      expect(saved, _plan);
    });

    testWidgets('plano com clima desligado abre desligado e ligar salva', (tester) async {
      final alexa = _alexa(plans: [_plan.copyWith(includeWeather: false)]);
      await _open(tester, alexa);
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('weather-switch'))).value, isFalse);
      await tester.ensureVisible(find.byKey(const Key('weather-switch')));
      await tester.tap(find.byKey(const Key('weather-switch')));
      await tester.pump();
      expect((await _save(tester, alexa)).includeWeather, isTrue);
    });
  });

  group('dispositivos no despertar', () {
    testWidgets('seção vazia e botão de adicionar', (tester) async {
      await _open(tester, _alexa());
      expect(find.text('Dispositivos no despertar'), findsOneWidget);
      expect(find.byKey(const Key('device-action-add')), findsOneWidget);
    });

    testWidgets('o seletor oferece só smart não ocultos e ainda não usados', (tester) async {
      final settings = MemorySettingsRepository(initial: const UserSettings(hiddenAlexaDevices: ['luz-oculta']));
      final alexa = _alexa(plans: [
        _plan.copyWith(deviceActions: const [
          WakeDeviceAction(entityId: 'tomada', name: 'Cafeteira', action: WakeActionType.turnOn),
        ]),
      ]);
      await _open(tester, alexa, settings: settings);
      await tester.ensureVisible(find.byKey(const Key('device-action-add')));
      await tester.tap(find.byKey(const Key('device-action-add')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('device-pick-luz1')), findsOneWidget);
      expect(find.byKey(const ValueKey('device-pick-tomada')), findsNothing); // já adicionado
      expect(find.byKey(const ValueKey('device-pick-luz-oculta')), findsNothing); // oculto
      expect(find.byKey(const ValueKey('device-pick-ECHO')), findsNothing); // Echo não é smart
    });

    testWidgets('sem dispositivos: mensagem no seletor', (tester) async {
      await _open(tester, _alexa(withSmart: false));
      await tester.ensureVisible(find.byKey(const Key('device-action-add')));
      await tester.tap(find.byKey(const Key('device-action-add')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Nenhum dispositivo disponível'), findsOneWidget);
    });

    testWidgets('adicionar, ajustar brilho e atraso, e salvar', (tester) async {
      final alexa = _alexa();
      await _open(tester, alexa);
      await _addDevice(tester, 'luz1');
      expect(find.byKey(const ValueKey('device-action-luz1')), findsOneWidget);
      expect(find.text('Luz do quarto'), findsWidgets);
      expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('device-type-luz1-turnOn'))).selected, isTrue);
      expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('device-delay-luz1-0'))).selected, isTrue);

      await tester.ensureVisible(find.byKey(const ValueKey('device-type-luz1-setBrightness')));
      await tester.tap(find.byKey(const ValueKey('device-type-luz1-setBrightness')));
      await tester.pump();
      final slider = find.byKey(const ValueKey('device-brightness-luz1'));
      expect(slider, findsOneWidget);
      tester.widget<Slider>(slider).onChanged!(30);
      await tester.pump();
      expect(find.text('Brilho 30%'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('device-delay-luz1-10')));
      await tester.tap(find.byKey(const ValueKey('device-delay-luz1-10')));
      await tester.pump();

      final saved = await _save(tester, alexa);
      expect(saved.deviceActions, [
        const WakeDeviceAction(
            entityId: 'luz1', name: 'Luz do quarto', action: WakeActionType.setBrightness, brightness: 30, delayMin: 10),
      ]);
    });

    testWidgets('os atrasos oferecidos são 0, 1, 5, 10, 15 e 30 min', (tester) async {
      await _open(tester, _alexa());
      await _addDevice(tester, 'luz1');
      for (final m in [0, 1, 5, 10, 15, 30]) {
        expect(find.byKey(ValueKey('device-delay-luz1-$m')), findsOneWidget, reason: '$m');
      }
      expect(find.byKey(const ValueKey('device-delay-luz1-2')), findsNothing);
    });

    testWidgets('trocar para Desligar e remover', (tester) async {
      final alexa = _alexa(plans: [
        _plan.copyWith(deviceActions: const [
          WakeDeviceAction(entityId: 'luz1', name: 'Luz do quarto', action: WakeActionType.turnOn),
          WakeDeviceAction(entityId: 'tomada', name: 'Cafeteira', action: WakeActionType.turnOn, delayMin: 5),
        ]),
      ]);
      await _open(tester, alexa);
      expect(find.byKey(const ValueKey('device-action-luz1')), findsOneWidget);
      expect(find.byKey(const ValueKey('device-action-tomada')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('device-type-tomada-turnOff')));
      await tester.tap(find.byKey(const ValueKey('device-type-tomada-turnOff')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('device-remove-luz1')));
      await tester.tap(find.byKey(const ValueKey('device-remove-luz1')));
      await tester.pump();
      expect(find.byKey(const ValueKey('device-action-luz1')), findsNothing);
      final saved = await _save(tester, alexa);
      expect(saved.deviceActions, [
        const WakeDeviceAction(entityId: 'tomada', name: 'Cafeteira', action: WakeActionType.turnOff, delayMin: 5),
      ]);
    });

    testWidgets('dispositivo sem brilho não oferece a opção Brilho', (tester) async {
      final alexa = _alexa(plans: [
        _plan.copyWith(deviceActions: const [
          WakeDeviceAction(entityId: 'tomada', name: 'Cafeteira', action: WakeActionType.turnOn),
        ]),
      ]);
      await _open(tester, alexa);
      final chip = tester.widget<ChoiceChip>(find.byKey(const ValueKey('device-type-tomada-setBrightness')));
      expect(chip.onSelected, isNull);
    });

    testWidgets('ações duplicadas vindas do banco: salvar mostra o erro de validação', (tester) async {
      const a = WakeDeviceAction(entityId: 'luz1', name: 'Luz do quarto', action: WakeActionType.turnOn);
      final alexa = _alexa(plans: [_plan.copyWith(deviceActions: const [a, a])]);
      await _open(tester, alexa);
      await tester.ensureVisible(find.byKey(const Key('wake-save')));
      await tester.tap(find.byKey(const Key('wake-save')));
      await tester.pump();
      expect(find.text('Cada dispositivo só pode aparecer uma vez no despertar.'), findsOneWidget);
    });
  });
}
