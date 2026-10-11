import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/location_repository.dart';
import 'package:organizacional/data/memory_location_repository.dart';
import 'package:organizacional/data/repository.dart';
import 'package:organizacional/location/location_service.dart';

void main() {
  test('emite null sem relatório e depois cada relatório', () async {
    final repo = MemoryLocationRepository();
    final seen = <LocationReport?>[];
    final sub = repo.watchLocation().listen(seen.add);
    await Future<void>.delayed(Duration.zero);
    final at = DateTime(2026, 10, 12, 7);
    await repo.report(const GeoFix(lat: 1, lon: 2, accuracyM: 8), at);
    await Future<void>.delayed(Duration.zero);
    expect(seen.length, 2);
    expect(seen.first, isNull);
    expect(seen.last!.fix.lat, 1);
    expect(seen.last!.fix.accuracyM, 8);
    expect(seen.last!.reportedAt, at);
    expect(repo.reports, hasLength(1));
    await sub.cancel();
  });

  test('failWrites lança RepositoryException e não grava', () async {
    final repo = MemoryLocationRepository(failWrites: true);
    await expectLater(
        repo.report(const GeoFix(lat: 1, lon: 2), DateTime(2026)), throwsA(isA<RepositoryException>()));
    expect(await repo.watchLocation().first, isNull);
    expect(repo.reports, isEmpty);
  });

  test('o estado inicial é entregue a quem começa a ouvir', () async {
    final initial = LocationReport(fix: const GeoFix(lat: 3, lon: 4), reportedAt: DateTime(2026));
    final repo = MemoryLocationRepository(initial: initial);
    expect((await repo.watchLocation().first)!.fix.lon, 4);
  });
}
