# CleanTrack Chennai

**Smart waste routing, chronic dumping-spot detection and verified cleanup accountability for Greater Chennai Corporation (GCC).**

CleanTrack is a Flutter prototype built for HACK2IMPACT 2026 (theme: Environment and Sustainability). It connects citizens, sanitation workers and municipal reviewers in a single app:

- Citizens report waste with a geo-tagged photo.
- Spots that keep getting dumped on are flagged as **Chronic Garbage Vulnerable Points (GVPs)**.
- Simulated **ESP32 + HC-SR04** bin sensors decide which bins need collecting, and trucks get a **need-based route** instead of a fixed one.
- A complaint can be closed only with **after-photo + GPS + reviewer approval + citizen confirmation**, all kept in an append-only audit log.

> **Data notice.** Complaints, bins, sensor readings, vehicles, distances and diesel figures are **demo / simulated data**. The Tondiarpet (Zone 4) screen shows figures **reported** in three Zone 4 reports, each tagged with its source. Nothing in the app is live municipal data.

---

## Contents

- [Problem](#problem)
- [Features](#features)
- [Quick start](#quick-start)
- [Project structure](#project-structure)
- [Running the tests](#running-the-tests)
- [Sample data](#sample-data)
- [Demo script](#demo-script-2-minutes)
- [KPIs](#kpis)
- [Roadmap](#roadmap-prototype--production)
- [Limitations](#limitations)
- [Licence](#licence)

---

## Problem

Chennai generates about 6,150 tonnes of municipal solid waste a day. The main gaps CleanTrack addresses are:

| Gap | What happens today | CleanTrack response |
|---|---|---|
| Garbage Vulnerable Points | The same corners are re-dumped after every cleanup | GVP detection: 3+ reports within 150 m in 30 days |
| Static, fuel-wasting routes | Trucks visit empty bins while full ones overflow | Sensor threshold + need-based greedy routing, compared live with a fixed route |
| Narrow lanes | Compactors can't enter inner lanes, so piles sit for hours | E-tricycle micro-routes; the app blocks a compactor from being sent into a narrow lane |
| Low segregation | Mixed waste reaches transfer points | Waste streams, ward segregation scores, stream-wise trips, AI classifier (simulated) |
| Unverified closures | Tickets are closed administratively | Photo + GPS (200 m check) + reviewer + citizen confirmation, append-only audit |

## Features

| Screen | What it does |
|---|---|
| **Home** | KPIs, hotspot map, **RUN FULL DEMO** (11-step automated walkthrough) |
| **Report** | Geo-tagged complaint with category, priority, photo and GPS (simulated) |
| **Map** | Hotspots by priority and status, with Chronic GVP and smart-bin layers |
| **IoT Sensors** | Virtual ESP32 + HC-SR04: echo distance, fill gauge, 60/75/85/95% threshold, surge/overflow/clear, console log |
| **Streets & QR** | 20 named collection points, search, simulated scan by ID, civic tag preview |
| **Fleet Dispatch** | 4 vehicles, urgent queue, narrow-lane rule |
| **Live Route** | Animated vehicle on a zoomable map, next-stop and auto-drive controls, km and fuel |
| **Route Savings** | Fixed daily route vs need-based route (km, % and diesel saved), stream-wise trips |
| **Chronic GVPs** | Detected GVPs, re-dump count, suggested prevention actions |
| **AI Classifier** | Simulated inference mapped to Kaggle O/R classes and the TACO plan |
| **Segregation** | Ward segregation scores, awareness-drive flags, household guide |
| **Verify Cleanup** | Reviewer queue, GPS-mismatch override, worker accountability scorecards |
| **Worker Dashboard** | Assigned jobs, photo + GPS claim, personal scorecard |
| **Tondiarpet Data** | Reported Zone 4 figures with source tags, 24-hour SLA check |

Demo PINs: **Worker 1234**, **Reviewer 9999**. These are not real authentication.

## Quick start

### Option A: DartPad (no install)

1. Open <https://dartpad.dev>, then choose **New → Flutter**.
2. Delete the sample code and paste the whole of [`lib/main.dart`](lib/main.dart).
3. Press **Run**. On the Home screen, press **RUN FULL DEMO**.

### Option B: Local Flutter

Requirements: Flutter 3.24 or newer (Dart 3.4+). Developed against Dart 3.13 stable.

```bash
git clone https://github.com/Samrhidhi/cleantrack-chennai.git
cd cleantrack-chennai

# Platform folders are not committed; generate them once:
flutter create . --project-name cleantrack_chennai --platforms web,android

flutter pub get
flutter run -d chrome        # or: flutter run (Android device/emulator)
```

`flutter create .` keeps the existing `lib/main.dart` and `pubspec.yaml`; it only adds the platform folders.

## Project structure

```
cleantrack-chennai/
├── lib/
│   └── main.dart              # Whole app (single file so it runs in DartPad)
├── test/
│   ├── logic_test.dart        # 32 unit tests: GVP, sensors, routing, fleet, workflow, metrics
│   └── widget_test.dart       # 3 widget tests incl. the full 11-step demo
├── data/
│   ├── README.md              # What each file is and where it comes from
│   ├── bins.json              # 20 collection points (demo)
│   ├── complaints_seed.json   # 16 seed complaints (demo)
│   ├── trucks.json            # 4 vehicles (demo)
│   ├── wards.json             # 10 wards used by the prototype
│   └── tondiarpet_zone4_reported.json   # Figures reported in the 3 Zone 4 reports
├── docs/
│   ├── ARCHITECTURE.md        # Components, data model, algorithms, production design
│   └── DEMO_SCRIPT.md         # 2-minute judging walkthrough
├── pubspec.yaml
├── analysis_options.yaml
├── LICENSE                    # MIT
└── README.md
```

The app is one file on purpose, so judges can paste it into DartPad. [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) maps the sections of that file to the layers they would become in a production build.

## Running the tests

```bash
flutter test                     # all tests
flutter test test/logic_test.dart
flutter test test/widget_test.dart
```

| Suite | Tests | Covers |
|---|---|---|
| `logic_test.dart` | 32 | Haversine distance; seed integrity; GVP clustering; sensor threshold, alerts, clamping, echo; overflow report to nearest bin; fixed vs need-based route (77.3 km vs 43.9 km); stream-wise trips; narrow-lane and maintenance rules; live route; claim, approve, reject, dispute; append-only audit; segregation score; worker scorecard |
| `widget_test.dart` | 3 | Loading to home; IoT "Force overflow" button; full 11-step demo ends with a verified, citizen-confirmed complaint |

**Verification status.** All 32 logic tests have been executed and pass (run in DartPad with a minimal stand-in for `flutter_test`, against Dart 3.13.5 stable). The expected values were cross-checked with an independent Python implementation. The widget tests need the Flutter SDK; run `flutter test` once locally before relying on them. The 11-step demo they exercise was also run by hand in DartPad and completed.

## Sample data

The app seeds itself from the data inside `lib/main.dart`. The JSON files in [`data/`](data/) mirror that seed data in a portable format: for a backend, for slides, or for reviewers who want to inspect it. Everything except `tondiarpet_zone4_reported.json` is demo data. [data/README.md](data/README.md) describes each field.

## Demo script (2 minutes)

See [docs/DEMO_SCRIPT.md](docs/DEMO_SCRIPT.md). The short version:

1. Home, then **RUN FULL DEMO**. It plays sensor breach, alert, e-tricycle dispatch, route, collection, worker claim, reviewer approval, citizen confirmation and audit, in about 25 seconds.
2. **Route Savings**: fixed 77.3 km vs need-based 43.9 km, about 12 L diesel saved per trip (simulated).
3. Complaints, then **CT-2026-1008 (Perungudi)**: a claim rejected for GPS mismatch.
4. **Verify Cleanup** (PIN 9999): worker scorecards with rework %.

## KPIs

| KPI | How the app computes it |
|---|---|
| Distance and diesel saved | Fixed route km minus need-based route km; diesel at an assumed 0.35 L/km |
| Verified closure rate | Complaints closed with reviewer approval and citizen confirmation, as a share of closures |
| GVP recurrence | Re-dumps after a verified cleanup, per GVP |
| Ward segregation score | 1 minus (mixed-waste reports / all reports) per ward; below 60% flags an awareness drive |
| Worker rework rate | (Rejected + disputed claims) / claims |
| SLA breaches | Open complaints older than 24 hours (the blackspot SLA reported for Zone 4) |

## Roadmap: prototype to production

| Prototype (now) | Production |
|---|---|
| In-memory `Store` (`ChangeNotifier`) | Firebase / PostgreSQL + PostGIS backend with REST API |
| Simulated GPS and photos | `geolocator`, `image_picker`, EXIF + server-side timestamp |
| Simulated HC-SR04 readings | ESP32 + HC-SR04 over NB-IoT/LoRa to MQTT |
| Straight-line greedy routing | OSRM / OpenStreetMap road network, Google OR-Tools VRP with capacity and time windows |
| Simulated classifier | TFLite model trained on Kaggle Waste Classification (O/R) + TACO, extended with local sanitary and C&D images |
| Visual civic tag | Real QR codes (`qr_flutter`) printed at each collection point |
| Demo PINs | GCC SSO / OTP login with role-based access |

## Limitations

- All operational data is simulated; distances are straight-line, not road distances.
- State resets on reload (no persistence in DartPad).
- Civic tags are visual previews, not scannable QR codes.
- Ward coordinates are approximate centres; streets are not placed on real ward boundaries.
- Reported Zone 4 figures come from team-supplied reports; check them against GCC sources before quoting them.

## Licence

[MIT](LICENSE). Datasets referenced in the roadmap (Kaggle Waste Classification, TACO, OpenStreetMap) have their own licences; check them before redistributing.
