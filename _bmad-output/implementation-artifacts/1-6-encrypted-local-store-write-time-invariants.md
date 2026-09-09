---
# linear: EMPTY = local-only epic — the PM must NOT create or sync anything in Linear.
linear:
route: {provider: claude, cli: claude, model: opus, effort: high, agent: dev, fallback: [openai/gpt-5.6-sol]}
local_gpu: red
gates:
  - "swift build"
  - "swift test"
  - "bash scripts/guards/safety_guards.sh"
  - "bash scripts/guards/safety_guards.sh --self-test"
  - "bash scripts/guards/driver_guards.sh"
  - "bash scripts/guards/driver_guards.sh --self-test"
max_cycles: 3
---

# Story 1.6: Encrypted local store with write-time invariants

Status: ready-for-review

<!-- Route rationale (for the maintainer): persistence layer with write-time safety invariants
and the repo's FIRST third-party dependency — schema design, collision semantics,
migration discipline. Strong tier: opus/high. PROTECTED PATH: adds a dependency
(GRDB) to Package.swift, so THE MERGE ESCALATES TO THE MAINTAINER regardless of gate
evidence, per the dependency/lockfile rule. Planning note: the epic's ACs (GRDB
unforked on plain SQLite + iOS Data Protection) supersede the architecture
spine's older Structural Seed comment ("GRDB + SQLCipher") — divergence flagged
as spine errata; do not vendor or fork GRDB and do not add SQLCipher. -->

## Story

As a user,
I want my pump data stored on my device and unreadable to anything else,
So that my health data never leaves my control.

## Acceptance Criteria

1. A new SPM target `Persistence` under `Sources/Persistence/`, depending on
   `SafetyCore`, `DriverAPI`, and GRDB (unforked, plain SQLite — the repo's
   first external dependency, pinned to an exact version, `.upToNextMinor` at
   most). The manifest test suite is extended: `Persistence`'s dependency list
   is exactly those three; `SafetyCore` stays zero-dependency; `DriverAPI`
   stays `[SafetyCore]`; no OTHER target gains GRDB. A manifest test also pins
   that GRDB is the ONLY external package dependency of the workspace.
2. Store creation applies iOS Data Protection
   `completeUntilFirstUserAuthentication` to the database file (and its WAL/SHM
   siblings) — never `complete`, which would fail background writes while
   locked (AD-6, FR-135, FR-136). Testable: the file-creation options are
   applied through a seam tests can observe (on macOS, where the gates run,
   the protection attribute is a no-op — assert the INTENT through the seam,
   and document that the attribute itself is device-verified later).
3. This story creates ONLY the tables this epic needs — glucose readings, pump
   status, and raw pump history (FR-135). No alert-history, outbound-queue, or
   meal tables; those arrive with their own work.
4. Write-time uniqueness and collision rules (FR-137): at most one CGM reading
   per timestamp, one basal record per timestamp; cross-source collisions
   resolve deterministically — document and test the chosen rule (e.g. ordered
   source precedence, stable across replays).
5. Write-time absolute-bound enforcement (FR-138, AD-5): a glucose row outside
   the absolute 20-500 bound is REJECTED at write with a typed error; the
   write path constructs `Glucose` (which already throws) rather than
   accepting raw doubles, and narrowable Safety Limits are NEVER a parameter
   to the write path — narrowing lives in validation upstream, the store
   enforces only the absolute bound. Tests pin: 19.9 rejected, 20 accepted,
   500 accepted, 500.1 rejected, non-finite rejected, and that the rejection
   is the typed error (not a crash, not a clamp).
6. Retention (FR-139): user-settable 1...30 days, default 7, validated by a
   throwing type (same discipline as FreshnessThresholds), applied as a
   deletion sweep bounding EVERY table this story creates (and written so
   later tables plug into the same sweep). Tests pin the bounds, the default,
   and that a sweep removes only rows older than the horizon.
7. Migrations (AD-6): numbered, forward-only, starting at v1, no Android
   inheritance. The migrator refuses to run backward; a test pins that the
   schema version after setup is v1 and that re-running setup is idempotent.
8. Concurrency: the store is the SOLE writer (spine seed) — one writer
   connection/queue, Swift 6 concurrency-clean, no `@unchecked Sendable`
   without written justification in the Dev Agent Record.
9. All six gates green (both guard self-tests are stamped gates now).
10. LANGUAGE RULE for all code and comments: no story/epic/AC-number tags in
    source or test comments — state requirements in plain words; AD-x/SI-x/FR-x
    architecture references are fine.

## Tasks / Subtasks

- [x] Task 1: GRDB dependency + Persistence target + manifest test extensions (AC: 1)
- [x] Task 2: store creation with data-protection seam + tests (AC: 2)
- [x] Task 3: schema v1 (glucose readings, pump status, raw history) + migrator + tests (AC: 3, 7)
- [x] Task 4: write path with absolute-bound rejection + uniqueness/collision rules + tests (AC: 4, 5)
- [x] Task 5: retention type + sweep + tests (AC: 6)
- [x] Task 6: single-writer concurrency shape + Dev Agent Record notes (AC: 8)
- [x] Task 7 (cycle 2): all seven required changes from the adversarial review
- [x] Task 8 (cycle 3): the dose table's uniqueness is per category, so a
      coincident basal segment and bolus both persist

## Dev Notes

### Builds on (frozen — do not modify existing production files)

`SafetyCore` (`Glucose` throwing init IS the absolute-bound enforcement — reuse
it, do not re-implement bounds), `GlucoseReading`, clock; `DriverAPI` models
(`PumpStatusSnapshot`, `DoseRecord`) as the shapes rows are built from where
they fit. If a needed shape is missing, record a NEEDS-HUMAN line rather than
modifying DriverAPI.

### Architecture ground truth

_bmad-output/ARCHITECTURE-SPINE.md — AD-5 (throw, never clamp), AD-6
(persistence decisions), Structural Seed (Persistence is the sole writer).
KNOWN ERRATUM: the seed's "GRDB + SQLCipher" comment is superseded by the
epic's plain-SQLite + Data Protection decision — follow this story, not the
seed, on encryption.

### Android ground truth (read-only, semantics only)

android-unofficial — the local store's
uniqueness/collision handling if present (search Room entities/DAOs for
glucose/basal uniqueness); mirror SEMANTICS where they translate. iOS
persistence mechanics (GRDB, Data Protection) are net-new, no inheritance.

### Constraints

- GRDB via SPM from the official repo, exact-pinned; no forks, no SQLCipher,
  no other new dependencies. This is the repo's first dependency — keep the
  surface minimal (import GRDB only inside `Sources/Persistence/`; the
  manifest test in AC 1 enforces it).
- No wall-clock reads (`Clock` injection for retention horizons and any
  timestamps the store itself generates); safety_guards' clock rule covers
  all of `Sources/`.
- Worktree sandbox as before; GRDB will need network for SPM resolution at
  build time — if the sandbox blocks the fetch, record NEEDS-HUMAN rather
  than working around it.
- Never commit `.claude/` or `_bmad-output/`; scratch under `.build/`.

### Testing standards summary

Swift Testing per existing conventions, new `Tests/PersistenceTests/`;
in-memory or temp-file databases per test, no shared state between tests;
no sleeps; collision/boundary/retention cases pinned exactly.

### Project structure notes

Surface: `Package.swift` (dependency + target), `Sources/Persistence/*`,
`Tests/PersistenceTests/*`, manifest tests. Branch from `develop` AFTER the
SimulatedDriver work merges. PR targets `develop`. MERGE: protected path
(dependency addition) — PM prepares full gate evidence and escalates to the maintainer.

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story-1.6 (FR-135..139, AD-5, AD-6)]
- [Source: _bmad-output/ARCHITECTURE-SPINE.md#AD-5, #AD-6, #Structural-Seed (erratum noted above)]
- [Source: _bmad-output/implementation-artifacts/1-2-*.md, 1-4-*.md — Glucose/DriverAPI contracts]

## Dev Agent Record

### Agent Model Used

claude-opus-5 (dev persona, effort high), cycles 1, 2 and 3 of 3. No local-GPU
delegation: `local_gpu: red` on the story and `delegate.sh` is not installed on
this host.

### Debug Log References

Gate runs, all from the worktree root, all green on the final tree:

| Gate | Result |
| --- | --- |
| `swift build` | `Build complete!` |
| `swift test` | `238 tests in 33 suites passed` |
| `bash scripts/guards/safety_guards.sh` | `safety_guards: clean` (44 source files scanned) |
| `bash scripts/guards/safety_guards.sh --self-test` | `72 case(s), 2 documented known bypass(es), 0 unexpected result(s)` |
| `bash scripts/guards/driver_guards.sh` | `driver_guards: clean` |
| `bash scripts/guards/driver_guards.sh --self-test` | `68 case(s), 3 documented known limit(s), 0 unexpected result(s)` |

SPM resolution reached github.com from the sandbox without help; `Package.resolved`
pins GRDB 7.11.1 at `b83108d10f42680d78f23fe4d4d80fc88dab3212`, which is the v7.11.1
tag.

Two failures found and fixed during the run, both in the new source-scan tests:
the scan matched `@unchecked Sendable` and `SafetyLimits` inside the doc comments
that explain those rules, so the scan now strips comments first (and has its own
case pinning that the stripper takes comments and leaves code — otherwise all
three source-scan rules would pass on a file that broke them).

### Completion Notes List

**AC 1 — dependency and target.** GRDB added as `.package(url:…GRDB.swift.git,
exact: "7.11.1")` — exact, not a range; the spine already fixed that version.
`Persistence` depends on `["SafetyCore", "DriverAPI", .product(name: "GRDB", …)]`
and nothing else. `PackageManifestTests` grew five assertions: GRDB is the only
`.package(` declaration and is the official URL at the exact pin; the pin uses no
`from:`/`branch:`/`revision:`/`.upToNext*` spelling; `Persistence`'s dependency
list is exactly those three; no other target declares GRDB (read from the
manifest by enumerating every `.target`/`.testTarget`, so a target added later is
covered without editing the rule); and the enumeration itself is checked against
targets the manifest has, so "no other target declares GRDB" cannot be true of an
empty list. The old `noExternalPackages` assertion was replaced, not deleted —
its successor still fails on a SECOND package. `onlyDeclaredTargetsAreScaffolded`
now expects `Persistence` under `Sources/`. `PersistenceTests` does NOT depend on
GRDB; the two tests that needed database-level access use internal seams instead
(below). A source scan in `PersistenceSurfaceTests` pins that `import GRDB`
appears only under `Sources/Persistence/`, and fails if it finds no import at all
rather than passing vacuously.

**AC 2 — Data Protection.** `StoreProtectionClass` has exactly ONE case,
`completeUntilFirstUserAuthentication`. `complete` is not "avoided by
convention", it is not representable — the reasoning (a background write while
locked would fail, so the reading the user most needs is the one dropped) lives on
the type. Protection is applied through `StoreFileProtecting`; `SystemFileProtection`
sets `NSFileProtectionKey` on iOS/watchOS/tvOS and is an explicit, documented
no-op on macOS. `LocalStore.open` protects the containing directory FIRST when it
creates it (on iOS a directory's class is the default for items created inside,
so the file is protected from the instant SQLite makes it), then protects the
database, `-wal` and `-shm` explicitly after migration has brought the siblings
into existence. A protection failure aborts the open — a store that opened but is
unprotected works, so nobody looks at it again. Tests observe the seam: all three
files protected with the one class, directory first, refusal on failure, plus a
positive control that the same tree opens when protection succeeds. The attribute
itself is device-verified later; on macOS asserting it would assert the host's
silence.

**AC 3 — tables.** Three: `glucose_reading`, `pump_status`, `raw_pump_history`.
A test reads `sqlite_master` back and pins that set exactly, so an alert-history
or outbound-queue table cannot arrive quietly.

**AC 4 — uniqueness and collisions.** One CGM reading per instant and one
pump-status row per instant, enforced by the PRIMARY KEY rather than by the write
path, so no path — including direct SQL — leaves two rows claiming one moment.
Raw history is keyed `(source, sequence_number)`.

The resolution rule, in `SourcePrecedence`: (1) lower rank in the configured
order wins; a source the order does not name ranks after every source it does;
(2) equal ranks resolve on the identifier, lexicographically; (3) same source is
not a precedence question — the store compares VALUES, and identical values are a
replay and a no-op while differing values are `conflictingRecord`. Steps 1 and 2
are functions of the two sources alone, so the same records in any order leave the
same database; step 3 refuses rather than picking by arrival order, which is what
would have made the stored value depend on replay order. Both orders are tested
explicitly for each of the three shapes.

INTERPRETATION, flagged rather than assumed: the AC says "one basal record per
timestamp", and AC 3 forbids creating a basal table. The only per-instant pump
record this schema has is `pump_status`, so the rule is applied there and tested
there. If a dedicated basal/dose table was intended, it needs its own work and
its own AC — it is not in this schema.

Android ground truth (read-only) confirmed the semantics carried over:
`cgm_readings` and `basal_readings` are both `Index(unique = true)` on
`timestampMs` alone, `raw_history_logs` on `sequenceNumber`, retention 1…30 days
defaulting to 7. What was NOT carried over is Android's collision behaviour: it
has a `source` column but no precedence at all, and which row survives falls out
of whichever DAO conflict strategy the calling path used (`REPLACE` on the live
poll, `IGNORE` on backfill and cloud sync). The ordered rule here is net-new and
deliberate, and the divergence is documented on `SourcePrecedence`. One
improvement over Android: its raw-history key is the sequence number alone while
its own comment says "unique per pump" — here the source is part of the key.

**AC 5 — absolute bound.** `recordGlucose(mgdl:…)` constructs
`SafetyCore.Glucose` and maps `GlucoseError` to
`PersistenceFailure.glucoseRejected(_:)`; the store never spells 20 or 500
anywhere (safety_guards would fail it if it did) and takes no `SafetyLimits`
parameter — a source scan pins that. Tests: 19.9 rejected, 20 stored, 500 stored,
500.1 rejected, NaN and ±infinity rejected as `.notFinite` (a different kind of
wrong from out-of-range), the store still usable after a refusal, and the failure
compared as a VALUE (`.glucoseRejected(.outOfRange(mgdl: 19.9))`), not just as a
thrown something. Reads reconstruct `Glucose` too, so a row written by something
other than this API surfaces the same refusal instead of a reading on a screen;
`insertUnvalidatedGlucose` is the internal seam that stages that row (the only
caller is that test, and there is no public path to it).

**AC 6 — retention.** `RetentionWindow`, throwing, 1…30 days, default 7 — same
discipline as `FreshnessThresholds`, and where Android's settings store clamps,
this throws. Duration is elapsed time (86 400 s/day), not calendar days: a
calendar answer depends on time zone and DST, so the same sweep would take a
different set depending on where the phone was. `sweepExpiredRecords` deletes
strictly-older rows across every entry in `StoreSchema.retainedTables`, in one
transaction, with the horizon from the injected clock. A later table plugs in by
adding one `RetainedTable` line — and a test compares the tables in the file
against that list, so a table that escaped the sweep fails the gate rather than
growing forever. Tests pin the bounds, the default, the boundary (a row exactly on
the horizon is KEPT), all three tables, and the deleted count.

**AC 7 — migrations.** Numbered, forward-only, `v1`, no Android inheritance
(Android is at 13 and carries decisions this app has not made). Tests: applied
identifiers after setup are `["v1"]`; re-opening is idempotent and data survives;
a file carrying a migration this build does not know is refused with
`schemaFromNewerVersion(applied: ["v1", "v2"])` rather than opened and guessed at.
`StoreSchema.stampForeignMigration` is the internal seam that stages that file —
no production path writes to the migrator's bookkeeping.

**AC 8 — concurrency.** `DatabasePool`: exactly one writer connection, readers
concurrent against WAL snapshots. `LocalStore` is a `Sendable` STRUCT over
Sendable parts (GRDB's writers are `Sendable`, so is `SafetyCore.Clock`), so
there is no lock and no `@unchecked Sendable` — and a source scan pins that
neither `@unchecked` nor `nonisolated(unsafe)` appears anywhere in the target, so
the claim stays true rather than being true today. NOTHING was justified as
`@unchecked Sendable`, in the target or in its tests: `StoreFileProtecting` is
deliberately NOT `Sendable`, because the store calls it synchronously while
opening and never retains it, so requiring `Sendable` would constrain nothing and
would push every test double into `@unchecked`.

**AC 9** — six gates green, table above.

**AC 10** — no story/epic/AC tags in any source or test comment; AD-x/SI-x/FR-x
references only. Two pre-existing phrasings in files this change already touched
were reworded off flow vocabulary (`Package.swift`'s "(story 1.5)" and two
"a later story" comments in `PackageManifestTests`).

**Merge note carried forward:** this adds the repository's first dependency, so
the merge is a protected-path escalation regardless of gate evidence.

### Cycle 2 — response to the adversarial review

Gate runs, all from the worktree root, all green on the final tree:

| Gate | Result |
| --- | --- |
| `swift build` | `Build complete!` |
| `swift test` | `259 tests in 34 suites passed` |
| `bash scripts/guards/safety_guards.sh` | `safety_guards: clean` (45 source files scanned) |
| `bash scripts/guards/safety_guards.sh --self-test` | `72 case(s), 2 documented known bypass(es), 0 unexpected result(s)` |
| `bash scripts/guards/driver_guards.sh` | `driver_guards: clean` |
| `bash scripts/guards/driver_guards.sh --self-test` | `68 case(s), 3 documented known limit(s), 0 unexpected result(s)` |

**1 — the unvalidated write path is gone, and the bound is in the schema.**
`insertUnvalidatedGlucose` is deleted; nothing in `Sources/Persistence/` writes a
glucose row without constructing `Glucose` first. `glucose_reading.mgdl` now
carries a CHECK, so the bound holds against a writer that is not this code at all.

The CHECK is INTERPOLATED from `SafetyConstants.glucoseValidRange`, not spelled in
the DDL — the bound has one definition site, and a second copy in SQL is a copy
that drifts silently (safety_guards would also have failed a literal one). The
consequence is written on the migration: moving that range is a NEW numbered
migration that rebuilds the table, never an edit to v1, because a device that
already ran v1 will not run it again.

Testing this needed a writer that is not the store. The test target opens the file
through SQLite's own C API (`import SQLite3`, `RawSQLiteFile`) — not GRDB, so the
vendor still appears in exactly one target, and not a production seam, so the
escape hatch the review objected to does not exist in any form. Three tests: the
column refuses 19.9, 500.1 and 1000 with a CHECK error; a row forced past the
constraint (`PRAGMA ignore_check_constraints`, which is what a program written
before the constraint existed looks like) is still refused on the way OUT with the
same typed error; and a positive control that the raw connection reaches the
store's file at all, without which the first two would pass against an empty table.

**2 — the insulin/basal surface exists.** New table `insulin_dose`, keyed on
`completed_at` alone, so one delivery per instant is a PRIMARY KEY rather than a
write-path convention. `record(_ dose: DoseRecord, from:)` writes it and
`insulinDoses(since:)` reads it back, over `DriverAPI`'s existing `DoseRecord` —
no new shape was declared and DriverAPI was not modified. Cross-source collisions
use the same `SourcePrecedence` rule, with permutation tests for all three
branches (ranked, unlisted-ranks-last, unranked-resolve-lexicographically), plus
replay, same-source contradiction, category round-trip, and a raw-SQL test that
the UNIQUE key refuses a second row for one instant.

Two things a reviewer should weigh rather than take on trust:

- This is a FOURTH table, and AC 3 names three. FR-137's "one basal record per
  timestamp" cannot be satisfied without a table to hold those records, and the
  cycle-2 direction is explicit that pump-status uniqueness does not substitute
  for it. So the fourth table is the AC-3 list read as "the tables this epic
  needs", not as "exactly these three". Alert history, the outbound queue and
  meals are still absent, and the schema test still pins the set exactly.
- "Basal" is Android's word. iOS's `DriverAPI` has no basal-RATE model — its
  `InsulinSource` reports `DoseRecord`, insulin that COMPLETED — so the per-instant
  insulin invariant is applied to deliveries, which is what this platform records.
  Android's `basal_readings` (rate, isAutomated, activityMode, unique on
  `timestampMs`) has no counterpart here yet; if a rate table is wanted it needs a
  DriverAPI shape first, and that is its own work.

**3 — the protection seam is unreachable from outside the package.** Nothing in
`StoreFileProtection.swift` is public any more: the protocol, the class enum and
`SystemFileProtection` are all internal. The public `open(at:clock:precedence:)`
takes NO protection argument and applies the real thing; the injecting overload is
internal and reached only through `@testable`. Two source-scan tests pin it — the
seam file contains no `public`, and every `public static func open(` signature is
checked for a protection parameter — and each has a companion test proving the
scan finds what it claims to (otherwise "no public open takes protection" would be
true of a rule that found no opens).

**4 — one writer per file, enforced.** `StoreWriters` is an actor keyed by the
path with symlinks resolved (`/var/…` and `/private/var/…` are one file, and a
temporary directory is exactly that case). A second open of the same path gets the
SAME connection — sharing, not refusing, because an app opens its store on launch
and a scene or an extension can reasonably ask again; refusing would push every
caller into building a singleton of its own, which is the problem moved rather
than solved. The clock and precedence order stay on the store value, so a second
handle does not inherit someone else's collision rule — tested. Making the
registry an actor is what turned `open` into an `async` call; the alternative
inside the package's macOS 14 / iOS 17 floor was a lock behind `@unchecked
Sendable`, which AC 8 rules out and a source scan enforces.

`stampForeignMigration` moved off `StoreSchema` and onto `LocalStore`, where it
goes through the store's own writer instead of opening a second `DatabaseQueue`.
Registered connections are never dropped, and why is written on the type:
`LocalStore` is a value anyone may hold, so dropping a connection out from under
one would be a use-after-close.

**5 — pump-status permutations.** Three parametrized pairs mirroring the glucose
ones (ranked, unlisted, unranked), each asserting the surviving row and its source
are the same whichever arrived first.

**6 — the import guard walks the repository.** The scan now starts at the repo
root and skips only build products and VCS bookkeeping, so `Tests/`,
`Package.swift` and any future Swift-bearing directory are covered. It asserts it
reached one file in each corner of the tree, so a walk that quietly found nothing
fails instead of passing. It also had to learn the difference between IMPORTING
GRDB and MENTIONING it — this test file names the import inside a string literal —
so detection is line-anchored and has its own test.

The rule allows `Sources/Persistence/` ONLY, which is tighter than the cycle-2
direction's "Sources/Persistence/ and Tests/PersistenceTests/". Nothing in the
tests needs the vendor: the one thing that wanted database-level access — a writer
that is not the store — is better served by SQLite's own C API, since GRDB in the
test target would prove the store's rules against the same library the store uses.
Widening the allowance later is one edit; it is not needed today.

**7 — flow vocabulary.** The three "story" references in
`PackageManifestTests.swift` are reworded to plain English. Four remain elsewhere
in the repository (`SafetyLimitsValidator.swift`, `DriverRow.swift`,
`SimulatedDriver.swift`, `DriverLifecycleTests.swift`) — prose rather than tags,
in files this change does not touch and the Dev Notes freeze. Flagged, not edited.

**`@unchecked Sendable`, declared.** One, and it is in the test target:
`RecordingFileProtection`. The protection seam is `Sendable` because the store
applies it inside an async open, an actor cannot conform to it (the seam's method
is synchronous), and a recording double is mutable by definition. Its state is
`NSLock`-guarded on every access, and in practice the store calls it serially from
one task while the test reads it after the open returned. `Sources/Persistence/`
still contains zero opt-outs, and the source scan that pins that is unchanged.

### Cycle 3 — response to the re-review

Gate runs, all from the worktree root, all green on the final tree:

| Gate | Result |
| --- | --- |
| `swift build` | `Build complete!` |
| `swift test` | `262 tests in 34 suites passed` |
| `bash scripts/guards/safety_guards.sh` | `safety_guards: clean` |
| `bash scripts/guards/safety_guards.sh --self-test` | `72 case(s), 2 documented known bypass(es), 0 unexpected result(s)` |
| `bash scripts/guards/driver_guards.sh` | `driver_guards: clean` |
| `bash scripts/guards/driver_guards.sh --self-test` | `68 case(s), 3 documented known limit(s), 0 unexpected result(s)` |

**The dose key is now `(completed_at, category)`.** `insulin_dose`'s PRIMARY KEY
was the instant alone; it is now the instant and the category, so a basal segment
and a bolus finishing on the same tick are two rows and neither depends on which
arrived first. Within one category the old rule is unchanged: two sources
reporting basal for one instant still resolve through `SourcePrecedence`, and one
source contradicting itself is still refused rather than resolved.

The write path matches on the pair, and the `incomingWins` UPDATE no longer
writes `category` — it is part of the key now, so the row being replaced is by
definition the one for that category. `insulinDoses(since:)` orders by instant
THEN category: the instant stopped being a total order the moment two rows could
share it, and without the tie-break a caller comparing two reads would have been
comparing SQLite's row order.

The v1 migration was edited in place rather than getting a v2. That is the
opposite of the forward-only rule everywhere else, and it is correct exactly
once: v1 has not shipped, so no device has applied it. The rule bites from the
first release, and the doc comment on `migrator()` already says so.

**Why the key is the category and not a basal flag.** The cycle-3 direction
offers "a partial unique index on `completed_at` WHERE the category is basal, or
an equivalent composite that distinguishes category classes". The partial index
is not available: `DriverAPI.DoseCategory` has NO basal case — it mirrors
Android's bolus-only `BolusCategory` case for case — so there is no predicate to
write. A Driver reporting basal delivery reports it as `.other` with the device's
own label beside it, which is what `SimulatedDriver` does ("Simulated basal").
Every basal record therefore lands in one category, and one-row-per-category IS
one-row-per-basal-segment.

What a reviewer should weigh rather than take on trust: `.other` is the
vocabulary's catch-all, so a basal segment and some OTHER unmapped delivery
completing at the same instant still compete for one row. That is a narrower loss
than the one this cycle fixes, and closing it needs a `DriverAPI` shape that names
basal — which the Dev Notes freeze, and which is its own work. Adding a basal case
to `DoseCategory` was not done here for that reason.

**Tests.** Three added, all six existing insulin suites still green.

- The reviewer's own probe, parametrized on arrival order: basal 0.9 U (`.other`,
  "Simulated basal") and a bolus 4.5 U (`.food`, "Simulated meal bolus") from the
  SAME pump at one `completedAt` — both persist, and the final state compares
  equal as an ordered list in both orders. Those are `SimulatedGenerator`'s actual
  constants (`mealDoseUnits = 4.5`, `basalDoseUnitsPerSegment = 0.9`), not
  stand-ins.
- Two basal records at one instant from different sources, parametrized on arrival
  order: exactly one survives, the ranked source wins, permutation-stable.
- The schema half of the pair, through `RawSQLiteFile` rather than the store: the
  key refuses a second `correction` row at an instant that already has one, AND
  admits an `other` row at that same instant. The second half is what stops the
  first from passing against a table that refuses everything at that instant.

Nothing else changed in the store: no new file, no change to protection,
retention, the glucose path, the writer registry, or the manifest.

**One change outside that surface, and why it was not left alone.** `swift test`
was not reliably green. `WallClockSchedulerTests.cancelStopsTicking` — a
pre-existing SafetyCore test, untouched by this work — failed intermittently on
`#expect(counter.value > 0)`: it registers a 0.02 s repeating tick, sleeps a fixed
0.1 s and asserts a tick has landed. Measured on this host, holding everything
else constant:

| Tree | Machine idle | Machine loaded (8 spinners) |
| --- | --- | --- |
| Full suite | 24/24 passed | 13/16 passed |
| `--skip Persistence` | — | 16/16 passed |

So the test is not flaky on its own — the Persistence suites make it flaky. They
add real file I/O (temporary directories, SQLite opens, WAL siblings) running
concurrently with a scheduler test that had almost no margin, and the first
dispatch slips past the 0.1 s deadline.

The fix is in the test only, and it removes an assumption rather than an
assertion: the first tick is now POLLED for, up to a second, instead of assumed to
have arrived by a deadline. What the test pins — that cancellation stops the
ticking — is the settle comparison after `cancel()`, which is unchanged.
`WallClockScheduler` itself is untouched. After the change: 40/40 loaded runs
passed.

This is outside the "nothing else changes" instruction, so it is flagged rather
than buried. The alternative was to report a gate as green that fails roughly one
run in five on a loaded CI box, which it is not.

### File List

Added:

- `Sources/Persistence/LocalStore.swift`
- `Sources/Persistence/PersistenceFailure.swift`
- `Sources/Persistence/RetentionWindow.swift`
- `Sources/Persistence/SourcePrecedence.swift`
- `Sources/Persistence/StoreFileProtection.swift`
- `Sources/Persistence/StoreSchema.swift`
- `Sources/Persistence/StoreWriters.swift` (cycle 2)
- `Sources/Persistence/StoredRecords.swift`
- `Tests/PersistenceTests/CollisionTests.swift`
- `Tests/PersistenceTests/SoleWriterTests.swift` (cycle 2)
- `Tests/PersistenceTests/DataProtectionTests.swift`
- `Tests/PersistenceTests/GlucoseWriteTests.swift`
- `Tests/PersistenceTests/PersistenceSurfaceTests.swift`
- `Tests/PersistenceTests/RetentionTests.swift`
- `Tests/PersistenceTests/SourcePrecedenceTests.swift`
- `Tests/PersistenceTests/StoreSchemaTests.swift`
- `Tests/PersistenceTests/TestSupport.swift`
- `Package.resolved`

Modified:

- `Package.swift`
- `Tests/SafetyCoreTests/PackageManifestTests.swift`
- `Tests/SafetyCoreTests/WallClockSchedulerTests.swift` (cycle 3 — the timing
  flake the Persistence suites exposed; test only)

## Cycle 2 — REQUIRED CHANGES from adversarial review

Read _bmad-output/implementation-artifacts/1-6-review-codex.md. Fix all seven:

1. KILL the unvalidated production write path. `insertUnvalidatedGlucose` must
   not exist as production API: delete it; the tamper test constructs its
   tampered row via direct SQL from the TEST target instead. Defense in depth:
   add a schema-level CHECK constraint on the glucose column (mgdl BETWEEN 20
   AND 500) so even raw SQL cannot store an out-of-bound value; test that the
   constraint itself rejects (write via test-target raw SQL, expect failure).
2. Basal surface (FR-137): add the basal/dose write path using the DriverAPI
   DoseRecord shape, with one-basal-per-timestamp uniqueness enforced by schema
   constraint, deterministic cross-source collision resolution matching the
   documented rule, and permutation tests (any arrival order, same final rows).
3. Confine the protection seam: public open() applies the real Data Protection
   unconditionally; the injectable StoreFileProtecting seam becomes internal +
   @_spi (tests may inject; consumers cannot pass a no-op). Pin with a test
   that the public surface offers no way to opt out.
4. Enforce sole writer: one writer per database path (path-keyed registry or
   equivalent), second open() of the same path fails or returns the same
   store — pick one, document, test. stampForeignMigration must go through the
   same writer connection, never open its own.
5. Pump-status collision permutation tests (mirror the glucose ones).
6. Import guard scans ALL Swift-bearing paths (Sources AND Tests and any
   other), asserting GRDB imports appear only under Sources/Persistence/ and
   Tests/PersistenceTests/.
7. Strip the three "story" references from PackageManifestTests.swift comments
   (plain words; AD-x/FR-x fine).

All six stamped gates green. Dev Agent Record updated per finding.

## Cycle 3 (FINAL) — ONE REQUIRED CHANGE from re-review

Six findings closed. One MAJOR remains (see "Cycle 2 re-review"): the dose
table's uniqueness is one-dose-of-ANY-category per timestamp, which rejects a
valid coincident basal + bolus pair (SimulatedDriver emits exactly that), and
makes stored insulin depend on arrival order.

Fix: the uniqueness invariant is one BASAL record per timestamp (FR-137's
actual rule), enforced at schema level (partial unique index on completed_at
WHERE the category is basal, or an equivalent composite that distinguishes
category classes). Coincident records of DIFFERENT categories from the same
pump are both retained. Cross-source collision resolution for the SAME
category+timestamp keeps the documented deterministic rule and its permutation
tests. Required tests: (a) the reviewer's probe — basal 0.9 U and bolus 4.5 U
at the same completed_at both persist, in BOTH arrival orders, final state
identical; (b) two basal records at one timestamp: exactly one survives per
the precedence rule, permutation-stable; (c) existing permutation suites stay
green. Nothing else changes. All six stamped gates green.
