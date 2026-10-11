import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/domain/alexa.dart';

void main() {
  const plan = WakePlan(
    id: 'p1', label: 'Aula cedo', days: [1, 2, 3, 4, 5], hour: 7, minute: 0,
    echoDeviceId: 'ECHO', spotifyQuery: 'lofi',
  );
  Map<String, dynamic> legacy() => {
        'id': 'p1', 'label': 'Aula cedo', 'days': [1, 2, 3, 4, 5], 'time': '07:00:00',
        'echo_device_id': 'ECHO', 'spotify_query': 'lofi', 'music_first': true,
        'briefing_delay_min': 3, 'volume': 30, 'fallback_alarm': true, 'enabled': true,
      };

  group('WakeDeviceAction', () {
    test('toMap só leva brilho no setBrightness', () {
      expect(const WakeDeviceAction(entityId: 'l1', name: 'Luz', action: WakeActionType.turnOn).toMap(),
          {'entityId': 'l1', 'name': 'Luz', 'action': 'turnOn', 'delayMin': 0});
      expect(
          const WakeDeviceAction(entityId: 'l1', name: 'Luz', action: WakeActionType.turnOff, brightness: 40, delayMin: 5)
              .toMap(),
          {'entityId': 'l1', 'name': 'Luz', 'action': 'turnOff', 'delayMin': 5});
      expect(
          const WakeDeviceAction(entityId: 'l1', name: 'Luz', action: WakeActionType.setBrightness, brightness: 40, delayMin: 15)
              .toMap(),
          {'entityId': 'l1', 'name': 'Luz', 'action': 'setBrightness', 'brightness': 40, 'delayMin': 15});
    });

    test('tryParse lê entradas válidas e descarta as ruins', () {
      final ok = WakeDeviceAction.tryParse(
          {'entityId': 'l1', 'name': 'Luz', 'action': 'setBrightness', 'brightness': 30.0, 'delayMin': 10.0});
      expect(ok, const WakeDeviceAction(entityId: 'l1', name: 'Luz', action: WakeActionType.setBrightness, brightness: 30, delayMin: 10));
      expect(WakeDeviceAction.tryParse('x'), isNull);
      expect(WakeDeviceAction.tryParse(null), isNull);
      expect(WakeDeviceAction.tryParse({'name': 'Luz', 'action': 'turnOn'}), isNull); // sem entityId
      expect(WakeDeviceAction.tryParse({'entityId': '', 'action': 'turnOn'}), isNull);
      expect(WakeDeviceAction.tryParse({'entityId': 'l1', 'action': 'explodir'}), isNull);
      expect(WakeDeviceAction.tryParse({'entityId': 'l1'}), isNull);
    });

    test('tryParse completa o que falta e limita os números', () {
      final a = WakeDeviceAction.tryParse({'entityId': 'l1', 'action': 'turnOn', 'delayMin': 99})!;
      expect(a.name, 'l1'); // sem nome mostra o id
      expect(a.delayMin, 30);
      expect(WakeDeviceAction.tryParse({'entityId': 'l1', 'action': 'turnOn', 'delayMin': -4})!.delayMin, 0);
      expect(WakeDeviceAction.tryParse({'entityId': 'l1', 'action': 'turnOn', 'delayMin': 'x'})!.delayMin, 0);
      final b = WakeDeviceAction.tryParse({'entityId': 'l1', 'action': 'setBrightness', 'brightness': 500})!;
      expect(b.brightness, 100);
      expect(WakeDeviceAction.tryParse({'entityId': 'l1', 'action': 'setBrightness'})!.brightness, 100);
      expect(WakeDeviceAction.tryParse({'entityId': 'l1', 'action': 'setBrightness', 'brightness': -3})!.brightness, 0);
    });

    test('copyWith e igualdade', () {
      const a = WakeDeviceAction(entityId: 'l1', name: 'Luz', action: WakeActionType.turnOn);
      expect(a.copyWith(delayMin: 5).delayMin, 5);
      expect(a.copyWith(action: WakeActionType.setBrightness, brightness: 20).brightness, 20);
      expect(a, const WakeDeviceAction(entityId: 'l1', name: 'Luz', action: WakeActionType.turnOn));
      expect(a.hashCode, const WakeDeviceAction(entityId: 'l1', name: 'Luz', action: WakeActionType.turnOn).hashCode);
      expect(a, isNot(a.copyWith(delayMin: 1)));
    });
  });

  group('WakePlan inteligente', () {
    test('padrões: clima ligado, sem dispositivos, alarme no celular como reserva', () {
      expect(plan.includeWeather, isTrue);
      expect(plan.deviceActions, isEmpty);
      expect(plan.phoneAlarm, PhoneAlarm.fallback);
      final m = plan.toMap();
      expect(m['include_weather'], true);
      expect(m['device_actions'], <Object>[]);
      expect(m['phone_alarm'], 'fallback');
    });

    test('plano antigo (sem as colunas novas) lê com os padrões e continua igual', () {
      final read = WakePlan.fromMap(legacy());
      expect(read, plan);
      expect(read.hashCode, plan.hashCode);
      expect(read.includeWeather, isTrue);
      expect(read.phoneAlarm, PhoneAlarm.fallback);
      expect(read.deviceActions, isEmpty);
    });

    test('ida e volta com clima desligado, dispositivos e phone_alarm', () {
      final p = plan.copyWith(
        includeWeather: false,
        phoneAlarm: PhoneAlarm.always,
        deviceActions: const [
          WakeDeviceAction(entityId: 'l1', name: 'Luz do quarto', action: WakeActionType.setBrightness, brightness: 30, delayMin: 5),
          WakeDeviceAction(entityId: 'c1', name: 'Cafeteira', action: WakeActionType.turnOn),
        ],
      );
      final map = p.toMap();
      expect(map['include_weather'], false);
      expect(map['phone_alarm'], 'always');
      expect((map['device_actions'] as List).first, {
        'entityId': 'l1', 'name': 'Luz do quarto', 'action': 'setBrightness', 'brightness': 30, 'delayMin': 5,
      });
      final read = WakePlan.fromMap({...map, 'time': '07:00:00'});
      expect(read, p);
      expect(read.hashCode, p.hashCode);
      expect(read, isNot(plan));
      expect(p.copyWith(label: 'x').deviceActions, hasLength(2));
    });

    test('fromMap tolera device_actions e phone_alarm quebrados', () {
      final read = WakePlan.fromMap({
        ...legacy(),
        'include_weather': null,
        'phone_alarm': 'sempre',
        'device_actions': [
          {'entityId': 'l1', 'name': 'Luz', 'action': 'turnOff'},
          'lixo',
          {'action': 'turnOn'},
          42,
        ],
      });
      expect(read.includeWeather, isTrue);
      expect(read.phoneAlarm, PhoneAlarm.fallback);
      expect(read.deviceActions.map((a) => a.entityId), ['l1']);
      expect(WakePlan.fromMap({...legacy(), 'device_actions': 'x'}).deviceActions, isEmpty);
      expect(WakePlan.fromMap({...legacy(), 'device_actions': null}).deviceActions, isEmpty);
      expect(WakePlan.fromMap({...legacy(), 'phone_alarm': 'never'}).phoneAlarm, PhoneAlarm.never);
    });

    test('validateWakePlan: ações dos dispositivos', () {
      const on = WakeDeviceAction(entityId: 'l1', name: 'Luz', action: WakeActionType.turnOn);
      expect(validateWakePlan(plan.copyWith(deviceActions: const [on])), isNull);
      expect(
          validateWakePlan(plan.copyWith(deviceActions: [on, on.copyWith(action: WakeActionType.turnOff)])),
          'Cada dispositivo só pode aparecer uma vez no despertar.');
      expect(validateWakePlan(plan.copyWith(deviceActions: [on.copyWith(delayMin: 31)])),
          'O atraso de cada dispositivo deve ficar entre 0 e 30 min.');
      expect(validateWakePlan(plan.copyWith(deviceActions: [on.copyWith(delayMin: -1)])),
          'O atraso de cada dispositivo deve ficar entre 0 e 30 min.');
      expect(
          validateWakePlan(plan.copyWith(
              deviceActions: [on.copyWith(action: WakeActionType.setBrightness, brightness: 101)])),
          'O brilho deve ficar entre 0 e 100%.');
      expect(
          validateWakePlan(plan.copyWith(
              deviceActions: [on.copyWith(action: WakeActionType.setBrightness)])),
          'O brilho deve ficar entre 0 e 100%.');
      expect(validateWakePlan(plan.copyWith(deviceActions: [on.copyWith(entityId: '')])),
          'Escolha o dispositivo de cada ação.');
      expect(
          validateWakePlan(plan.copyWith(deviceActions: [
            for (var i = 0; i < maxWakeDeviceActions + 1; i++) on.copyWith(entityId: 'l$i'),
          ])),
          'No máximo $maxWakeDeviceActions dispositivos por despertar.');
    });
  });
}
