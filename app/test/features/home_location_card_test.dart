import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/location_repository.dart';
import 'package:organizacional/data/memory_location_repository.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/data/memory_settings_repository.dart';
import 'package:organizacional/domain/user_settings.dart';
import 'package:organizacional/location/location_service.dart';

import '../helpers.dart';

/// Serviço de localização falso: níveis de permissão e posição programáveis.
class FakeLocationService implements LocationService {
  FakeLocationService({
    this.level = LocationPermissionLevel.denied,
    this.onRequest = LocationPermissionLevel.whileInUse,
    this.onBackground = LocationPermissionLevel.always,
    this.fix = const GeoFix(lat: -19.9167, lon: -43.9345, accuracyM: 8),
  });

  LocationPermissionLevel level;

  /// O que o pedido em primeiro plano resulta.
  LocationPermissionLevel onRequest;

  /// O que o pedido "o tempo todo" resulta.
  LocationPermissionLevel onBackground;
  GeoFix? fix;
  final calls = <String>[];

  /// Só os pedidos de permissão (a sincronização em primeiro plano do app
  /// também chama [currentFix] sozinha quando há casa definida).
  List<String> get requests => calls.where((c) => c.startsWith('request')).toList();

  @override
  Future<LocationPermissionLevel> permission() async => level;

  @override
  Future<LocationPermissionLevel> requestPermission({bool background = false}) async {
    calls.add(background ? 'request-background' : 'request');
    level = background ? onBackground : onRequest;
    return level;
  }

  @override
  Future<GeoFix?> currentFix({Duration timeout = const Duration(seconds: 25)}) async {
    calls.add('fix');
    return fix;
  }
}

const _size = Size(1000, 2200);
const _home = UserSettings(homeLat: -19.9167, homeLon: -43.9345);

MemoryLocationRepository _locationAt(double metersNorth, {double? acc, Duration age = Duration.zero}) {
  const mPerDeg = 111194.9;
  return MemoryLocationRepository(
    initial: LocationReport(
      fix: GeoFix(lat: -19.9167 + metersNorth / mPerDeg, lon: -43.9345, accuracyM: acc),
      reportedAt: defaultNow.subtract(age),
    ),
  );
}

Future<void> _open(
  WidgetTester tester, {
  MemorySettingsRepository? settings,
  MemoryLocationRepository? location,
  LocationService? service,
}) =>
    pumpApp(tester, MemoryRepository(),
        location: '/ajustes',
        settings: settings ?? MemorySettingsRepository(),
        size: _size,
        locationRepo: location,
        locationService: service);

void main() {
  group('sem casa definida', () {
    testWidgets('mostra o botão, o aviso de bateria e não mostra status', (tester) async {
      await _open(tester);
      expect(find.byKey(const Key('home-set')), findsOneWidget);
      expect(find.text('Definir minha casa aqui'), findsOneWidget);
      expect(find.byKey(const Key('home-status')), findsNothing);
      expect(find.byKey(const Key('home-require-switch')), findsNothing);
      expect(find.textContaining('bateria'), findsOneWidget);
      expect(find.textContaining('o tempo todo'), findsOneWidget);
    });

    testWidgets('permissão já concedida: confirma com a precisão e salva a casa', (tester) async {
      final settings = MemorySettingsRepository();
      final svc = FakeLocationService(level: LocationPermissionLevel.always);
      await _open(tester, settings: settings, service: svc);
      await tester.tap(find.byKey(const Key('home-set')));
      await tester.pumpAndSettle();
      expect(find.text('Precisão do GPS: cerca de 8 m'), findsOneWidget);
      expect(find.byKey(const Key('home-weak-signal')), findsNothing);
      await tester.tap(find.byKey(const Key('home-confirm')));
      await tester.pumpAndSettle();
      final s = await settings.watchSettings().first;
      expect([s.homeLat, s.homeLon], [-19.9167, -43.9345]);
      expect(find.text('Casa definida · raio 50 m'), findsOneWidget);
      expect(svc.requests, isEmpty); // já tinha "o tempo todo": nada a pedir
      expect(find.byKey(const Key('home-bg-continue')), findsNothing);
    });

    testWidgets('permissão negada: pede primeiro plano e depois explica e pede "o tempo todo"', (tester) async {
      final settings = MemorySettingsRepository();
      final svc = FakeLocationService();
      await _open(tester, settings: settings, service: svc);
      await tester.tap(find.byKey(const Key('home-set')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home-confirm')));
      await tester.pumpAndSettle();
      expect((await settings.watchSettings().first).hasHome, isTrue);
      // Segundo passo, com explicação.
      expect(find.byKey(const Key('home-bg-continue')), findsOneWidget);
      expect(find.textContaining('mesmo fechado'), findsOneWidget);
      await tester.tap(find.byKey(const Key('home-bg-continue')));
      await tester.pumpAndSettle();
      expect(svc.requests, ['request', 'request-background']);
      expect(find.byKey(const Key('home-background')), findsNothing);
    });

    testWidgets('recusar o "o tempo todo" mantém a casa e deixa o lembrete', (tester) async {
      final settings = MemorySettingsRepository();
      final svc = FakeLocationService(level: LocationPermissionLevel.whileInUse);
      await _open(tester, settings: settings, service: svc);
      await tester.tap(find.byKey(const Key('home-set')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home-confirm')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home-bg-skip')));
      await tester.pumpAndSettle();
      expect((await settings.watchSettings().first).hasHome, isTrue);
      expect(svc.requests, isEmpty);
      expect(find.byKey(const Key('home-background-note')), findsOneWidget);
    });

    testWidgets('precisão acima de 30 m avisa sinal fraco; cancelar não salva', (tester) async {
      final settings = MemorySettingsRepository();
      final svc = FakeLocationService(
        level: LocationPermissionLevel.always,
        fix: const GeoFix(lat: 1, lon: 2, accuracyM: 45),
      );
      await _open(tester, settings: settings, service: svc);
      await tester.tap(find.byKey(const Key('home-set')));
      await tester.pumpAndSettle();
      expect(find.text('Precisão do GPS: cerca de 45 m'), findsOneWidget);
      expect(find.text('Sinal fraco; tente perto de uma janela.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('home-cancel')));
      await tester.pumpAndSettle();
      expect((await settings.watchSettings().first).hasHome, isFalse);
      expect(find.byKey(const Key('home-set')), findsOneWidget);
    });

    testWidgets('exatamente 30 m não avisa', (tester) async {
      final svc = FakeLocationService(
        level: LocationPermissionLevel.always,
        fix: const GeoFix(lat: 1, lon: 2, accuracyM: 30),
      );
      await _open(tester, service: svc);
      await tester.tap(find.byKey(const Key('home-set')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('home-weak-signal')), findsNothing);
    });

    testWidgets('permissão negada de vez: explica como liberar nos Ajustes do Android', (tester) async {
      final settings = MemorySettingsRepository();
      final svc = FakeLocationService(level: LocationPermissionLevel.deniedForever);
      await _open(tester, settings: settings, service: svc);
      await tester.tap(find.byKey(const Key('home-set')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('home-permission-help')), findsOneWidget);
      expect(find.textContaining('Ajustes do Android'), findsOneWidget);
      expect(svc.calls.where((c) => c != 'fix'), isEmpty); // nem tenta pedir ou ler a posição
      expect((await settings.watchSettings().first).hasHome, isFalse);
      expect(find.byKey(const Key('home-set')), findsOneWidget);
    });

    testWidgets('o usuário nega o pedido: mensagem e nada salvo', (tester) async {
      final settings = MemorySettingsRepository();
      final svc = FakeLocationService(onRequest: LocationPermissionLevel.denied);
      await _open(tester, settings: settings, service: svc);
      await tester.tap(find.byKey(const Key('home-set')));
      await tester.pumpAndSettle();
      expect(find.text('Sem a permissão de localização não dá para definir a casa.'), findsOneWidget);
      expect(find.byKey(const Key('home-permission-help')), findsNothing);
      expect(svc.requests, ['request']);
      expect((await settings.watchSettings().first).hasHome, isFalse);
    });

    testWidgets('o pedido vira "negada de vez": mostra a ajuda', (tester) async {
      final svc = FakeLocationService(onRequest: LocationPermissionLevel.deniedForever);
      await _open(tester, service: svc);
      await tester.tap(find.byKey(const Key('home-set')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('home-permission-help')), findsOneWidget);
    });

    testWidgets('GPS desligado', (tester) async {
      final svc = FakeLocationService(level: LocationPermissionLevel.serviceDisabled);
      await _open(tester, service: svc);
      await tester.tap(find.byKey(const Key('home-set')));
      await tester.pumpAndSettle();
      expect(find.textContaining('GPS está desligado'), findsOneWidget);
    });

    testWidgets('sem posição (tempo esgotado): erro e nada salvo', (tester) async {
      final settings = MemorySettingsRepository();
      final svc = FakeLocationService(level: LocationPermissionLevel.always, fix: null);
      await _open(tester, settings: settings, service: svc);
      await tester.tap(find.byKey(const Key('home-set')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('home-error')), findsOneWidget);
      expect(find.textContaining('Não foi possível obter a sua localização'), findsOneWidget);
      expect((await settings.watchSettings().first).hasHome, isFalse);
    });

    testWidgets('falha ao salvar: erro em pt-BR e continua sem casa', (tester) async {
      final settings = MemorySettingsRepository(failWrites: true);
      final svc = FakeLocationService(level: LocationPermissionLevel.always);
      await _open(tester, settings: settings, service: svc);
      await tester.tap(find.byKey(const Key('home-set')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('Não foi possível salvar a casa.'), findsOneWidget);
      expect(find.byKey(const Key('home-set')), findsOneWidget);
      expect(find.byKey(const Key('home-status')), findsNothing);
    });

    testWidgets('serviço padrão (sem GPS): erro claro, sem travar', (tester) async {
      await _open(tester); // NoopLocationService: permissão negada e sem posição
      await tester.tap(find.byKey(const Key('home-set')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('home-error')), findsOneWidget);
    });
  });

  group('com casa definida', () {
    testWidgets('resumo, chave ligada e botões', (tester) async {
      await _open(tester, settings: MemorySettingsRepository(initial: _home), service: FakeLocationService(level: LocationPermissionLevel.always));
      expect(find.text('Casa definida · raio 50 m'), findsOneWidget);
      expect(find.text('Só tocar o despertar quando eu estiver em casa'), findsOneWidget);
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('home-require-switch'))).value, isTrue);
      expect(find.byKey(const Key('home-reset')), findsOneWidget);
      expect(find.byKey(const Key('home-remove')), findsOneWidget);
      expect(find.byKey(const Key('home-set')), findsNothing);
      expect(find.byKey(const Key('home-background-note')), findsNothing);
    });

    testWidgets('status: sem localização, em casa, fora e desatualizada', (tester) async {
      Future<String> statusFor(MemoryLocationRepository? loc) async {
        await _open(tester, settings: MemorySettingsRepository(initial: _home), location: loc);
        return tester.widget<Text>(find.byKey(const Key('home-status'))).data!;
      }

      expect(await statusFor(null), 'Sem localização recente');
      expect(await statusFor(_locationAt(10)), 'Em casa');
      expect(await statusFor(_locationAt(2300, acc: 10)), 'Fora (a 2,3 km)');
      expect(await statusFor(_locationAt(850, acc: 10)), 'Fora (a 850 m)');
      expect(await statusFor(_locationAt(10, age: const Duration(minutes: 50))), 'Sem localização recente');
      expect(await statusFor(_locationAt(78, acc: 30)), 'Posição incerta (a 78 m)');
    });

    testWidgets('o status acompanha novos relatórios', (tester) async {
      final loc = MemoryLocationRepository();
      await _open(tester, settings: MemorySettingsRepository(initial: _home), location: loc);
      expect(find.text('Sem localização recente'), findsOneWidget);
      await loc.report(const GeoFix(lat: -19.9167, lon: -43.9345, accuracyM: 5), defaultNow);
      await tester.pumpAndSettle();
      expect(find.text('Em casa'), findsOneWidget);
    });

    testWidgets('a chave grava require_home e preserva a casa', (tester) async {
      final settings = MemorySettingsRepository(initial: _home);
      await _open(tester, settings: settings);
      await tester.tap(find.byKey(const Key('home-require-switch')));
      await tester.pumpAndSettle();
      var s = await settings.watchSettings().first;
      expect([s.requireHome, s.hasHome], [false, true]);
      await tester.tap(find.byKey(const Key('home-require-switch')));
      await tester.pumpAndSettle();
      s = await settings.watchSettings().first;
      expect(s.requireHome, isTrue);
    });

    testWidgets('falha ao gravar a chave mantém o valor e avisa', (tester) async {
      final settings = MemorySettingsRepository(initial: _home);
      await _open(tester, settings: settings);
      settings.failWrites = true;
      await tester.tap(find.byKey(const Key('home-require-switch')));
      await tester.pumpAndSettle();
      expect(find.text('Não foi possível salvar.'), findsOneWidget);
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('home-require-switch'))).value, isTrue);
    });

    testWidgets('Remover casa limpa só a casa', (tester) async {
      final settings = MemorySettingsRepository(initial: _home.copyWith(theme: 'coral'));
      await _open(tester, settings: settings);
      await tester.tap(find.byKey(const Key('home-remove')));
      await tester.pumpAndSettle();
      final s = await settings.watchSettings().first;
      expect([s.hasHome, s.theme], [false, 'coral']);
      expect(find.byKey(const Key('home-set')), findsOneWidget);
    });

    testWidgets('falha ao remover mantém a casa', (tester) async {
      final settings = MemorySettingsRepository(initial: _home);
      await _open(tester, settings: settings);
      settings.failWrites = true;
      await tester.tap(find.byKey(const Key('home-remove')));
      await tester.pumpAndSettle();
      expect(find.text('Não foi possível remover a casa.'), findsOneWidget);
      expect(find.text('Casa definida · raio 50 m'), findsOneWidget);
    });

    testWidgets('Redefinir aqui troca o ponto', (tester) async {
      final settings = MemorySettingsRepository(initial: _home);
      final svc = FakeLocationService(
        level: LocationPermissionLevel.always,
        fix: const GeoFix(lat: -22.3, lon: -45.8, accuracyM: 12),
      );
      await _open(tester, settings: settings, service: svc);
      await tester.tap(find.byKey(const Key('home-reset')));
      await tester.pumpAndSettle();
      expect(find.text('Redefinir a casa aqui?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('home-confirm')));
      await tester.pumpAndSettle();
      final s = await settings.watchSettings().first;
      expect([s.homeLat, s.homeLon], [-22.3, -45.8]);
    });

    testWidgets('sem "o tempo todo": lembrete e botão que pede a permissão', (tester) async {
      final svc = FakeLocationService(level: LocationPermissionLevel.whileInUse);
      await _open(tester, settings: MemorySettingsRepository(initial: _home), service: svc);
      expect(find.byKey(const Key('home-background-note')), findsOneWidget);
      await tester.tap(find.byKey(const Key('home-background')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home-bg-continue')));
      await tester.pumpAndSettle();
      expect(svc.requests, ['request-background']);
      expect(find.byKey(const Key('home-background-note')), findsNothing);
    });

    testWidgets('"o tempo todo" negado de vez mostra a ajuda', (tester) async {
      final svc = FakeLocationService(
        level: LocationPermissionLevel.whileInUse,
        onBackground: LocationPermissionLevel.deniedForever,
      );
      await _open(tester, settings: MemorySettingsRepository(initial: _home), service: svc);
      await tester.tap(find.byKey(const Key('home-background')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home-bg-continue')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('home-permission-help')), findsOneWidget);
    });
  });
}
