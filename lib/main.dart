// CleanTrack Chennai - Smart Waste Management & Municipal Accountability
// HACK2IMPACT 2026 - single-file Flutter prototype for DartPad (dartpad.dev)
//
// HOW TO RUN: open https://dartpad.dev -> New -> Flutter -> delete the sample
// code -> paste this whole file -> press Run.
//
// LIVE DEMO: tap "RUN FULL DEMO" on Home for an 11-step automated walkthrough
// (sensor breach -> alert -> fleet -> route -> collection -> worker claim ->
// reviewer approval -> citizen confirmation -> audit trail).
//
// WHAT THIS PROTOTYPE SOLVES (problem -> feature):
//  1. Garbage Vulnerable Points  -> citizen geo-tagged reports, hotspot map and
//     automatic CHRONIC GVP detection (3+ reports within 150 m in 30 days).
//  2. Static, fuel-wasting routes -> simulated smart-bin fill levels and a
//     need-based route compared live against a fixed daily route (km + diesel).
//  3. Low segregation at source  -> waste streams (wet / dry / sanitary / C&D),
//     ward segregation scores, awareness-drive flags and stream-wise trips.
//  4. Accountability gaps        -> workers can only CLAIM; reviewers verify
//     photo + GPS + time; GPS-mismatch checks; citizen confirm/dispute;
//     append-only audit log; worker accountability scorecards.
//
// DEMO MODE: no Firebase, maps, sensors or photo upload are used (DartPad
// cannot use them). ALL complaints, locations, bin fill levels, counts,
// percentages, distances, diesel figures and routes are DEMO / SIMULATED data -
// never real-time municipal information.
// Demo PINs: Worker 1234, Reviewer 9999.

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

void main() => runApp(const CleanTrackApp());

// ───────────────────────── Theme colours ─────────────────────────
const kForest = Color(0xFF14532D);
const kForestDark = Color(0xFF0B3D20);
const kSage = Color(0xFFE6EFE1);
const kSageMid = Color(0xFFCFE0C8);
const kLime = Color(0xFFA3E635);
const kBg = Color(0xFFF3F7EF);
const kHigh = Color(0xFFD32F2F);
const kMed = Color(0xFFF57C00);
const kLow = Color(0xFF2E7D32);
const kBlue = Color(0xFF1565C0);
const kGvp = Color(0xFF6A1B9A);

// ───────────────────────── Demo rules (tunable) ─────────────────────────
const kGvpRadiusM = 150.0; // reports this close together = same spot
const kGvpMinReports = 3; // this many reports ...
const kGvpWindowDays = 30; // ... within this many days = Chronic GVP
const kDefaultThreshold = 75; // default collection threshold (tunable 60-95%)
const kBinDepthCm = 120.0; // HC-SR04 calibration depth (demo)
const kGpsLimitM = 200.0; // claim GPS further than this is flagged
const kDieselLPerKm = 0.35; // ASSUMED compactor-truck consumption (demo)
const kSegregationAlert = 0.6; // ward score below this -> awareness drive
const depotLat = 13.0827, depotLon = 80.2707; // assumed depot (demo)

// ───────────────────────── Models ─────────────────────────
enum Priority { high, medium, low }

extension PriorityX on Priority {
  String get label => const ['High', 'Medium', 'Low'][index];
  Color get color => const [kHigh, kMed, kLow][index];
  int get weight => const [3, 2, 1][index];
}

/// Waste streams that must stay separate from source to processing.
enum WasteStream { wet, dry, sanitary, cnd, mixed }

extension WasteStreamX on WasteStream {
  String get label =>
      const ['Wet', 'Dry', 'Sanitary', 'C&D debris', 'Mixed'][index];
  Color get color => const [
        Color(0xFF2E7D32),
        kBlue,
        Color(0xFFC2185B),
        Color(0xFF795548),
        Color(0xFF616161)
      ][index];
}

enum Category { plastic, wet, mixed, construction, overflow, sanitary }

extension CategoryX on Category {
  String get label => const [
        'Plastic',
        'Wet waste',
        'Mixed waste',
        'Construction debris',
        'Overflowing bin',
        'Sanitary waste'
      ][index];
  IconData get icon => const [
        Icons.local_drink,
        Icons.eco,
        Icons.delete_sweep,
        Icons.construction,
        Icons.delete_outline,
        Icons.sanitizer
      ][index];
  WasteStream get stream => const [
        WasteStream.dry,
        WasteStream.wet,
        WasteStream.mixed,
        WasteStream.cnd,
        WasteStream.mixed,
        WasteStream.sanitary
      ][index];
}

enum Status { pending, inProgress, claim, verified, reopened }

extension StatusX on Status {
  String get label => const [
        'Pending',
        'In Progress',
        'Cleanup Completed - Awaiting Verification',
        'Verified Resolved',
        'Reopened'
      ][index];
  String get shortLabel => const [
        'Pending',
        'In Progress',
        'Awaiting Verification',
        'Verified',
        'Reopened'
      ][index];
  Color get color =>
      const [Color(0xFF616161), kMed, kBlue, kLow, kHigh][index];
  bool get isOpen =>
      this == Status.pending ||
      this == Status.inProgress ||
      this == Status.reopened;
}

enum Role { citizen, worker, reviewer }

class Ward {
  final String name;
  final double lat, lon;
  const Ward(this.name, this.lat, this.lon);
}

const wards = [
  Ward('T. Nagar', 13.0418, 80.2341),
  Ward('Adyar', 13.0012, 80.2565),
  Ward('Velachery', 12.9815, 80.2180),
  Ward('Tondiarpet', 13.1260, 80.2900),
  Ward('Royapuram', 13.1130, 80.2950),
  Ward('Anna Nagar', 13.0850, 80.2101),
  Ward('Mylapore', 13.0368, 80.2676),
  Ward('Perungudi', 12.9650, 80.2461),
  Ward('Guindy', 13.0067, 80.2206),
  Ward('Kodambakkam', 13.0521, 80.2255),
];

const workers = ['Ravi Kumar', 'Meena S', 'Arul P'];

class AuditEntry {
  final DateTime time;
  final String actor;
  final String text;
  AuditEntry(this.time, this.actor, this.text);
}

class Complaint {
  final String id;
  final String location;
  final String ward;
  final int wardIndex;
  final Category category;
  final Priority priority;
  final String description;
  final double lat, lon;
  final bool gpsCaptured;
  final DateTime created;
  final String beforePhoto;
  final String worker;
  Status status;
  String? afterPhoto;
  DateTime? claimTime;
  double? claimLat, claimLon;
  String? reviewNote;
  String? citizenFeedback; // 'confirmed' once the reporting citizen agrees
  final List<AuditEntry> _audit = [];

  Complaint({
    required this.id,
    required this.location,
    required this.ward,
    required this.wardIndex,
    required this.category,
    required this.priority,
    required this.description,
    required this.lat,
    required this.lon,
    required this.gpsCaptured,
    required this.created,
    required this.beforePhoto,
    required this.worker,
    required this.status,
  });

  /// Append-only: entries can be added but never edited or removed.
  List<AuditEntry> get audit => List.unmodifiable(_audit);

  void log(String actor, String text, [DateTime? at]) =>
      _audit.add(AuditEntry(at ?? DateTime.now(), actor, text));

  double? get claimDistanceM {
    final la = claimLat, lo = claimLon;
    if (la == null || lo == null) return null;
    return haversineM(lat, lon, la, lo);
  }
}

/// Simulated smart bin (stands in for an IoT fill-level sensor).
class Bin {
  final String id;
  final String name;
  final int capacityL;
  final bool narrowLane; // lane under 3 m: E-tricycle only (Wards 38/39)
  final int wardIndex;
  final WasteStream stream;
  final double lat, lon;
  int fill;
  DateTime lastEmptied;
  Bin({
    required this.id,
    required this.name,
    required this.capacityL,
    this.narrowLane = false,
    required this.wardIndex,
    required this.stream,
    required this.lat,
    required this.lon,
    required this.fill,
    required this.lastEmptied,
  });
  String get ward => wards[wardIndex].name;
  bool get urgent => fill >= kBinThreshold;
  Color get fillColor =>
      fill >= kBinThreshold ? kHigh : (fill >= 50 ? kMed : kLow);

  /// Simulated HC-SR04 echo: distance from lid sensor to waste surface.
  double get echoCm => kBinDepthCm * (1 - fill / 100);
}

/// A Chronic Garbage Vulnerable Point: repeated dumping at one spot.
class Gvp {
  final int number;
  final List<Complaint> reports; // oldest first
  Gvp(this.number, this.reports);
  String get id => 'GVP-${number.toString().padLeft(2, '0')}';
  double get lat =>
      reports.map((c) => c.lat).reduce((a, b) => a + b) / reports.length;
  double get lon =>
      reports.map((c) => c.lon).reduce((a, b) => a + b) / reports.length;
  String get ward => reports.first.ward;
  String get location => reports.first.location;
  int get open => reports
      .where((c) => c.status.isOpen || c.status == Status.claim)
      .length;

  /// Times the spot was cleaned and verified, then dumped on again.
  int get redumped => reports
      .sublist(0, reports.length - 1)
      .where((c) => c.status == Status.verified)
      .length;
  DateTime get firstSeen => reports.first.created;
  DateTime get lastSeen => reports.last.created;
}

/// One stop on a collection route: either a complaint or a full bin.
class RouteStop {
  final Complaint? complaint;
  final Bin? bin;
  double km = 0;
  RouteStop({this.complaint, this.bin});
  double get lat => complaint?.lat ?? bin!.lat;
  double get lon => complaint?.lon ?? bin!.lon;
  String get title => complaint?.location ?? '${bin!.name} (${bin!.id})';
  String get ward => complaint?.ward ?? bin!.ward;
  WasteStream get stream => complaint?.category.stream ?? bin!.stream;
  int get weight {
    final c = complaint;
    if (c != null) return c.priority.weight;
    return bin!.fill >= 100 ? 3 : 2;
  }
}

class WorkerStats {
  final String name;
  int assigned = 0,
      open = 0,
      claims = 0,
      approved = 0,
      rejected = 0,
      gpsFlags = 0,
      disputes = 0;
  WorkerStats(this.name);

  /// Share of claims that came back (rejected by reviewer or disputed).
  double get reworkRate => claims == 0 ? 0 : (rejected + disputes) / claims;
}

double haversineM(double la1, double lo1, double la2, double lo2) {
  const r = 6371000.0;
  const d2r = math.pi / 180;
  final dLa = (la2 - la1) * d2r, dLo = (lo2 - lo1) * d2r;
  final a = math.sin(dLa / 2) * math.sin(dLa / 2) +
      math.cos(la1 * d2r) *
          math.cos(la2 * d2r) *
          math.sin(dLo / 2) *
          math.sin(dLo / 2);
  return 2 * r * math.asin(math.sqrt(a));
}

String fmt(DateTime t) {
  const m = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.day} ${m[t.month - 1]} ${t.year}, ${two(t.hour)}:${two(t.minute)}';
}

String fmtDay(DateTime t) {
  const m = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${t.day} ${m[t.month - 1]}';
}

String claimLogText(double distM) {
  final d = distM.toStringAsFixed(0);
  final flag = distM > kGpsLimitM ? ' [GPS MISMATCH]' : '';
  return 'Cleanup CLAIM submitted (after-photo, GPS $d m from site, timestamp). Not yet verified.$flag';
}

// ───────────────────────── Store (demo-mode backend) ─────────────────────────
class Store extends ChangeNotifier {
  List<Complaint> complaints = [];
  List<Bin> bins = [];
  int _next = 1001;
  Role role = Role.citizen;
  String workerName = workers[0];
  bool loading = true;
  final _rng = math.Random();

  // IoT sensor telemetry
  int threshold = kDefaultThreshold;
  List<String> sensorLog = [];

  // Fleet + live route
  List<Truck> trucks = [];
  Truck? routeTruck;
  List<RouteStop> liveRoute = [];
  int liveIdx = 0;
  List<double> liveOrigin = const [depotLat, depotLon];

  // Automated demo runner
  int demoStep = 0;
  bool demoRunning = false;

  Store() {
    _boot();
  }

  Future<void> _boot() async {
    await Future.delayed(const Duration(milliseconds: 900)); // simulated load
    seed();
    loading = false;
    notifyListeners();
  }

  void setRole(Role r) {
    role = r;
    notifyListeners();
  }

  void setWorker(String w) {
    workerName = w;
    notifyListeners();
  }

  void seed() {
    complaints = [];
    _next = 1001;
    _add('Near T. Nagar bus terminus', 0, .0010, .0008, Category.overflow,
        Priority.high, Status.pending, 0, 30,
        'Bin overflowing onto footpath, stray animals');
    _add('Adyar river bridge approach', 1, -.0008, .0012, Category.mixed,
        Priority.high, Status.inProgress, 1, 52,
        'Large mixed garbage heap near the bridge');
    _add('Velachery main road junction', 2, .0006, -.0010, Category.plastic,
        Priority.medium, Status.pending, 2, 20,
        'Plastic bags and bottles piled at junction');
    _add('Elaya Street Market Lane (W38)', 3, .0009, .0009, Category.wet,
        Priority.high, Status.pending, 0, 41,
        'Market vendors dumping vegetable waste; rotting, strong smell');
    _add('Royapuram fish market road', 4, .0009, -.0007, Category.mixed,
        Priority.medium, Status.claim, 1, 70,
        'Mixed waste beside the market wall');
    _add('Anna Nagar 2nd Avenue park edge', 5, -.0005, .0009, Category.plastic,
        Priority.low, Status.verified, 2, 96,
        'Plastic cups scattered near park gate',
        confirmed: true);
    _add('Mylapore tank street', 6, .0004, .0005, Category.wet,
        Priority.medium, Status.pending, 0, 12,
        'Temple flower waste not collected');
    _add('Perungudi approach road', 7, -.0010, -.0006, Category.construction,
        Priority.high, Status.reopened, 1, 110,
        'Construction debris blocking the lane',
        farClaim: true);
    _add('Guindy industrial estate gate', 8, .0007, .0010,
        Category.construction, Priority.low, Status.pending, 2, 8,
        'Small pile of rubble near gate');
    _add('Kodambakkam station road', 9, -.0004, -.0008, Category.overflow,
        Priority.medium, Status.inProgress, 0, 26,
        'Community bin overflowing since two days');
    _add('T. Nagar Pondy Bazaar side lane', 0, -.0012, -.0009,
        Category.plastic, Priority.low, Status.pending, 1, 5,
        'Plastic wrappers along the lane');
    // Older reports at the SAME spots -> these become Chronic GVPs.
    _add('Near T. Nagar bus terminus', 0, .0011, .0007, Category.overflow,
        Priority.medium, Status.verified, 0, 24 * 19,
        'Bin overflowed, was cleared - dumping started again',
        confirmed: true);
    _add('Near T. Nagar bus terminus', 0, .0009, .0009, Category.mixed,
        Priority.high, Status.verified, 0, 24 * 9,
        'Mixed garbage dumped at the same corner again',
        confirmed: true);
    _add('Elaya Street Market Lane (W38)', 3, .0010, .0008, Category.mixed,
        Priority.medium, Status.verified, 0, 24 * 21,
        'Market waste dumped beside the lane',
        confirmed: true);
    _add('Elaya Street Market Lane (W38)', 3, .0008, .0010, Category.mixed,
        Priority.high, Status.verified, 0, 24 * 6,
        'Same spot - mixed market waste piled again');
    _add('Velachery lake bund road', 2, -.0009, .0007, Category.sanitary,
        Priority.medium, Status.pending, 2, 15,
        'Sanitary waste and diapers dumped in the open');
    _seedBins();
    _seedTrucks();
    threshold = kDefaultThreshold;
    routeTruck = null;
    liveRoute = [];
    liveIdx = 0;
    sensorLog = [];
    logSensor('[ESP32_BOOT] HC-SR04 ultrasonic transceivers online (${bins.length} bins).');
    logSensor('[SYS_INIT] Ping interval 30 s. Calibration depth ${kBinDepthCm.toStringAsFixed(0)} cm.');
    notifyListeners();
  }

  void _seedTrucks() {
    final t = wards[3];
    trucks = [
      Truck('TRK-ET-01', 'Zone 4 Micro-Collector', TruckType.eTricycle, 500,
          t.lat, t.lon),
      Truck('TRK-CMP-02', 'Central Compactor A', TruckType.compactor, 8000,
          depotLat, depotLon),
      Truck('TRK-CMP-03', 'South Compactor B', TruckType.compactor, 8000,
          wards[1].lat, wards[1].lon),
      Truck('TRK-SWP-04', 'Boulevard Sweeper', TruckType.sweeper, 2000,
          wards[5].lat, wards[5].lon,
          status: TruckStatus.maintenance),
    ];
  }

  void _seedBins() {
    final now = DateTime.now();
    Bin mk(String id, String name, int wi, double lat, double lon, int cap,
            WasteStream st, int fill, int hoursAgo,
            {bool narrow = false}) =>
        Bin(
          id: id,
          name: name,
          capacityL: cap,
          narrowLane: narrow,
          wardIndex: wi,
          stream: st,
          lat: lat,
          lon: lon,
          fill: fill,
          lastEmptied: now.subtract(Duration(hours: hoursAgo)),
        );
    // Named collection points (DEMO coordinates and sensor readings).
    bins = [
      mk('CHN-TNG-01', 'Usman Road Junction', 0, 13.0428, 80.2349, 1100,
          WasteStream.wet, 92, 14),
      mk('CHN-TNG-02', 'Ranganathan Street Pedestrian Zone', 0, 13.0405,
          80.2332, 800, WasteStream.dry, 45, 12),
      mk('CHN-ADY-01', 'Sardar Patel Road Corner', 1, 13.0022, 80.2575,
          1100, WasteStream.wet, 30, 15),
      mk('CHN-ADY-02', 'Besant Nagar 2nd Cross', 1, 12.9985, 80.2660, 600,
          WasteStream.dry, 85, 20),
      mk('CHN-VEL-01', '100 Feet Bypass Road', 2, 12.9825, 80.2195, 1200,
          WasteStream.wet, 78, 16),
      mk('CHN-VEL-02', 'Velachery Main Road Bus Stop', 2, 12.9800, 80.2170,
          800, WasteStream.dry, 20, 9),
      mk('CHN-TND-01', 'Elaya Street Market Lane (W38)', 3, 13.1270,
          80.2910, 1500, WasteStream.mixed, 96, 24,
          narrow: true),
      mk('CHN-TND-02', 'Vaithyanathan Street (W39)', 3, 13.1251, 80.2885,
          750, WasteStream.wet, 88, 17,
          narrow: true),
      mk('CHN-ROY-01', 'Fish Market Approach Road', 4, 13.1140, 80.2960,
          1500, WasteStream.wet, 70, 13),
      mk('CHN-ROY-02', 'Royapuram Harbour Gate', 4, 13.1115, 80.2940, 800,
          WasteStream.dry, 35, 10),
      mk('CHN-ANN-01', '2nd Avenue Roundabout', 5, 13.0860, 80.2115, 1000,
          WasteStream.dry, 25, 11),
      mk('CHN-ANN-02', 'Anna Nagar Tower Park Gate', 5, 13.0838, 80.2090,
          1100, WasteStream.wet, 35, 12),
      mk('CHN-MYL-01', 'Kapaleeshwarar Tank South', 6, 13.0360, 80.2680,
          900, WasteStream.wet, 82, 14),
      mk('CHN-MYL-02', 'Luz Corner', 6, 13.0378, 80.2665, 800,
          WasteStream.dry, 45, 9),
      mk('CHN-PER-01', 'Perungudi Lake Road', 7, 12.9665, 80.2449, 1100,
          WasteStream.wet, 85, 21),
      mk('CHN-PER-02', 'OMR Service Lane', 7, 12.9637, 80.2475, 800,
          WasteStream.dry, 55, 13),
      mk('CHN-GUI-01', 'Guindy Industrial Estate Gate', 8, 13.0082, 80.2194,
          1100, WasteStream.wet, 15, 7),
      mk('CHN-GUI-02', 'Kathipara Junction', 8, 13.0054, 80.2220, 800,
          WasteStream.dry, 40, 10),
      mk('CHN-KOD-01', 'Kodambakkam Station Road', 9, 13.0536, 80.2243,
          1100, WasteStream.wet, 92, 22),
      mk('CHN-KOD-02', 'Arcot Road Signal', 9, 13.0508, 80.2269, 800,
          WasteStream.dry, 45, 11),
    ];
  }

  void _add(String loc, int wi, double dLat, double dLon, Category cat,
      Priority pri, Status st, int wk, int hoursAgo, String desc,
      {bool farClaim = false, bool confirmed = false}) {
    final w = wards[wi];
    final created = DateTime.now().subtract(Duration(hours: hoursAgo));
    final n = _next++;
    final c = Complaint(
      id: 'CT-2026-$n',
      location: loc,
      ward: w.name,
      wardIndex: wi,
      category: cat,
      priority: pri,
      description: desc,
      lat: w.lat + dLat,
      lon: w.lon + dLon,
      gpsCaptured: true,
      created: created,
      beforePhoto: 'before_$n.jpg',
      worker: workers[wk],
      status: st,
    );
    c.log('Citizen (demo)', 'Complaint reported [DEMO DATA]', created);
    c.log('System', 'Assigned to ${c.worker}',
        created.add(const Duration(minutes: 10)));
    if (st != Status.pending) {
      c.log(c.worker, 'Status changed to In Progress',
          created.add(const Duration(hours: 2)));
    }
    if (st == Status.claim || st == Status.verified || st == Status.reopened) {
      final at = created.add(const Duration(hours: 5));
      c.claimTime = at;
      c.claimLat = c.lat + (farClaim ? .0040 : .0003);
      c.claimLon = c.lon + (farClaim ? .0030 : .0002);
      c.afterPhoto = 'after_$n.jpg';
      c.log(c.worker, claimLogText(c.claimDistanceM!), at);
    }
    if (st == Status.verified) {
      c.reviewNote = 'Area clear, matches before photo';
      c.log('Reviewer (demo)', 'Cleanup APPROVED -> Verified Resolved',
          c.claimTime!.add(const Duration(hours: 1)));
      if (confirmed) {
        c.citizenFeedback = 'confirmed';
        c.log('Citizen (demo)', 'Cleanup CONFIRMED by reporting citizen',
            c.claimTime!.add(const Duration(hours: 3)));
      }
    }
    if (st == Status.reopened) {
      final d = c.claimDistanceM!.toStringAsFixed(0);
      c.reviewNote = 'Claim GPS was $d m from the site; debris still visible';
      c.log('Reviewer (demo)', 'Evidence REJECTED -> Reopened: ${c.reviewNote}',
          c.claimTime!.add(const Duration(hours: 1)));
      c.afterPhoto = null;
      c.claimTime = null;
      c.claimLat = null;
      c.claimLon = null;
    }
    complaints.add(c);
  }

  Complaint report({
    required String location,
    required int wardIndex,
    required Category category,
    required Priority priority,
    required String description,
    required String photo,
    double? lat,
    double? lon,
  }) {
    final w = wards[wardIndex];
    final c = Complaint(
      id: 'CT-2026-${_next++}',
      location: location,
      ward: w.name,
      wardIndex: wardIndex,
      category: category,
      priority: priority,
      description: description,
      lat: lat ?? w.lat,
      lon: lon ?? w.lon,
      gpsCaptured: lat != null,
      created: DateTime.now(),
      beforePhoto: photo,
      worker: workers[wardIndex % workers.length],
      status: Status.pending,
    );
    c.log('Citizen', 'Complaint reported');
    c.log('System', 'Assigned to ${c.worker}');
    // An overflow report acts as a "human sensor" for the nearest bin.
    if (category == Category.overflow) {
      Bin? near;
      var best = 1000.0;
      for (final b in bins) {
        final d = haversineM(c.lat, c.lon, b.lat, b.lon);
        if (d < best) {
          best = d;
          near = b;
        }
      }
      if (near != null) {
        near.fill = 100;
        c.log('System',
            'Nearest bin ${near.id} (${best.toStringAsFixed(0)} m) marked 100% full - added to next collection route');
      }
    }
    complaints.add(c);
    final g = gvpFor(c);
    if (g != null) {
      c.log('System',
          'Spot flagged as Chronic ${g.id}: ${g.reports.length} reports within ${kGvpRadiusM.toStringAsFixed(0)} m in $kGvpWindowDays days');
    }
    notifyListeners();
    return c;
  }

  void startWork(Complaint c) {
    c.status = Status.inProgress;
    c.log(workerName, 'Status changed to In Progress');
    notifyListeners();
  }

  void submitClaim(Complaint c, String photo, double lat, double lon) {
    c.afterPhoto = photo;
    c.claimLat = lat;
    c.claimLon = lon;
    c.claimTime = DateTime.now();
    c.status = Status.claim;
    c.log(workerName, claimLogText(c.claimDistanceM!));
    notifyListeners();
  }

  void approve(Complaint c, String note, {bool gpsOverride = false}) {
    c.status = Status.verified;
    c.citizenFeedback = null;
    c.reviewNote = note.trim().isEmpty ? 'Approved' : note.trim();
    c.log(
        'Reviewer',
        'Cleanup APPROVED -> Verified Resolved (${c.reviewNote})'
            '${gpsOverride ? ' [override: claim GPS outside ${kGpsLimitM.toStringAsFixed(0)} m]' : ''}');
    notifyListeners();
  }

  void reject(Complaint c, String reason) {
    c.status = Status.reopened;
    c.reviewNote = reason.trim();
    c.afterPhoto = null;
    c.claimTime = null;
    c.claimLat = null;
    c.claimLon = null;
    c.log('Reviewer', 'Evidence REJECTED -> Reopened: ${c.reviewNote}');
    notifyListeners();
  }

  void confirmByCitizen(Complaint c) {
    c.citizenFeedback = 'confirmed';
    c.log('Citizen', 'Cleanup CONFIRMED by reporting citizen');
    notifyListeners();
  }

  void dispute(Complaint c, String reason) {
    c.status = Status.reopened;
    c.citizenFeedback = null;
    c.reviewNote = 'Citizen dispute: ${reason.trim()}';
    c.afterPhoto = null;
    c.claimTime = null;
    c.claimLat = null;
    c.claimLon = null;
    c.log('Citizen', 'Cleanup DISPUTED -> Reopened: ${reason.trim()}');
    notifyListeners();
  }

  Complaint? byId(String id) {
    for (final c in complaints) {
      if (c.id == id) return c;
    }
    return null;
  }

  // ── 1. Chronic GVP detection ──
  /// Groups reports within [kGvpRadiusM] of each other (last
  /// [kGvpWindowDays] days). Groups with [kGvpMinReports]+ reports are GVPs.
  List<Gvp> get gvps {
    final cutoff =
        DateTime.now().subtract(const Duration(days: kGvpWindowDays));
    final recent = complaints.where((c) => c.created.isAfter(cutoff)).toList();
    final parent = List<int>.generate(recent.length, (i) => i);
    int find(int i) {
      while (parent[i] != i) {
        parent[i] = parent[parent[i]];
        i = parent[i];
      }
      return i;
    }

    for (var i = 0; i < recent.length; i++) {
      for (var j = i + 1; j < recent.length; j++) {
        final d = haversineM(
            recent[i].lat, recent[i].lon, recent[j].lat, recent[j].lon);
        if (d <= kGvpRadiusM) parent[find(i)] = find(j);
      }
    }
    final groups = <int, List<Complaint>>{};
    for (var i = 0; i < recent.length; i++) {
      groups.putIfAbsent(find(i), () => []).add(recent[i]);
    }
    final big = groups.values.where((g) => g.length >= kGvpMinReports).toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    return [
      for (var i = 0; i < big.length; i++)
        Gvp(i + 1, big[i]..sort((a, b) => a.created.compareTo(b.created))),
    ];
  }

  Gvp? gvpFor(Complaint c) {
    for (final g in gvps) {
      if (g.reports.any((r) => r.id == c.id)) return g;
    }
    return null;
  }

  // ── 2. Smart bins (IoT telemetry) + need-based routing ──
  void logSensor(String msg) {
    final t = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    sensorLog.insert(
        0, '[${two(t.hour)}:${two(t.minute)}:${two(t.second)}] $msg');
    if (sensorLog.length > 40) sensorLog.removeLast();
  }

  Bin? binById(String id) {
    for (final b in bins) {
      if (b.id == id) return b;
    }
    return null;
  }

  void setThreshold(int v) {
    threshold = v;
    logSensor('[CONFIG] Collection threshold set to $v%. '
        '${bins.where((b) => b.urgent).length} bin(s) now in the urgent queue.');
    notifyListeners();
  }

  void setFill(Bin b, int v,
      {String source = 'HC-SR04', bool quiet = false}) {
    final wasUrgent = b.urgent;
    b.fill = v.clamp(0, 100);
    if (!quiet) {
      logSensor('[$source] ${b.id} echo ${b.echoCm.toStringAsFixed(1)} cm -> fill ${b.fill}%');
    }
    if (!wasUrgent && b.urgent) {
      logSensor('[ALERT] ${b.id} crossed $threshold% - pushed to urgent dispatch queue');
    }
    notifyListeners();
  }

  void emptyBin(Bin b, {String by = 'Worker'}) {
    b.fill = 0;
    b.lastEmptied = DateTime.now();
    for (final t in trucks) {
      t.assigned.remove(b.id);
    }
    logSensor('[CLEARED] ${b.id} emptied by $by. Echo ${kBinDepthCm.toStringAsFixed(0)} cm -> 0%');
    notifyListeners();
  }

  /// Simulates 12 hours of bins filling up.
  void simulateHalfDay() {
    var alerts = 0;
    for (final b in bins) {
      final was = b.urgent;
      b.fill = math.min(100, b.fill + 5 + _rng.nextInt(26));
      if (!was && b.urgent) alerts++;
    }
    logSensor('[SIM] +12 hours of accumulation across ${bins.length} bins; $alerts new threshold alert(s).');
    notifyListeners();
  }

  List<RouteStop> _greedy(List<RouteStop> rem, double la, double lo) {
    final out = <RouteStop>[];
    while (rem.isNotEmpty) {
      RouteStop? best;
      double bestScore = double.infinity, bestDist = 0;
      for (final s in rem) {
        final d = haversineM(la, lo, s.lat, s.lon) / 1000;
        final score = (d + 0.5) / s.weight;
        if (score < bestScore) {
          bestScore = score;
          best = s;
          bestDist = d;
        }
      }
      final b = best!;
      rem.remove(b);
      b.km = bestDist;
      out.add(b);
      la = b.lat;
      lo = b.lon;
    }
    return out;
  }

  /// Greedy "priority + proximity" sequence over open complaints and bins
  /// at or above the threshold. Optional [trip] keeps one waste stream per
  /// truck. SIMULATED: straight-line distances only.
  List<RouteStop> suggestRoute({WasteStream? trip}) => _greedy([
        for (final c in complaints)
          if (c.status.isOpen && (trip == null || c.category.stream == trip))
            RouteStop(complaint: c),
        for (final b in bins)
          if (b.urgent && (trip == null || b.stream == trip))
            RouteStop(bin: b),
      ], depotLat, depotLon);

  // ── Fleet dispatch ──
  Truck? truckById(String id) {
    for (final t in trucks) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// Returns an error message if the assignment breaks a rule.
  String? assignTruck(Truck t, Bin b) {
    if (t.status == TruckStatus.maintenance) {
      return '${t.id} is under maintenance.';
    }
    if (b.narrowLane && t.type != TruckType.eTricycle) {
      return '${b.name} is a narrow lane (under 3 m). Only the E-tricycle can enter.';
    }
    if (!t.assigned.contains(b.id)) t.assigned.add(b.id);
    if (t.status == TruckStatus.available) t.status = TruckStatus.enRoute;
    logSensor('[DISPATCH] ${b.id} assigned to ${t.id} (${t.type.label}).');
    notifyListeners();
    return null;
  }

  /// Stops for one vehicle: the E-tricycle serves Zone 4 (Tondiarpet) inner
  /// lanes; compactors serve everything else except narrow lanes.
  List<RouteStop> routeFor(Truck t) {
    final z4 = wards.indexWhere((w) => w.name == 'Tondiarpet');
    final micro = t.type == TruckType.eTricycle;
    final rem = <RouteStop>[
      for (final b in bins)
        if ((b.urgent || t.assigned.contains(b.id)) &&
            b.fill > 0 &&
            (micro ? b.wardIndex == z4 : !b.narrowLane))
          RouteStop(bin: b),
      for (final c in complaints)
        if (c.status.isOpen && (micro ? c.wardIndex == z4 : c.wardIndex != z4))
          RouteStop(complaint: c),
    ];
    return _greedy(rem, t.lat, t.lon);
  }

  void startRoute(Truck t) {
    if (routeTruck != null && routeTruck != t) _finishRoute();
    routeTruck = t;
    liveOrigin = [t.lat, t.lon];
    liveRoute = routeFor(t);
    liveIdx = 0;
    t.status = TruckStatus.enRoute;
    logSensor('[ROUTE] ${t.id} started: ${liveRoute.length} stop(s), '
        '${liveRoute.fold<double>(0, (s, r) => s + r.km).toStringAsFixed(1)} km (simulated).');
    notifyListeners();
  }

  void _finishRoute() {
    final t = routeTruck;
    if (t != null) {
      t.status = TruckStatus.available;
      t.assigned.clear();
    }
  }

  /// Moves the truck to the next stop and services it.
  void advanceRoute() {
    final t = routeTruck;
    if (t == null || liveIdx >= liveRoute.length) return;
    final s = liveRoute[liveIdx];
    t.lat = s.lat;
    t.lon = s.lon;
    t.status = TruckStatus.collecting;
    final b = s.bin, c = s.complaint;
    if (b != null) emptyBin(b, by: t.id);
    if (c != null && c.status.isOpen) {
      if (c.status != Status.inProgress) {
        c.status = Status.inProgress;
        c.log(c.worker, 'Status changed to In Progress');
      }
      c.log(t.id,
          'Vehicle reached the site. Crew must file an after-photo + GPS claim before review.');
    }
    liveIdx++;
    if (liveIdx >= liveRoute.length) {
      logSensor('[ROUTE] ${t.id} completed all stops and is returning.');
      _finishRoute();
    }
    notifyListeners();
  }

  void resetRoute() {
    _finishRoute();
    routeTruck = null;
    liveRoute = [];
    liveIdx = 0;
    notifyListeners();
  }

  void setDemo(int step, bool running) {
    demoStep = step;
    demoRunning = running;
    notifyListeners();
  }

  /// Old way: one truck visits EVERY bin in fixed ward order, full or not.
  double fixedRouteKm() {
    var la = depotLat, lo = depotLon, total = 0.0;
    for (final b in bins) {
      total += haversineM(la, lo, b.lat, b.lon) / 1000;
      la = b.lat;
      lo = b.lon;
    }
    return total;
  }

  // ── 3. Segregation ──
  /// 1.0 = no mixed-waste reports in the ward. Null if no reports.
  double? segregationScore(int w) {
    final list = complaints.where((c) => c.wardIndex == w).toList();
    if (list.isEmpty) return null;
    final mixed = list.where((c) => c.category == Category.mixed).length;
    return 1 - mixed / list.length;
  }

  // ── 4. Accountability ──
  WorkerStats statsFor(String name) {
    final s = WorkerStats(name);
    for (final c in complaints.where((x) => x.worker == name)) {
      s.assigned++;
      if (c.status.isOpen) s.open++;
      for (final a in c.audit) {
        if (a.text.startsWith('Cleanup CLAIM')) s.claims++;
        if (a.text.contains('GPS MISMATCH')) s.gpsFlags++;
        if (a.text.contains('APPROVED')) s.approved++;
        if (a.text.contains('REJECTED')) s.rejected++;
        if (a.text.contains('DISPUTED')) s.disputes++;
      }
    }
    return s;
  }
}

final store = Store();

/// Current collection threshold (tunable on the IoT Sensors screen).
int get kBinThreshold => store.threshold;

/// Lets the automated demo runner move between screens.
final navKey = GlobalKey<NavigatorState>();

// ───────────────────────── App + shell ─────────────────────────
class CleanTrackApp extends StatelessWidget {
  const CleanTrackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navKey,
      builder: (context, child) => Column(
        children: [
          const DemoRunnerBar(),
          Expanded(child: child ?? const SizedBox()),
        ],
      ),
      title: 'CleanTrack Chennai',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: kForest),
        scaffoldBackgroundColor: kBg,
        appBarTheme: const AppBarTheme(
            backgroundColor: kForest, foregroundColor: Colors.white),
      ),
      home: const AppShell(),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int tab = 0;
  void goTab(int i) => setState(() => tab = i);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (store.loading) {
          return const Scaffold(
            backgroundColor: kForest,
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.recycling, size: 72, color: kLime),
                  SizedBox(height: 16),
                  Text('CleanTrack Chennai',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.bold)),
                  SizedBox(height: 20),
                  CircularProgressIndicator(color: kLime),
                  SizedBox(height: 12),
                  Text('Loading demo data...',
                      style: TextStyle(color: Colors.white70)),
                ],
              ),
            ),
          );
        }
        return Scaffold(
          body: IndexedStack(
            index: tab,
            children: [
              HomeScreen(goTab: goTab),
              const MapScreen(),
              ReportScreen(goTab: goTab),
              const ComplaintsScreen(),
              const ProfileScreen(),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: tab,
            onDestinationSelected: goTab,
            backgroundColor: Colors.white,
            indicatorColor: kLime,
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: 'Home'),
              NavigationDestination(
                  icon: Icon(Icons.map_outlined),
                  selectedIcon: Icon(Icons.map),
                  label: 'Map'),
              NavigationDestination(
                  icon: Icon(Icons.add_circle_outline),
                  selectedIcon: Icon(Icons.add_circle),
                  label: 'Report'),
              NavigationDestination(
                  icon: Icon(Icons.list_alt_outlined),
                  selectedIcon: Icon(Icons.list_alt),
                  label: 'Complaints'),
              NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: 'Profile'),
            ],
          ),
        );
      },
    );
  }
}

// ───────────────────────── Shared widgets ─────────────────────────
class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color color;
  const Panel(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(14),
      this.color = Colors.white});

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kSageMid),
        ),
        child: child,
      );
}

class DemoBanner extends StatelessWidget {
  const DemoBanner({super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFF1FBD8),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kLime),
        ),
        child: const Row(
          children: [
            Icon(Icons.science_outlined, size: 18, color: kForest),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'DEMO DATA: sample Chennai hotspots, bin levels, counts and routes are simulated. Not real-time municipal information.',
                style: TextStyle(fontSize: 12, color: kForestDark),
              ),
            ),
          ],
        ),
      );
}

class NoteBox extends StatelessWidget {
  final String text;
  final Color color;
  final IconData icon;
  const NoteBox(this.text,
      {super.key, this.color = kMed, this.icon = Icons.info_outline});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
          ],
        ),
      );
}

class StatusBadge extends StatelessWidget {
  final Status status;
  final bool full;
  const StatusBadge(this.status, {super.key, this.full = false});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: status.color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: status.color),
        ),
        child: Text(full ? status.label : status.shortLabel,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: status.color)),
      );
}

class PriorityChip extends StatelessWidget {
  final Priority priority;
  const PriorityChip(this.priority, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: priority.color,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text('${priority.label} priority',
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.white)),
      );
}

class Tag extends StatelessWidget {
  final String text;
  final Color color;
  const Tag(this.text, this.color, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w800, color: color)),
      );
}

class SectionTitle extends StatelessWidget {
  final String text;
  const SectionTitle(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(text,
            style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.w800, color: kForestDark)),
      );
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  const EmptyState(this.icon, this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(28),
        child: Center(
          child: Column(
            children: [
              Icon(icon, size: 44, color: kSageMid),
              const SizedBox(height: 8),
              Text(text,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600)),
            ],
          ),
        ),
      );
}

class InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const InfoRow(this.icon, this.label, this.value, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: kForest),
            const SizedBox(width: 8),
            SizedBox(
                width: 86,
                child: Text(label,
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 13))),
            Expanded(
                child: Text(value,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600))),
          ],
        ),
      );
}

/// Placeholder "photo" (DartPad cannot pick or upload real images).
class PhotoBox extends StatelessWidget {
  final String label;
  final String? name;
  final Color tint;
  const PhotoBox(this.label, this.name, this.tint, {super.key});
  @override
  Widget build(BuildContext context) {
    final has = name != null;
    return AspectRatio(
      aspectRatio: 1.15,
      child: Container(
        decoration: BoxDecoration(
          color: has ? tint.withOpacity(0.14) : kSage,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: has ? tint : kSageMid, width: 1.5),
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(has ? Icons.photo_camera_back : Icons.image_not_supported_outlined,
                size: 34, color: has ? tint : Colors.grey),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: has ? tint : Colors.grey.shade700)),
            Text(name ?? 'No photo yet',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11)),
            if (has)
              const Text('(demo placeholder)',
                  style: TextStyle(fontSize: 10, color: Colors.black54)),
          ],
        ),
      ),
    );
  }
}

class ComplaintTile extends StatelessWidget {
  final Complaint c;
  const ComplaintTile(this.c, {super.key});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => openDetail(context, c),
        child: Panel(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: c.priority.color,
                child: Icon(c.category.icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.location,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text('${c.id}  |  ${c.ward}  |  ${c.category.label}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade700)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusBadge(c.status),
            ],
          ),
        ),
      ),
    );
  }
}

void openDetail(BuildContext context, Complaint c) {
  Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => DetailScreen(id: c.id)));
}

void openScreen(BuildContext context, Widget screen) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
}

void snack(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg),
    backgroundColor: error ? kHigh : kForest,
  ));
}

Future<bool> confirmDialog(
    BuildContext context, String title, String body) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continue')),
      ],
    ),
  );
  return ok == true;
}

/// Demo sign-in gate for Worker / Reviewer actions.
Future<bool> ensureRole(BuildContext context, Role needed) async {
  if (store.role == needed) return true;
  final pin = needed == Role.worker ? '1234' : '9999';
  final name = needed == Role.worker ? 'Worker' : 'Reviewer';
  final ctrl = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      String? err;
      return StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text('$name sign-in (demo)'),
          content: TextField(
            controller: ctrl,
            obscureText: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Demo PIN',
              helperText: 'Demo PIN for $name: $pin',
              errorText: err,
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (ctrl.text == pin) {
                  Navigator.pop(ctx, true);
                } else {
                  setS(() => err = 'Incorrect PIN');
                }
              },
              child: const Text('Sign in'),
            ),
          ],
        ),
      );
    },
  );
  if (ok == true) {
    store.setRole(needed);
    return true;
  }
  return false;
}

// ───────────────────────── Hotspot map widget ─────────────────────────
const _latMax = 13.14, _latMin = 12.94, _lonMin = 80.17, _lonMax = 80.31;

/// Geographic box shown by a map (city-wide by default, or zoomed to a route).
class MapBounds {
  final double latMin, latMax, lonMin, lonMax;
  const MapBounds(this.latMin, this.latMax, this.lonMin, this.lonMax);
  double x(double lon, double w) => (lon - lonMin) / (lonMax - lonMin) * w;
  double y(double lat, double h) => (latMax - lat) / (latMax - latMin) * h;
  bool get isCity => latMin == _latMin && latMax == _latMax;
  double get widthM => haversineM(
      (latMin + latMax) / 2, lonMin, (latMin + latMax) / 2, lonMax);

  /// Fits a box around [pts] ([lat, lon] pairs); falls back to the city
  /// view when the points are spread across the city.
  static MapBounds fit(List<List<double>> pts, {double minSpan = 0.006}) {
    if (pts.isEmpty) return kCityBounds;
    var a = pts.first[0], b = a, c = pts.first[1], d = c;
    for (final p in pts) {
      a = math.min(a, p[0]);
      b = math.max(b, p[0]);
      c = math.min(c, p[1]);
      d = math.max(d, p[1]);
    }
    if (b - a > 0.06 || d - c > 0.05) return kCityBounds;
    final latSpan = math.max(b - a, minSpan) * 1.5;
    final lonSpan = math.max(d - c, minSpan) * 1.5;
    final cl = (a + b) / 2, co = (c + d) / 2;
    return MapBounds(cl - latSpan / 2, cl + latSpan / 2, co - lonSpan / 2,
        co + lonSpan / 2);
  }
}

const kCityBounds = MapBounds(_latMin, _latMax, _lonMin, _lonMax);

class HotspotMap extends StatelessWidget {
  final List<Complaint> items;
  final List<Gvp> gvps;
  final List<Bin> bins;
  final double height;
  final void Function(Complaint) onTap;
  final void Function(Gvp)? onGvpTap;
  final void Function(Bin)? onBinTap;
  final List<List<double>> path; // [lat, lon] points of a route
  final int pathDone; // segments already driven
  final List<double>? truck; // [lat, lon] of the live vehicle
  final IconData truckIcon;
  final MapBounds bounds;
  const HotspotMap(
      {super.key,
      required this.items,
      required this.onTap,
      this.gvps = const [],
      this.bins = const [],
      this.path = const [],
      this.pathDone = 0,
      this.truck,
      this.truckIcon = Icons.local_shipping,
      this.bounds = kCityBounds,
      this.onGvpTap,
      this.onBinTap,
      this.height = 300});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, cs) {
      final w = cs.maxWidth;
      // draw low priority first so high priority markers end up on top
      final sorted = [...items]
        ..sort((a, b) => b.priority.index.compareTo(a.priority.index));
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: w,
          height: height,
          child: Stack(
            children: [
              Positioned.fill(child: CustomPaint(painter: _MapPainter(bounds))),
              if (path.length > 1)
                Positioned.fill(
                    child: CustomPaint(
                        painter: _PathPainter(path, pathDone, bounds))),
              // Chronic GVP rings (under everything else)
              for (final g in gvps)
                Positioned(
                  left: bounds.x(g.lon, w) - 30,
                  top: bounds.y(g.lat, height) - 30,
                  child: GestureDetector(
                    onTap: () => onGvpTap?.call(g),
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: kGvp.withOpacity(0.15),
                        border: Border.all(color: kGvp, width: 2),
                      ),
                      child: const Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: EdgeInsets.only(bottom: 3),
                          child: Text('GVP',
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  color: kGvp)),
                        ),
                      ),
                    ),
                  ),
                ),
              // Smart bins
              for (final b in bins)
                Positioned(
                  left: bounds.x(b.lon, w) - 11,
                  top: bounds.y(b.lat, height) - 11,
                  child: GestureDetector(
                    onTap: () => onBinTap?.call(b),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: b.fillColor,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: const Icon(Icons.delete,
                          size: 13, color: Colors.white),
                    ),
                  ),
                ),
              // Complaint markers
              for (final c in sorted)
                Positioned(
                  left: bounds.x(c.lon, w) - 20,
                  top: bounds.y(c.lat, height) - 34,
                  child: GestureDetector(
                    onTap: () => onTap(c),
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: Icon(Icons.location_on,
                          size: 34,
                          color: c.priority.color,
                          shadows: const [
                            Shadow(color: Colors.black38, blurRadius: 3)
                          ]),
                    ),
                  ),
                ),
              if (truck != null)
                AnimatedPositioned(
                  key: const ValueKey('live-truck'),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeInOut,
                  left: bounds.x(truck![1], w) - 16,
                  top: bounds.y(truck![0], height) - 16,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: kForestDark,
                      shape: BoxShape.circle,
                      border: Border.all(color: kLime, width: 2.5),
                      boxShadow: const [
                        BoxShadow(color: Colors.black38, blurRadius: 4)
                      ],
                    ),
                    child: Icon(truckIcon, size: 18, color: kLime),
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }
}

class _PathPainter extends CustomPainter {
  final List<List<double>> pts;
  final int done;
  final MapBounds bounds;
  _PathPainter(this.pts, this.done, this.bounds);

  @override
  void paint(Canvas canvas, Size size) {
    Offset o(List<double> p) =>
        Offset(bounds.x(p[1], size.width), bounds.y(p[0], size.height));
    for (var i = 0; i < pts.length - 1; i++) {
      final driven = i < done;
      final paint = Paint()
        ..color = driven ? kLow : kForestDark.withOpacity(0.75)
        ..strokeWidth = driven ? 3.5 : 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      final a = o(pts[i]), b = o(pts[i + 1]);
      if (driven) {
        canvas.drawLine(a, b, paint);
      } else {
        // dashed line for the remaining route
        final d = (b - a).distance;
        if (d == 0) continue;
        final dir = (b - a) / d;
        for (double t = 0; t < d; t += 10) {
          canvas.drawLine(a + dir * t, a + dir * math.min(t + 6, d), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PathPainter old) => true;
}

class _MapPainter extends CustomPainter {
  final MapBounds bounds;
  _MapPainter(this.bounds);

  void _text(Canvas canvas, String s, Offset o,
      {double size = 10, Color color = Colors.black54, bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(
          text: s,
          style: TextStyle(
              fontSize: size,
              color: color,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, o);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = kSage);
    if (bounds.isCity) {
      // sea (Bay of Bengal) - schematic coastline
      final sea = Path()
        ..moveTo(w * 0.93, 0)
        ..lineTo(w, 0)
        ..lineTo(w, h)
        ..lineTo(w * 0.64, h)
        ..close();
      canvas.drawPath(sea, Paint()..color = const Color(0xFFCDE4EE));
    }
    // faint grid
    final grid = Paint()
      ..color = Colors.white.withOpacity(0.7)
      ..strokeWidth = 1;
    for (var i = 1; i < 6; i++) {
      canvas.drawLine(Offset(w * i / 6, 0), Offset(w * i / 6, h), grid);
    }
    for (var i = 1; i < 5; i++) {
      canvas.drawLine(Offset(0, h * i / 5), Offset(w, h * i / 5), grid);
    }
    // ward labels
    for (final wd in wards) {
      final x = bounds.x(wd.lon, w);
      final y = bounds.y(wd.lat, h);
      canvas.drawCircle(
          Offset(x, y), 2.5, Paint()..color = kForest.withOpacity(0.35));
      _text(canvas, wd.name, Offset(x + 5, y - 5),
          size: 9, color: kForest.withOpacity(0.6));
    }
    // depot
    final dx = bounds.x(depotLon, w), dy = bounds.y(depotLat, h);
    canvas.drawRect(Rect.fromCenter(center: Offset(dx, dy), width: 8, height: 8),
        Paint()..color = kForestDark);
    _text(canvas, 'Depot', Offset(dx + 6, dy - 6),
        size: 9, color: kForestDark, bold: true);
    if (bounds.isCity) {
      _text(canvas, 'Bay of Bengal', Offset(w - 86, h * 0.45),
          size: 11, color: const Color(0xFF4A7C93), bold: true);
      _text(canvas, 'DEMO MAP - schematic, not to scale', Offset(8, h - 18),
          size: 10, color: kForestDark, bold: true);
    } else {
      _text(
          canvas,
          'ZOOMED DEMO MAP - about ${bounds.widthM.toStringAsFixed(0)} m across',
          Offset(8, h - 18),
          size: 10,
          color: kForestDark,
          bold: true);
    }
  }

  @override
  bool shouldRepaint(covariant _MapPainter old) =>
      old.bounds.latMin != bounds.latMin || old.bounds.lonMin != bounds.lonMin;
}

class MapLegend extends StatelessWidget {
  final bool showGvp;
  final bool showBins;
  const MapLegend({super.key, this.showGvp = false, this.showBins = false});
  @override
  Widget build(BuildContext context) {
    Widget item(Widget icon, String t) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            Text(' $t', style: const TextStyle(fontSize: 12)),
          ],
        );
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 4,
        children: [
          item(const Icon(Icons.location_on, color: kHigh, size: 16), 'High'),
          item(const Icon(Icons.location_on, color: kMed, size: 16), 'Medium'),
          item(const Icon(Icons.location_on, color: kLow, size: 16), 'Low'),
          if (showGvp)
            item(
                Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: kGvp.withOpacity(0.15),
                        border: Border.all(color: kGvp, width: 2))),
                'Chronic GVP'),
          if (showBins)
            item(
                Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                        color: kHigh,
                        borderRadius: BorderRadius.circular(3))),
                'Bin >= $kBinThreshold%'),
        ],
      ),
    );
  }
}

void showMarkerSheet(BuildContext context, Complaint c) {
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (sheet) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            PriorityChip(c.priority),
            const SizedBox(width: 8),
            StatusBadge(c.status),
          ]),
          const SizedBox(height: 10),
          Text(c.id,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          InfoRow(Icons.place, 'Location', '${c.location} (${c.ward})'),
          InfoRow(Icons.category, 'Waste type', c.category.label),
          InfoRow(Icons.flag, 'Cleanup', c.status.label),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                Navigator.pop(sheet);
                openDetail(context, c);
              },
              child: const Text('View full details'),
            ),
          ),
        ],
      ),
    ),
  );
}

void showGvpSheet(BuildContext context, Gvp g) {
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => ConstrainedBox(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(sheet).size.height * 0.8),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: GvpCard(g, inSheet: true),
      ),
    ),
  );
}

void showBinSheet(BuildContext context, Bin b) {
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (sheet) => ListenableBuilder(
      listenable: store,
      builder: (sheet, _) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text(b.id,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              Tag('${b.stream.label} bin', b.stream.color),
              const Spacer(),
              Tag('${b.fill}% full', b.fillColor),
            ]),
            const SizedBox(height: 8),
            InfoRow(Icons.map_outlined, 'Ward', b.ward),
            InfoRow(Icons.schedule, 'Last emptied', fmt(b.lastEmptied)),
            InfoRow(
                Icons.local_shipping,
                'Route',
                b.urgent
                    ? 'On next collection route (>= $kBinThreshold%)'
                    : 'Skipped until it reaches $kBinThreshold%'),
            const SizedBox(height: 6),
            const Text('Demo sensor: drag to simulate the fill level',
                style: TextStyle(fontSize: 12)),
            Slider(
              value: b.fill.toDouble(),
              min: 0,
              max: 100,
              divisions: 20,
              label: '${b.fill}%',
              activeColor: b.fillColor,
              onChanged: (v) => store.setFill(b, v.round(), quiet: true),
              onChangeEnd: (v) => store.setFill(b, v.round()),
            ),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.cleaning_services),
                label: const Text('Mark emptied (Worker)'),
                onPressed: () async {
                  final ok = await ensureRole(context, Role.worker);
                  if (ok) {
                    store.emptyBin(b);
                    if (sheet.mounted) Navigator.pop(sheet);
                    if (context.mounted) {
                      snack(context, '${b.id} emptied by ${store.workerName}.');
                    }
                  }
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class GvpCard extends StatelessWidget {
  final Gvp g;
  final bool inSheet;
  const GvpCard(this.g, {super.key, this.inSheet = false});
  @override
  Widget build(BuildContext context) {
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          const Icon(Icons.warning_amber_rounded, color: kGvp),
          const SizedBox(width: 6),
          Text(g.id,
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w800, color: kGvp)),
          const Spacer(),
          Tag('${g.reports.length} reports / $kGvpWindowDays days', kGvp),
        ]),
        const SizedBox(height: 6),
        InfoRow(Icons.place, 'Spot', '${g.location} (${g.ward})'),
        InfoRow(Icons.date_range, 'Seen',
            '${fmtDay(g.firstSeen)} to ${fmtDay(g.lastSeen)}'),
        InfoRow(Icons.replay, 'Re-dumped',
            '${g.redumped} time(s) after a verified cleanup'),
        InfoRow(Icons.pending_actions, 'Still open', '${g.open} report(s)'),
        const SizedBox(height: 6),
        const Text('Suggested GVP actions',
            style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        for (final a in const [
          'Twice-daily lifting + sweeping for 2 weeks',
          'Signboard, CCTV / night patrol and spot fines',
          'Place twin wet-dry bins within 50 m',
          'Beautify with residents (kolam / plants) to stop re-dumping',
        ])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('-  ', style: TextStyle(color: kGvp)),
                Expanded(
                    child: Text(a, style: const TextStyle(fontSize: 12))),
              ],
            ),
          ),
        if (inSheet) ...[
          const SectionTitle('Reports at this spot'),
          for (final c in g.reports.reversed) ComplaintTile(c),
        ] else ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => showGvpSheet(context, g),
              icon: const Icon(Icons.list),
              label: const Text('View reports'),
            ),
          ),
        ],
      ],
    );
    if (inSheet) return body;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Panel(child: body),
    );
  }
}

// ───────────────────────── Home ─────────────────────────
class HomeScreen extends StatelessWidget {
  final void Function(int) goTab;
  const HomeScreen({super.key, required this.goTab});

  @override
  Widget build(BuildContext context) {
    final cs = store.complaints;
    final open = cs.where((c) => c.status.isOpen).length;
    final claim = cs.where((c) => c.status == Status.claim).length;
    final ver = cs.where((c) => c.status == Status.verified).length;
    final gvps = store.gvps;
    final urgentBins = store.bins.where((b) => b.urgent).length;
    final recent = [...cs]..sort((a, b) => b.created.compareTo(a.created));

    Widget stat(String label, int v, IconData icon, Color color) => Expanded(
          child: Panel(
            child: Row(
              children: [
                CircleAvatar(
                    backgroundColor: color.withOpacity(0.15),
                    child: Icon(icon, color: color)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$v',
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w800)),
                      Text(label,
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade700)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );

    Widget action(IconData icon, String label, VoidCallback onTap) => InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Panel(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircleAvatar(
                    radius: 22,
                    backgroundColor: kLime,
                    child: Icon(icon, color: kForestDark)),
                const SizedBox(height: 6),
                Text(label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        );

    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [
          Icon(Icons.recycling, color: kLime),
          SizedBox(width: 8),
          Text('CleanTrack Chennai',
              style: TextStyle(fontWeight: FontWeight.w800)),
        ]),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Smart Waste Management & Municipal Accountability',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: kForestDark)),
          const SizedBox(height: 10),
          const DemoBanner(),
          const SizedBox(height: 12),
          const RunDemoCard(),
          const SizedBox(height: 12),
          Row(children: [
            stat('Reported hotspots', cs.length, Icons.place, kForest),
            const SizedBox(width: 10),
            stat('Pending cleanup', open, Icons.pending_actions, kMed),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            stat('Awaiting verification', claim, Icons.hourglass_top, kBlue),
            const SizedBox(width: 10),
            stat('Verified cleanups', ver, Icons.verified, kLow),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            stat('Chronic GVPs', gvps.length, Icons.warning_amber_rounded,
                kGvp),
            const SizedBox(width: 10),
            stat('Bins to collect', urgentBins, Icons.delete, kHigh),
          ]),
          const SectionTitle('Waste hotspot map'),
          HotspotMap(
              items: cs,
              gvps: gvps,
              height: 210,
              onTap: (c) => showMarkerSheet(context, c),
              onGvpTap: (g) => showGvpSheet(context, g)),
          const MapLegend(showGvp: true),
          const SizedBox(height: 12),
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => openScreen(context, const TondiarpetScreen()),
            child: const NoteBox(
                'Reported data: Tondiarpet (Zone 4) - 380-420 MT/day, segregation below 45%, 24-hour blackspot SLA. Tap to open.',
                color: kBlue,
                icon: Icons.location_city),
          ),
          const SectionTitle('Quick actions'),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.0,
            children: [
              action(Icons.add_a_photo, 'Report Waste', () => goTab(2)),
              action(Icons.map, 'View Hotspots', () => goTab(1)),
              action(Icons.track_changes, 'Track Complaints', () => goTab(3)),
              action(Icons.memory, 'IoT Sensors',
                  () => openScreen(context, const SensorScreen())),
              action(Icons.qr_code_2, 'Streets & QR',
                  () => openScreen(context, const StreetDirectoryScreen())),
              action(Icons.local_shipping, 'Fleet Dispatch',
                  () => openScreen(context, const FleetScreen())),
              action(Icons.navigation, 'Live Route',
                  () => openScreen(context, const LiveRouteScreen())),
              action(Icons.alt_route, 'Route Savings',
                  () => openScreen(context, const CollectionScreen())),
              action(Icons.warning_amber_rounded, 'Chronic GVPs',
                  () => openScreen(context, const GvpScreen())),
              action(Icons.document_scanner, 'AI Classifier',
                  () => openScreen(context, const ClassifierScreen())),
              action(Icons.recycling, 'Segregation',
                  () => openScreen(context, const SegregationScreen())),
              action(Icons.fact_check, 'Verify Cleanup', () async {
                final ok = await ensureRole(context, Role.reviewer);
                if (ok && context.mounted) {
                  openScreen(context, const VerifyScreen());
                }
              }),
              action(Icons.engineering, 'Worker Dashboard', () async {
                final ok = await ensureRole(context, Role.worker);
                if (ok && context.mounted) {
                  openScreen(context, const WorkerScreen());
                }
              }),
              action(Icons.location_city, 'Tondiarpet Data',
                  () => openScreen(context, const TondiarpetScreen())),
              action(Icons.delete, 'Smart Bins',
                  () => openScreen(context, const BinsScreen())),
            ],
          ),
          const SectionTitle('Recent complaints'),
          if (recent.isEmpty)
            const EmptyState(Icons.inbox, 'No complaints yet.')
          else
            for (final c in recent.take(5)) ComplaintTile(c),
        ],
      ),
    );
  }
}

// ───────────────────────── Map screen ─────────────────────────
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  Priority? pf;
  int sf = 0; // 0 all, 1 open, 2 awaiting, 3 verified
  bool showGvp = true, showBins = false;

  bool _match(Complaint c) {
    if (pf != null && c.priority != pf) return false;
    switch (sf) {
      case 1:
        return c.status.isOpen;
      case 2:
        return c.status == Status.claim;
      case 3:
        return c.status == Status.verified;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final items = store.complaints.where(_match).toList();
    Widget chip(String label, bool sel, VoidCallback onTap) => ChoiceChip(
          label: Text(label),
          selected: sel,
          selectedColor: kLime,
          onSelected: (_) => setState(onTap),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Hotspot Map')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const DemoBanner(),
          const SizedBox(height: 12),
          const Text('Priority',
              style: TextStyle(fontWeight: FontWeight.w700)),
          Wrap(spacing: 8, children: [
            chip('All', pf == null, () => pf = null),
            for (final p in Priority.values)
              chip(p.label, pf == p, () => pf = p),
          ]),
          const SizedBox(height: 6),
          const Text('Status', style: TextStyle(fontWeight: FontWeight.w700)),
          Wrap(spacing: 8, children: [
            chip('All', sf == 0, () => sf = 0),
            chip('Open', sf == 1, () => sf = 1),
            chip('Awaiting verification', sf == 2, () => sf = 2),
            chip('Verified', sf == 3, () => sf = 3),
          ]),
          const SizedBox(height: 6),
          const Text('Layers', style: TextStyle(fontWeight: FontWeight.w700)),
          Wrap(spacing: 8, children: [
            FilterChip(
                label: const Text('Chronic GVPs'),
                selected: showGvp,
                selectedColor: kLime,
                onSelected: (v) => setState(() => showGvp = v)),
            FilterChip(
                label: const Text('Smart bins'),
                selected: showBins,
                selectedColor: kLime,
                onSelected: (v) => setState(() => showBins = v)),
          ]),
          const SizedBox(height: 12),
          HotspotMap(
              items: items,
              gvps: showGvp ? store.gvps : const [],
              bins: showBins ? store.bins : const [],
              height: 340,
              onTap: (c) => showMarkerSheet(context, c),
              onGvpTap: (g) => showGvpSheet(context, g),
              onBinTap: (b) => showBinSheet(context, b)),
          MapLegend(showGvp: showGvp, showBins: showBins),
          SectionTitle('Showing ${items.length} hotspot(s) - tap a marker'),
          if (items.isEmpty)
            const EmptyState(Icons.filter_alt_off,
                'No hotspots match these filters.\nTry changing the priority or status filter.')
          else
            for (final c in items) ComplaintTile(c),
        ],
      ),
    );
  }
}

// ───────────────────────── Report screen ─────────────────────────
class ReportScreen extends StatefulWidget {
  final void Function(int) goTab;
  const ReportScreen({super.key, required this.goTab});
  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final _form = GlobalKey<FormState>();
  final _loc = TextEditingController();
  final _desc = TextEditingController();
  int ward = 0;
  Category? cat;
  Priority pri = Priority.medium;
  String? photo;
  double? gLat, gLon;
  bool submitting = false;
  String? extraError;

  Future<void> _captureGps() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Allow location access?'),
        content: const Text(
            'CleanTrack would like to capture your GPS location for this report.\n\n'
            'Demo mode: a SIMULATED location near the selected ward is used.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Deny')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Allow')),
        ],
      ),
    );
    if (!mounted) return;
    if (ok != true) {
      snack(context, 'Location not shared - the ward centre will be used.');
      return;
    }
    final r = math.Random();
    setState(() {
      gLat = wards[ward].lat + (r.nextDouble() - .5) * .002;
      gLon = wards[ward].lon + (r.nextDouble() - .5) * .002;
    });
  }

  Future<void> _submit() async {
    final valid = _form.currentState!.validate();
    String? err;
    if (cat == null) {
      err = 'Please select a waste category.';
    } else if (photo == null) {
      err = 'Please attach a photo of the waste.';
    }
    setState(() => extraError = err);
    if (!valid || err != null) return;

    setState(() => submitting = true);
    await Future.delayed(const Duration(milliseconds: 700)); // simulated upload
    final c = store.report(
      location: _loc.text.trim(),
      wardIndex: ward,
      category: cat!,
      priority: pri,
      description: _desc.text.trim(),
      photo: photo!,
      lat: gLat,
      lon: gLon,
    );
    final g = store.gvpFor(c);
    if (!mounted) return;
    setState(() {
      submitting = false;
      _loc.clear();
      _desc.clear();
      cat = null;
      photo = null;
      gLat = null;
      gLon = null;
      pri = Priority.medium;
    });
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: kLow, size: 40),
        title: const Text('Complaint submitted'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'ID: ${c.id}\nTime: ${fmt(c.created)}\nStatus: ${c.status.label}\nWaste stream: ${c.category.stream.label}\nAssigned to: ${c.worker}'),
            if (g != null) ...[
              const SizedBox(height: 10),
              NoteBox(
                  'This spot is a Chronic GVP (${g.id}): ${g.reports.length} reports within ${kGvpRadiusM.toStringAsFixed(0)} m in $kGvpWindowDays days. It has been flagged for preventive action.',
                  color: kGvp,
                  icon: Icons.warning_amber_rounded),
            ],
          ],
        ),
        actions: [
          FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                widget.goTab(3);
              },
              child: const Text('Track complaints')),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _loc.dispose();
    _desc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Report Waste')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const DemoBanner(),
            const SizedBox(height: 14),
            TextFormField(
              controller: _loc,
              decoration: const InputDecoration(
                labelText: 'Waste location or landmark',
                prefixIcon: Icon(Icons.place),
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
              validator: (v) => (v == null || v.trim().length < 3)
                  ? 'Enter the location or a nearby landmark'
                  : null,
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<int>(
              value: ward,
              decoration: const InputDecoration(
                labelText: 'Ward / area',
                prefixIcon: Icon(Icons.map_outlined),
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
              items: [
                for (var i = 0; i < wards.length; i++)
                  DropdownMenuItem(value: i, child: Text(wards[i].name)),
              ],
              onChanged: (v) => setState(() {
                ward = v ?? 0;
                gLat = null;
                gLon = null;
              }),
            ),
            const SectionTitle('Waste category'),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final c in Category.values)
                  ChoiceChip(
                    avatar: Icon(c.icon, size: 16),
                    label: Text(c.label),
                    selected: cat == c,
                    selectedColor: kLime,
                    onSelected: (_) => setState(() => cat = c),
                  ),
              ],
            ),
            if (cat == Category.mixed)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: NoteBox(
                    'Mixed waste lowers this ward\'s segregation score. Wards with low scores are flagged for an awareness drive.'),
              ),
            if (cat == Category.sanitary)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: NoteBox(
                    'Sanitary waste is collected separately. Households should wrap it in paper and keep it apart from wet and dry waste.',
                    color: Color(0xFFC2185B)),
              ),
            if (cat == Category.overflow)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: NoteBox(
                    'Your report marks the nearest bin as 100% full, so it joins the next collection route.',
                    color: kBlue),
              ),
            const SectionTitle('Priority level'),
            SegmentedButton<Priority>(
              segments: [
                for (final p in Priority.values)
                  ButtonSegment(value: p, label: Text(p.label)),
              ],
              selected: {pri},
              onSelectionChanged: (s) => setState(() => pri = s.first),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _desc,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Description',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
              validator: (v) => (v == null || v.trim().length < 10)
                  ? 'Please describe the problem (at least 10 characters)'
                  : null,
            ),
            const SectionTitle('Photo'),
            Row(
              children: [
                SizedBox(
                    width: 140,
                    child: PhotoBox('BEFORE', photo, kHigh)),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => setState(() => photo =
                        'IMG_${DateTime.now().millisecondsSinceEpoch % 100000}.jpg'),
                    icon: const Icon(Icons.add_a_photo),
                    label: Text(photo == null
                        ? 'Attach photo (demo)'
                        : 'Replace photo (demo)'),
                  ),
                ),
              ],
            ),
            const SectionTitle('GPS location'),
            Panel(
              child: Row(
                children: [
                  Icon(gLat == null ? Icons.location_off : Icons.my_location,
                      color: gLat == null ? Colors.grey : kLow),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      gLat == null
                          ? 'Not captured. Ward centre will be used.'
                          : 'Captured (simulated): ${gLat!.toStringAsFixed(5)}, ${gLon!.toStringAsFixed(5)}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  TextButton(
                      onPressed: _captureGps, child: const Text('Capture')),
                ],
              ),
            ),
            if (extraError != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(extraError!,
                    style: const TextStyle(
                        color: kHigh, fontWeight: FontWeight.w700)),
              ),
            const SizedBox(height: 18),
            SizedBox(
              height: 50,
              child: FilledButton.icon(
                onPressed: submitting ? null : _submit,
                icon: submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send),
                label: Text(submitting ? 'Submitting...' : 'Submit complaint'),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── Complaints tab ─────────────────────────
class ComplaintsScreen extends StatefulWidget {
  const ComplaintsScreen({super.key});
  @override
  State<ComplaintsScreen> createState() => _ComplaintsScreenState();
}

class _ComplaintsScreenState extends State<ComplaintsScreen> {
  Status? filter;

  @override
  Widget build(BuildContext context) {
    final list = store.complaints
        .where((c) => filter == null || c.status == filter)
        .toList()
      ..sort((a, b) => b.created.compareTo(a.created));
    return Scaffold(
      appBar: AppBar(title: const Text('Track Complaints')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                  label: const Text('All'),
                  selected: filter == null,
                  selectedColor: kLime,
                  onSelected: (_) => setState(() => filter = null)),
              for (final s in Status.values)
                ChoiceChip(
                    label: Text(s.shortLabel),
                    selected: filter == s,
                    selectedColor: kLime,
                    onSelected: (_) => setState(() => filter = s)),
            ],
          ),
          const SizedBox(height: 12),
          if (list.isEmpty)
            const EmptyState(Icons.inbox, 'No complaints with this status.')
          else
            for (final c in list) ComplaintTile(c),
        ],
      ),
    );
  }
}

// ───────────────────────── Complaint detail ─────────────────────────
class DetailScreen extends StatelessWidget {
  final String id;
  const DetailScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final c = store.byId(id);
        if (c == null) {
          return Scaffold(
              appBar: AppBar(title: const Text('Complaint')),
              body: const EmptyState(Icons.error_outline, 'Complaint not found.'));
        }
        final dist = c.claimDistanceM;
        final gvp = store.gvpFor(c);
        return Scaffold(
          appBar: AppBar(title: Text(c.id)),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(children: [
                PriorityChip(c.priority),
                const SizedBox(width: 8),
                Expanded(child: StatusBadge(c.status, full: true)),
              ]),
              const SizedBox(height: 12),
              if (gvp != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: InkWell(
                    onTap: () => showGvpSheet(context, gvp),
                    child: NoteBox(
                        'Part of Chronic ${gvp.id}: ${gvp.reports.length} reports at this spot in $kGvpWindowDays days, re-dumped ${gvp.redumped} time(s) after cleanup. Tap for GVP actions.',
                        color: kGvp,
                        icon: Icons.warning_amber_rounded),
                  ),
                ),
              if (c.status == Status.claim)
                _banner(Icons.hourglass_top, kBlue,
                    'This is only a worker CLAIM. It is NOT a verified cleanup until a reviewer approves it.'),
              if (c.status == Status.verified)
                _banner(
                    Icons.verified,
                    kLow,
                    'VERIFIED by a reviewer. Note: ${c.reviewNote ?? '-'}'
                    '${c.citizenFeedback == 'confirmed' ? '\nCONFIRMED by the reporting citizen.' : '\nWaiting for the citizen to confirm.'}'),
              if (c.status == Status.reopened)
                _banner(Icons.replay, kHigh,
                    'Reopened. Note: ${c.reviewNote ?? '-'}'),
              Panel(
                child: Column(children: [
                  InfoRow(Icons.place, 'Location', c.location),
                  InfoRow(Icons.map_outlined, 'Ward', c.ward),
                  InfoRow(
                      Icons.my_location,
                      'GPS',
                      '${c.lat.toStringAsFixed(5)}, ${c.lon.toStringAsFixed(5)}'
                          '${c.gpsCaptured ? '' : ' (ward centre)'}'),
                  InfoRow(c.category.icon, 'Waste type', c.category.label),
                  InfoRow(Icons.recycling, 'Stream', c.category.stream.label),
                  InfoRow(Icons.schedule, 'Reported', fmt(c.created)),
                  InfoRow(Icons.engineering, 'Assigned', c.worker),
                  InfoRow(Icons.notes, 'Details', c.description),
                ]),
              ),
              const SectionTitle('Before / After evidence'),
              Row(children: [
                Expanded(child: PhotoBox('BEFORE', c.beforePhoto, kHigh)),
                const SizedBox(width: 12),
                Expanded(child: PhotoBox('AFTER', c.afterPhoto, kLow)),
              ]),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                      child: Text('${fmt(c.created)}\n${c.lat.toStringAsFixed(5)}, ${c.lon.toStringAsFixed(5)}',
                          style: const TextStyle(fontSize: 11))),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Text(
                          c.claimTime == null
                              ? 'No cleanup claim yet'
                              : '${fmt(c.claimTime!)}\n${c.claimLat!.toStringAsFixed(5)}, ${c.claimLon!.toStringAsFixed(5)}',
                          style: const TextStyle(fontSize: 11))),
                ],
              ),
              if (dist != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    dist > kGpsLimitM
                        ? 'WARNING: claim GPS is ${dist.toStringAsFixed(0)} m from the reported location (over ${kGpsLimitM.toStringAsFixed(0)} m).'
                        : 'Claim GPS is ${dist.toStringAsFixed(0)} m from the reported location.',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: dist > kGpsLimitM ? kHigh : kLow),
                  ),
                ),
              const SectionTitle('Actions'),
              _actions(context, c),
              const SectionTitle('Audit history (append-only)'),
              Panel(
                child: Column(
                  children: [
                    for (final a in c.audit)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 4, right: 10),
                              child: Icon(Icons.circle,
                                  size: 9,
                                  color: a.text.contains('MISMATCH') ||
                                          a.text.contains('REJECTED') ||
                                          a.text.contains('DISPUTED')
                                      ? kHigh
                                      : kForest),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(a.text,
                                      style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600)),
                                  Text('${fmt(a.time)}  |  ${a.actor}',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade700)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  Widget _banner(IconData icon, Color color, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color),
          ),
          child: Row(children: [
            Icon(icon, color: color),
            const SizedBox(width: 10),
            Expanded(
                child: Text(text,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: color))),
          ]),
        ),
      );

  Widget _actions(BuildContext context, Complaint c) {
    final buttons = <Widget>[];
    if (c.status == Status.pending || c.status == Status.reopened) {
      buttons.add(FilledButton.icon(
        icon: const Icon(Icons.play_arrow),
        label: const Text('Mark In Progress (Worker)'),
        onPressed: () async {
          final ok = await ensureRole(context, Role.worker);
          if (ok && context.mounted) {
            store.startWork(c);
            snack(context, 'Marked In Progress.');
          }
        },
      ));
    }
    if (c.status == Status.inProgress) {
      buttons.add(FilledButton.icon(
        icon: const Icon(Icons.cleaning_services),
        label: const Text('Submit cleanup claim (Worker)'),
        onPressed: () async {
          final ok = await ensureRole(context, Role.worker);
          if (!ok || !context.mounted) return;
          final sent = await showDialog<bool>(
              context: context, builder: (_) => ClaimDialog(c));
          if (sent == true && context.mounted) {
            snack(context,
                'Claim submitted. Status: Awaiting Verification (not resolved yet).');
          }
        },
      ));
    }
    if (c.status == Status.claim) {
      buttons.add(FilledButton.icon(
        icon: const Icon(Icons.verified),
        label: const Text('Approve cleanup (Reviewer)'),
        onPressed: () async {
          final ok = await ensureRole(context, Role.reviewer);
          if (!ok || !context.mounted) return;
          final d = c.claimDistanceM;
          final far = d != null && d > kGpsLimitM;
          if (far) {
            final go = await confirmDialog(
                context,
                'GPS mismatch',
                'The claim GPS is ${d.toStringAsFixed(0)} m from the reported spot. '
                    'Approving anyway will be recorded as an override in the audit log.');
            if (!go || !context.mounted) return;
          }
          final note = await _askText(context, 'Approve cleanup',
              'Optional note', false);
          if (note != null && context.mounted) {
            store.approve(c, note, gpsOverride: far);
            snack(context, 'Verified Resolved. Citizen asked to confirm.');
          }
        },
      ));
      buttons.add(OutlinedButton.icon(
        icon: const Icon(Icons.replay, color: kHigh),
        label: const Text('Reject evidence & reopen (Reviewer)',
            style: TextStyle(color: kHigh)),
        onPressed: () async {
          final ok = await ensureRole(context, Role.reviewer);
          if (!ok || !context.mounted) return;
          final reason = await _askText(
              context, 'Reject evidence', 'Reason (required)', true);
          if (reason != null && context.mounted) {
            store.reject(c, reason);
            snack(context, 'Complaint reopened and returned to the worker.',
                error: true);
          }
        },
      ));
    }
    if (c.status == Status.verified && c.citizenFeedback == null) {
      buttons.add(FilledButton.icon(
        icon: const Icon(Icons.thumb_up),
        label: const Text('Confirm cleanup (Citizen)'),
        onPressed: () {
          store.confirmByCitizen(c);
          snack(context, 'Thank you! Cleanup confirmed.');
        },
      ));
      buttons.add(OutlinedButton.icon(
        icon: const Icon(Icons.report_problem, color: kHigh),
        label: const Text('Dispute - still not clean (Citizen)',
            style: TextStyle(color: kHigh)),
        onPressed: () async {
          final reason = await _askText(context, 'Dispute cleanup',
              'What is still wrong? (required)', true);
          if (reason != null && context.mounted) {
            store.dispute(c, reason);
            snack(context, 'Complaint reopened after citizen dispute.',
                error: true);
          }
        },
      ));
    }
    if (buttons.isEmpty) {
      return const Panel(
          child: Text(
              'No further actions. Verified by a reviewer and confirmed by the citizen.'));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final b in buttons)
          Padding(padding: const EdgeInsets.only(bottom: 8), child: b),
        Text(
            'Workers can never mark a complaint resolved - only a reviewer can, after checking the evidence. The citizen can still dispute it.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
      ],
    );
  }
}

Future<String?> _askText(
    BuildContext context, String title, String label, bool required) {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) {
      String? err;
      return StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: ctrl,
            maxLines: 2,
            decoration: InputDecoration(labelText: label, errorText: err),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (required && ctrl.text.trim().isEmpty) {
                  setS(() => err = 'This field is required');
                } else {
                  Navigator.pop(ctx, ctrl.text);
                }
              },
              child: const Text('Confirm'),
            ),
          ],
        ),
      );
    },
  );
}

/// Worker cleanup-claim form: after photo + timestamp + GPS are all required.
class ClaimDialog extends StatefulWidget {
  final Complaint c;
  const ClaimDialog(this.c, {super.key});
  @override
  State<ClaimDialog> createState() => _ClaimDialogState();
}

class _ClaimDialogState extends State<ClaimDialog> {
  String? photo;
  double? lat, lon;
  bool far = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final ready = photo != null && lat != null;
    final dist = lat == null ? null : haversineM(c.lat, c.lon, lat!, lon!);
    return AlertDialog(
      title: const Text('Submit cleanup claim'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                'Required: after-cleanup photo, GPS location and timestamp. This sends the work for review - it does NOT mark it resolved.',
                style: TextStyle(fontSize: 12)),
            const SizedBox(height: 12),
            SizedBox(width: 150, child: PhotoBox('AFTER', photo, kLow)),
            OutlinedButton.icon(
              onPressed: () => setState(() => photo =
                  'after_${DateTime.now().millisecondsSinceEpoch % 100000}.jpg'),
              icon: const Icon(Icons.add_a_photo),
              label: Text(photo == null ? 'Attach after photo' : 'Replace photo'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Demo: simulate GPS far from site',
                  style: TextStyle(fontSize: 12)),
              value: far,
              onChanged: (v) => setState(() {
                far = v;
                lat = null;
                lon = null;
              }),
            ),
            OutlinedButton.icon(
              onPressed: () {
                final r = math.Random();
                setState(() {
                  // far: always 400-700 m away; near: within ~30 m
                  if (far) {
                    final ang = r.nextDouble() * 2 * math.pi;
                    final m = 400 + r.nextDouble() * 300;
                    lat = c.lat + m / 111000 * math.sin(ang);
                    lon = c.lon + m / 108000 * math.cos(ang);
                  } else {
                    lat = c.lat + (r.nextDouble() - .5) * .0004;
                    lon = c.lon + (r.nextDouble() - .5) * .0004;
                  }
                });
              },
              icon: const Icon(Icons.my_location),
              label: Text(lat == null
                  ? 'Capture GPS (simulated)'
                  : '${lat!.toStringAsFixed(5)}, ${lon!.toStringAsFixed(5)}'),
            ),
            if (dist != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  dist > kGpsLimitM
                      ? '${dist.toStringAsFixed(0)} m from the site - this claim will be flagged as a GPS MISMATCH.'
                      : '${dist.toStringAsFixed(0)} m from the site - OK.',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: dist > kGpsLimitM ? kHigh : kLow),
                ),
              ),
            const SizedBox(height: 8),
            Text('Timestamp: ${fmt(DateTime.now())} (automatic)',
                style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: ready
              ? () {
                  store.submitClaim(c, photo!, lat!, lon!);
                  Navigator.pop(context, true);
                }
              : null,
          child: const Text('Submit claim'),
        ),
      ],
    );
  }
}

// ───────────────────────── Worker scorecard ─────────────────────────
class WorkerScoreCard extends StatelessWidget {
  final WorkerStats s;
  const WorkerScoreCard(this.s, {super.key});
  @override
  Widget build(BuildContext context) {
    final rate = s.reworkRate;
    final rateColor = rate > 0.3 ? kHigh : (rate > 0 ? kMed : kLow);
    Widget cell(String label, String v, [Color color = kForestDark]) =>
        SizedBox(
          width: 92,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(v,
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800, color: color)),
              Text(label,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
            ],
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.engineering, color: kForest),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(s.name,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800))),
              Tag('Rework ${(rate * 100).round()}%', rateColor),
            ]),
            const SizedBox(height: 10),
            Wrap(
              runSpacing: 8,
              children: [
                cell('Assigned', '${s.assigned}'),
                cell('Open now', '${s.open}', kMed),
                cell('Claims', '${s.claims}', kBlue),
                cell('Approved', '${s.approved}', kLow),
                cell('Rejected', '${s.rejected}',
                    s.rejected > 0 ? kHigh : kForestDark),
                cell('Disputed', '${s.disputes}',
                    s.disputes > 0 ? kHigh : kForestDark),
                cell('GPS flags', '${s.gpsFlags}',
                    s.gpsFlags > 0 ? kHigh : kForestDark),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── Worker dashboard ─────────────────────────
class WorkerScreen extends StatelessWidget {
  const WorkerScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final list = store.complaints
            .where((c) =>
                c.worker == store.workerName &&
                (c.status.isOpen || c.status == Status.claim))
            .toList()
          ..sort((a, b) => a.priority.index.compareTo(b.priority.index));
        return Scaffold(
          appBar: AppBar(title: const Text('Worker Dashboard')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              DropdownButtonFormField<String>(
                value: store.workerName,
                decoration: const InputDecoration(
                  labelText: 'Signed in as (demo worker)',
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                ),
                items: [
                  for (final w in workers)
                    DropdownMenuItem(value: w, child: Text(w)),
                ],
                onChanged: (v) => store.setWorker(v ?? workers[0]),
              ),
              const SectionTitle('My accountability record'),
              WorkerScoreCard(store.statsFor(store.workerName)),
              const SectionTitle('Assigned complaints (highest priority first)'),
              if (list.isEmpty)
                const EmptyState(Icons.celebration,
                    'No active assignments. Great work!')
              else
                for (final c in list) ComplaintTile(c),
              const SizedBox(height: 6),
              Text(
                  'Tip: open a complaint to mark it In Progress or submit a cleanup claim. Workers cannot mark complaints as resolved.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            ],
          ),
        );
      },
    );
  }
}

// ───────────────────────── Verification queue ─────────────────────────
class VerifyScreen extends StatelessWidget {
  const VerifyScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final list =
            store.complaints.where((c) => c.status == Status.claim).toList();
        return Scaffold(
          appBar: AppBar(title: const Text('Cleanup Verification')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Panel(
                child: Text(
                  'Review before-and-after evidence. A complaint becomes "Verified Resolved" only after you approve it. Rejecting reopens it. Claims over 200 m from the site are flagged and need an explicit override.',
                  style: TextStyle(fontSize: 13),
                ),
              ),
              const SectionTitle('Claims awaiting verification'),
              if (list.isEmpty)
                const EmptyState(Icons.task_alt,
                    'No claims awaiting verification.')
              else
                for (final c in list) ComplaintTile(c),
              const SectionTitle('Worker accountability scorecards'),
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                    'Rework = claims rejected by a reviewer or disputed by a citizen. Counted from the append-only audit log.',
                    style: TextStyle(fontSize: 12)),
              ),
              for (final w in workers) WorkerScoreCard(store.statsFor(w)),
            ],
          ),
        );
      },
    );
  }
}

// ───────────────────────── Chronic GVP screen ─────────────────────────
class GvpScreen extends StatelessWidget {
  const GvpScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final gvps = store.gvps;
        return Scaffold(
          appBar: AppBar(title: const Text('Chronic GVPs')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const DemoBanner(),
              const SizedBox(height: 10),
              const NoteBox(
                  'Garbage Vulnerable Point rule (demo): $kGvpMinReports or more reports within ${kGvpRadiusM ~/ 1} m of each other in the last $kGvpWindowDays days. '
                  'Repeat dumping after a verified cleanup shows the spot needs prevention, not just another pickup.',
                  color: kGvp,
                  icon: Icons.warning_amber_rounded),
              const SizedBox(height: 12),
              HotspotMap(
                items: [for (final g in gvps) ...g.reports],
                gvps: gvps,
                height: 280,
                onTap: (c) => showMarkerSheet(context, c),
                onGvpTap: (g) => showGvpSheet(context, g),
              ),
              const MapLegend(showGvp: true),
              SectionTitle('${gvps.length} chronic GVP(s) detected'),
              if (gvps.isEmpty)
                const EmptyState(Icons.check_circle_outline,
                    'No spot has repeated dumping right now.')
              else
                for (final g in gvps) GvpCard(g),
            ],
          ),
        );
      },
    );
  }
}

// ───────────────────────── Smart bins screen ─────────────────────────
class BinsScreen extends StatefulWidget {
  const BinsScreen({super.key});
  @override
  State<BinsScreen> createState() => _BinsScreenState();
}

class _BinsScreenState extends State<BinsScreen> {
  bool onlyUrgent = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final list = store.bins
            .where((b) => !onlyUrgent || b.urgent)
            .toList()
          ..sort((a, b) => b.fill.compareTo(a.fill));
        final urgent = store.bins.where((b) => b.urgent).length;
        return Scaffold(
          appBar: AppBar(title: const Text('Smart Bins')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const DemoBanner(),
              const SizedBox(height: 10),
              NoteBox(
                  'SIMULATED fill-level sensors (a real deployment would use ultrasonic bin sensors or worker check-ins). '
                  'Bins at or above $kBinThreshold% join the collection route; the rest are skipped, saving fuel.',
                  color: kBlue,
                  icon: Icons.sensors),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.fast_forward),
                    label: const Text('Simulate +12 hours'),
                    onPressed: () {
                      store.simulateHalfDay();
                      snack(context, 'Bins filled up over 12 simulated hours.');
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.alt_route),
                    label: const Text('See route'),
                    onPressed: () =>
                        openScreen(context, const CollectionScreen()),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              HotspotMap(
                items: const [],
                bins: store.bins,
                height: 260,
                onTap: (_) {},
                onBinTap: (b) => showBinSheet(context, b),
              ),
              const SizedBox(height: 6),
              Text(
                  '$urgent of ${store.bins.length} bins need collection now. Tap a bin to change its demo sensor reading.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              FilterChip(
                  label: Text('Only bins >= $kBinThreshold%'),
                  selected: onlyUrgent,
                  selectedColor: kLime,
                  onSelected: (v) => setState(() => onlyUrgent = v)),
              const SizedBox(height: 8),
              for (final b in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => showBinSheet(context, b),
                    child: Panel(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: b.stream.color,
                            child: const Icon(Icons.delete,
                                color: Colors.white, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${b.id}  |  ${b.ward}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                                Text(
                                    '${b.stream.label} bin  |  emptied ${fmt(b.lastEmptied)}',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade700)),
                                const SizedBox(height: 6),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: LinearProgressIndicator(
                                    value: b.fill / 100,
                                    minHeight: 8,
                                    color: b.fillColor,
                                    backgroundColor: kSage,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text('${b.fill}%',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: b.fillColor)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ───────────────────────── Collection / smart routes ─────────────────────────
class CollectionScreen extends StatefulWidget {
  const CollectionScreen({super.key});
  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  WasteStream? trip; // null = one truck takes everything

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final fixedKm = store.fixedRouteKm();
        final allStops = store.suggestRoute();
        final needKm = allStops.fold<double>(0, (s, r) => s + r.km);
        final savedKm = fixedKm - needKm;
        final savedPct = fixedKm == 0 ? 0 : savedKm / fixedKm * 100;
        final route = trip == null ? allStops : store.suggestRoute(trip: trip);
        final tripKm = route.fold<double>(0, (s, r) => s + r.km);

        final rows = <DataRow>[];
        for (var w = 0; w < wards.length; w++) {
          final inWard = store.complaints.where((c) => c.wardIndex == w);
          if (inWard.isEmpty) continue;
          final total = inWard.length;
          final pend = inWard.where((c) => c.status.isOpen).length;
          final wait = inWard.where((c) => c.status == Status.claim).length;
          final ver = inWard.where((c) => c.status == Status.verified).length;
          final seg = store.segregationScore(w) ?? 1;
          rows.add(DataRow(cells: [
            DataCell(Text(wards[w].name)),
            DataCell(Text('$total')),
            DataCell(Text('$pend')),
            DataCell(Text('$wait')),
            DataCell(Text('$ver')),
            DataCell(Text('${(100 * ver / total).round()}%')),
            DataCell(Text('${(seg * 100).round()}%',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: seg < kSegregationAlert ? kHigh : kLow))),
          ]));
        }

        Widget routeBox(String title, double km, String sub, Color color) =>
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: color)),
                    Text('${km.toStringAsFixed(1)} km',
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w800)),
                    Text(sub, style: const TextStyle(fontSize: 11)),
                  ],
                ),
              ),
            );

        return Scaffold(
          appBar: AppBar(title: const Text('Smart Collection Routes')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const DemoBanner(),
              const SectionTitle('Fixed route vs need-based route'),
              Row(children: [
                routeBox('FIXED DAILY ROUTE', fixedKm,
                    'Visits all ${store.bins.length} bins in ward order, full or empty. Ignores dumping complaints.',
                    Colors.grey.shade700),
                const SizedBox(width: 10),
                routeBox('NEED-BASED ROUTE', needKm,
                    '${allStops.length} stops: bins >= $kBinThreshold% + open complaints, by priority & distance.',
                    kLow),
              ]),
              const SizedBox(height: 10),
              Panel(
                color: savedKm > 0 ? const Color(0xFFF1FBD8) : Colors.white,
                child: Row(children: [
                  Icon(savedKm > 0 ? Icons.local_gas_station : Icons.info,
                      color: savedKm > 0 ? kForest : kMed),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      savedKm > 0
                          ? 'Saves ${savedKm.toStringAsFixed(1)} km (${savedPct.round()}%) ≈ ${(savedKm * kDieselLPerKm).toStringAsFixed(1)} L diesel per trip'
                          : 'Many bins are full today - the need-based route is ${(-savedKm).toStringAsFixed(1)} km longer, but every stop is needed.',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 6),
              const Text(
                  'SIMULATED: straight-line distances from an assumed depot near Ripon Building; diesel uses an ASSUMED 0.35 L/km. No road, traffic or real sensor data is connected. Try "Simulate +12 hours" on Smart Bins and watch the numbers change.',
                  style: TextStyle(fontSize: 11)),
              const SectionTitle('Stream-wise trips (keeps segregated waste separate)'),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  ChoiceChip(
                      label: const Text('All waste'),
                      selected: trip == null,
                      selectedColor: kLime,
                      onSelected: (_) => setState(() => trip = null)),
                  for (final s in WasteStream.values)
                    ChoiceChip(
                        label: Text('${s.label} trip'),
                        selected: trip == s,
                        selectedColor: kLime,
                        onSelected: (_) => setState(() => trip = s)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                  '${route.length} stop(s), ${tripKm.toStringAsFixed(1)} km (simulated)',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              if (route.isEmpty)
                const EmptyState(Icons.check_circle_outline,
                    'Nothing to collect for this stream - no trip needed.')
              else
                for (var i = 0; i < route.length; i++)
                  _stopTile(context, i, route[i]),
              const SectionTitle('Pending complaints by ward'),
              for (var w = 0; w < wards.length; w++) ..._wardGroup(w),
              const SectionTitle('Collection & segregation by area (demo)'),
              Panel(
                padding: EdgeInsets.zero,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columnSpacing: 18,
                    headingRowHeight: 40,
                    dataRowMinHeight: 36,
                    dataRowMaxHeight: 40,
                    columns: const [
                      DataColumn(label: Text('Ward')),
                      DataColumn(label: Text('Total')),
                      DataColumn(label: Text('Pending')),
                      DataColumn(label: Text('Awaiting')),
                      DataColumn(label: Text('Verified')),
                      DataColumn(label: Text('Verified %')),
                      DataColumn(label: Text('Segregation')),
                    ],
                    rows: rows,
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  Widget _stopTile(BuildContext context, int i, RouteStop s) {
    final c = s.complaint, b = s.bin;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          if (c != null) openDetail(context, c);
          if (b != null) showBinSheet(context, b);
        },
        child: Panel(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              CircleAvatar(
                radius: 15,
                backgroundColor: kForest,
                child: Text('${i + 1}',
                    style: const TextStyle(color: Colors.white, fontSize: 12)),
              ),
              const SizedBox(width: 10),
              Icon(c != null ? c.category.icon : Icons.delete,
                  size: 18, color: s.stream.color),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(
                        '${s.ward}  |  ${s.stream.label}  |  +${s.km.toStringAsFixed(1)} km',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade700)),
                  ],
                ),
              ),
              if (c != null) PriorityChip(c.priority),
              if (b != null) Tag('${b.fill}% full', b.fillColor),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _wardGroup(int w) {
    final list = store.complaints
        .where((c) => c.wardIndex == w && c.status.isOpen)
        .toList()
      ..sort((a, b) => a.priority.index.compareTo(b.priority.index));
    if (list.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 4),
        child: Text('${wards[w].name} (${list.length} pending)',
            style: const TextStyle(
                fontWeight: FontWeight.w800, color: kForest)),
      ),
      for (final c in list) ComplaintTile(c),
    ];
  }
}

// ───────────────────────── Segregation screen ─────────────────────────
class SegregationScreen extends StatelessWidget {
  const SegregationScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final total = store.complaints.length;
        final byStream = <WasteStream, int>{
          for (final s in WasteStream.values)
            s: store.complaints.where((c) => c.category.stream == s).length,
        };
        final scores = <MapEntry<int, double>>[];
        for (var w = 0; w < wards.length; w++) {
          final s = store.segregationScore(w);
          if (s != null) scores.add(MapEntry(w, s));
        }
        scores.sort((a, b) => a.value.compareTo(b.value));
        final flagged =
            scores.where((e) => e.value < kSegregationAlert).length;

        return Scaffold(
          appBar: AppBar(title: const Text('Segregation at Source')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const DemoBanner(),
              const SizedBox(height: 10),
              const NoteBox(
                  'Ward segregation score = share of reports in that ward where waste was NOT found mixed. '
                  'Low scores mean wet, dry and sanitary waste are reaching the street together - recycling becomes unviable.',
                  color: kForest,
                  icon: Icons.recycling),
              const SectionTitle('Reports by waste stream (city-wide)'),
              Panel(
                child: Column(
                  children: [
                    for (final s in WasteStream.values)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(children: [
                          SizedBox(
                              width: 92,
                              child: Text(s.label,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: s.color))),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: total == 0 ? 0 : byStream[s]! / total,
                                minHeight: 10,
                                color: s.color,
                                backgroundColor: kSage,
                              ),
                            ),
                          ),
                          SizedBox(
                              width: 36,
                              child: Text('${byStream[s]}',
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800))),
                        ]),
                      ),
                  ],
                ),
              ),
              SectionTitle(
                  'Ward scores ($flagged ward(s) need an awareness drive)'),
              for (final e in scores)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Panel(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                              child: Text(wards[e.key].name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800))),
                          if (e.value < kSegregationAlert)
                            const Tag('Awareness drive', kHigh)
                          else
                            const Tag('On track', kLow),
                          const SizedBox(width: 8),
                          Text('${(e.value * 100).round()}%',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: e.value < kSegregationAlert
                                      ? kHigh
                                      : kLow)),
                        ]),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: e.value,
                            minHeight: 8,
                            color: e.value < kSegregationAlert ? kHigh : kLow,
                            backgroundColor: kSage,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                            'Based on ${store.complaints.where((c) => c.wardIndex == e.key).length} report(s)',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade700)),
                      ],
                    ),
                  ),
                ),
              const SectionTitle('Household segregation guide (demo)'),
              Panel(
                child: Column(
                  children: [
                    for (final g in const [
                      [Icons.eco, 'Wet', 'Food scraps, peels, flowers -> green bin, compost locally'],
                      [Icons.local_drink, 'Dry', 'Plastic, paper, metal, glass -> blue bin, clean and dry for recycling'],
                      [Icons.sanitizer, 'Sanitary', 'Diapers, pads -> wrap in paper, keep separate'],
                      [Icons.construction, 'C&D', 'Rubble, debris -> request a bulk pickup, never on the street'],
                    ])
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(g[0] as IconData, color: kForest, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text.rich(TextSpan(children: [
                                TextSpan(
                                    text: '${g[1]}: ',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800)),
                                TextSpan(text: g[2] as String),
                              ]), style: const TextStyle(fontSize: 13)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                icon: const Icon(Icons.alt_route),
                label: const Text('Plan stream-wise collection trips'),
                onPressed: () => openScreen(context, const CollectionScreen()),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }
}

// ───────────────────────── Profile ─────────────────────────
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final all = <MapEntry<Complaint, AuditEntry>>[];
    for (final c in store.complaints) {
      for (final a in c.audit) {
        all.add(MapEntry(c, a));
      }
    }
    all.sort((a, b) => b.value.time.compareTo(a.value.time));
    final recent = all.take(15).toList();

    Widget tool(IconData icon, String title, VoidCallback onTap) => ListTile(
          leading: Icon(icon, color: kForest),
          title: Text(title),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Panel(
            child: Row(
              children: [
                const CircleAvatar(
                    radius: 26,
                    backgroundColor: kForest,
                    child: Icon(Icons.person, color: kLime, size: 30)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Demo user',
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w800)),
                      Text(
                          'Current role: ${const ['Citizen', 'Worker', 'Reviewer'][store.role.index]}',
                          style: TextStyle(color: Colors.grey.shade700)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SectionTitle('Switch role (demo)'),
          SegmentedButton<Role>(
            segments: const [
              ButtonSegment(value: Role.citizen, label: Text('Citizen')),
              ButtonSegment(value: Role.worker, label: Text('Worker')),
              ButtonSegment(value: Role.reviewer, label: Text('Reviewer')),
            ],
            selected: {store.role},
            onSelectionChanged: (s) async {
              final r = s.first;
              if (r == Role.citizen) {
                store.setRole(r);
              } else {
                await ensureRole(context, r);
              }
            },
          ),
          const SizedBox(height: 6),
          Text('Demo PINs - Worker: 1234, Reviewer: 9999 (not real authentication).',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          const SectionTitle('Municipal tools'),
          Panel(
            padding: EdgeInsets.zero,
            child: Material(
              // ListTiles need a Material ancestor inside the coloured Panel.
              type: MaterialType.transparency,
              child: Column(
              children: [
                tool(Icons.engineering, 'Worker dashboard', () async {
                  final ok = await ensureRole(context, Role.worker);
                  if (ok && context.mounted) {
                    openScreen(context, const WorkerScreen());
                  }
                }),
                tool(Icons.fact_check, 'Verify cleanup & scorecards', () async {
                  final ok = await ensureRole(context, Role.reviewer);
                  if (ok && context.mounted) {
                    openScreen(context, const VerifyScreen());
                  }
                }),
                tool(Icons.warning_amber_rounded, 'Chronic GVPs',
                    () => openScreen(context, const GvpScreen())),
                tool(Icons.memory, 'IoT sensor telemetry',
                    () => openScreen(context, const SensorScreen())),
                tool(Icons.qr_code_2, 'Street directory & QR tags',
                    () => openScreen(context, const StreetDirectoryScreen())),
                tool(Icons.local_shipping, 'Fleet dispatch',
                    () => openScreen(context, const FleetScreen())),
                tool(Icons.navigation, 'Live route',
                    () => openScreen(context, const LiveRouteScreen())),
                tool(Icons.document_scanner, 'AI waste classifier',
                    () => openScreen(context, const ClassifierScreen())),
                tool(Icons.sensors, 'Smart bins',
                    () => openScreen(context, const BinsScreen())),
                tool(Icons.alt_route, 'Smart collection routes',
                    () => openScreen(context, const CollectionScreen())),
                tool(Icons.location_city, 'Tondiarpet Zone 4 data',
                    () => openScreen(context, const TondiarpetScreen())),
                tool(Icons.recycling, 'Segregation at source',
                    () => openScreen(context, const SegregationScreen())),
              ],
            ),
            ),
          ),
          const SectionTitle('Recent audit log (all complaints)'),
          Panel(
            child: recent.isEmpty
                ? const Text('No activity yet.')
                : Column(
                    children: [
                      for (final e in recent)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 4, right: 8),
                                child:
                                    Icon(Icons.circle, size: 8, color: kForest),
                              ),
                              Expanded(
                                child: Text(
                                    '${e.key.id}: ${e.value.text}\n${fmt(e.value.time)} | ${e.value.actor}',
                                    style: const TextStyle(fontSize: 12)),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
          const SectionTitle('Data notice'),
          const Panel(
            child: Text(
              'All sample hotspot locations, complaint counts, bin fill levels, collection percentages, distances, diesel figures and routes in this prototype are DEMO / SIMULATED data. '
              'They are never real-time municipal information. Any real city statistics added later must show their source and date.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            icon: const Icon(Icons.restart_alt),
            label: const Text('Reset demo data'),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Reset demo data?'),
                  content: const Text(
                      'This removes new complaints and restores the sample complaints and bin readings.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Reset')),
                  ],
                ),
              );
              if (ok == true) {
                stopDemo();
                store.seed();
                if (context.mounted) snack(context, 'Demo data restored.');
              }
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// TONDIARPET (ZONE 4) - REPORTED DATA MODULE for CleanTrack Chennai
//
// HOW TO ADD: paste this whole block at the very END of cleantrack_chennai.dart
// in DartPad (below the last closing brace). It needs no extra imports.
// Then add the two hooks described at the bottom of this block so the screen
// can be opened from Home and Profile.
//
// DATA: figures below are copied from three Zone 4 reports supplied by the
// team (dated October 2026). Every figure carries its source tag (R1/R2/R3).
// Where the reports disagree, both values are shown. These are REPORTED
// figures, not live data. The "SLA check" section applies a reported GCC rule
// to the app's own DEMO complaints.
// ═════════════════════════════════════════════════════════════════════════

class TndSource {
  final String tag;
  final String title;
  const TndSource(this.tag, this.title);
}

const tndSources = [
  TndSource('R1',
      'GCC Municipal Solid Waste Management Report - Zone 4 (Tondiarpet) Comprehensive Evaluation & Strategic Review, Oct 2026'),
  TndSource('R2',
      'Municipal Solid Waste Optimization Framework - Tondiarpet (Zone 4), GCC, Oct 2026'),
  TndSource('R3',
      'Tondiarpet (Zone 4) Waste Management Evaluation - 5-Year Comparative Analysis 2021-2026'),
];

class TndFact {
  final IconData icon;
  final String label;
  final String value;
  final String note;
  final String src;
  const TndFact(this.icon, this.label, this.value, this.note, this.src);
}

const tndProfile = [
  TndFact(Icons.scale, 'Daily waste generated', '380 - 420 MT/day',
      'City-wide total: 6,150 MT/day', 'R1, R2, R3'),
  TndFact(Icons.person, 'Per-capita generation', '0.75 kg/person/day',
      'City average: 0.71 kg/person/day', 'R1'),
  TndFact(Icons.eco, 'Organic (biodegradable) share', '54%',
      'City-wide: organic 52%, plastics ~9.5%', 'R1'),
  TndFact(Icons.landscape, 'Disposal destination', 'Kodungaiyur Dump Yard',
      'City-wide: Kodungaiyur & Perungudi', 'R1'),
  TndFact(Icons.sentiment_dissatisfied, 'Residents dissatisfied',
      'Nearly 35%', 'Survey before the privatisation framework', 'R1'),
  TndFact(Icons.timer_off, 'Corner piles left uncollected', 'Up to 14 hours',
      'Wards 38 & 39: E-tricycles run without dynamic routing', 'R3'),
];

/// Zone 4 share of city waste, computed from the reported ranges.
String tndCityShare() {
  const city = 6150.0;
  final lo = 380 / city * 100, hi = 420 / city * 100;
  return '${lo.toStringAsFixed(1)} - ${hi.toStringAsFixed(1)}%';
}

class TndWardHotspot {
  final String ward;
  final String localities;
  final String bottleneck;
  final String appFeature;
  const TndWardHotspot(
      this.ward, this.localities, this.bottleneck, this.appFeature);
}

const tndWards = [
  TndWardHotspot(
      'Ward 38',
      'Elaya Street, Korukkupet slum belts',
      'High-density commercial transit mixing; open dumpster overflow',
      'Smart bins (fill threshold) + overflow reports feed the route'),
  TndWardHotspot(
      'Ward 39',
      'Vaithyanathan Street, Old Washermanpet',
      'Very narrow lanes (<3 m per R2; <2.5 m per R3); compactor trucks cannot enter',
      'Need-based micro-routes for light E-tricycles'),
  TndWardHotspot(
      'Ward 42',
      'Tondiarpet High Road, Ennore Expressway link',
      'Industrial bypass run-off; high volume of non-segregated commercial waste',
      'Ward segregation score + fine mapping for mixed waste'),
  TndWardHotspot(
      'Ward 45',
      'Seni Amman Koil Street, Nethaji Nagar',
      'High domestic organic load; slow collection rotations',
      'Wet-stream trips (organic to Bio-CNG)'),
];

class TndShift {
  final String domain;
  final String before; // 2021 - 2023
  final String after; // 2024 - 2026
  final String cleanTrack;
  const TndShift(this.domain, this.before, this.after, this.cleanTrack);
}

const tndShifts = [
  TndShift(
      'Operations',
      'Direct GCC payroll with NULM contract workers; manual errors and absenteeism',
      'DBFOT privatisation: 10-year concessions held to 43 SLAs',
      'SLA check + worker accountability scorecards'),
  TndShift(
      'Fleet & lanes',
      'Heavy compactors stuck in the narrow lanes of Wards 38 & 39',
      'Light E-tricycles and mechanical sweepers for inner lanes',
      'Need-based routing (prototype uses straight-line distance)'),
  TndShift(
      'Segregation',
      'Green (wet) / blue (dry) bins; compliance below 30%',
      'Four-stream mandate: Wet, Dry, Domestic Hazardous, E-Waste',
      'Waste streams, ward segregation scores, stream-wise trips'),
  TndShift(
      'Monitoring',
      'Paper logs at ward desks; blackspots unmapped for long periods',
      'Geo-fenced truck routing, night-shift telemetry, public tracking portal',
      'Geo-tagged reports, hotspot map, chronic GVP detection'),
  TndShift(
      'Disposal',
      'Legacy waste over 66 lakh tonnes on 335 acres; fires and protests',
      'Bio-mining remediation; target: urban eco-park',
      'Segregated streams reduce what reaches Kodungaiyur'),
];

class TndFine {
  final String offence;
  final String residential;
  final String commercial;
  final String appCategories;
  const TndFine(
      this.offence, this.residential, this.commercial, this.appCategories);
}

/// Fine matrix as given in R3 (GCC Solid Waste Management Bye-laws).
const tndFinesR3 = [
  TndFine('Failure to segregate at source', 'Rs 100', 'Rs 500',
      'Mixed waste, Overflowing bin'),
  TndFine('Littering / dumping in public spaces', 'Rs 500', 'Rs 1,000',
      'Plastic, Wet waste, Mixed waste'),
  TndFine('Open burning of waste', 'Rs 500', 'Rs 2,000', '-'),
  TndFine('Dumping construction & demolition debris', 'Rs 2,000',
      'Rs 5,000', 'Construction debris'),
  TndFine('Bulk generator not managing organic waste on site', 'N/A',
      'Rs 5,000 - Rs 25,000', 'Wet waste (bulk sources)'),
];

/// Different tiering given in R2.
const tndFinesR2 = [
  ['Individual residential', 'Failure to segregate wet / dry / hazardous', 'Rs 100'],
  ['Bulk generator (residential)', 'Composting / zero-waste failure', 'Rs 5,000'],
  ['Commercial outlets / shops', 'Littering pathways or commercial mixing', 'Rs 500 - Rs 2,000'],
  ['Industrial / institutional', 'Illegal dumping of bulk C&D / hazardous items', 'Rs 10,000 - Rs 25,000'],
];

const tndKodungaiyur = [
  TndFact(Icons.account_balance, 'Bio-mining project cost',
      'Rs 640.8 crore (R3) / Rs 641 crore (R1, R2)',
      'Split across six geographic packages (R3)', 'R1, R2, R3'),
  TndFact(Icons.layers, 'Legacy waste', 'Over 66 lakh tonnes',
      'R3: on 335 acres; R1/R2: reclaim over 250 acres', 'R1, R3'),
  TndFact(Icons.settings, 'Processing rate', '10,000 tonnes/day',
      'Rotary trommels and magnetic separators -> RDF, bio-earth, inert rubble',
      'R3'),
  TndFact(Icons.local_gas_station, 'Planned Bio-CNG plant',
      '500 tonnes capacity, Rs 99 crore',
      'Converts organic / market waste to gas', 'R1, R2, R3'),
  TndFact(Icons.bolt, 'Waste-to-energy (planned)', 'Up to 20.76 MW',
      'Early phases; residents demand emissions tracking', 'R1'),
];

const tndConflicts = [
  'Lane width in Wards 38 & 39: "<3 m" (R2) vs "<2.5 m" (R3).',
  'Bio-mining cost: Rs 641 crore (R1, R2) vs Rs 640.8 crore (R3).',
  'Kodungaiyur area: 335 acres covered (R3) vs over 250 acres to reclaim (R1, R2).',
  'Fines: R2 and R3 use different tiers (e.g. commercial mixing Rs 500-2,000 in R2 vs Rs 500 in R3).',
];

const tndContacts = [
  ['GCC Central Helpline', 'City-wide grievances (24/7, toll-free)', '1913'],
  ['Zone 4 Sanitation Desk', 'Local fleet dispatch', '044-25912161 / 25915412'],
  ['Zone 4 Zonal Office', 'Executive office', '266, Thiruvottiyur High Road, Tondiarpet'],
  ['Zonal Officer (Zone 4)', 'Zonal waste compliance', 'z4.gcc@chennaicorporation.gov.in'],
  ['Kodungaiyur Bio-Mining Unit', 'Legacy waste project', 'gcc.solidwaste@chennaicorporation.gov.in'],
];

// Reported compliance bounds (upper limits, "below X%").
const tndSegBaseline = 0.30; // 2021-2023, R3
const tndSegCurrent = 0.45; // current, R2
const tndSlaHours = 24; // blackspot clearance SLA under DBFOT, R3

// ───────────────────────── Tondiarpet screen ─────────────────────────
class TondiarpetScreen extends StatelessWidget {
  const TondiarpetScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final now = DateTime.now();
        final open = store.complaints.where((c) => c.status.isOpen).toList();
        final breaches = open
            .where((c) => now.difference(c.created).inHours >= tndSlaHours)
            .toList()
          ..sort((a, b) => a.created.compareTo(b.created));
        final tIdx = wards.indexWhere((w) => w.name == 'Tondiarpet');
        final tOpen = open.where((c) => c.wardIndex == tIdx).length;
        final tBreach = breaches.where((c) => c.wardIndex == tIdx).length;

        return Scaffold(
          appBar: AppBar(title: const Text('Tondiarpet (Zone 4) Data')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const NoteBox(
                  'REPORTED DATA from three Zone 4 (Tondiarpet) reports, October 2026. '
                  'Each figure shows its source tag (R1, R2, R3). Not live data. '
                  'The rest of the app still uses DEMO data.',
                  color: kBlue,
                  icon: Icons.source),
              const SectionTitle('Zone profile'),
              for (final f in tndProfile) _TndFactTile(f),
              _TndFactTile(TndFact(
                  Icons.pie_chart,
                  'Zone 4 share of city waste',
                  tndCityShare(),
                  'Computed from 380-420 MT of 6,150 MT/day',
                  'computed')),
              const SectionTitle('Critical ward hotspots'),
              for (final w in tndWards) _TndWardCard(w),
              const SectionTitle('Source segregation compliance'),
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _tndBar('2021 - 2023 (R3)', tndSegBaseline, kHigh),
                    const SizedBox(height: 10),
                    _tndBar('Current (R2)', tndSegCurrent, kMed),
                    const SizedBox(height: 10),
                    const Text(
                        'Both values are upper bounds ("below 30%", "below 45%"). Most households still put mixed waste in green/blue carts, so workers sort by hand without safety gear (R1, R2).',
                        style: TextStyle(fontSize: 12)),
                    const SizedBox(height: 8),
                    const Text('Four-stream mandate (R3):',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    const Wrap(spacing: 6, runSpacing: 6, children: [
                      Tag('Wet', Color(0xFF2E7D32)),
                      Tag('Dry', kBlue),
                      Tag('Domestic Hazardous', kHigh),
                      Tag('E-Waste', Color(0xFF6D4C41)),
                    ]),
                  ],
                ),
              ),
              const SectionTitle('DBFOT SLA check (applied to app complaints)'),
              Panel(
                color: breaches.isEmpty ? Colors.white : const Color(0xFFFFF3E0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                        'Under DBFOT, concessionaires are held to 43 SLAs, including clearing public blackspots within 24 hours; misses lead to deductions from monthly billing (R3).',
                        style: TextStyle(fontSize: 12)),
                    const SizedBox(height: 10),
                    Text(
                        '${breaches.length} of ${open.length} open complaints are past $tndSlaHours hours',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800)),
                    Text(
                        'Tondiarpet ward: $tBreach of $tOpen open complaints past $tndSlaHours hours',
                        style: const TextStyle(fontSize: 13)),
                    const SizedBox(height: 4),
                    const Text(
                        'Complaints here are DEMO data; the 24-hour rule is from R3.',
                        style: TextStyle(fontSize: 11, color: Colors.black54)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              for (final c in breaches) ComplaintTile(c),
              const SectionTitle('2021 vs 2026: what changed'),
              for (final s in tndShifts) _TndShiftCard(s),
              const SectionTitle('Fines under the SWM Bye-laws (R3)'),
              Panel(
                padding: EdgeInsets.zero,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columnSpacing: 16,
                    headingRowHeight: 40,
                    dataRowMinHeight: 40,
                    dataRowMaxHeight: 56,
                    columns: const [
                      DataColumn(label: Text('Offence')),
                      DataColumn(label: Text('Residential')),
                      DataColumn(label: Text('Commercial')),
                      DataColumn(label: Text('App categories')),
                    ],
                    rows: [
                      for (final f in tndFinesR3)
                        DataRow(cells: [
                          DataCell(SizedBox(
                              width: 180,
                              child: Text(f.offence,
                                  style: const TextStyle(fontSize: 12)))),
                          DataCell(Text(f.residential)),
                          DataCell(Text(f.commercial)),
                          DataCell(Text(f.appCategories,
                              style: const TextStyle(fontSize: 12))),
                        ]),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Alternative tiers given in R2',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    for (final r in tndFinesR2)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                                child: Text('${r[0]}: ${r[1]}',
                                    style: const TextStyle(fontSize: 12))),
                            const SizedBox(width: 8),
                            Text(r[2],
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SectionTitle('Kodungaiyur landfill & processing'),
              for (final f in tndKodungaiyur) _TndFactTile(f),
              const SectionTitle('Where the reports disagree'),
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final t in tndConflicts)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.compare_arrows,
                                size: 16, color: kMed),
                            const SizedBox(width: 6),
                            Expanded(
                                child: Text(t,
                                    style: const TextStyle(fontSize: 12))),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SectionTitle('Zone 4 escalation contacts (as listed)'),
              Panel(
                child: Column(
                  children: [
                    for (final c in tndContacts)
                      InfoRow(Icons.call, c[0], '${c[2]}\n${c[1]}'),
                  ],
                ),
              ),
              const SectionTitle('Sources'),
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final s in tndSources)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Text('${s.tag}: ${s.title}',
                            style: const TextStyle(fontSize: 12)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  Widget _tndBar(String label, double upTo, Color color) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
                child: Text(label,
                    style: const TextStyle(fontWeight: FontWeight.w700))),
            Text('below ${(upTo * 100).round()}%',
                style: TextStyle(fontWeight: FontWeight.w800, color: color)),
          ]),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: upTo,
              minHeight: 10,
              color: color,
              backgroundColor: kSage,
            ),
          ),
        ],
      );
}

class _TndFactTile extends StatelessWidget {
  final TndFact f;
  const _TndFactTile(this.f);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Panel(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                  radius: 18,
                  backgroundColor: kSage,
                  child: Icon(f.icon, color: kForest, size: 20)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(f.label,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade700)),
                    Text(f.value,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800)),
                    Text(f.note, style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              Tag(f.src, kBlue),
            ],
          ),
        ),
      );
}

class _TndWardCard extends StatelessWidget {
  final TndWardHotspot w;
  const _TndWardCard(this.w);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Panel(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text(w.ward,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: kForestDark)),
                const Spacer(),
                const Tag('R2', kBlue),
              ]),
              const SizedBox(height: 4),
              InfoRow(Icons.place, 'Localities', w.localities),
              InfoRow(Icons.warning_amber_rounded, 'Bottleneck', w.bottleneck),
              InfoRow(Icons.lightbulb_outline, 'CleanTrack', w.appFeature),
            ],
          ),
        ),
      );
}

class _TndShiftCard extends StatelessWidget {
  final TndShift s;
  const _TndShiftCard(this.s);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Panel(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text(s.domain,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800)),
                const Spacer(),
                const Tag('R3', kBlue),
              ]),
              const SizedBox(height: 4),
              InfoRow(Icons.history, '2021-23', s.before),
              InfoRow(Icons.update, '2024-26', s.after),
              InfoRow(Icons.phone_android, 'CleanTrack', s.cleanTrack),
            ],
          ),
        ),
      );
}

// ═════════════════════════════════════════════════════════════════════════
// SIMULATION MODULE (ported from the CleanTrack React prototype)
// IoT sensors (ESP32 + HC-SR04), street directory & civic tags, fleet
// dispatch, animated live route, waste classifier, 11-step demo runner.
// Everything here is SIMULATED / DEMO data.
// ═════════════════════════════════════════════════════════════════════════

enum TruckType { eTricycle, compactor, sweeper }

extension TruckTypeX on TruckType {
  String get label =>
      const ['Light E-Tricycle', 'Compactor Truck', 'Mechanical Sweeper'][index];
  IconData get icon => const [
        Icons.electric_bike,
        Icons.local_shipping,
        Icons.cleaning_services
      ][index];
}

enum TruckStatus { available, enRoute, collecting, maintenance }

extension TruckStatusX on TruckStatus {
  String get label =>
      const ['Available', 'En route', 'Collecting', 'Maintenance'][index];
  Color get color => const [kLow, kBlue, kMed, Color(0xFF616161)][index];
}

class Truck {
  final String id;
  final String name;
  final TruckType type;
  final int capacityKg;
  double lat, lon;
  TruckStatus status;
  final List<String> assigned = []; // bin ids
  Truck(this.id, this.name, this.type, this.capacityKg, this.lat, this.lon,
      {this.status = TruckStatus.available});
  bool get electric => type == TruckType.eTricycle;
  String get fuel => electric ? 'Electric' : 'Diesel';
}

// ───────────────────────── IoT sensor screen ─────────────────────────
class SensorScreen extends StatefulWidget {
  final String? binId;
  const SensorScreen({super.key, this.binId});
  @override
  State<SensorScreen> createState() => _SensorScreenState();
}

class _SensorScreenState extends State<SensorScreen> {
  late String sel = widget.binId ?? store.bins.first.id;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final b = store.binById(sel) ?? store.bins.first;
        final th = store.threshold;
        final urgent = store.bins.where((x) => x.urgent).length;
        return Scaffold(
          appBar: AppBar(title: const Text('IoT Sensor Telemetry')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              NoteBox(
                  'Virtual ESP32 + HC-SR04 ultrasonic sensor (SIMULATED). The sensor measures the distance from the lid to the waste surface; '
                  'fill % = 1 - distance / ${kBinDepthCm.toStringAsFixed(0)} cm bin depth.',
                  color: kBlue,
                  icon: Icons.memory),
              const SectionTitle('Collection threshold'),
              Panel(
                child: Row(
                  children: [
                    const Expanded(
                        child: Text('Collect bins at or above',
                            style: TextStyle(fontWeight: FontWeight.w700))),
                    DropdownButton<int>(
                      value: th,
                      items: const [
                        DropdownMenuItem(value: 60, child: Text('60% (Proactive)')),
                        DropdownMenuItem(value: 75, child: Text('75% (Standard)')),
                        DropdownMenuItem(value: 85, child: Text('85% (Critical only)')),
                        DropdownMenuItem(value: 95, child: Text('95% (Emergency)')),
                      ],
                      onChanged: (v) {
                        if (v != null) store.setThreshold(v);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text('$urgent of ${store.bins.length} bins are in the urgent queue at $th%.',
                  style: const TextStyle(fontSize: 12)),
              const SectionTitle('Collection point'),
              DropdownButtonFormField<String>(
                value: b.id,
                isExpanded: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                ),
                items: [
                  for (final x in store.bins)
                    DropdownMenuItem(
                        value: x.id,
                        child: Text('${x.name} (${x.id}) - ${x.fill}%',
                            overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => sel = v ?? sel),
              ),
              const SizedBox(height: 12),
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text('${b.fill}%',
                          style: TextStyle(
                              fontSize: 40,
                              fontWeight: FontWeight.w900,
                              color: b.fillColor)),
                      const Spacer(),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Tag(b.urgent ? 'URGENT - in queue' : 'Below threshold',
                              b.urgent ? kHigh : kLow),
                          const SizedBox(height: 4),
                          const Row(children: [
                            Icon(Icons.wifi_tethering, size: 14, color: kLow),
                            Text(' ESP32 online (NB-IoT, simulated)',
                                style: TextStyle(fontSize: 11)),
                          ]),
                        ],
                      ),
                    ]),
                    const SizedBox(height: 8),
                    LayoutBuilder(builder: (context, cs) {
                      final w = cs.maxWidth;
                      return SizedBox(
                        height: 28,
                        child: Stack(children: [
                          Positioned(
                            left: 0,
                            right: 0,
                            top: 5,
                            height: 18,
                            child: Container(
                                decoration: BoxDecoration(
                                    color: kSage,
                                    borderRadius: BorderRadius.circular(9))),
                          ),
                          Positioned(
                            left: 0,
                            top: 5,
                            height: 18,
                            width: w * b.fill / 100,
                            child: Container(
                                decoration: BoxDecoration(
                                    color: b.fillColor,
                                    borderRadius: BorderRadius.circular(9))),
                          ),
                          Positioned(
                            left: (w * th / 100 - 1).clamp(0.0, w - 2).toDouble(),
                            top: 0,
                            width: 3,
                            height: 28,
                            child: Container(color: kForestDark),
                          ),
                        ]),
                      );
                    }),
                    Text('Black marker = $th% threshold',
                        style: const TextStyle(fontSize: 11)),
                    const SizedBox(height: 8),
                    InfoRow(Icons.sensors, 'Echo',
                        '${b.echoCm.toStringAsFixed(1)} cm to waste surface'),
                    InfoRow(Icons.delete, 'Bin',
                        '${b.capacityL} L  |  ${b.stream.label}  |  ${b.ward}'),
                    InfoRow(Icons.schedule, 'Emptied', fmt(b.lastEmptied)),
                    Slider(
                      value: b.fill.toDouble(),
                      min: 0,
                      max: 100,
                      divisions: 100,
                      label: '${b.fill}%',
                      activeColor: b.fillColor,
                      onChanged: (v) =>
                          store.setFill(b, v.round(), quiet: true),
                      onChangeEnd: (v) => store.setFill(b, v.round()),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          icon: const Icon(Icons.bolt, color: kMed),
                          label: const Text('Surge (+35%)'),
                          onPressed: () =>
                              store.setFill(b, b.fill + 35, source: 'SURGE'),
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.warning_amber, color: kHigh),
                          label: const Text('Force overflow'),
                          onPressed: () =>
                              store.setFill(b, 100, source: 'OVERFLOW'),
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.refresh, color: kLow),
                          label: const Text('Simulate cleared'),
                          onPressed: () => store.emptyBin(b, by: 'field crew'),
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.fast_forward),
                          label: const Text('All bins +12 h'),
                          onPressed: store.simulateHalfDay,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SectionTitle('ESP32 console'),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0B1F14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final l in store.sensorLog.take(16))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(l,
                            style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                                color: l.contains('[ALERT')
                                    ? const Color(0xFFFF8A80)
                                    : kLime)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                icon: const Icon(Icons.local_shipping),
                label: const Text('Open fleet dispatch queue'),
                onPressed: () => openScreen(context, const FleetScreen()),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }
}

// ───────────────────────── Street directory & civic tags ─────────────────────────
class StreetDirectoryScreen extends StatefulWidget {
  const StreetDirectoryScreen({super.key});
  @override
  State<StreetDirectoryScreen> createState() => _StreetDirectoryScreenState();
}

class _StreetDirectoryScreenState extends State<StreetDirectoryScreen> {
  String q = '';
  final _scan = TextEditingController();

  @override
  void dispose() {
    _scan.dispose();
    super.dispose();
  }

  void _lookup() {
    final code = _scan.text.trim().toUpperCase();
    final b = store.binById(code.replaceFirst('CLEANTRACK://STREET/', ''));
    if (b == null) {
      snack(context, 'Street ID "$code" not found in demo records.', error: true);
      return;
    }
    _scan.clear();
    showQrSheet(context, b);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final ql = q.toLowerCase();
        final list = store.bins
            .where((b) =>
                ql.isEmpty ||
                b.name.toLowerCase().contains(ql) ||
                b.id.toLowerCase().contains(ql) ||
                b.ward.toLowerCase().contains(ql))
            .toList();
        return Scaffold(
          appBar: AppBar(title: const Text('Streets & Civic Tags')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const NoteBox(
                  'Every collection point gets a civic tag. Citizens scan it to see live status and report; workers scan it to check in. Street names and readings are DEMO data.',
                  color: kBlue,
                  icon: Icons.qr_code_2),
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: 'Search street, ID or ward',
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                ),
                onChanged: (v) => setState(() => q = v),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _scan,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.qr_code_scanner),
                      labelText: 'Simulated scan: type a street ID',
                      hintText: 'e.g. CHN-TND-01',
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    onSubmitted: (_) => _lookup(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _lookup, child: const Text('Scan')),
              ]),
              SectionTitle('${list.length} collection point(s)'),
              for (final b in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Panel(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        CircleAvatar(
                            backgroundColor: b.stream.color,
                            child: const Icon(Icons.delete,
                                color: Colors.white, size: 20)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(b.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                              Text(
                                  '${b.id}  |  ${b.ward}  |  ${b.stream.label}  |  ${b.capacityL} L',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade700)),
                              const SizedBox(height: 5),
                              Row(children: [
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: LinearProgressIndicator(
                                        value: b.fill / 100,
                                        minHeight: 7,
                                        color: b.fillColor,
                                        backgroundColor: kSage),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text('${b.fill}%',
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color: b.fillColor)),
                              ]),
                              if (b.narrowLane)
                                const Padding(
                                  padding: EdgeInsets.only(top: 4),
                                  child: Tag('Narrow lane - E-tricycle only',
                                      kGvp),
                                ),
                            ],
                          ),
                        ),
                        IconButton(
                            icon: const Icon(Icons.qr_code_2, color: kForest),
                            onPressed: () => showQrSheet(context, b)),
                        IconButton(
                            icon: const Icon(Icons.memory, color: kForest),
                            onPressed: () =>
                                openScreen(context, SensorScreen(binId: b.id))),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

void showQrSheet(BuildContext context, Bin b) {
  final payload = 'cleantrack://street/${b.id}';
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Greater Chennai Corporation civic tag (demo)',
              style: TextStyle(fontWeight: FontWeight.w800, color: kForest)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: kForest, width: 2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: SizedBox(
              width: 170,
              height: 170,
              child: CustomPaint(painter: _TagPainter(payload)),
            ),
          ),
          const SizedBox(height: 8),
          Text(b.name,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          Text(payload,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          const SizedBox(height: 8),
          InfoRow(Icons.map_outlined, 'Ward', b.ward),
          InfoRow(Icons.delete, 'Fill', '${b.fill}% (${b.stream.label}, ${b.capacityL} L)'),
          InfoRow(Icons.schedule, 'Emptied', fmt(b.lastEmptied)),
          const SizedBox(height: 8),
          const NoteBox(
              'Visual tag preview drawn from the street ID. It is not a scannable QR code; the full app would generate real codes with a QR library and print them at each collection point.',
              icon: Icons.info_outline),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.memory),
              label: const Text('Open live sensor'),
              onPressed: () {
                Navigator.pop(sheet);
                openScreen(context, SensorScreen(binId: b.id));
              },
            ),
          ),
        ],
      ),
    ),
  );
}

/// 21x21 QR-style tag: real finder/timing patterns, payload area derived
/// from a hash of the text (visual only, not decodable).
class _TagPainter extends CustomPainter {
  final String data;
  _TagPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    const n = 21;
    final grid = List.generate(n, (_) => List.filled(n, false));
    void finder(int r0, int c0) {
      for (var r = 0; r < 7; r++) {
        for (var c = 0; c < 7; c++) {
          if (r == 0 || r == 6 || c == 0 || c == 6 ||
              (r >= 2 && r <= 4 && c >= 2 && c <= 4)) {
            grid[r0 + r][c0 + c] = true;
          }
        }
      }
    }

    finder(0, 0);
    finder(0, n - 7);
    finder(n - 7, 0);
    for (var i = 8; i < n - 8; i++) {
      grid[6][i] = i.isEven;
      grid[i][6] = i.isEven;
    }
    var hash = 0;
    for (final code in data.codeUnits) {
      hash = ((hash << 5) - hash + code).toSigned(32);
    }
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        final reserved = (r < 8 && c < 8) ||
            (r < 8 && c >= n - 8) ||
            (r >= n - 8 && c < 8) ||
            r == 6 ||
            c == 6;
        if (!reserved) {
          grid[r][c] = ((hash ^ (r * 31 + c * 17)) & (1 << ((r + c) % 8))) != 0;
        }
      }
    }
    final cell = size.width / n;
    final paint = Paint()..color = kForestDark;
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        if (grid[r][c]) {
          canvas.drawRect(
              Rect.fromLTWH(c * cell, r * cell, cell + 0.4, cell + 0.4), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TagPainter old) => old.data != data;
}

// ───────────────────────── Fleet dispatch ─────────────────────────
class FleetScreen extends StatelessWidget {
  const FleetScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final queue = store.bins.where((b) => b.urgent).toList()
          ..sort((a, b) => b.fill.compareTo(a.fill));
        return Scaffold(
          appBar: AppBar(title: const Text('Fleet & Dispatch')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const NoteBox(
                  'Light E-tricycles serve the narrow inner lanes of Tondiarpet Wards 38 & 39 (reported under 3 m wide); compactor trucks serve main roads. '
                  'The app blocks a compactor from being sent into a narrow lane. Vehicles and positions are DEMO data.',
                  color: kBlue,
                  icon: Icons.local_shipping),
              SectionTitle('Vehicles (${store.trucks.length})'),
              for (final t in store.trucks)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Panel(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          CircleAvatar(
                              backgroundColor: kSage,
                              child: Icon(t.type.icon, color: kForest)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${t.id} - ${t.name}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800)),
                                Text(
                                    '${t.type.label}  |  ${t.fuel}  |  ${t.capacityKg} kg',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade700)),
                              ],
                            ),
                          ),
                          Tag(t.status.label, t.status.color),
                        ]),
                        const SizedBox(height: 6),
                        Text(
                            t.assigned.isEmpty
                                ? 'Assigned stops: none'
                                : 'Assigned stops: ${t.assigned.join(', ')}',
                            style: const TextStyle(fontSize: 12)),
                        if (t.status != TruckStatus.maintenance)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              icon: const Icon(Icons.navigation),
                              label: Text(store.routeTruck == t
                                  ? 'View live route'
                                  : 'Start live route'),
                              onPressed: () {
                                if (store.routeTruck != t) store.startRoute(t);
                                openScreen(
                                    context, LiveRouteScreen(truckId: t.id));
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              SectionTitle('Urgent queue (bins >= ${store.threshold}%)'),
              if (queue.isEmpty)
                const EmptyState(Icons.check_circle_outline,
                    'No bins are above the threshold right now.')
              else
                for (final b in queue)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Panel(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(b.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                                Text('${b.id}  |  ${b.ward}  |  ${b.stream.label}',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade700)),
                                const SizedBox(height: 4),
                                Wrap(spacing: 6, runSpacing: 4, children: [
                                  Tag('${b.fill}% full', b.fillColor),
                                  if (b.narrowLane)
                                    const Tag('Narrow lane', kGvp),
                                  for (final t in store.trucks)
                                    if (t.assigned.contains(b.id))
                                      Tag('to ${t.id}', kBlue),
                                ]),
                              ],
                            ),
                          ),
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.assignment_ind,
                                color: kForest),
                            onSelected: (id) {
                              final t = store.truckById(id);
                              if (t == null) return;
                              final err = store.assignTruck(t, b);
                              snack(context,
                                  err ?? '${b.id} assigned to ${t.id}.',
                                  error: err != null);
                            },
                            itemBuilder: (_) => [
                              for (final t in store.trucks)
                                PopupMenuItem(
                                  value: t.id,
                                  enabled:
                                      t.status != TruckStatus.maintenance,
                                  child: Text(
                                      '${t.id} (${t.type.label})'
                                      '${t.status == TruckStatus.maintenance ? ' - maintenance' : ''}'
                                      '${b.narrowLane && t.type != TruckType.eTricycle ? ' - cannot enter lane' : ''}',
                                      style: const TextStyle(fontSize: 13)),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }
}

// ───────────────────────── Live route (animated) ─────────────────────────
class LiveRouteScreen extends StatefulWidget {
  final String? truckId;
  const LiveRouteScreen({super.key, this.truckId});
  @override
  State<LiveRouteScreen> createState() => _LiveRouteScreenState();
}

class _LiveRouteScreenState extends State<LiveRouteScreen> {
  late String sel =
      widget.truckId ?? store.routeTruck?.id ?? store.trucks.first.id;
  Timer? auto;

  @override
  void dispose() {
    auto?.cancel();
    super.dispose();
  }

  void _toggleAuto() {
    if (auto != null) {
      auto!.cancel();
      setState(() => auto = null);
      return;
    }
    setState(() {
      auto = Timer.periodic(const Duration(milliseconds: 1400), (tm) {
        if (store.routeTruck == null ||
            store.liveIdx >= store.liveRoute.length) {
          tm.cancel();
          if (mounted) setState(() => auto = null);
          return;
        }
        store.advanceRoute();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final t = store.truckById(sel) ?? store.trucks.first;
        final active = store.routeTruck == t;
        final route = active ? store.liveRoute : store.routeFor(t);
        final idx = active ? store.liveIdx : 0;
        final origin = active ? store.liveOrigin : [t.lat, t.lon];
        final path = <List<double>>[
          origin,
          for (final s in route) [s.lat, s.lon],
        ];
        final total = route.fold<double>(0, (s, r) => s + r.km);
        final done = route.take(idx).fold<double>(0, (s, r) => s + r.km);
        final finished = active && idx >= route.length && route.isNotEmpty;
        return Scaffold(
          appBar: AppBar(title: const Text('Live Route')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final x in store.trucks)
                    ChoiceChip(
                      avatar: Icon(x.type.icon, size: 16),
                      label: Text(x.id),
                      selected: x.id == t.id,
                      selectedColor: kLime,
                      onSelected: x.status == TruckStatus.maintenance
                          ? null
                          : (_) => setState(() => sel = x.id),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              NoteBox(
                  t.electric
                      ? 'Zone 4 micro-route for ${t.id}: Tondiarpet bins at or above ${store.threshold}% plus open complaints in the inner lanes, ordered by priority and distance.'
                      : 'City route for ${t.id}: bins at or above ${store.threshold}% and open complaints outside Zone 4. Narrow lanes are left to the E-tricycle.',
                  color: kForest,
                  icon: t.type.icon),
              const SizedBox(height: 12),
              HotspotMap(
                items: [
                  for (final s in route)
                    if (s.complaint != null) s.complaint!
                ],
                bins: [
                  for (final s in route)
                    if (s.bin != null) s.bin!
                ],
                path: path,
                pathDone: idx,
                truck: [t.lat, t.lon],
                truckIcon: t.type.icon,
                bounds: MapBounds.fit(path),
                height: 320,
                onTap: (c) => showMarkerSheet(context, c),
                onBinTap: (b) => showBinSheet(context, b),
              ),
              const SizedBox(height: 10),
              Row(children: [
                _stat('Stops', '${math.min(idx, route.length)}/${route.length}'),
                _stat('Distance', '${done.toStringAsFixed(2)} / ${total.toStringAsFixed(2)} km'),
                _stat(
                    'Fuel',
                    t.electric
                        ? 'Electric'
                        : '${(total * kDieselLPerKm).toStringAsFixed(2)} L'),
              ]),
              const SizedBox(height: 4),
              Text(
                  t.electric
                      ? 'E-tricycle: no diesel used on this route (simulated straight-line distances).'
                      : 'Diesel uses an ASSUMED 0.35 L/km; straight-line distances (simulated).',
                  style: const TextStyle(fontSize: 11)),
              const SizedBox(height: 10),
              if (!active)
                FilledButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: Text(route.isEmpty
                      ? 'Nothing to collect on this route'
                      : 'Start route (${route.length} stops)'),
                  onPressed: route.isEmpty ? null : () => store.startRoute(t),
                )
              else
                Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.skip_next),
                      label: Text(finished ? 'Route complete' : 'Next stop'),
                      onPressed: finished ? null : store.advanceRoute,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: Icon(auto == null ? Icons.play_circle : Icons.pause),
                      label: Text(auto == null ? 'Auto-drive' : 'Pause'),
                      onPressed: finished ? null : _toggleAuto,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.restart_alt),
                    onPressed: () {
                      auto?.cancel();
                      setState(() => auto = null);
                      store.resetRoute();
                    },
                  ),
                ]),
              const SectionTitle('Stop sequence'),
              if (route.isEmpty)
                const EmptyState(Icons.check_circle_outline,
                    'No bins above the threshold or open complaints for this vehicle.')
              else
                for (var i = 0; i < route.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Panel(
                      padding: const EdgeInsets.all(10),
                      color: active && i == idx
                          ? const Color(0xFFF1FBD8)
                          : Colors.white,
                      child: Row(children: [
                        Icon(
                            active && i < idx
                                ? Icons.check_circle
                                : (active && i == idx
                                    ? Icons.navigation
                                    : Icons.radio_button_unchecked),
                            color: active && i < idx
                                ? kLow
                                : (active && i == idx ? kMed : Colors.grey)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${i + 1}. ${route[i].title}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                              Text(
                                  '${route[i].bin != null ? 'Bin ${route[i].bin!.fill}% full' : 'Complaint ${route[i].complaint!.id} - ${route[i].complaint!.status.shortLabel}'}'
                                  '  |  +${(route[i].km * 1000).toStringAsFixed(0)} m',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade700)),
                            ],
                          ),
                        ),
                      ]),
                    ),
                  ),
              const SizedBox(height: 6),
              const Text(
                  'Reaching a complaint only marks it In Progress. It is resolved only after the worker files a photo + GPS claim and a reviewer approves it.',
                  style: TextStyle(fontSize: 11)),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  Widget _stat(String label, String value) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Panel(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                Text(value,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ),
      );
}

// ───────────────────────── Waste classifier (simulated) ─────────────────────────
class ClassifierSample {
  final String name;
  final String result;
  final double confidence;
  final WasteStream stream;
  final Category category;
  final String datasetLabel;
  final String handling;
  final IconData icon;
  const ClassifierSample(this.name, this.result, this.confidence, this.stream,
      this.category, this.datasetLabel, this.handling, this.icon);
}

const classifierSamples = [
  ClassifierSample(
      'Household kitchen scraps',
      'Organic waste',
      0.94,
      WasteStream.wet,
      Category.wet,
      'Kaggle class: O (Organic)',
      'Ward micro-composting centre, or the planned Bio-CNG plant for organic waste.',
      Icons.eco),
  ClassifierSample(
      'PET beverage bottles',
      'Recyclable plastic',
      0.91,
      WasteStream.dry,
      Category.plastic,
      'Kaggle class: R (Recyclable)',
      'Bale at a resource recovery facility for polymer recyclers.',
      Icons.local_drink),
  ClassifierSample(
      'Masonry & concrete rubble',
      'Construction & demolition debris',
      0.97,
      WasteStream.cnd,
      Category.construction,
      'Not covered by the Kaggle O/R classes - needs extra training data',
      'Bulk pickup to a C&D processing facility; recycle into paver blocks.',
      Icons.construction),
  ClassifierSample(
      'Mixed household bag',
      'Unsegregated (organic + recyclable together)',
      0.88,
      WasteStream.mixed,
      Category.mixed,
      'Both O and R detected in one bag (litter objects: TACO-style detector)',
      'Return to the household for segregation; counts against the ward segregation score.',
      Icons.delete_sweep),
  ClassifierSample(
      'Diapers / sanitary pads',
      'Sanitary waste',
      0.86,
      WasteStream.sanitary,
      Category.sanitary,
      'Not covered by the Kaggle O/R classes - needs extra training data',
      'Keep wrapped and separate; never hand-sorted by workers.',
      Icons.sanitizer),
];

class ClassifierScreen extends StatefulWidget {
  const ClassifierScreen({super.key});
  @override
  State<ClassifierScreen> createState() => _ClassifierScreenState();
}

class _ClassifierScreenState extends State<ClassifierScreen> {
  ClassifierSample sample = classifierSamples.first;
  bool busy = false;

  Future<void> _pick(ClassifierSample s) async {
    setState(() => busy = true);
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    setState(() {
      sample = s;
      busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = sample;
    return Scaffold(
      appBar: AppBar(title: const Text('AI Waste Classifier')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const NoteBox(
              'SIMULATED inference. Production plan: train an image classifier on the Kaggle Waste Classification data '
              '(Organic vs Recyclable, about 25,000 images) and a litter detector on TACO (1,500 images, 60 litter categories), '
              'export to TensorFlow Lite and run it on the worker\'s phone camera at the doorstep.',
              color: kBlue,
              icon: Icons.document_scanner),
          const SectionTitle('Choose a demo sample'),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final x in classifierSamples)
                ChoiceChip(
                  avatar: Icon(x.icon, size: 16),
                  label: Text(x.name),
                  selected: x == sample,
                  selectedColor: kLime,
                  onSelected: busy ? null : (_) => _pick(x),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Panel(
            child: busy
                ? const Padding(
                    padding: EdgeInsets.all(30),
                    child: Center(
                      child: Column(children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 10),
                        Text('Running on-device model (simulated)...'),
                      ]),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 120,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: s.stream.color.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: s.stream.color),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(s.icon, size: 40, color: s.stream.color),
                            Text('${s.name} (demo photo)',
                                style: TextStyle(color: s.stream.color)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(s.result,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 4),
                      Wrap(spacing: 6, children: [
                        Tag('${s.stream.label} stream', s.stream.color),
                        Tag('Confidence ${(s.confidence * 100).toStringAsFixed(0)}% [SIMULATED]',
                            kBlue),
                      ]),
                      const SizedBox(height: 8),
                      InfoRow(s.category.icon, 'App category', s.category.label),
                      InfoRow(Icons.storage, 'Dataset', s.datasetLabel),
                      InfoRow(Icons.route, 'Handling', s.handling),
                    ],
                  ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

// ───────────────────────── 11-step automated demo ─────────────────────────
const demoSteps = [
  ['Initialize system', 'Resetting demo data and seeding Chennai collection points.'],
  ['Sensor breach', 'Rapid dumping at Elaya Street (CHN-TND-01) pushes the bin to 98%.'],
  ['Telemetry alert', 'Virtual ESP32 fires a threshold alert; the bin joins the urgent queue.'],
  ['Fleet allocation', 'E-tricycle TRK-ET-01 assigned - the narrow lane blocks compactors.'],
  ['Route optimisation', 'Greedy priority + distance sequence built for the Zone 4 micro-route.'],
  ['Truck movement', 'TRK-ET-01 drives to the reported blackspot; complaint goes In Progress.'],
  ['Arrival & collection', 'Bin CHN-TND-01 emptied; sensor confirms 0%.'],
  ['Worker evidence claim', 'Worker files after-photo + GPS claim (within 200 m). Not resolved yet.'],
  ['Reviewer verification', 'Municipal reviewer checks the evidence and approves.'],
  ['Citizen confirmation', 'Reporting citizen confirms the spot is clean.'],
  ['Audit trail', 'Every event is preserved in the append-only audit log.'],
];

int _demoToken = 0;

void _demoGo(Widget screen) {
  final nav = navKey.currentState;
  if (nav == null) return;
  nav.popUntil((r) => r.isFirst);
  nav.push(MaterialPageRoute(builder: (_) => screen));
}

void stopDemo() {
  _demoToken++;
  store.setDemo(0, false);
}

Future<void> runFullDemo() async {
  final token = ++_demoToken;
  Future<bool> step(int n) async {
    await Future.delayed(const Duration(milliseconds: 2400));
    if (token != _demoToken) return false;
    store.setDemo(n, true);
    return true;
  }

  // 1. Initialize
  navKey.currentState?.popUntil((r) => r.isFirst);
  store.seed();
  store.setRole(Role.citizen);
  final bin = store.binById('CHN-TND-01')!;
  final truck = store.truckById('TRK-ET-01')!;
  Complaint? c;
  for (final x in store.complaints) {
    if (x.location.startsWith('Elaya') && x.status.isOpen) c = x;
  }
  store.setFill(bin, 62, source: 'HC-SR04');
  store.setDemo(1, true);

  // 2. Sensor breach
  if (!await step(2)) return;
  _demoGo(SensorScreen(binId: bin.id));
  store.setFill(bin, 98, source: 'SURGE');

  // 3. Telemetry alert
  if (!await step(3)) return;
  store.logSensor('[NB-IoT] Alert for ${bin.id} delivered to the Zone 4 control desk.');
  _demoGo(const FleetScreen());

  // 4. Fleet allocation
  if (!await step(4)) return;
  store.assignTruck(truck, bin);

  // 5. Route optimisation
  if (!await step(5)) return;
  store.startRoute(truck);
  _demoGo(LiveRouteScreen(truckId: truck.id));

  // 6. Truck movement
  if (!await step(6)) return;
  store.advanceRoute();

  // 7. Arrival & collection
  if (!await step(7)) return;
  if (bin.fill > 0) store.advanceRoute();
  if (bin.fill > 0) store.emptyBin(bin, by: truck.id);

  final cc = c;
  if (cc == null) {
    store.setDemo(11, false);
    return;
  }

  // 8. Worker evidence claim
  if (!await step(8)) return;
  store.setWorker(cc.worker);
  if (cc.status != Status.inProgress) store.startWork(cc);
  store.submitClaim(cc, 'after_demo.jpg', cc.lat + .0001, cc.lon + .0001);
  _demoGo(DetailScreen(id: cc.id));

  // 9. Reviewer verification
  if (!await step(9)) return;
  store.approve(cc,
      'Before/after photos match; claim GPS within 200 m (automated demo)');

  // 10. Citizen confirmation
  if (!await step(10)) return;
  store.confirmByCitizen(cc);

  // 11. Audit trail
  if (!await step(11)) return;
  store.logSensor('[AUDIT] ${cc.id} closed with ${cc.audit.length} audit entries.');
  store.setDemo(11, false);
}

class RunDemoCard extends StatelessWidget {
  const RunDemoCard({super.key});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => _card(context),
    );
  }

  Widget _card(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kForestDark,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.auto_awesome, color: kLime),
            SizedBox(width: 8),
            Expanded(
              child: Text('Live end-to-end demo',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800)),
            ),
          ]),
          const SizedBox(height: 4),
          const Text(
              'Sensor breach > alert > dispatch > route > collection > worker claim > reviewer > citizen > audit. 11 steps, about 25 seconds.',
              style: TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: kLime, foregroundColor: kForestDark),
                icon: const Icon(Icons.play_arrow),
                label: Text(store.demoRunning
                    ? 'Running...'
                    : 'RUN FULL DEMO'),
                onPressed: store.demoRunning
                    ? null
                    : () async {
                        final ok = await confirmDialog(
                            context,
                            'Run the full demo?',
                            'This resets the demo data and walks through all 11 steps automatically.');
                        if (ok) runFullDemo();
                      },
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54)),
              onPressed: () {
                stopDemo();
                store.seed();
                snack(context, 'Demo data reset.');
              },
              child: const Text('Reset'),
            ),
          ]),
        ],
      ),
    );
  }
}

/// Progress bar shown above every screen while the demo runs.
class DemoRunnerBar extends StatelessWidget {
  const DemoRunnerBar({super.key});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final step = store.demoStep;
        if (step == 0) return const SizedBox.shrink();
        final total = demoSteps.length;
        final info = demoSteps[(step - 1).clamp(0, total - 1)];
        final complete = !store.demoRunning;
        return Material(
          color: Colors.white,
          elevation: 3,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    Icon(complete ? Icons.check_circle : Icons.autorenew,
                        size: 18, color: complete ? kLow : kMed),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                          complete
                              ? 'Demo complete - all $total steps'
                              : 'Step $step of $total: ${info[0]}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: kForestDark)),
                    ),
                    TextButton(
                      onPressed: stopDemo,
                      child: Text(complete ? 'Dismiss' : 'Stop'),
                    ),
                  ]),
                  Text(complete ? demoSteps.last[1] : info[1],
                      style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: step / total,
                      minHeight: 6,
                      color: kLime,
                      backgroundColor: kSage,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 24,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (var i = 1; i <= total; i++)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: i < step || complete
                                    ? kSage
                                    : (i == step
                                        ? const Color(0xFFF1FBD8)
                                        : Colors.grey.shade100),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: i == step && !complete
                                        ? kLime
                                        : kSageMid),
                              ),
                              child: Text(
                                  '${i < step || complete ? 'Done' : 'Step'} $i: ${demoSteps[i - 1][0]}',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: i == step
                                          ? FontWeight.w800
                                          : FontWeight.w500,
                                      color: i <= step || complete
                                          ? kForestDark
                                          : Colors.grey)),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
