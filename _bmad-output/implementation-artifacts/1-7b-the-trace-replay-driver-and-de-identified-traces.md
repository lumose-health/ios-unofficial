---
# linear: EMPTY = local-only epic — the PM must NOT create or sync anything in Linear.
linear:
stamp: _bmad-output/implementation-artifacts/1-7b-the-trace-replay-driver-and-de-identified-traces.md.stamp.json
persona: dev
memory_mode: advisory
gates:
  - "swift build"
  - "swift test"
  - "bash scripts/guards/safety_guards.sh"
  - "bash scripts/guards/safety_guards.sh --self-test"
  - "bash scripts/guards/driver_guards.sh"
  - "bash scripts/guards/driver_guards.sh --self-test"
  - "bash scripts/ci-local.sh --self-test"
  - "xcodebuild test -scheme GlycemicGPT-Package -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath .build/xcode-dd"
  - "xcodebuild build -project Apps/GlycemicGPT/GlycemicGPT.xcodeproj -scheme GlycemicGPT -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath .build/xcode-dd CODE_SIGNING_ALLOWED=NO"
max_cycles: 3
---

# Story 1.7b: The Trace-Replay Driver and de-identified traces

Status: done

<!-- Planning note (for the maintainer): second of three parts of epics.md Story 1.7 (the split is
explained in 1-7a's planning note). DEPENDS ON 1.7a merged to develop: this Driver replays frames
through `TandemWire`, and that is the whole point of it. Estimate: ~800 reviewable lines over
~14 files, about 40% tests and ~60 lines of fixture JSON. At budget, so no further split; if it
runs over, move the de-identification README to 1.7c.

What this story does NOT do: the Driver is registered in the catalog here (driver_guards requires
the entry in the same change as the target), but it is NOT composed into the app, so no user can
see or activate it yet. The kill switch, the app composition and the DEMO DATA label are 1.7c.

Decisions taken here that the maintainer should see:
- Traces are SYNTHESIZED, not captured. Android has no Trace-Replay Driver and no trace files;
  its Tandem frames exist only as hex inside unit tests. Every value in the bundled trace is
  invented (A-7 is met by construction). The format also accepts a de-identified capture, but
  only with a named reviewer, which is OQ-18's open question; until it is answered, no capture
  lands.
- Replay is immediate, not paced: each activation replays the whole trace once. Samples keep
  the timestamps the frames carry, so in the app they read as old (Too Stale). That is the
  honest result of replaying a recording, and changing frame timestamps to "now" would be a
  test-only branch. A paced replay is a later decision; re-anchoring is in scope (see the PM decision at the end).
- The replay cursor is in memory and restarts at frame 0 on every activation. AD-19's durable
  cursor exists so that a live pump's history is not lost across termination; a trace is
  immutable, so restarting loses nothing. Please confirm.
- No trace picker. One bundled trace; the UI for choosing a trace is out of scope.

Route: NOT chosen here; the PM routes via /v1/route. Blast radius is moderate: a new Driver
target, the catalog, the manifest tests. No dosing logic, no alert floor, no CI workflow, no
dependency change. The ingestion mapping itself lives in 1.7a and is not changed here. -->

## Story

As a maintainer,
I want a shipped Driver that replays committed, de-identified Tandem frames through the real
decode path,
so that protocol correctness and safety filtering are testable in CI and in the Simulator
without hardware and without a live pump.

## Acceptance Criteria

From epics.md Story 1.7 (FR-36, AD-22), with FR-36's testable consequences, A-7 and §8.3's
device-table row for this Driver. AC numbering is local to this file.

1. **A Driver target registered in the catalog (FR-22, FR-36, §8.3).** New target
   `TraceReplayDriver` at `Sources/Drivers/TraceReplay/` with dependencies exactly `DriverAPI`,
   `SafetyCore` and `TandemWire`, `resources: [.copy("Traces")]`, `exclude: ["README.md"]`, and
   a test target `TraceReplayDriverTests` with its own `resources: [.copy("Traces")]`.
   `DriverCatalog.entries` gains, after the Simulated entry:
   identifier `com.glycemicgpt.trace-replay`, targetName `TraceReplayDriver`, displayName
   `Trace-Replay Driver`, transport `.inProcess`, version `1.0.0`, capabilities
   `[.glucoseSource, .insulinSource]`, verification `.beta`. The instance's `descriptor` equals
   that entry (a test, as `SimulatedDriverCapabilityTests` does). `PackageManifestTests` asserts
   the exact dependency list and enumerates both targets. `DriverCatalogTests` is updated for two
   entries without weakening any assertion.
2. **Trace format v1, strict (A-7, FR-36).** `TraceFile` decodes a JSON document with exactly
   these keys, and **fails on any key it does not know, at any level**:
   - top level: `format` (must be `"glycemicgpt-trace"`), `version` (must be `1`), `vendor`
     (must be `"tandem"` in v1), `description` (non-empty), `pumpTimeZone` (a valid
     `TimeZone` identifier), `provenance`, `frames` (non-empty array);
   - `provenance`: `source` (`"synthesized"` or `"deidentified-capture"`), `method` (non-empty),
     `reviewedBy` (string or null; **must be a non-empty string when `source` is
     `"deidentified-capture"`**);
   - each frame: `channel` (a `TandemChannel` raw value), `receivedAt` (ISO-8601 instant),
     `notifications` (non-empty array of lowercase, even-length hex strings), `note` (string).

   Rejecting unknown keys is the de-identification backstop: a field such as a serial number
   cannot ride along in a fixture. Any violation surfaces as
   `DriverFailure.decodeFailed(detail: "trace file")`, never a trap.
3. **Frames go through the production path, with no test-only branch (FR-36, AD-22).** For each
   frame in order: a fresh `TandemPacketAssembler` is fed every notification; exactly one
   message must complete, on the last notification; `TandemMessage.decode` must succeed; then
   `TandemReadMapper(validator:pumpTimeZone:)` maps it with the frame's `receivedAt`. The Driver
   reads nothing else from the trace: `note` and `description` never affect behaviour, and there
   is no code path that exists only for tests. Incomplete reassembly, an extra completed
   message, or a failed `decode` is `.decodeFailed(detail: "frame")`.
4. **What each outcome does (AD-22, SI-2, SI-8).**
   - `.glucose(sample)`: yielded on the glucose stream and held as the latest reading.
   - `.insulinOnBoard(sample)`: yielded on the IOB stream.
   - `.sensorReadingUnusable`, `.notRead`: consumed, logged, nothing emitted.
   - `.valueRejected(bound:)`: consumed, logged with the bound, nothing emitted, replay continues.
     Never clamped.
   - `.decodeFailed`: **replay halts at that frame.** The cursor stays on it, no later frame is
     replayed, the failure is logged, and from then on `latestReading()` and `doses(since:)`
     throw that `.decodeFailed` (the designated channel for a runtime fault, as in the Simulated
     Driver). Samples emitted before the halt stay emitted.
   - A trace file that does not load makes `activate()` throw `.decodeFailed(detail: "trace
     file")`.
5. **The bundled trace and its golden result (FR-36).** `Traces/tandem-status-01.json` ships in
   the target, byte-for-byte as given in Dev Notes. Replayed with limits equal to the absolute
   bound, the per-frame results equal the golden table in Dev Notes, kept as a literal table in
   the test so that a parser change that alters extraction fails CI with a visible diff. This one
   trace proves: `egvStatusId` 0 and 4 discard an in-range value; 2 and 3 are admitted; the IOB
   selector 0, 1 and an unknown value pick Mudaliar, Swan-6hr and Mudaliar from a cargo whose
   two fields differ; a value below and a value above the absolute bound are rejected with the
   validator's bound and logged; multi-packet reassembly works (the IOB frames are two
   notifications).
6. **Decode failure holds the cursor (SI-8, AD-22).** The test-only trace
   `Tests/TraceReplayDriverTests/Traces/tandem-decode-failure-01.json` (Dev Notes) has a CRC
   error in frame 1 of 3. After activation: the glucose stream has yielded exactly frame 0's
   sample, the cursor is 1, frame 2 was never mapped, `latestReading()` throws
   `.decodeFailed(detail: "frame")`, and the log recorded one halt at frame 1.
7. **Deterministic (FR-36).** Two fresh Drivers replaying the same trace produce identical
   per-frame results and identical sample sequences. Deactivate then activate on one instance
   replays from frame 0 into fresh streams and produces the same sequence again; the previous
   activation's streams are finished.
8. **Limits are read fresh (FR-32).** With the validator's limits narrowed (through `adopt`)
   so that 131 mg/dL is outside them, a fresh activation rejects frame 2 with `.valueRejected`
   and still admits 123 and 118. No Driver restart logic is involved beyond activation.
9. **Logged without health values (SI-9).** A `TraceReplayLogging` protocol with an
   `os.Logger` implementation (subsystem `com.glycemicgpt.ios`, category `TraceReplayDriver`).
   Log calls carry the frame index, the `bound` or `detail` string, or the `egvStatusId`, and
   never a glucose value, an IOB value or hex. A recording double in the tests asserts the
   exact calls for the bundled trace (two value rejections with the validator's bound strings,
   two unusable readings with status 0 and 4) and none for frames that produced samples.
10. **Every committed trace is checked.** A test loads every `.json` under both `Traces`
    directories and asserts it decodes, declares an allowed `source`, and (for any
    `deidentified-capture`) names a reviewer. A `README.md` beside the target's `Traces`
    directory states the de-identification rule from A-7 (values, doses and serial numbers
    synthesized or offset; the repository is public), the format, and that a capture needs a
    named reviewer before it lands.
11. **Gates.** All nine frontmatter gates pass. The Dev Agent Record states the reviewable diff
    size and that `Package.resolved` is unchanged.

## Tasks / Subtasks

- [x] Task 1: package, catalog, manifest (AC 1)
  - [x] `Package.swift`: the target and test target (see AC 1). Keep `.swiftLanguageMode(.v6)`.
  - [x] `Sources/DriverAPI/DriverCatalog.swift`: the second entry. Update the "first entry" doc
        paragraph so it stays true with two entries.
  - [x] `Tests/DriverAPITests/DriverCatalogTests.swift`: count 2; the Trace-Replay entry's
        fields; `entries(providing: .glucoseSource)` and `.insulinSource` are
        `["SimulatedDriver", "TraceReplayDriver"]` in catalog order; lookup of
        `com.glycemicgpt.trace-replay`. Keep `everyDriverInTheTreeIsRegistered` as is; it must
        pass unmodified.
  - [x] `Tests/SafetyCoreTests/PackageManifestTests.swift`: exact dependency assertion and the
        enumeration.
- [x] Task 2: format (AC 2): `Sources/Drivers/TraceReplay/TraceFile.swift`
  - [x] Strict keys: in `init(from:)`, open a container keyed by a small `AnyCodingKey`, compare
        `allKeys` with the allowed set, throw on extras, then decode the typed fields. Same for
        `provenance` and each frame.
  - [x] Hex: a `private` decoder that rejects odd length, uppercase and non-hex characters.
  - [x] `static func load(_ data: Data) throws(DriverFailure) -> TraceFile`. A
        `JSONDecoder` with `.iso8601` dates. Any `DecodingError` maps to
        `.decodeFailed(detail: "trace file")`.
- [x] Task 3: the Driver (AC 3, 4, 7, 8): `Sources/Drivers/TraceReplay/TraceReplayDriver.swift`
  - [x] `public actor TraceReplayDriver: Driver`, `public static let identifier`, the
        descriptor, `public static let defaultTraceName = "tandem-status-01"`.
  - [x] `public enum TraceSource: Sendable { case bundled(name: String); case data(Data) }`.
        `.bundled` loads `Bundle.module.url(forResource:withExtension:"json",
        subdirectory:"Traces")`; missing or unreadable is `.decodeFailed(detail: "trace file")`.
  - [x] `public init(validator: SafetyLimitsValidator, trace: TraceSource = .bundled(name:
        TraceReplayDriver.defaultTraceName), log: some TraceReplayLogging = OSTraceReplayLog())`.
  - [x] `activate()`: set active, clear the halt, renew the streams (finish the old pair, make a
        new one), load the trace, replay every frame per AC 3-4. `deactivate()`: clear active,
        finish the streams. Both idempotent; neither needs a scheduler.
  - [x] Internal, for tests: `cursor: Int` (index of the next unconsumed frame) and
        `frameResults: [TraceFrameResult]` where `TraceFrameResult` is
        `.read(TandemReadOutcome)`, `.valueRejected(bound: String)` or
        `.decodeFailed(detail: String)`.
- [x] Task 4: ports and streams: `Sources/Drivers/TraceReplay/TraceReplayCapabilityPorts.swift`
  - [x] Glucose and insulin ports shaped like `SimulatedCapabilityPorts.swift`.
        `doses(since:)` returns `[]` (no history records in v1 traces) or throws the halt.
  - [x] A private per-activation stream holder with `renew()` and `finish()` (lock-guarded,
        `@unchecked Sendable`, same reasoning as the Simulated Driver's `ActivationStreams`,
        smaller because emission only happens inside `activate()`). Buffer:
        `.bufferingNewest(256)`.
- [x] Task 5: logging (AC 9): `Sources/Drivers/TraceReplay/TraceReplayLog.swift`
- [x] Task 6: fixtures and README (AC 5, 6, 10)
  - [x] `Sources/Drivers/TraceReplay/Traces/tandem-status-01.json` (verbatim, Dev Notes)
  - [x] `Tests/TraceReplayDriverTests/Traces/tandem-decode-failure-01.json` (verbatim)
  - [x] `Sources/Drivers/TraceReplay/README.md`
- [x] Task 7: tests in `Tests/TraceReplayDriverTests/`
  - [x] `TraceFileTests.swift`: the bundled trace loads; an unknown top-level key, an unknown
        frame key (`"serialNumber"`), a capture without `reviewedBy`, an odd-length or uppercase
        hex string, version 2, vendor `"medtronic"` and an unknown zone each fail with
        `.decodeFailed(detail: "trace file")`. Every committed trace passes (AC 10).
  - [x] `TraceReplayDriverTests.swift`: descriptor equals catalog entry; golden table (AC 5);
        the streams' sample sequences; decode-failure halt (AC 6); determinism and reactivation
        (AC 7); narrowed limits (AC 8); log calls (AC 9); a trace that fails to load makes
        `activate()` throw.
  - [x] A small `TestDoubles.swift` with the recording log. Validator construction as in the
        Simulated Driver tests (SPI import in the test file only).
- [ ] Task 8: run every gate; fill the Dev Agent Record.

## Dev Notes

### Known pitfalls (read before writing code)

- The worker cannot compile, so write carefully. A `switch` after any statement in a function or getter needs `return switch`. Test functions that `await` must be `async`. In Swift Testing, `#expect` over a key-path closure such as `allSatisfy(\.x)` is treated as throwing, so bind it to a `let` first. Typed-throws closures can't call `NSLock.withLock` and throw a typed error; use `lock()`/`defer unlock()`. In an init, assign every stored property before reading any `self` property.
- AppFeature and the other packages also build for macOS (`swift test` runs on macOS in CI). Wrap iOS-only APIs in `#if os(iOS)`.
- Never write a numeric safety constant inline, and never disguise one. Literals equal to safety constants (for example 18, 20, 21, 55, 58, 61, 70, 180, 250) trip the guard. Hex colour components count too.
- Swift 6 strict concurrency. Tests that check state that settles asynchronously must wait with the existing `eventually` helper, not assert immediately.
- Code comments must not mention stories, epics, AC numbers, agents or cycles. No private UIKit API.
- Diff budget: about 800 reviewable lines.

### Rules of the road

- **AD-3:** the target depends on `DriverAPI`, `SafetyCore` and `TandemWire` only (the
  `Sources/Wire` rule from 1.7a). No `Persistence`, no `DomainCore`, no networking.
- **AD-16:** no `@_spi` import anywhere in `Sources/Drivers/TraceReplay/` (driver_guards fails
  it). The Driver never touches its lifecycle; the platform does.
- **Do not edit** `Sources/Wire/**` (if the decode path is wrong, write NEEDS-HUMAN; do not
  patch it here), `Sources/SafetyCore/**`, `Sources/AppFeature/**`, `Apps/**`, `ci-local.sh`,
  CI files or the guards. The only DriverAPI edit is the catalog entry and its doc paragraph.
- **No `#if` anywhere in this story.** The compile-time kill switch is 1.7c.
- **No scheduler, no clock.** Timestamps come from the frames (glucose) and from `receivedAt`
  (IOB). The Driver never reads the wall clock (AD-14).
- **Scratch files only under `.build/`.**

### Driver-guard traps (this target IS scanned)

The read-only scan reads identifiers and comments under `Sources/Drivers/`. These fail it:
`bolus`, `deliver` (also "delivers", "delivered" as separate words: write "yields" or "emits"),
`suspend`, `resume` (write "restart" or "replay again"), `prime`, `cannula`, `therapy`,
`enact`, `administer`, `infuse`, `inject`, and the pairs `set basal`, `temp basal`,
`write value`, `write characteristic`, `command characteristic`, `control characteristic`.
The consumer-cast rule forbids `as?`, `as!` or `is` against port types outside DriverAPI; use
`case` patterns on `CapabilityPort` in tests, as the Simulated tests do. The fixture JSON is not
scanned (the guards read `.swift` only), but keep the same words out of it anyway.

### Safety-guard traps

Numeric literals under `Sources/` in 17.5–18.5, 19–21, 57–63, 342–378, 475–525, 855–945 and
3420–3780 fail. This target needs only small indices and `256`. Do not write glucose values
in `Sources/` (they live in the JSON and in tests). Tests may use any literal.

### Bundled trace: `Sources/Drivers/TraceReplay/Traces/tandem-status-01.json` (verbatim)

Generated from the cargo layouts with CRC-16/CCITT-FALSE and checked by an independent decoder
when this story was written. Copy it exactly; one frame per line keeps review diffs readable.

```json
{
  "format": "glycemicgpt-trace",
  "version": 1,
  "vendor": "tandem",
  "description": "Synthesized Tandem current-status session: CGM EGV and Control-IQ IOB responses covering the egvStatusId gate, the IOB selector byte and absolute-bound rejection.",
  "pumpTimeZone": "America/Chicago",
  "provenance": {
    "source": "synthesized",
    "method": "Every value invented; no capture was used. Frames built from the documented cargo layouts with CRC-16/CCITT-FALSE.",
    "reviewedBy": null
  },
  "frames": [
    {"channel": "currentStatus", "receivedAt": "2025-01-15T14:00:05Z", "notifications": ["000123010880e80d207b000100561f"], "note": "VALID reading"},
    {"channel": "currentStatus", "receivedAt": "2025-01-15T14:00:07Z", "notifications": ["01026d0211c4090000201c0000b80b0000dc", "00020500000069a7"], "note": "selector 0, Control-IQ off: Mudaliar 2500 mU, Swan-6hr 1500 mU"},
    {"channel": "currentStatus", "receivedAt": "2025-01-15T14:05:05Z", "notifications": ["0003230308ace90d2083000100ec09"], "note": "VALID reading"},
    {"channel": "currentStatus", "receivedAt": "2025-01-15T14:05:07Z", "notifications": ["01046d0411c4090000f41a0000b80b0000dc", "0004050000011fa4"], "note": "selector 1, Control-IQ on: Swan-6hr selected"},
    {"channel": "currentStatus", "receivedAt": "2025-01-15T14:10:05Z", "notifications": ["0005230508d8ea0d20340002001fe8"], "note": "LOW status still carries a value"},
    {"channel": "currentStatus", "receivedAt": "2025-01-15T14:15:05Z", "notifications": ["000623060804ec0d209a0103008a93"], "note": "HIGH status still carries a value"},
    {"channel": "currentStatus", "receivedAt": "2025-01-15T14:20:05Z", "notifications": ["000723070830ed0d208c0000004253"], "note": "INVALID status: in range, discarded"},
    {"channel": "currentStatus", "receivedAt": "2025-01-15T14:25:05Z", "notifications": ["00082308085cee0d2096000400b6fe"], "note": "UNAVAILABLE status: in range, discarded"},
    {"channel": "currentStatus", "receivedAt": "2025-01-15T14:25:07Z", "notifications": ["01096d0911c4090000c8190000b80b0000dc", "000905000002f6a2"], "note": "unknown selector 2: falls back to Mudaliar"},
    {"channel": "currentStatus", "receivedAt": "2025-01-15T14:30:05Z", "notifications": ["000a230a0888ef0d200f000100c86b"], "note": "below the absolute bound: rejected, never clamped"},
    {"channel": "currentStatus", "receivedAt": "2025-01-15T14:35:05Z", "notifications": ["000b230b08b4f00d20620203002286"], "note": "above the absolute bound: rejected, never clamped"},
    {"channel": "currentStatus", "receivedAt": "2025-01-15T14:40:05Z", "notifications": ["000c230c08e0f10d2076000100e43f"], "note": "VALID reading"}
  ]
}
```

### Golden table for that trace (limits = absolute bound, zone America/Chicago)

Pump seconds start at 537782400 (2025-01-15 08:00:00 local CST = 14:00:00Z) and step 300 s per
EGV frame.

| Frame | Cargo (decoded) | Expected result |
|---|---|---|
| 0 | EGV 123, status 1, pump 537782400 | `.read(.glucose)` 123 mg/dL at 2025-01-15T14:00:00Z, trend nil |
| 1 | IOB Mudaliar 2500, Swan 1500, selector 0 | `.read(.insulinOnBoard)` 2.5 U at 14:00:07Z |
| 2 | EGV 131, status 1 | `.read(.glucose)` 131 at 14:05:00Z |
| 3 | IOB, selector 1 | `.read(.insulinOnBoard)` 1.5 U at 14:05:07Z |
| 4 | EGV 52, status 2 (LOW) | `.read(.glucose)` 52 at 14:10:00Z |
| 5 | EGV 410, status 3 (HIGH) | `.read(.glucose)` 410 at 14:15:00Z |
| 6 | EGV 140, status 0 | `.read(.sensorReadingUnusable(egvStatusID: 0))` |
| 7 | EGV 150, status 4 | `.read(.sensorReadingUnusable(egvStatusID: 4))` |
| 8 | IOB, selector 2 | `.read(.insulinOnBoard)` 2.5 U at 14:25:07Z |
| 9 | EGV 15, status 1 | `.valueRejected(bound:)` with the validator's string |
| 10 | EGV 610, status 3 | `.valueRejected(bound:)` with the validator's string |
| 11 | EGV 118, status 1 | `.read(.glucose)` 118 at 14:40:00Z |

Resulting streams: glucose 123, 131, 52, 410, 118; IOB 2.5, 1.5, 2.5. `latestReading()` is the
118 sample. Cursor after replay: 12. Do not hard-code the bound string; take it from
`try? validator.validate(mgdl: 15)` failing, or compare against the string the validator throws
in a direct call, so a wording change in DriverAPI does not break this test.

### Test-only trace: `Tests/TraceReplayDriverTests/Traces/tandem-decode-failure-01.json` (verbatim)

```json
{
  "format": "glycemicgpt-trace",
  "version": 1,
  "vendor": "tandem",
  "description": "Synthesized: a CRC failure in the middle of three EGV responses.",
  "pumpTimeZone": "America/Chicago",
  "provenance": {
    "source": "synthesized",
    "method": "Every value invented; no capture was used. Frames built from the documented cargo layouts with CRC-16/CCITT-FALSE.",
    "reviewedBy": null
  },
  "frames": [
    {"channel": "currentStatus", "receivedAt": "2025-01-15T14:00:05Z", "notifications": ["000123010880e80d20780001008a84"], "note": "VALID reading"},
    {"channel": "currentStatus", "receivedAt": "2025-01-15T14:05:05Z", "notifications": ["0002230208ace90d207d000100be5a"], "note": "CRC corrupted: a decode failure; replay must halt here"},
    {"channel": "currentStatus", "receivedAt": "2025-01-15T14:10:05Z", "notifications": ["0003230308d8ea0d2082000100bb18"], "note": "VALID reading"}
  ]
}
```

Frame 0 is EGV 120 (status 1) at 14:00:00Z. Frame 1 is EGV 125 with its last CRC byte flipped.
Frame 2 is EGV 130. Load it in tests with `Bundle.module.url(forResource:
"tandem-decode-failure-01", withExtension: "json", subdirectory: "Traces")` from the TEST
target's bundle and pass `.data(...)`.

### How AD-22 and SI-8 apply to a trace

A trace is the record log, so the frame index is the cursor. A decode failure is a record that
was not consumed: the cursor stays, nothing after it is read, and the failure is surfaced
rather than skipped. A value rejection is a record that was consumed: the cursor moves on. A
reading the sensor itself disowns (`egvStatusId` 0 or 4+) is also consumed. The halt is not
retried within an activation because re-reading the same bytes gives the same result; the next
activation starts again from frame 0 and halts at the same frame, which is the deterministic
behaviour AC 7 pins.

### Existing code to build on (develop after 1.7a merges)

- `Sources/Drivers/Simulated/SimulatedDriver.swift`: the actor shape, `descriptor`, the
  failure channel (`glucoseFailure` thrown from reads), `ActivationStreams` (private; copy the
  idea, not the type), `deinit` concerns (none here: there is no registration to cancel).
- `Sources/Drivers/Simulated/SimulatedCapabilityPorts.swift`: port structs.
- `Sources/Wire/Tandem/` (1.7a): `TandemPacketAssembler`, `TandemMessage.decode`,
  `TandemChannel`, `TandemReadMapper`, `TandemReadOutcome`.
- `Tests/SimulatedDriverTests/SimulatedDriverValidationTests.swift`: building a validator in a
  test. `SafetyLimitsValidator.adopt(_:)` narrows the limits (SPI, test-only use).
- `Tests/DriverAPITests/DriverCatalogTests.swift` and
  `Tests/SimulatedDriverTests/SimulatedDriverCapabilityTests.swift`: patterns to extend.

### Architecture compliance

- **FR-36 / AD-22:** production decode path only; outcomes per AC 4.
- **SI-2:** nothing is clamped; a rejected value produces no sample.
- **SI-9:** logs carry indices, status ids and bound or detail strings only.
- **§8.3:** `verification: .beta`, permanently. A green replay never raises any device row.
- **AD-17:** no `#if DEBUG`, no configuration branch.

### Out of scope (later work; do not build)

- Kill switch, app composition, DEMO DATA, Drivers-screen Beta row (1.7c).
- A trace picker, paced replay, looping (re-anchoring is in scope; see the PM decision at the end).
- Medtronic traces (Epic 7), history-log traces and dose records (no story yet; see 1.7a).
- Moving the stream holder into a shared module. The duplication with the Simulated Driver is
  deliberate for now; a shared helper would be a DriverAPI public-surface change.

### Project structure notes

- New:
  - `Sources/Drivers/TraceReplay/TraceReplayDriver.swift`
  - `Sources/Drivers/TraceReplay/TraceReplayCapabilityPorts.swift`
  - `Sources/Drivers/TraceReplay/TraceFile.swift`
  - `Sources/Drivers/TraceReplay/TraceReplayLog.swift`
  - `Sources/Drivers/TraceReplay/README.md`
  - `Sources/Drivers/TraceReplay/Traces/tandem-status-01.json`
  - `Tests/TraceReplayDriverTests/TraceFileTests.swift`
  - `Tests/TraceReplayDriverTests/TraceReplayDriverTests.swift`
  - `Tests/TraceReplayDriverTests/TestDoubles.swift`
  - `Tests/TraceReplayDriverTests/Traces/tandem-decode-failure-01.json`
- Modified:
  - `Package.swift`
  - `Sources/DriverAPI/DriverCatalog.swift`
  - `Tests/DriverAPITests/DriverCatalogTests.swift`
  - `Tests/SafetyCoreTests/PackageManifestTests.swift`
- Branch from `develop` after 1.7a merges, for example `feat/trace-replay-driver`.

### References

- [Source: _bmad-output/planning-artifacts/epics.md, Story 1.7]
- [Source: prd.md FR-22 (:534), FR-32 (:654), FR-36 (:714), SI-2 (:169), SI-8 (:175),
  SI-9 (:176), §8.1 and §8.3 Trace-Replay row (:5932), OQ-18 (:6304), A-7 (:6390)]
- [Source: ARCHITECTURE-SPINE.md AD-3, AD-13, AD-14, AD-16, AD-17, AD-19, AD-22]
- [Source: 1-7a-tandem-wire-decoding-for-recorded-frames.md]
- [Source: Sources/Drivers/Simulated/*, Sources/DriverAPI/DriverCatalog.swift]

## Dev Agent Record

### Agent Model Used

Codex (Amelia persona), cycle 1.

### Debug Log References

- `.build/swift-build-final.log`, `.build/swift-test-final.log`: adjusted local SwiftPM commands pass; 490 tests.
- `.build/safety-final.log`, `.build/driver-rerun.log`, `.build/gate-6.log`, `.build/gate-7.log`: guards and their available completed self tests.
- `.build/gate-1.log` through `.build/gate-9.log`: exact frontmatter command attempts. SwiftPM default cache and Xcode simulator restrictions affected gates 1, 2, 8, 9.
- `.build/safety-self-rerun.log`: safety guard self test passes after source fixes (75 cases, 0 unexpected results).

### Completion Notes List

- Added the TraceReplayDriver package target and catalog entry, strict versioned trace parser, production Tandem reassembly and mapping, per-activation streams, typed halt behavior, and health-value-free logging.
- Bundled the exact synthesized traces and added format, golden, fault, determinism, limits, provenance, and stream tests.
- Applied the later PM decisions: one activation-time offset re-anchors timestamps; LOW/HIGH statuses log by kind and emit no numeric sample. Home LOW/HIGH display remains owed to later work.
- Safety follow-up (2026-11-02): replay now anchors the newest frame's `receivedAt` to replay start (`now − max(receivedAt)`), and every glucose, IOB and out-of-range timestamp uses `receivedAt` plus that offset. The pump EGV time is still decoded (a bad one halts) but no longer sets replay time, so pump clock skew or a wrong `pumpTimeZone` cannot misalign glucose against IOB or push readings into the future. Added a 4 MiB file bound and a 4096-frame bound (`TraceFile.maximumFileBytes`, `maximumFrameCount`); stream buffers are sized to the frame bound so no sample is dropped. Traces with backwards receive times are rejected. `deactivate()` clears the last reading and halt state. New tests: no timestamp after start, IOB-first trace, skewed pump zone, backwards receive time, size bounds, teardown clearing.
- Open follow-up for de-identification: the free-text fields (`description`, `provenance.method`, `provenance.reviewedBy`, frame `note`) are not screened for identifying content, and `JSONDecoder` silently accepts duplicate keys (last wins), so a duplicated key could hide a value from review. Still-missing negative tests: incomplete reassembly, an extra completed message in one frame, a frame with no notifications, a missing required key, a non-ISO date, and an accepted reviewed `deidentified-capture`.
- Source and test additions total 765 lines after the safety follow-up (645 before); tracked-file edits add 48 and remove 5 lines, for about 813 added reviewable lines, slightly over the 800-line budget. `Package.resolved` is unchanged.
- The exact nine gates were invoked. Safety guard, both guard self tests, driver guard, and CI-local self test pass. The completed local build and full test suite pass with `--disable-sandbox --disable-automatic-resolution` and a workspace-local compiler cache. The raw SwiftPM commands fail at compiler cache permissions. The Xcode package test scheme is not discoverable by the installed Xcode, and the requested iPhone 17 / iOS 26.5 simulator is unavailable. These environment gates remain unverified here.

### File List

- `Package.swift`
- `Sources/DriverAPI/DriverCatalog.swift`
- `Sources/Drivers/TraceReplay/TraceFile.swift`
- `Sources/Drivers/TraceReplay/TraceReplayDriver.swift`
- `Sources/Drivers/TraceReplay/TraceReplayCapabilityPorts.swift`
- `Sources/Drivers/TraceReplay/TraceReplayLog.swift`
- `Sources/Drivers/TraceReplay/README.md`
- `Sources/Drivers/TraceReplay/Traces/tandem-status-01.json`
- `Tests/DriverAPITests/DriverCatalogTests.swift`
- `Tests/SafetyCoreTests/PackageManifestTests.swift`
- `Tests/TraceReplayDriverTests/TestDoubles.swift`
- `Tests/TraceReplayDriverTests/TraceFileTests.swift`
- `Tests/TraceReplayDriverTests/TraceReplayDriverTests.swift`
- `Tests/TraceReplayDriverTests/Traces/tandem-decode-failure-01.json`

### PM decisions before dispatch (2026-11-02)
- **Depends on PR #28 (TandemWire), merged before dispatch.** Use `TandemReadMapper.map(_:receivedAt:pumpTimeZone:)`. The time zone is passed on every call. Out-of-range statuses arrive as `.outOfRange(.below/.above)` and never as a number.
- **Replay timestamps (revised 2026-11-02; replaces the earlier rule that mapped the first frame's pump time to replay start).** Replay is immediate, so anchoring the first frame put every later frame in the future. The Trace-Replay Driver re-anchors the trace so the NEWEST frame's time maps to the moment replay starts: one fixed offset per activation, `now − max(frame time)`, applied to every frame. Intervals stay exactly as recorded and nothing is emitted later than replay start. The time basis is the phone receive time (`receivedAt`) for every frame, glucose and IOB alike, so a skewed pump clock or wrong pump time zone cannot misalign them. This is a demo and validation Driver, and everything it emits carries the DEMO DATA label, so the shift is honest. Document the shift in the Driver's doc comment and in the trace format note, and test it. Never re-anchor per frame.
- **Out-of-range frames during replay.** Since no Home LOW/HIGH display exists yet, the Driver must not emit a numeric sample for them. Log the frame by kind only and skip it. Record that Home LOW/HIGH display is still owed.
- PR #28 (TandemWire) merged 2026-11-02. Dispatch now.
- **Known pitfalls** for the worker, which can't compile: a `switch` after any statement needs `return switch`; tests that await must be `async`; bind any `#expect` over a key-path closure to a `let` first; typed-throws closures need `lock()`/`defer unlock()` rather than `withLock`; in an `init`, assign every stored property before reading `self`; iOS-only APIs go under `#if os(iOS)`; tests whose state settles asynchronously must wait with `eventually`; no literal may equal a safety constant (including hex colour parts).
- budget: CONTINUATION_REQUIRED sha256:6e90c2cc80c9ec68fef7e74a4877497afde3c08866aa4143dbf0d38934175fa3 cycle 1 2026-11-02T07:40:29Z
