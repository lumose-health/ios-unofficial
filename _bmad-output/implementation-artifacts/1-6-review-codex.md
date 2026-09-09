# Adversarial review: encrypted local store (cycle 1)

- MAJOR — The absolute write-time bound is bypassable inside production code: `LocalStore.insertUnvalidatedGlucose` executes `INSERT OR REPLACE` with a raw `Double`, `glucose_reading.mgdl` has no validating constraint, and `readRefusesATamperedRow` proves that this path writes `1000` into the table before the read rejects it (`LocalStore.swift:510-522`, `StoreSchema.swift:80-85`, `GlucoseWriteTests.swift:81-89`).
- MAJOR — The required one-basal-record-per-timestamp invariant is absent: v1 creates only glucose, pump-status, and raw-history keys, Persistence exposes no `DoseRecord`/basal write surface despite `DriverAPI` already defining `DoseRecord`, and the implementation substitutes pump-status uniqueness for basal uniqueness (`StoreSchema.swift:76-119`, `LocalStore.swift:249-319`, `InsulinModels.swift:41-89`).
- MAJOR — Data Protection is optional at the public boundary: `LocalStore.open` publicly accepts any `StoreFileProtecting`, so a consumer can pass a no-op implementation and create/open an unprotected database; the recording test double demonstrates that arbitrary implementations are accepted rather than confining this seam to tests (`LocalStore.swift:71-76`, `StoreFileProtection.swift:40-48`, `DataProtectionTests.swift:28-43`).
- MAJOR — A sole writer is not enforced: every call to public `LocalStore.open` creates another `DatabasePool` for the same path with no singleton/path guard, and production `StoreSchema.stampForeignMigration` independently opens a `DatabaseQueue`, so the module can own multiple writer connections despite the one-writer claim (`LocalStore.swift:71-102`, `StoreSchema.swift:125-141`).
- MINOR — Collision replay coverage does not match the Dev Agent Record: glucose permutations are exercised, but pump status is tested only cloud-first and raw-history sources use different composite keys rather than colliding, so no permutation test exists for the missing basal surface (`CollisionTests.swift:69-129`, `CollisionTests.swift:131-143`, `CollisionTests.swift:179-212`).
- MINOR — The GRDB import guard proves only the production `Sources` subtree, not the stated “nowhere outside `Sources/Persistence/`” boundary; `swiftFiles(under: "Sources")` never examines `Tests` or other Swift-bearing repository paths (`PersistenceSurfaceTests.swift:57-66`).
- MINOR — The language-rule claim is false on the reviewed tree: modified manifest tests still contain three source-comment references to “story” even though the acceptance criterion prohibits story/epic/AC tags in all source and test comments (`PackageManifestTests.swift:201-205`).

Gate evidence: `swift build --disable-sandbox` passed; `swift test --disable-sandbox` passed 238 tests in 33 suites; both safety guards and both driver guards passed, including their self-tests.

VERDICT: CHANGES-REQUIRED
The store currently permits invariant-bypassing writes, omits basal uniqueness, and does not make protection or the single-writer rule mandatory.

## Cycle 2 re-review

- RESOLVED — The unvalidated production write path is gone. An ordinary consumer cannot compile a call to `insertUnvalidatedGlucose`; the public raw-value writer rejects 1000 mg/dL with `PersistenceFailure.glucoseRejected`, and an independent SQLite connection is rejected by the `glucose_reading.mgdl` CHECK constraint (`LocalStore.swift:206-220`, `StoreSchema.swift:93-102`).
- MAJOR — The new `DoseRecord` surface enforces one dose of any category per timestamp, not one basal record per timestamp. `record(_:from:)` is documented and exposed for every completed insulin delivery, while `insulin_dose.completed_at` alone is the primary key (`LocalStore.swift:351-421`, `StoreSchema.swift:118-136`). This conflicts with an existing valid producer: `SimulatedDriver` can emit a meal bolus and a basal segment on the same tick with the same completion timestamp (`SimulatedGenerator.swift:12-20`, `SimulatedGenerator.swift:142-149`). A reconstructed public-surface probe wrote those two valid `DoseRecord`s from the same pump: basal-first retained 0.9 U and rejected 4.5 U; bolus-first retained 4.5 U and rejected 0.9 U. The final stored insulin therefore depends on arrival order, and the store cannot persist the platform's valid dose stream. The schema uniqueness check and cross-source permutation tests pass, but they pin the overly broad key rather than the required basal-only invariant.
- RESOLVED — Consumers cannot inject a no-op protector: the protection types and injecting overload are internal, and an ordinary consumer compile probe reports an extra `protection` argument. The sole public file-backed `open` constructs `SystemFileProtection` unconditionally (`LocalStore.swift:70-102`, `StoreFileProtection.swift:21-82`).
- RESOLVED — Repeated opens of the same canonical path share the registry's writer, including symlinked spellings; reconstructed double-open state sharing and the writer-identity tests pass. `stampForeignMigration` is internal and writes through `performWrite` on that same writer rather than opening another connection (`StoreWriters.swift:43-66`, `LocalStore.swift:636-655`).
- RESOLVED — Pump-status collision coverage now exercises both arrival orders for ranked, unlisted, and unranked sources (`CollisionTests.swift:131-194`).
- RESOLVED — The GRDB import guard walks the repository root, skips only build/VCS directories, asserts representative production, test, driver, and manifest files were reached, and permits imports only under `Sources/Persistence/` (`PersistenceSurfaceTests.swift:12-20`, `PersistenceSurfaceTests.swift:32-108`).
- RESOLVED — The three `story` references are absent from `PackageManifestTests.swift` comments.

Gate evidence: `swift build --disable-sandbox` passed; `swift test --disable-sandbox` passed 259 tests in 34 suites; both safety guards and both driver guards passed, including 72-case and 68-case self-tests with only their documented known limits.

VERDICT: CHANGES-REQUIRED
The new generic dose writer drops or refuses a valid coincident basal/bolus pair, making stored insulin depend on arrival order.

## Cycle 3 re-review

- RESOLVED — Basal 0.9 U and bolus 4.5 U at one `completed_at` both persist in basal-first and bolus-first order, and both permutations produce the same ordered final state.
- RESOLVED — Two basal records at one timestamp resolve to exactly one ranked-source winner in either arrival order.
- RESOLVED — The `(completed_at, category)` schema key enforces same-category uniqueness while admitting a coincident delivery from another category; the existing collision and permutation suite remains intact.

Gate evidence: the three focused dose/schema probes passed; all 25 collision tests passed; `swift test --disable-sandbox` passed 262 tests in 34 suites; both safety and driver guards passed, including their 72-case and 68-case self-tests with only the documented known limits.

VERDICT: APPROVED
The dose key now retains coincident basal and bolus deliveries while preserving deterministic, schema-enforced basal collision resolution.
