import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/location/location_background.dart';
import 'package:organizacional/location/location_service.dart';
import 'package:organizacional/location/report_policy.dart';

class FakeSource implements LocationBackendSource {
  FakeSource({
    this.hasSession = true,
    this.config = const HomeReportConfig(homeLat: -19.9167, homeLon: -45.7),
    this.failRead = false,
    this.failUpsert = false,
  });

  @override
  bool hasSession;
  HomeReportConfig? config;
  bool failRead;
  bool failUpsert;
  final upserts = <GeoFix>[];

  @override
  Future<HomeReportConfig?> readConfig() async {
    if (failRead) throw Exception('sem rede');
    return config;
  }

  @override
  Future<void> upsertLocation(GeoFix fix) async {
    if (failUpsert) throw Exception('sem rede');
    upserts.add(fix);
  }
}

class FakeService implements LocationService {
  FakeService({this.level = LocationPermissionLevel.always, this.throws = false});

  LocationPermissionLevel level;
  GeoFix? fix = const GeoFix(lat: -19.9167, lon: -45.7, accuracyM: 9);
  bool throws;
  Duration? timeout;
  int fixCalls = 0;

  @override
  Future<LocationPermissionLevel> permission() async => level;

  @override
  Future<LocationPermissionLevel> requestPermission({bool background = false}) async => level;

  @override
  Future<GeoFix?> currentFix({Duration timeout = const Duration(seconds: 25)}) async {
    fixCalls++;
    this.timeout = timeout;
    if (throws) throw Exception('gps');
    return fix;
  }
}

void main() {
  test('constantes da tarefa', () {
    expect(locationReportTask, 'locationReport');
    expect(locationReportFrequency, const Duration(minutes: 15));
    expect(locationReportFixTimeout, const Duration(seconds: 30));
  });

  test('reporta com casa, chave ligada e permissão "o tempo todo"', () async {
    final source = FakeSource();
    final service = FakeService();
    expect(await reportLocationInBackground(source: source, service: service), isTrue);
    expect(source.upserts.single.accuracyM, 9);
    expect(service.timeout, const Duration(seconds: 30));
  });

  test('sem sessão não faz nada', () async {
    final source = FakeSource(hasSession: false);
    final service = FakeService();
    expect(await reportLocationInBackground(source: source, service: service), isFalse);
    expect(service.fixCalls, 0);
    expect(source.upserts, isEmpty);
  });

  test('sem casa, sem ajustes ou com a chave desligada não pede o GPS', () async {
    for (final cfg in <HomeReportConfig?>[
      null,
      const HomeReportConfig(),
      const HomeReportConfig(homeLat: -19.9167, homeLon: -45.7, requireHome: false),
    ]) {
      final source = FakeSource(config: cfg);
      final service = FakeService();
      expect(await reportLocationInBackground(source: source, service: service), isFalse);
      expect(service.fixCalls, 0);
      expect(source.upserts, isEmpty);
    }
  });

  test('só com "o tempo todo": enquanto em uso, negada e GPS desligado não reportam', () async {
    for (final l in LocationPermissionLevel.values.where((l) => l != LocationPermissionLevel.always)) {
      final source = FakeSource();
      final service = FakeService(level: l);
      expect(await reportLocationInBackground(source: source, service: service), isFalse, reason: '$l');
      expect(service.fixCalls, 0, reason: '$l');
    }
  });

  test('sem posição não grava', () async {
    final source = FakeSource();
    final service = FakeService()..fix = null;
    expect(await reportLocationInBackground(source: source, service: service), isFalse);
    expect(source.upserts, isEmpty);
  });

  test('qualquer falha é engolida', () async {
    expect(await reportLocationInBackground(source: FakeSource(failRead: true), service: FakeService()), isFalse);
    expect(await reportLocationInBackground(source: FakeSource(failUpsert: true), service: FakeService()), isFalse);
    expect(await reportLocationInBackground(source: FakeSource(), service: FakeService(throws: true)), isFalse);
  });
}
