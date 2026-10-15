import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/app/providers.dart';
import 'package:organizacional/data/location_repository.dart';
import 'package:organizacional/data/memory_location_repository.dart';
import 'package:organizacional/data/memory_settings_repository.dart';
import 'package:organizacional/domain/user_settings.dart';
import 'package:organizacional/location/location_report_sync.dart';
import 'package:organizacional/location/location_service.dart';

class FakeLocationService implements LocationService {
  FakeLocationService({this.level = LocationPermissionLevel.whileInUse});

  LocationPermissionLevel level;
  GeoFix? fix = const GeoFix(lat: -19.93, lon: -43.94, accuracyM: 12);
  int fixCalls = 0;

  @override
  Future<LocationPermissionLevel> permission() async => level;

  @override
  Future<LocationPermissionLevel> requestPermission({bool background = false}) async => level;

  @override
  Future<GeoFix?> currentFix({Duration timeout = const Duration(seconds: 25)}) async {
    fixCalls++;
    return fix;
  }
}

const _homeSettings = UserSettings(homeLat: -19.93, homeLon: -43.94, requireHome: true);

void main() {
  late DateTime now;
  late MemoryLocationRepository repo;
  late MemorySettingsRepository settings;
  late FakeLocationService service;
  var signedIn = true;

  ProviderContainer build({UserSettings initial = _homeSettings}) {
    now = DateTime(2026, 10, 11, 12);
    signedIn = true;
    repo = MemoryLocationRepository();
    settings = MemorySettingsRepository(initial: initial);
    final container = ProviderContainer(overrides: [
      settingsRepositoryProvider.overrideWithValue(settings),
      locationRepositoryProvider.overrideWithValue(repo),
      locationServiceProvider.overrideWithValue(service),
      clockProvider.overrideWithValue(() => now),
      locationSignedInProvider.overrideWithValue(() => signedIn),
    ]);
    addTearDown(container.dispose);
    container.listen(locationReportSyncProvider, (_, _) {});
    return container;
  }

  setUp(() => service = FakeLocationService());

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  testWidgets('reporta ao iniciar quando casa, chave e permissão valem', (tester) async {
    build();
    await settle(tester);
    expect(repo.reports, hasLength(1));
    expect(repo.reports.single.fix.lat, -19.93);
    expect(repo.reports.single.reportedAt, now);
  });

  testWidgets('aceita também a permissão "o tempo todo"', (tester) async {
    service.level = LocationPermissionLevel.always;
    build();
    await settle(tester);
    expect(repo.reports, hasLength(1));
  });

  testWidgets('não reporta sem casa', (tester) async {
    build(initial: const UserSettings());
    await settle(tester);
    expect(repo.reports, isEmpty);
    expect(service.fixCalls, 0);
  });

  testWidgets('não reporta com a chave "só em casa" desligada', (tester) async {
    build(initial: const UserSettings(homeLat: -19.93, homeLon: -43.94, requireHome: false));
    await settle(tester);
    expect(repo.reports, isEmpty);
  });

  testWidgets('não reporta com permissão negada, negada de vez ou GPS desligado', (tester) async {
    for (final l in [
      LocationPermissionLevel.denied,
      LocationPermissionLevel.deniedForever,
      LocationPermissionLevel.serviceDisabled,
    ]) {
      service = FakeLocationService(level: l);
      build();
      await settle(tester);
      expect(repo.reports, isEmpty, reason: '$l');
      expect(service.fixCalls, 0, reason: '$l');
    }
  });

  testWidgets('não reporta sem sessão', (tester) async {
    signedIn = true;
    build();
    signedIn = false;
    // a leitura inicial já aconteceu com sessão; refaz o cenário sem sessão
    await settle(tester);
    repo.reports.clear();
    now = now.add(const Duration(minutes: 5));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);
    expect(repo.reports, isEmpty);
  });

  testWidgets('GPS sem posição ou repositório com falha não derrubam nada', (tester) async {
    service.fix = null;
    build();
    await settle(tester);
    expect(repo.reports, isEmpty);

    service = FakeLocationService();
    build();
    repo.failWrites = true;
    now = now.add(const Duration(minutes: 5));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);
    expect(repo.reports, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ao retomar o app reporta de novo, respeitando 2 minutos', (tester) async {
    build();
    await settle(tester);
    expect(repo.reports, hasLength(1));

    now = now.add(const Duration(seconds: 90));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);
    expect(repo.reports, hasLength(1), reason: 'menos de 2 min desde o último');

    now = now.add(const Duration(seconds: 30)); // 2 min exatos
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);
    expect(repo.reports, hasLength(2));
  });

  testWidgets('só reage à retomada, não a pausa ou inatividade', (tester) async {
    build();
    await settle(tester);
    now = now.add(const Duration(minutes: 10));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await settle(tester);
    expect(repo.reports, hasLength(1));
  });

  testWidgets('definir a casa ou ligar a chave reporta (depois do intervalo)', (tester) async {
    build(initial: const UserSettings());
    await settle(tester);
    expect(repo.reports, isEmpty);

    await settings.setHome(-19.93, -43.94);
    await settle(tester);
    expect(repo.reports, hasLength(1), reason: 'casa definida');

    await settings.setRequireHome(false);
    await settle(tester);
    now = now.add(const Duration(minutes: 3));
    await settings.setRequireHome(true);
    await settle(tester);
    expect(repo.reports, hasLength(2), reason: 'chave religada após 3 min');
  });

  testWidgets('mudança de casa dentro de 2 minutos não reporta de novo', (tester) async {
    build();
    await settle(tester);
    now = now.add(const Duration(seconds: 30));
    await settings.setHome(-23.0, -46.0);
    await settle(tester);
    expect(repo.reports, hasLength(1));
  });

  testWidgets('mudar só o tema não dispara relatório', (tester) async {
    build();
    await settle(tester);
    now = now.add(const Duration(minutes: 10));
    await settings.setTheme('safira');
    await settle(tester);
    expect(repo.reports, hasLength(1));
  });

  testWidgets('descartado o provider, retomar o app não reporta mais', (tester) async {
    final c = build();
    await settle(tester);
    c.dispose();
    now = now.add(const Duration(minutes: 10));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);
    expect(repo.reports, hasLength(1));
  });
}
