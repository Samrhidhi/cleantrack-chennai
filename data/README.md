# Sample data

These files mirror the data the app seeds itself with (in `lib/main.dart`), in a portable JSON form.

| File | Type | Contents |
|---|---|---|
| `wards.json` | DEMO | 10 Chennai wards (approximate centres) and the assumed central depot |
| `bins.json` | DEMO | 20 named collection points: ward, coordinates, capacity (L), waste stream, simulated fill %, hours since emptied, narrow-lane flag |
| `trucks.json` | DEMO | 4 vehicles: E-tricycle, 2 compactors, sweeper (under maintenance) |
| `complaints_seed.json` | DEMO | 16 complaints with status, priority, worker and age. They produce two chronic GVPs and one GPS-mismatch rejection |
| `tondiarpet_zone4_reported.json` | REPORTED | Figures from three team-supplied Zone 4 (Tondiarpet) reports, tagged R1/R2/R3 |

## Field notes

- **Coordinates** are WGS84 decimal degrees. Ward points are approximate centres, not official boundaries.
- **`stream`** is one of `wet`, `dry`, `sanitary`, `cnd` (construction and demolition), `mixed`.
- **`fill_percent`** is a simulated HC-SR04 reading. The app converts it to an echo distance: `120 cm × (1 − fill/100)`.
- **`narrow_lane: true`** marks lanes reported as under 3 m wide (Tondiarpet Wards 38/39). Only the E-tricycle may be routed there.
- **`reported_hours_ago`** and **`last_emptied_hours_ago`** are relative to when the app starts, so the demo always looks current.
- Complaint IDs are assigned in seed order, `CT-2026-1001` to `CT-2026-1016`. The tests refer to them by ID.

## Data quality

`tondiarpet_zone4_reported.json` keeps values where the reports disagree (lane width, bio-mining cost, landfill area, fine tiers) under separate keys rather than picking one. R2 is a hackathon proposal document, not an official GCC record. Verify against GCC sources before quoting any figure publicly.
