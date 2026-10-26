// Unit tests for CleanTrack Chennai's core logic (no UI).
// Run with:  flutter test test/logic_test.dart
//
// Expected numbers were computed independently from the seed data
// (see docs/ARCHITECTURE.md, "Algorithms").

import 'package:flutter_test/flutter_test.dart';
import 'package:cleantrack_chennai/main.dart';

Complaint byId(String id) => store.byId(id)!;

void main() {
  setUpAll(() async {
    // The global store seeds itself after a short simulated load.
    // Wait for that so it cannot re-seed in the middle of a test.
    while (store.loading) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  });

  setUp(() => store.seed());

  group('Geometry', () {
    test('haversine: depot to T. Nagar ward centre is about 6.03 km', () {
      final d = haversineM(depotLat, depotLon, 13.0418, 80.2341);
      expect(d, closeTo(6033, 2));
    });

    test('haversine: distance to the same point is zero', () {
      expect(haversineM(13.1, 80.2, 13.1, 80.2), closeTo(0, 1e-9));
    });
  });

  group('Seed data', () {
    test('loads 16 complaints, 20 bins and 4 vehicles', () {
      expect(store.complaints.length, 16);
      expect(store.bins.length, 20);
      expect(store.trucks.length, 4);
    });

    test('every complaint starts with an audit trail', () {
      for (final c in store.complaints) {
        expect(c.audit.length >= 2, isTrue);
      }
    });
  });

  group('Chronic GVP detection (3+ reports within 150 m in 30 days)', () {
    test('finds exactly two chronic GVPs in the seed data', () {
      expect(store.gvps.length, 2);
    });

    test('Elaya Street (Tondiarpet) is a GVP with 3 reports', () {
      final g = store.gvpFor(byId('CT-2026-1004'));
      expect(g, isNotNull);
      expect(g!.reports.length, 3);
      expect(g.ward, 'Tondiarpet');
    });

    test('an isolated complaint is not a GVP', () {
      // Pondy Bazaar side lane is ~306 m from the T. Nagar terminus cluster.
      expect(store.gvpFor(byId('CT-2026-1011')), isNull);
    });

    test('a new report at a GVP spot is flagged in its audit log', () {
      final e = byId('CT-2026-1004');
      final c = store.report(
        location: 'Elaya Street again',
        wardIndex: 3,
        category: Category.mixed,
        priority: Priority.high,
        description: 'Fresh dumping at the same corner',
        photo: 'test.jpg',
        lat: e.lat,
        lon: e.lon,
      );
      expect(store.gvpFor(c), isNotNull);
      expect(c.audit.any((a) => a.text.contains('Chronic')), isTrue);
    });
  });

  group('IoT bin sensors and threshold', () {
    test('8 bins are urgent at the default 75% threshold', () {
      expect(store.threshold, 75);
      expect(store.bins.where((b) => b.urgent).length, 8);
    });

    test('raising the threshold to 95% leaves 1 urgent bin', () {
      store.setThreshold(95);
      expect(store.bins.where((b) => b.urgent).length, 1);
    });

    test('HC-SR04 echo distance matches the fill level', () {
      final b = store.binById('CHN-TND-01')!; // 96% full, 120 cm deep
      expect(b.echoCm, closeTo(4.8, 1e-9));
    });

    test('crossing the threshold writes an ALERT to the sensor log', () {
      final b = store.binById('CHN-ROY-01')!; // 70%
      store.setFill(b, 90);
      expect(store.sensorLog.first.contains('[ALERT]'), isTrue);
    });

    test('fill level is clamped to 0-100', () {
      final b = store.binById('CHN-ADY-01')!;
      store.setFill(b, 180);
      expect(b.fill, 100);
      store.setFill(b, -5);
      expect(b.fill, 0);
    });

    test('an overflow report marks the nearest bin 100% full', () {
      store.report(
        location: 'Near Usman Road',
        wardIndex: 0,
        category: Category.overflow,
        priority: Priority.high,
        description: 'Bin overflowing onto the road',
        photo: 'test.jpg',
      );
      // Ward centre is 141 m from CHN-TNG-01, its nearest bin.
      expect(store.binById('CHN-TNG-01')!.fill, 100);
    });
  });

  group('Need-based routing vs fixed route', () {
    test('fixed daily route through all 20 bins is about 77.3 km', () {
      expect(store.fixedRouteKm(), closeTo(77.34, 0.05));
    });

    test('need-based route has 18 stops and is about 43.9 km', () {
      final r = store.suggestRoute();
      final km = r.fold<double>(0, (s, x) => s + x.km);
      expect(r.length, 18);
      expect(km, closeTo(43.90, 0.05));
      expect(km < store.fixedRouteKm(), isTrue);
    });

    test('route contains only open complaints and urgent bins', () {
      for (final s in store.suggestRoute()) {
        final c = s.complaint, b = s.bin;
        if (c != null) expect(c.status.isOpen, isTrue);
        if (b != null) expect(b.urgent, isTrue);
      }
    });

    test('stream-wise trip keeps one waste stream', () {
      for (final s in store.suggestRoute(trip: WasteStream.wet)) {
        expect(s.stream, WasteStream.wet);
      }
    });
  });

  group('Fleet dispatch rules', () {
    test('a compactor cannot be sent into a narrow lane', () {
      final err = store.assignTruck(
          store.truckById('TRK-CMP-02')!, store.binById('CHN-TND-01')!);
      expect(err, isNotNull);
      expect(err!.contains('narrow lane'), isTrue);
    });

    test('a vehicle under maintenance cannot be assigned', () {
      final err = store.assignTruck(
          store.truckById('TRK-SWP-04')!, store.binById('CHN-TNG-01')!);
      expect(err!.contains('maintenance'), isTrue);
    });

    test('the E-tricycle can be assigned to a narrow lane', () {
      final t = store.truckById('TRK-ET-01')!;
      expect(store.assignTruck(t, store.binById('CHN-TND-01')!), isNull);
      expect(t.assigned.contains('CHN-TND-01'), isTrue);
      expect(t.status, TruckStatus.enRoute);
    });
  });

  group('Live route simulation', () {
    test('E-tricycle micro-route: complaint first, then both Zone 4 bins', () {
      final t = store.truckById('TRK-ET-01')!;
      store.startRoute(t);
      expect(store.liveRoute.length, 3);
      expect(store.liveRoute.first.complaint?.id, 'CT-2026-1004');
    });

    test('reaching a complaint does NOT resolve it', () {
      store.startRoute(store.truckById('TRK-ET-01')!);
      store.advanceRoute();
      expect(byId('CT-2026-1004').status, Status.inProgress);
    });

    test('finishing the route empties the bins and frees the vehicle', () {
      final t = store.truckById('TRK-ET-01')!;
      store.startRoute(t);
      store.advanceRoute();
      store.advanceRoute();
      store.advanceRoute();
      expect(store.binById('CHN-TND-01')!.fill, 0);
      expect(store.binById('CHN-TND-02')!.fill, 0);
      expect(t.status, TruckStatus.available);
    });
  });

  group('Verified closure workflow', () {
    test('claim -> approve -> citizen confirm', () {
      final c = byId('CT-2026-1001');
      store.startWork(c);
      store.submitClaim(c, 'after.jpg', c.lat + .0001, c.lon);
      expect(c.status, Status.claim);
      expect(c.claimDistanceM! < kGpsLimitM, isTrue);
      expect(c.audit.last.text.contains('GPS MISMATCH'), isFalse);
      store.approve(c, 'Looks clean');
      expect(c.status, Status.verified);
      store.confirmByCitizen(c);
      expect(c.citizenFeedback, 'confirmed');
    });

    test('a claim filed 500+ m away is flagged as a GPS mismatch', () {
      final c = byId('CT-2026-1003');
      store.startWork(c);
      store.submitClaim(c, 'after.jpg', c.lat + .005, c.lon);
      expect(c.claimDistanceM! > kGpsLimitM, isTrue);
      expect(c.audit.last.text.contains('GPS MISMATCH'), isTrue);
    });

    test('reviewer rejection reopens and wipes the evidence', () {
      final c = byId('CT-2026-1005'); // seeded as an open claim
      store.reject(c, 'Debris still visible');
      expect(c.status, Status.reopened);
      expect(c.afterPhoto, isNull);
      expect(c.claimTime, isNull);
    });

    test('citizen dispute reopens a verified complaint', () {
      final c = byId('CT-2026-1001');
      store.startWork(c);
      store.submitClaim(c, 'after.jpg', c.lat, c.lon);
      store.approve(c, '');
      store.dispute(c, 'Garbage is back');
      expect(c.status, Status.reopened);
      expect(c.audit.last.text.contains('DISPUTED'), isTrue);
    });

    test('the audit log is append-only', () {
      final c = byId('CT-2026-1001');
      expect(() => c.audit.add(AuditEntry(DateTime.now(), 'x', 'y')),
          throwsUnsupportedError);
    });
  });

  group('Segregation and accountability metrics', () {
    test('Tondiarpet segregation score is 1/3 (2 of 3 reports mixed)', () {
      expect(store.segregationScore(3), closeTo(1 / 3, 1e-9));
    });

    test('Adyar scores 0 and Anna Nagar scores 1', () {
      expect(store.segregationScore(1), closeTo(0, 1e-9));
      expect(store.segregationScore(5), closeTo(1, 1e-9));
    });

    test('worker scorecard counts claims, rejections and GPS flags', () {
      final s = store.statsFor('Meena S');
      expect(s.assigned, 4);
      expect(s.open, 3);
      expect(s.claims, 2);
      expect(s.rejected, 1);
      expect(s.gpsFlags, 1);
      expect(s.reworkRate, closeTo(0.5, 1e-9));
    });
  });
}
