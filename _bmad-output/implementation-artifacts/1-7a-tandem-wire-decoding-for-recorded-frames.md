---
# linear: EMPTY = local-only epic — the PM must NOT create or sync anything in Linear.
linear:
stamp: _bmad-output/implementation-artifacts/1-7a-tandem-wire-decoding-for-recorded-frames.md.stamp.json
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

# Story 1.7a: Tandem wire decoding for recorded frames

Status: done

<!-- Planning note (for the maintainer): epics.md Story 1.7 is split three ways because the whole of
it is about 1,800 reviewable lines, over the 800-line budget. The split follows the layers:
1.7a (this file) the Tandem current-status decode path, about 700 lines, half tests;
1.7b the Trace-Replay Driver target, trace format and de-identified fixtures, about 800 lines;
1.7c the compile-time kill switch, app composition and DEMO DATA label, about 250 lines.
1.7b stacks on 1.7a, 1.7c on 1.7b.

Why 1.7 has to build parsers at all: "the same parsing path a live Driver uses" (FR-36) assumes
a live Tandem Driver exists. It does not. Stories 1.8-1.11 cover scanning, pairing and
reconnection, and no Epic 1 story ports Tandem's read parsers. So this story writes the
current-status read path once, and the live Tandem Driver (1.8 onward) must call it rather than
write a second one.

PRECONDITION, maintainer or architect, before dispatch. AD-3 says a Driver may depend ONLY on
DriverAPI and SafetyCore, and the spine draws TraceReplay -> DriverAPI only. A parser two
Drivers share therefore cannot live inside either Driver target. This story puts it in a new
library target, `TandemWire` (`Sources/Wire/Tandem/`), which itself depends only on DriverAPI
and SafetyCore. A Driver's transitive closure is still {DriverAPI, SafetyCore}, which keeps
what AD-3 protects (no Driver acquires storage or network). The literal sentence of AD-3 still
needs an amendment: "a Driver may depend on DriverAPI, SafetyCore, and Sources/Wire targets
whose own dependencies are only those two". The story enforces that rule in the manifest tests.
If the answer is no, the alternative is a transport seam in DriverAPI, which is a bigger change
and needs re-planning.

PROTECTED PATH: `TandemReadMapper` turns device bytes into platform samples, so it is an
ingestion mapper. The maintainer merges; the PM does not. Recommended review on the strongest
model available, with focus on the AD-22 classification table and the egvStatusId and IOB
selector gates.

Route: NOT chosen here; the PM routes via /v1/route. No dosing logic, no alert floor, no
safety_validation, no CI workflow, no dependency or lockfile change. -->

## Story

As a maintainer,
I want Tandem's current-status frames (packet reassembly, CRC, the CGM EGV and Control-IQ IOB
responses, pump time) decoded by one shared module,
so that the Trace-Replay Driver and the live Tandem Driver parse the same bytes through the same
code, and a parser change shows up in both.

## Acceptance Criteria

From epics.md Story 1.7 (FR-36, AD-22), FR-32's device gates (PD-41), FR-206's parser rules, and
the Android parser this ports (`android-unofficial/plugins/shipped/tandem/...`, copied into Dev
Notes).

1. **A shared wire target that keeps AD-3's closure (AD-3).** A new library target `TandemWire`
   at `Sources/Wire/Tandem/` with test target `TandemWireTests`. Its dependencies are exactly
   `DriverAPI` and `SafetyCore`. `PackageManifestTests` asserts that exact list, adds `Wire` to
   the expected `Sources/` directory list, adds both targets to the enumeration test, and adds a
   rule read from the manifest: every target whose path starts with `Sources/Wire/` depends on
   nothing but `DriverAPI` and `SafetyCore`. `TandemWire` is a library product, not a Driver: it
   has no catalog entry, no `Driver` conformance, no actor, no stream and no logging.
2. **The read-only scan covers the new code (AD-12, SI-1).** `scripts/guards/driver_guards.sh`
   adds `Sources/Wire` to `SCAN_DIRS`, so the delivery-verb and write-characteristic scan runs
   over `TandemWire`. Its `--self-test` gains one case: a denied word in a file under
   `Sources/Wire/` fails the guard. Nothing else in the guard changes.
3. **Packet reassembly, Android parity.** `TandemPacketAssembler` (value type, `mutating`) takes
   one notification (`[UInt8]`). Byte 0's low nibble is packets remaining, byte 1 the transaction
   id, bytes 2+ the payload fragment. A notification shorter than 2 bytes is ignored. A
   transaction id different from the one in progress discards the partial message and starts
   again with the new one. When packets remaining is 0, `feed` returns the reassembled message
   and resets; otherwise it returns `nil`. Android's `PacketAssemblerTest` vectors pass (Dev
   Notes).
4. **Message framing with CRC (FR-206).** `TandemMessage.decode(_ raw: [UInt8], channel:)`
   returns `TandemMessage?` with `channel`, `opcode`, `transactionID` and `cargo`. Layout: opcode,
   transaction id, cargo length, cargo, then a 2-byte CRC-16/CCITT-FALSE (poly 0x1021, init
   0xFFFF, no reflection, no final XOR) over everything before it, low byte first. It returns
   `nil` for a message under 5 bytes, a cargo length that runs past the end, or a CRC mismatch.
   The CRC's standard check value holds: `"123456789"` → `0x29B1`. Little-endian throughout. No
   path calls `precondition`, `fatalError`, `!` on an optional, or traps on an out-of-range index.
5. **CGM EGV response, opcode 35 on the current-status channel.** `TandemEGVResponse.parse(_
   cargo:)` returns `nil` for cargo under 8 bytes, otherwise: bytes 0-3 pump seconds (UInt32
   LE), bytes 4-5 glucose mg/dL (UInt16 LE), byte 6 `egvStatusId`, byte 7 trend rate (Int8, not
   an arrow). The Android vector `c87c131c7b000100` gives pump seconds 471039176, 123 mg/dL,
   status 1, trend rate 0. The parser applies no gate and no bound: it reports what the bytes
   say.
6. **Control-IQ IOB response, opcode 109 (FR-32, PD-41).** `TandemIOBResponse.parse(_ cargo:)`
   returns `nil` for cargo under 17 bytes, otherwise Mudaliar IOB (bytes 0-3), time remaining
   (4-7), Mudaliar total (8-11), Swan-6hr IOB (12-15), all UInt32 LE milliunits/seconds, and the
   selector at byte 16. `selectedMilliunits` is Swan-6hr when the selector is 1, Mudaliar when it
   is 0, and **Mudaliar for every other value**. Pinned against a cargo whose two IOB fields
   differ, for selector 0, 1 and 2, plus Android's two pumpX2 vectors (192 mU and 154 mU).
7. **Pump time, in a stated zone (FR-206, AD-14).** `TandemPumpTime.date(pumpSeconds:in:)`
   adds `SafetyConstants.tandemEpochOffset` (never a literal), reads the result as a local
   wall-clock date-time, and resolves it in the given `TimeZone` with a Gregorian calendar.
   Pinned results (all verified in Foundation; table in Dev Notes): UTC, America/Chicago in
   winter and summer, Australia/Sydney in both seasons, a spring-forward gap time (moves forward
   by the gap, as Android's `atZone` does) and a fall-back overlap time (takes the earlier
   offset, as Android does). It returns `nil`, never traps, if the calendar cannot build a date.
8. **The read mapper, and the AD-22 classification (SI-2, SI-8, AD-13, AD-22).**
   `TandemReadMapper(validator:)` maps one `TandemMessage`, plus the instant it was received and
   the pump's time zone at that moment (supplied per call, amended 2026-11-02), to a `TandemReadOutcome` or a typed `DriverFailure`. The order is fixed: framing,
   then opcode, then the device's own validity gate, then the Safety Limits in force, then the
   sample. Exactly this table:

   | Input | Result | Consumed? |
   |---|---|---|
   | current-status opcode 35, cargo too short | throws `.decodeFailed(detail: "CurrentEGVGuiDataResponse")` | no |
   | current-status opcode 109, cargo too short | throws `.decodeFailed(detail: "ControlIQIOBResponse")` | no |
   | EGV with `egvStatusId` 0, or 4 and above | `.sensorReadingUnusable(egvStatusID:)` | yes |
   | EGV, status 2 (LOW) or 3 (HIGH), any value | `.outOfRange(.below / .above, recordedAt:)`, never a numeric sample (amended 2026-11-02) | yes |
   | EGV, status 1-3, pump time unresolvable | throws `.decodeFailed(detail: "pump timestamp")` | no |
   | EGV, status 1, value the validator refuses | throws the validator's `.valueRejected(bound:)` unchanged | yes |
   | EGV, status 1, value admitted | `.glucose(GlucoseSample)`: `recordedAt` from pump time, `trend: nil` | yes |
   | IOB, parsed | `.insulinOnBoard(InsulinOnBoardSample)`: units = selected milliunits / 1000, `calculatedAt` = receive instant | yes |
   | any other opcode, or any channel other than current status | `.notRead(channel:opcode:)` | yes |

   A message whose bytes failed framing never reaches the mapper; the caller reports it as
   `.decodeFailed(detail: "frame")`. `detail` names the response or the field, never bytes or
   values (SI-9). Status is checked before the value, so an in-range glucose with status 0 or 4
   is unusable, not admitted (PD-41). Validation calls `validator.validate(mgdl:)` on every
   message, so narrowing the limits between two messages changes the result of the second with
   no new mapper (FR-32): a test re-maps the same frame after `adopt` of narrower limits and gets
   `.valueRejected`. The mapper never clamps and never substitutes a default.
9. **Gates.** All nine frontmatter gates pass. The Dev Agent Record states the reviewable diff
   size and that `Package.resolved` is unchanged.

## Tasks / Subtasks

- [x] Task 1: package and guard wiring (AC 1, 2)
  - [x] `Package.swift`: add `.library(name: "TandemWire", targets: ["TandemWire"])`; target
        `TandemWire` (`path: "Sources/Wire/Tandem"`, dependencies `["DriverAPI", "SafetyCore"]`,
        `.swiftLanguageMode(.v6)`); test target `TandemWireTests` (dependencies
        `["TandemWire", "DriverAPI", "SafetyCore"]`). Add a short manifest comment that says why
        the target exists outside `Sources/Drivers/` (shared by two Drivers; AD-3 closure).
  - [x] `Tests/SafetyCoreTests/PackageManifestTests.swift`: the four changes in AC 1.
  - [x] `scripts/guards/driver_guards.sh`: `SCAN_DIRS` plus one self-test case.
- [x] Task 2: framing (AC 3, 4)
  - [x] `Sources/Wire/Tandem/TandemPacketAssembler.swift`
  - [x] `Sources/Wire/Tandem/TandemMessage.swift`: `TandemChannel` (see Dev Notes), `TandemMessage`,
        the CRC as a `private` or `internal` function, `decode`.
- [x] Task 3: response parsers (AC 5, 6)
  - [x] `Sources/Wire/Tandem/TandemCurrentStatus.swift`: the two opcodes as named `static let`s,
        `TandemEGVResponse`, `TandemIOBResponse`. Plain `Equatable, Sendable` structs.
- [x] Task 4: pump time (AC 7): `Sources/Wire/Tandem/TandemPumpTime.swift`
- [x] Task 5: mapper (AC 8): `Sources/Wire/Tandem/TandemReadMapper.swift` with
      `TandemReadOutcome` (`Equatable, Sendable`).
- [x] Task 6: tests, in `Tests/TandemWireTests/`:
  - [x] `TandemFramingTests.swift`: CRC check value; Android assembler vectors; a two-packet
        IOB message reassembles; short, overrun and bad-CRC messages give `nil`; a mismatched
        transaction id restarts.
  - [x] `TandemCurrentStatusTests.swift`: the EGV vector; short cargo `nil`; IOB selector 0, 1,
        2 against differing fields; the two pumpX2 IOB vectors; short IOB `nil`.
  - [x] `TandemPumpTimeTests.swift`: every row of the pump-time table.
  - [x] `TandemReadMapperTests.swift`: every row of the AC 8 table; all five `egvStatusId`
        cases 0-4 plus 255; status 2 and 3 map to `.outOfRange` at 40, 400, in-range, 0 and 65535;
        the same frame in two time zones; narrowing between two calls; `bound` is
        the validator's own string; no `detail` contains a digit run from the cargo.
- [ ] Task 7: run every gate; fill the Dev Agent Record.

## Dev Notes

### Known pitfalls (read before writing code)

- The worker cannot compile, so write carefully. A `switch` after any statement in a function or getter needs `return switch`. Test functions that `await` must be `async`. In Swift Testing, `#expect` over a key-path closure such as `allSatisfy(\.x)` is treated as throwing, so bind it to a `let` first. Typed-throws closures can't call `NSLock.withLock` and throw a typed error; use `lock()`/`defer unlock()`. In an init, assign every stored property before reading any `self` property.
- AppFeature and the other packages also build for macOS (`swift test` runs on macOS in CI). Wrap iOS-only APIs in `#if os(iOS)`.
- Never write a numeric safety constant inline, and never disguise one. Literals equal to safety constants (for example 18, 20, 21, 55, 58, 61, 70, 180, 250) trip the guard. Hex colour components count too.
- Swift 6 strict concurrency. Tests that check state that settles asynchronously must wait with the existing `eventually` helper, not assert immediately.
- Code comments must not mention stories, epics, AC numbers, agents or cycles. No private UIKit API.
- Diff budget: about 800 reviewable lines.

### Rules of the road

- **Swift 6 language mode, typed throws.** Every public type is a `Sendable` value type. The
  mapper holds a `SafetyLimitsValidator` (a `final class`, `Sendable`) and a `TimeZone`; it
  is a `struct`.
- **Do not edit** `Sources/DriverAPI/**`, `Sources/SafetyCore/**`, `Sources/Drivers/**`,
  `Sources/AppFeature/**`, CI files or `safety_guards.sh`. If a DriverAPI shape seems
  necessary, write a NEEDS-HUMAN line in the Dev Agent Record instead.
- **Nothing in TandemWire writes to a pump.** It decodes notifications. There is no encoder
  for outbound messages here; the live Driver adds request encoding later, behind the same
  scan.
- **No logging in TandemWire.** It returns outcomes and typed failures; the caller logs. That
  keeps SI-9 a property of one place per Driver.
- **Scratch files only under `.build/` in your worktree.**

### Safety-guard traps for this code

`safety_guards.sh` fails on numeric literals under `Sources/` in these bands: 17.5–18.5,
19–21, 57–63, 342–378, 475–525, 855–945, 3420–3780, plus any literal equal to a canonical
constant (the Tandem epoch offset `1199145600` in any spelling is one of them: always use
`SafetyConstants.tandemEpochOffset`).

The values this code needs are clear of the bands: 0, 1, 2, 3, 4, 5, 6, 7, 8, 12, 16, 17,
35, 109, 1000, 0x0F, 0xFF, 0x1021, 0x8000, 0xFFFF. Do not introduce a named constant for
the Tandem chunk size (18): reassembly does not need it. If a byte offset in the 19–21 band
ever seems necessary, stop and re-read the cargo layout.

### Driver-guard traps for this code

`Sources/Wire/` joins the read-only scan. The scan splits identifiers on camel humps and
reads comments too. These words fail it anywhere in this target, including doc comments:
`bolus`, `deliver` (and `delivers`, `delivered` as a separate word), `suspend`, `resume`,
`prime`, `cannula`, `therapy`, `enact`, `administer`, `infuse`, `inject`, and the pairs
`set basal`, `temp basal`, `write value`, `write characteristic`, `command characteristic`,
`control characteristic`. In practice:
- Say "the Control-IQ IOB response", not "the control characteristic".
- The channel enum may have a case named `control`; never name anything
  `controlCharacteristic`.
- Do not port Android's bolus or basal parsers or their comments here. They are out of scope.

### TandemChannel

The Tandem pump disambiguates opcodes by notification channel (opcode 35 is the EGV response
on the current-status channel and a pairing message on the authorization channel). So a
message carries its channel:

```swift
public enum TandemChannel: String, CaseIterable, Sendable {
    case currentStatus, qualifyingEvents, historyLog, authorization, control, controlStream
}
```

The raw values are the names trace files use (1.7b). Characteristic UUIDs are not needed
until Core Bluetooth arrives (1.8) and are not added here.

### Android reference (copied; the Android repo may not be readable from your sandbox)

`android-unofficial/plugins/shipped/tandem/src/main/java/com/glycemicgpt/mobile/ble/protocol/`:
- `PacketAssembler.kt`: per AC 3. `feed` returns `Boolean`; iOS returns the message instead.
  Android keeps one assembler per transaction id for status responses
  (`BleConnectionManager.kt:941-958`) and then calls `Packetize.parseHeader(raw)`.
- `Packetize.kt` `parseHeader`: `raw.size < 5` → null; `raw.size < 3 + cargoLen + 2` → null;
  CRC over bytes `0 ..< 3 + cargoLen`, compared little-endian; mismatch → null.
- `Crc16.kt`: polynomial `0x1021`, initial `0xFFFF`, MSB-first, mask to 16 bits.
- `TandemProtocol.kt`: `OPCODE_CGM_EGV_RESP = 35`, `OPCODE_CONTROL_IQ_IOB_RESP = 109`.

`.../ble/messages/StatusResponseParser.kt`:
- `parseIoBResponse` (lines 75-100): layout per AC 6; `if (iobType == 1) swan6hrIOB else
  mudaliarIOB`; Android stamps `Instant.now()`. iOS uses the receive instant the caller passes,
  which is the same thing for a live Driver and the recorded receipt time for a trace.
- `parseCgmEgvResponse` (lines 186-215): status gate `if (egvStatus !in 1..3) return null`,
  then range check against Safety Limits, then `pumpTimeToInstant`. Trend comes from a
  different response (HomeScreenMirror, opcode 57), so Android reports UNKNOWN. iOS reports
  `trend: nil`, because `GlucoseTrend.unknown` means the sensor reported a direction outside
  the vocabulary, which is not what happened.
- `pumpTimeToInstant` (lines 49-55): `LocalDateTime.ofEpochSecond(pumpSec + offset, 0, UTC)
  .atZone(ZoneId.systemDefault())`. The pump counts local wall-clock seconds.

Android returns `null` for a status-0 reading AND for a malformed cargo. iOS keeps them apart,
because AD-22 requires it: malformed is a decode failure (not consumed), status 0 is a reading
the sensor itself disowns (consumed, no value), out-of-limits is a value rejection (consumed,
logged by the caller with the bound).

Test vectors, from `.../src/test/java/com/glycemicgpt/mobile/ble/`:
- `protocol/PacketAssemblerTest.kt`: `[00 01 AA BB]` completes as `[AA BB]`;
  `[01 05 01 02]` then `[00 05 03 04]` completes as `[01 02 03 04]`; `[01 01 AA]` then
  `[00 02 BB]` completes as `[BB]` (transaction id changed); `[00]` alone is ignored.
- `messages/StatusResponseParserTest.kt`: IOB `c00000007c380000f1000000a100000000` → fields
  (192, 14460, 241, 161, selector 0) → 192 mU; IOB `b80000008c370000f10000009a00000001` →
  (184, 14220, 241, 154, selector 1) → 154 mU; EGV `c87c131c7b000100` → (471039176, 123, 1,
  0). A cargo whose fields differ, for the selector table: Mudaliar 2500, remaining 7200,
  total 3000, Swan 1500, selector 0 → 2500 mU; selector 1 → 1500 mU; selector 2 → 2500 mU.

Complete framed messages you can use in mapper tests (CRC already correct; these come from the
1.7b fixture, transaction ids 1 and 2):
- EGV, 123 mg/dL, status 1, pump seconds 537782400:
  notification `000123010880e80d207b000100561f` → message `23010880e80d207b000100561f`.
- IOB, Mudaliar 2500 / Swan 1500, selector 0, two notifications:
  `01026d0211c4090000201c0000b80b0000dc` and `00020500000069a7`.

### Pump-time table (verified with Foundation on this machine)

| Pump seconds | Wall clock | Zone | Expected instant |
|---|---|---|---|
| 506160000 | 2024-01-15 08:00:00 | UTC | 2024-01-15T08:00:00Z |
| 506160000 | 2024-01-15 08:00:00 | America/Chicago | 2024-01-15T14:00:00Z |
| 506160000 | 2024-01-15 08:00:00 | Australia/Sydney | 2024-01-14T21:00:00Z |
| 520678800 | 2024-07-01 09:00:00 | America/Chicago | 2024-07-01T14:00:00Z |
| 520678800 | 2024-07-01 09:00:00 | Australia/Sydney | 2024-06-30T23:00:00Z |
| 510892200 | 2024-03-10 02:30:00 (does not exist) | America/Chicago | 2024-03-10T08:30:00Z |
| 531451800 | 2024-11-03 01:30:00 (occurs twice) | America/Chicago | 2024-11-03T06:30:00Z |
| 471039176 | 2022-12-04 20:12:56 | UTC | 2022-12-04T20:12:56Z |

Implementation that produces exactly these: build `Date(timeIntervalSince1970:
SafetyConstants.tandemEpochOffset + TimeInterval(seconds))`, read year through second from a
Gregorian calendar whose zone is UTC, then `date(from:)` on a Gregorian calendar whose zone is
the given one. Build both calendars inside the function; `Calendar` is a value type, so this
is safe under Swift 6. Tests pass `TimeZone(identifier:)!` values and compare with
`ISO8601DateFormatter` output or `timeIntervalSince1970`.

### Architecture compliance

- **AD-3:** see the precondition in the planning note. The manifest rule in AC 1 is what keeps
  it true over time.
- **AD-5, SI-2:** a `GlucoseSample` only exists if `validator.validate(mgdl:)` returned a
  `Glucose`. Never construct `Glucose` directly in this target.
- **AD-13, AD-22:** every failure is a `DriverFailure`; the table in AC 8 is the contract.
- **AD-14:** the mapper never reads the clock. The receive instant is a parameter.
- **SI-9:** `detail` and `bound` strings carry names, never values or bytes.
- **PD-41 / FR-32:** both Tandem device gates are here, pinned by test.

### Out of scope (later work; do not build)

- The Trace-Replay Driver, trace format, fixtures, catalog entry (1.7b); kill switch and app
  wiring (1.7c).
- Every other Tandem response: basal status, insulin status, battery, last-dose status, home
  screen mirror (trend arrows), pump settings and version. They arrive with the Tandem Driver.
- **History-log parsing** (CGM, dose and basal history records, the history cursor, AD-19
  durability). FR-36 mentions boluses and basal records; no current story owns porting
  Android's history parsers. The PM needs to give that work a home before the Tandem Driver
  reads history.
- Outbound request encoding, Core Bluetooth, characteristic UUIDs, pairing (1.8-1.11).
- A reassembly idle timeout. FR-206 mentions "the documented idle timeout"; Android documents
  none. Record that in the Dev Agent Record as a gap for the Tandem Driver story.

### Testing standards

- Swift Testing, as every existing target uses. No sleeps, no clock reads.
- Tests build a validator the way the platform does: `@_spi(DriverPlatform) import DriverAPI`
  in the TEST file only, then `SafetyLimitsValidator(limits: try SafetyLimits(glucoseLower:
  glucoseUpper:))`. See `Tests/SimulatedDriverTests/SimulatedDriverValidationTests.swift`.
  `TandemWire` itself never imports the SPI. The guard's SPI rule only scans
  `Sources/Drivers/`, so for this target the rule is held by review.
- Literals equal to safety constants are fine in `Tests/` (the guard scans `Sources/` only),
  but prefer `SafetyConstants.glucoseValidRange` bounds in assertions about the absolute bound.
- Hex helpers for tests go in a `private` function in the test target.

### Project structure notes

- New:
  - `Sources/Wire/Tandem/TandemPacketAssembler.swift`
  - `Sources/Wire/Tandem/TandemMessage.swift`
  - `Sources/Wire/Tandem/TandemCurrentStatus.swift`
  - `Sources/Wire/Tandem/TandemPumpTime.swift`
  - `Sources/Wire/Tandem/TandemReadMapper.swift`
  - `Tests/TandemWireTests/TandemFramingTests.swift`
  - `Tests/TandemWireTests/TandemCurrentStatusTests.swift`
  - `Tests/TandemWireTests/TandemPumpTimeTests.swift`
  - `Tests/TandemWireTests/TandemReadMapperTests.swift`
- Modified:
  - `Package.swift`
  - `Tests/SafetyCoreTests/PackageManifestTests.swift`
  - `scripts/guards/driver_guards.sh` (`SCAN_DIRS` and one self-test case)
- Estimate: ~330 production lines, ~370 test lines, ~30 manifest/guard lines.
- Branch from `develop`, for example `feat/tandem-wire`.

### References

- [Source: _bmad-output/planning-artifacts/epics.md, Story 1.7]
- [Source: prd.md FR-32 (:654), FR-36 (:714), FR-206 (:4126), SI-2 (:169), SI-8 (:175),
  SI-9 (:176), §7 PD-41 (:5825), §9 Tier 2 (:5957), A-7 (:6390)]
- [Source: ARCHITECTURE-SPINE.md AD-3, AD-5, AD-13, AD-14, AD-22, Structural Seed]
- [Source: Sources/DriverAPI/DriverFailure.swift (decode vs value), SafetyLimitsValidator.swift,
  Models/GlucoseSample.swift, Models/InsulinModels.swift]
- [Source: android-unofficial files cited above]

## Dev Agent Record

### Agent Model Used

- Codex (openai/strong, xhigh per the story stamp).

### Debug Log References

- `swift build` and `swift test`: both stopped at the sandbox-denied default Clang module cache before compiling the package. With a writable module cache and SwiftPM sandbox disabled, package resolution then stopped because `github.com` could not be resolved, so the pinned GRDB dependency was unavailable.
- `bash scripts/guards/safety_guards.sh`: passed. `--self-test`: passed, 75 cases with 0 unexpected results.
- `bash scripts/guards/driver_guards.sh`: passed. `--self-test`: passed, 69 cases with 0 unexpected results, including the new `Sources/Wire/` denial case.
- `bash scripts/ci-local.sh --self-test`: passed.
- `xcodebuild test -scheme GlycemicGPT-Package -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath .build/xcode-dd`: stopped before testing; CoreSimulatorService was unavailable and Xcode did not recognize the package at the working directory.
- `xcodebuild build -project Apps/GlycemicGPT/GlycemicGPT.xcodeproj -scheme GlycemicGPT -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath .build/xcode-dd CODE_SIGNING_ALLOWED=NO`: stopped before compiling; CoreSimulatorService and the default Clang/SwiftPM caches were unavailable.
- An isolated package under `.build/tandem-smoke/`, containing the actual SafetyCore, DriverAPI, TandemWire, and TandemWireTests sources but no GRDB dependency, passed all 14 Tandem tests. A copy of `PackageManifestTests.swift` pointing at this checkout passed all 15 manifest tests.

### Completion Notes List

- Implemented the shared read-only `TandemWire` target, packet reassembly, checked framing and CRC, EGV and IOB payload decoding, pump-local time conversion, and typed read outcomes.
- The mapper checks sensor status before validation and asks the shared validator on each accepted EGV, preserving the validator's rejection. Its time conversion failure branch was exercised with an internal resolver seam.
- The implementation diff is approximately 491 added lines and 3 removed lines, excluding this story and checkpoint artifacts. `Package.resolved` is unchanged.
- No reassembly idle timeout is specified by the Android parser. The live Tandem Driver needs an explicit timeout contract when it is built.
- The later caller of `TandemMessage.decode` must classify a nil frame as `.decodeFailed(detail: "frame")`; no caller exists in this change.
- The four environment-blocked gates remain unverified, so this story is not complete.

### Review fixes (2026-11-02)

- **EGV status 2 and 3 fail safe.** `egvStatusId` 2 (LOW) and 3 (HIGH) no longer produce a numeric `GlucoseSample`. They map to the new outcome `.outOfRange(TandemGlucoseRangeSide, recordedAt:)`, distinct from a valid sample, a decode failure and a value rejection. The value bytes are not validated or carried for these statuses. `GlucoseSample` and SafetyCore types are unchanged. AC 8's table and the mapper's doc comment were updated to match.
- **Deliberate difference from Android.** Android's `parseCgmEgvResponse` accepts statuses 1-3 and shows the number (`StatusResponseParser.kt:200-202`). A LOW reading means "below the sensor's range"; shown as "40 mg/dL" it tells the person the edge of the range, not how bad the low is. iOS refuses to turn a range-edge marker into a glucose value.
- **What statuses 2 and 3 mean, per the Android repo.** `StatusResponseParser.kt:188`: `egvStatusId (0=INVALID, 1=VALID, 2=LOW, 3=HIGH, 4=UNAVAILABLE)`; `:200`: "Accept VALID (1), LOW (2), and HIGH (3) readings -- all carry a glucose value." `StatusResponseParserTest.kt:221` and `:234` use 55 and 350 mg/dL for LOW and HIGH, labelled "still has a valid glucose value"; those values are hand-built, not pumpX2 vectors (the only pumpX2 EGV vector, `:210-211`, is status 1). pumpX2 sources are not vendored in the Android repo, so its enum could not be checked. Nothing in the repo shows what value the pump puts in the glucose bytes for LOW or HIGH. The fail-safe classification stands either way.
- **Pump time zone per call.** `map(_:receivedAt:pumpTimeZone:)` takes the zone on every call; the mapper no longer stores one. A test maps the same frame in Chicago, Sydney, then Chicago again.
- **REQUIRED follow-ups before any live Tandem data reaches a user:**
  - (a) The hero must show "LOW" or "HIGH" for `.outOfRange` outcomes. Owner: the live Tandem Driver work.
  - (b) The Alert Floor must treat a below-range outcome as an urgent low. Owner: Epic 2.
- **Known limits, no change here:**
  - *Future timestamps.* The mapper does not bound `recordedAt` against now. That bound lives downstream in `SafetyConstants.alertFloorMaxFutureSkew`, and a second copy here would be a competing authority.
  - *IOB upper bound.* `InsulinOnBoardSample` rejects only negative or non-finite units (`InsulinModels.swift:33`); there is no IOB ceiling, and the wire field allows up to about 4.29 million units. A ceiling needs a source-backed value before it can become a `SafetyConstants` entry; inventing one would be worse than none. Follow-up for the live Driver or Epic 2.
  - *Assembler ordering.* The assembler appends fragments in arrival order and does not check sequence. This matches Android, BLE notifications on one characteristic arrive in order, and a misordered message fails the CRC and is dropped as a decode failure. Revisit with the live Driver's idle-timeout contract.

### File List

- `Package.swift`
- `Tests/SafetyCoreTests/PackageManifestTests.swift`
- `scripts/guards/driver_guards.sh`
- `Sources/Wire/Tandem/TandemPacketAssembler.swift`
- `Sources/Wire/Tandem/TandemMessage.swift`
- `Sources/Wire/Tandem/TandemCurrentStatus.swift`
- `Sources/Wire/Tandem/TandemPumpTime.swift`
- `Sources/Wire/Tandem/TandemReadMapper.swift`
- `Tests/TandemWireTests/TandemFramingTests.swift`
- `Tests/TandemWireTests/TandemCurrentStatusTests.swift`
- `Tests/TandemWireTests/TandemPumpTimeTests.swift`
- `Tests/TandemWireTests/TandemReadMapperTests.swift`

### PM decision on the precondition (2026-11-02)
- **AD-3 amendment ACCEPTED.** Drivers may depend on vendor wire targets under `Sources/Wire/` whose own dependencies are only DriverAPI and SafetyCore. A Driver's transitive closure stays `{DriverAPI, SafetyCore}`. The spine change is PR #26. Implement exactly the manifest rule this story describes, and extend the AD-3 manifest test so it enforces the rule.
- **Protected path:** `TandemReadMapper` is an ingestion mapper. It gets a strong-model safety review that focuses on the AD-22 classification table and the EGV status and IOB mapping. Never clamp and never substitute a default; a rejected or undecodable value is dropped and logged by kind only.
- **History-log parsers:** these have no owner yet. They are recorded as a tracked follow-up, outside this story's scope.
- budget: CONTINUATION_REQUIRED sha256:0ea20b58524b0ee941b6157446d442b6787f15f24dd4146b666d6ac04abec6dd cycle 1 2026-11-02T04:14:29Z
