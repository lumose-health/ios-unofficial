---
# linear: EMPTY = local-only epic — the PM must NOT create or sync anything in Linear.
linear:
stamp: _bmad-output/implementation-artifacts/1-8-discover-a-tandem-pump-by-scanning.md.stamp.json
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

# Story 1.8: Discover a Tandem pump by scanning

Status: review

<!-- Planning note (for the maintainer):

WHAT THIS IS. The first live-radio Driver code: a new `TandemDriver` target at
`Sources/Drivers/Tandem` (depends on DriverAPI, SafetyCore, TandemWire; AD-3 as amended
2026-11-02), a Core Bluetooth central behind a protocol, and a scan engine that turns sightings
into a live, aged, ordered list of pumps identified by name and model. Everything is unit-tested
against a fake central. Estimate ~700 reviewable lines over ~12 files, about half tests.

WHAT THIS IS NOT. No pairing, no connection, no EC-JPAKE, no swift-crypto dependency (1.9). No
restoration identifier and no background scanning (1.10, AD-11). No scan screen: see "Where the
scan screen goes" in Dev Notes. The Driver is registered in the Driver Catalog (the guard
requires it) but is NOT composed into the app, so the Drivers screen, which lists the registry's
Drivers, does not show it and no user can select it yet.

VERIFICATION STATUS. Catalog entry `verification: .protocolCompatible`, which the Drivers screen
renders as "Protocol-compatible (unverified on hardware)" and which is the code's spelling of
the PRD's Protocol-Implemented (§8.1, §8.3). It is never `.hardwareVerified` in this or any
story until a named validator records §8.2 evidence. The simulator has no Bluetooth and nobody on
the team has a pump: live behaviour is validation debt for community testers on TestFlight
(AC 9). Tension for the PM: §8.1 defines Protocol-Implemented as "the protocol is fully
implemented and passes Tier 1 and Tier 2". At the end of this story only discovery exists. That
is harmless while the Driver is not composed into the app, but if the PM wants the catalog to be
literally true at every merge, use `.unverified` here and raise it in the story that composes the
Driver into the app.

DEPENDENCY ON 2.1 (AccessorySetupKit spike): none blocking. Reasoning in Dev Notes.

Route: NOT chosen here; the PM routes via /v1/route. Touches `Package.swift` (new target, new
test target; no external dependency, no lockfile), `DriverCatalog.swift`, and the manifest and
catalog tests. No dosing logic, no alert floor, no ingestion mapper, no CI workflow. Honest
profile: ambiguity medium (Core Bluetooth semantics cannot be observed here; two PRD timeouts are
marked ASSUMPTION; scan UI ownership needs PM confirmation), blast radius low-medium (a new
target; the only shared files touched are the catalog and its tests). -->

## Story

As a user pairing for the first time,
I want to see nearby pumps identified by name and model,
so that I can pick mine with confidence.

## Acceptance Criteria

From epics.md Story 1.8 and the PRD requirements it actually draws on. The epic cites FR-4,
FR-6, FR-7, FR-8 and FR-19; in the PRD the scan, list, age-out, auto-stop and blocking-condition
rules are all **FR-4**, the Disconnected reasons are **FR-8**, "no identifier" is **FR-19**, and
"no Bluetooth operation before the user acts" is **FR-3**. FR-6 (advertise-and-wait) and FR-7
(one-phone warning) are not in scope. AC numbering is local to this file.

1. **A new Driver target, inside AD-3.** `Package.swift` declares `.target(name: "TandemDriver",
   dependencies: ["DriverAPI", "SafetyCore", "TandemWire"], path: "Sources/Drivers/Tandem",
   swiftSettings: [.swiftLanguageMode(.v6)])` and `.testTarget(name: "TandemDriverTests",
   dependencies: ["TandemDriver", "DriverAPI", "SafetyCore", "TandemWire"], …)`, plus a library
   product. `PackageManifestTests` gains `TandemDriver`/`TandemDriverTests` in the enumeration
   test and a test that pins the target's exact dependency list.
2. **Registered, honestly labelled, not composed.** `DriverCatalog.entries` gains
   `com.glycemicgpt.tandem`, target `TandemDriver`, display name "Tandem Insulin Pump", transport
   `.bluetoothLowEnergy`, version "1.0.0", capabilities `[.glucoseSource, .insulinSource,
   .pumpStatus]`, verification `.protocolCompatible` (see planning note). `TandemDriver` is an
   actor conforming to `Driver` whose `descriptor` equals the catalog entry (tested), whose
   `capability(_:)` returns nil for everything, and whose `activate()` throws
   `DriverFailure.notPaired` because no pairing exists. `deactivate()` stops any scan and is
   idempotent. `Apps/**` is not touched. A test asserts the entry is never `.hardwareVerified`.
   `DriverCatalogTests` counts are updated.
3. **Core Bluetooth sits behind a protocol (AD-1, AD-4).** `BluetoothCentral` (protocol,
   `Sendable`) has `events: AsyncStream<CentralEvent>`, `startScan(services:)`, `stopScan()`.
   `CentralEvent` is `.radioStateChanged(BluetoothRadioState)` or `.discovered(PeripheralSighting)`.
   `PeripheralSighting` carries an opaque `UUID`, the advertised local name (`String?`) and RSSI
   (`Int`). `BluetoothRadioState` covers: unknown, resetting, unsupported, unauthorized(denied),
   unauthorized(restricted), poweredOff, poweredOn. Nothing outside the adapter imports
   CoreBluetooth.
4. **The real adapter (AD-4).** `CoreBluetoothCentral`, in its own file under `#if os(iOS)`,
   creates one `CBCentralManager` with a dedicated serial `DispatchQueue` (label
   `com.glycemicgpt.tandem.central`) and options `[CBCentralManagerOptionShowPowerAlertKey:
   false]` and **no** restoration identifier. It holds the manager and its delegate object
   strongly. Every delegate callback is converted to a `CentralEvent` and yielded into one
   `AsyncStream` (unbounded buffering, so no radio-state change is ever dropped); the engine
   actor consumes that stream in order. It maps `CBManagerState` plus `CBManager.authorization`
   (`.restricted` vs anything else for `.unauthorized`) to `BluetoothRadioState`, and reads the
   local name from `CBAdvertisementDataLocalNameKey`, falling back to `peripheral.name`. It scans
   with `scanForPeripherals(withServices: services.map { CBUUID(string: $0) }, options:
   [CBCentralManagerScanOptionAllowDuplicatesKey: true])` so RSSI updates live (FR-4). It is
   constructed only on the first `startScan` (FR-3: no Bluetooth operation, so no system prompt,
   before the user acts). It is never instantiated in a test.
5. **The scan filter is the Tandem service (FR-4).** The engine passes exactly
   `["0000FDFB-0000-1000-8000-00805F9B34FB"]` to `startScan(services:)` (the adapter turns it
   into a `CBUUID`). A fake-central test pins the argument.
6. **A live, ordered, aged list, never an identifier (FR-4, FR-19).** `TandemPumpDiscovery`
   (an actor owned by `TandemDriver`) publishes `PumpDiscoverySnapshot { state, pumps }` through
   `snapshots() -> AsyncStream<PumpDiscoverySnapshot>` (single consumer; a new call finishes the
   previous stream; the current snapshot is yielded first). Each `DiscoveredPump` has an opaque
   `DiscoveredPumpHandle` (wraps the peripheral `UUID`; its `description` is the fixed string
   `"pump"` so it can never be printed), `name`, `model`, `signalStrength: Int?` (dBm; nil when
   Core Bluetooth reports 127, "unavailable"), `firstSeen`, `lastSeen`. Rules:
   - one entry per peripheral; a later sighting updates RSSI and `lastSeen` and, when it carries
     a non-empty local name, the name and model;
   - order: strongest signal first, nil signal last, ties by earlier `firstSeen`, then by
     insertion order — stable across snapshots;
   - while scanning, an entry with no sighting for 10 s is removed
     (`TandemScanTiming.ageOut`, FR-4 ASSUMPTION);
   - a missing or empty name displays as "Tandem Pump" (Android `BleScanner.kt:58`) with model
     Unknown.
7. **Model from the advertised name (FR-4).** `TandemPumpModel.fromAdvertisedName(_:)`: trim,
   collapse every run of whitespace (including U+00A0) to one space, compare case-insensitively:
   leading "tslim X2" or "t:slim X2" → `.tslimX2`; leading "Tandem Mobi" → `.mobi`; anything
   else, empty or nil → `.unknown`. Display names "t:slim X2", "Mobi", "Unknown Tandem Pump";
   `hasScreen` true, false, nil. Android's `TandemPumpModelTest` cases all pass, plus
   `"tslim\u{00A0}X2 1"` → `.tslimX2` and `"tslimX2"` → `.unknown`.
8. **Scan lifecycle, bounded, and every blocking condition named (FR-4, FR-8, FR-3).**
   `ScanState` is `idle`, `waitingForBluetooth`, `scanning`, `blocked(BluetoothBlockedReason)`,
   `stopped(ScanStopReason)`. Reasons: blocked = `poweredOff`, `permissionDenied`,
   `permissionRestricted`, `unsupported`, `resetting`; stopped = `user`, `idleTimeout`,
   `pumpSelected`.
   - `startScan()` clears the list. If the radio is `poweredOn` it scans; if `unknown` it waits
     and scans on the first `poweredOn`; any other state → `blocked(<reason>)` and no scan call.
     Calling it while scanning restarts cleanly (one `stopScan` then one `startScan` on the
     central).
   - Leaving `poweredOn` while scanning or waiting stops the scan, clears the list and reports
     `blocked(<reason>)`. Returning to `poweredOn` does not restart it; the user starts again.
   - 120 s after the last interaction the scan stops with `stopped(.idleTimeout)`
     (`TandemScanTiming.idleStop`, FR-4 ASSUMPTION). Interactions are `startScan()` and
     `noteUserInteraction()`; sightings are not.
   - `stopScan()` → `stopped(.user)`. `select(_ handle:) -> DiscoveredPump?` stops the scan with
     `stopped(.pumpSelected)` and returns the entry, or nil for an unknown handle. Stopping in any
     way keeps the list as last seen and stops ageing it; it does not connect to anything.
   - Timing runs on one repeating housekeeping registration from the injected `Scheduler`
     (`TandemScanTiming.housekeeping`, 1 s), registered at scan start and cancelled at every
     stop. Ages come from the injected `Clock`. No `Task.sleep`, no `DispatchQueue.asyncAfter`.
9. **Validation debt, recorded (prd.md §8.1; Sprint Change Proposal 2026-10-30).** The Dev Agent
   Record carries a "Validation debt (live radio)" list: real scan returning a t:slim X2 and a
   Mobi under the FDFB filter; the local-name source (advertisement vs GAP name) and the model
   detection on real names; live RSSI with duplicates allowed; the 10 s age-out and 120 s stop
   feeling right on a device; the restricted/denied/off/unsupported/resetting reasons as iOS
   actually reports them; the authorization prompt not appearing before the first scan.
   Nothing in code, copy or comments claims the Driver has been tested on a device.
10. **Gates.** All nine frontmatter gates pass. `driver_guards.sh` passes with the new target in
    the catalog and no denied word in it (see pitfalls).

## Tasks / Subtasks

- [ ] Task 1: manifest and catalog (AC 1, 2)
  - [ ] `Package.swift`: product, target, test target. Update the header comment's target list.
  - [ ] `Sources/DriverAPI/DriverCatalog.swift`: the entry (if 1.7c has merged, it sits outside
        the `TRACE_REPLAY_DRIVER_ENABLED` block).
  - [ ] `Tests/SafetyCoreTests/PackageManifestTests.swift`, `Tests/DriverAPITests/DriverCatalogTests.swift`.
- [ ] Task 2: radio boundary (AC 3, 4, 5) — `Sources/Drivers/Tandem/BluetoothCentral.swift`
      (protocol and value types, platform-neutral) and
      `Sources/Drivers/Tandem/CoreBluetoothCentral.swift` (whole file under `#if os(iOS)`).
  - [ ] `TandemBluetooth.pumpServiceUUID = "0000FDFB-0000-1000-8000-00805F9B34FB"` with a
        comment citing Android `TandemProtocol.kt:16-17`. No characteristic UUIDs (1.9).
- [ ] Task 3: model detection (AC 7) — `Sources/Drivers/Tandem/TandemPumpModel.swift`.
- [ ] Task 4: the engine (AC 6, 8) — `Sources/Drivers/Tandem/TandemPumpDiscovery.swift`,
      `Sources/Drivers/Tandem/TandemScanTiming.swift` (the three named intervals, each with its
      PRD citation and the ASSUMPTION note).
  - [ ] `init(makeCentral: @escaping @Sendable () -> any BluetoothCentral, clock: any Clock,
        scheduler: any Scheduler)`. The central is created lazily on the first `startScan` and
        reused for the life of the engine.
- [ ] Task 5: the Driver actor (AC 2) — `Sources/Drivers/Tandem/TandemDriver.swift`. Holds
      `nonisolated let discovery: TandemPumpDiscovery`; `deactivate()` awaits
      `discovery.stopScan()` when scanning.
- [ ] Task 6: tests (AC 1-8) — `Tests/TandemDriverTests/`
  - [ ] `TestDoubles.swift`: `FakeCentral` (records `startScan(services:)`/`stopScan()` calls,
        lets the test push events), `ManualClock`, `ManualScheduler` (copy from
        `Tests/SimulatedDriverTests/TestDoubles.swift`).
  - [ ] `TandemPumpModelTests.swift`: AC 7.
  - [ ] `TandemPumpDiscoveryTests.swift`: filter argument; lazy central creation (factory not
        called before `startScan`); ordering and tiebreak; RSSI update in place; 127 → nil and
        sorted last; name update and the "Tandem Pump" fallback; age-out at 10 s (present at
        9 s, gone after the tick past 10 s); idle stop at 120 s and that `noteUserInteraction()`
        at 100 s moves it to 220 s; each blocked reason from `startScan`; radio lost mid-scan;
        `unknown` then `poweredOn` starts the scan once; restart while scanning; `select`
        stops and returns; stopped list does not age; handle `description` is `"pump"`.
  - [ ] `TandemDriverTests.swift`: descriptor equals catalog entry; never `.hardwareVerified`;
        `activate()` throws `.notPaired`; `capability(_:)` nil for all six; `deactivate()` twice
        is safe and stops a running scan.
- [ ] Task 7: Dev Agent Record — validation debt list (AC 9), diff size, NEEDS-HUMAN lines.

## Dev Notes

### Known pitfalls (read before writing code)

- The worker cannot compile, so write carefully. A `switch` after any statement in a function or getter needs `return switch`. Test functions that `await` must be `async`. In Swift Testing, `#expect` over a key-path closure such as `allSatisfy(\.x)` is treated as throwing, so bind it to a `let` first. Typed-throws closures can't call `NSLock.withLock` and throw a typed error; use `lock()`/`defer unlock()`. In an init, assign every stored property before reading any `self` property. Swift does not allow `#if` inside an array literal; put the whole declaration under `#if`/`#else`.
- AppFeature and the other packages also build for macOS (`swift test` runs on macOS in CI). Wrap iOS-only APIs (UIKit, UserNotifications specifics, CoreBluetooth specifics, AccessorySetupKit) in `#if os(iOS)`, or put them behind protocols.
- Never write a numeric safety constant inline, and never disguise one. Literals equal to safety constants (for example 18, 20, 21, 55, 58, 61, 70, 180, 250) trip the guard. Hex colour parts count too.
- Swift 6 strict concurrency; actors are reentrant across `await`. Tests whose state settles asynchronously must wait with `eventually`.
- Objects held only weakly by system APIs (CoreBluetooth delegates, `UNUserNotificationCenter` delegates) must be retained explicitly. Release builds free them early.
- Code comments must not mention stories, epics, AC numbers, agents or cycles. No private API.
- The diff budget is about 800 reviewable lines.

Specific to this story:
- **`driver_guards.sh` denies these words anywhere in code under `Sources/Drivers/`** (comments
  and strings are exempt): `resume`, `suspend`, `prime`, `inject`, `infuse`, `deliver`,
  `bolus`, `therapy`, `enact`, `administer`, `cannula`, and the pairs `write value`, `write
  characteristic`, `command characteristic`, `control characteristic`, `set basal`, `temp basal`.
  Identifiers are split on camel humps, so `continuation.resume(...)` and
  `withCheckedContinuation` call sites fail the gate. Bridge callbacks with `AsyncStream` only.
  Do not name anything `deliverEvent`, `resumeScan`, `primeCentral` and so on.
- **Never construct `CBCentralManager` in a test.** The package test host has no
  `NSBluetoothAlwaysUsageDescription`, and touching Bluetooth there is a privacy-violation crash.
  The adapter is compiled on iOS and exercised only on hardware (validation debt).
- **Delegate retention.** `CBCentralManager.delegate` is weak. The adapter keeps a strong
  reference to its delegate object for as long as it keeps the manager.
- **Order matters.** Do not hop each callback with `Task { await actor.handle(…) }`; separate
  tasks are not ordered. One `AsyncStream` from the delegate queue, consumed by one loop on the
  actor, keeps radio-state changes and sightings in the order Core Bluetooth produced them.
- **Actor reentrancy.** `startScan` must not await between reading and writing scan state.
  The central's calls are synchronous and non-throwing.
- **SI-9 / FR-19: no identifier, no name in logs.** Advertised names carry a serial suffix
  ("tslim X2 ABC123"). Log only counts and state transitions, if anything. `DiscoveredPumpHandle`
  must not be `CustomStringConvertible` over the UUID.
- **No `Date()`.** Ages come from the injected `Clock` (AD-14); the safety guard rejects wall-clock
  reads in `Sources/`.
- **Literals.** 10, 120 and 1 seconds are UX timing, not safety constants, and none collides with
  a CANON_SPEC band. Keep them as named statics in `TandemScanTiming`, each citing FR-4. RSSI 127
  is Core Bluetooth's "unavailable" sentinel; name it (`unavailableRSSI`) with a comment.

### Rules of the road

- Swift 6 language mode; Core Bluetooth callbacks land on the dedicated queue and hop into the
  engine actor through the stream (AD-4).
- **No therapeutic write, ever (SI-1).** Nothing in this story writes to a peripheral; it does
  not even connect.
- **Do not edit** `Sources/SafetyCore/**`, `Sources/Persistence/**`, `Sources/AppFeature/**`,
  `Sources/DomainCore/**`, `Sources/Wire/**` (TandemWire is a dependency, unchanged), `Apps/**`,
  CI workflows, or any guard script. `Sources/DriverAPI/**` changes only for the catalog entry.
- Comments and commit messages state requirements in plain words; FR/SI/AD ids are fine.
- Scratch files only under `.build/`. One operation per Bash call.

### Where the scan screen goes (open question for the PM)

The epic says "discovered pumps appear in a live-updating list". This story delivers the live
list as data (`snapshots()`), not a SwiftUI screen, because the screen cannot be built honestly
yet:
- AppFeature may not import a Driver target (spine graph: only the iOS App target links
  `Drivers/*`), so a scan screen needs a Driver-agnostic pairing contract in DriverAPI.
- FR-2 says all pairing copy is Driver-supplied and that exactly two pairing shapes exist
  (scan-and-connect, advertise-and-wait). That contract is 1.19's (FR-1, FR-2). Designing it
  here, for one shape, would either hard-code Tandem copy in a shared view (the Android defect
  FR-2 forbids) or pre-empt 1.19's design without Medtronic's shape in view.
- Settings currently says "Pump pairing isn't available in this build yet." There is no route.

Recommendation: 1.19 (or a 1.8b the PM inserts before 1.9) lifts `PumpDiscoverySnapshot`'s shape
into a DriverAPI pairing port and builds the scan list view from FR-4's strings ("No pumps found.
Tap Scan to search.", "Scan for Pumps" / "Stop Scan", "Scanning...") over it. 1.9's "a pump
selected from the scan list" can be satisfied by `select(_:)` until then.

### Does this depend on the 2.1 AccessorySetupKit spike? No, not blocking.

- The deployment floor is iOS 17.0 (NFR-1) and AccessorySetupKit exists only from iOS 18. A Core
  Bluetooth scan path is required on iOS 17 whatever 2.1 finds.
- AD-21 says adopt AccessorySetupKit for setup "wherever the OS provides it", and TN3115 says
  that from iOS 26 only AccessorySetupKit apps are relaunched after a force-quit or a Bluetooth
  toggle. If 2.1 confirms that, iOS 18+ setup moves to the system accessory picker and this
  story's list becomes the iOS 17 path. The engine is behind `BluetoothCentral`, the model
  detection and the handle are reusable, and nothing here sets an Info.plist key, so that change
  is additive.
- Risk to carry: an app that declares AccessorySetupKit support may see Core Bluetooth discovery
  limited to accessories the user granted through the picker. 2.1 must answer that before 1.10
  sets a restoration identifier. No 2.1 story file exists yet.

### Android reference (copied here; the Android repo may not be readable from your sandbox)

- `android-unofficial/plugins/shipped/tandem/src/main/java/com/glycemicgpt/mobile/ble/connection/BleScanner.kt`:
  `ScanFilter.Builder().setServiceUuid(TandemProtocol.PUMP_SERVICE_PARCEL)` (lines 72-76),
  `SCAN_MODE_LOW_LATENCY` (77-79). Dedupes by address and **emits once per device** (54-55), so
  RSSI freezes at first sighting: deliberately not ported (FR-4, PD-3). Fallback name
  `device.name ?: "Tandem Pump"` (58). Logs name and address at debug (62): not ported (FR-19,
  SI-9). `onScanFailed` closes the flow with an error that the UI swallows (66-69): replaced by
  named blocked reasons (FR-4). No scan timeout anywhere.
- `.../ble/protocol/TandemProtocol.kt:16-17`: `PUMP_SERVICE_UUID = 0000fdfb-0000-1000-8000-00805f9b34fb`.
- `android-unofficial/plugins/pump-driver-api/src/main/java/com/glycemicgpt/mobile/domain/model/TandemPumpModel.kt`:
  `fromAdvertisedName` (lines 32-41) trims, replaces `\s+` with a space, then case-insensitive
  `startsWith` "tslim X2", "t:slim X2", "Tandem Mobi". Display names and `hasScreen` as in AC 7.
  Its KDoc claims non-breaking spaces are handled, but Java's `\s` does not match U+00A0; iOS
  does handle it (deliberate, small difference). Tests: `TandemPumpModelTest.kt`.
- `android-unofficial/app/src/main/java/com/glycemicgpt/mobile/presentation/pairing/PairingViewModel.kt:79-102`:
  `startScan()` stops any scan, clears the list, then upserts by address; `stopScan()` keeps the
  list. Ported as AC 8.
- `.../pairing/PairingScreen.kt:299` derives the model from the name; `:517` shows "<rssi> dBm".

### Existing code to build on (develop @ e09202b)

- `Sources/DriverAPI/Driver.swift`: the `Driver` protocol (actor, `descriptor`,
  `capability(_:)`, `activate()`, `deactivate()`; `dashboardCards()` has a default).
- `Sources/DriverAPI/DriverDescriptor.swift`: `DriverIdentifier`, `DriverTransport.bluetoothLowEnergy`,
  `VerificationStatus` (`unverified`, `protocolCompatible`, `beta`, `hardwareVerified`).
- `Sources/DriverAPI/DriverFailure.swift`: `.notPaired`.
- `Sources/Drivers/TraceReplay/TraceReplayDriver.swift`: the newest Driver; copy its descriptor
  layout and its file-per-concern style.
- `Sources/SafetyCore/Scheduler.swift`: `scheduleRepeating(interval:action:)` →
  `SchedulerRegistration.cancel()`. `Sources/SafetyCore/Clock.swift`.
- `scripts/guards/driver_guards.sh`: catalog completeness (target ↔ entry) and the deny list.
- `Apps/GlycemicGPT/App/SystemOnboardingAuthorizations.swift`: onboarding already asks for
  Bluetooth permission (FR-165); this story does not ask again.

### Out of scope, and who owns it

| Not here | Owner |
|---|---|
| Scan list screen, Driver-supplied pairing copy, pairing-shape contract, Settings pump card | 1.19 (or a PM-inserted 1.8b) |
| Pre-explanation before the system prompt, code entry, EC-JPAKE, connect/cancel, failure categories, the "iOS pairing dialog will appear" warning | 1.9 |
| Restoration identifier, background scanning, indefinite reconnect, Keychain | 1.10 |
| Broken-pairing wall, unpair | 1.11 |
| The seven-state connection model in DriverAPI and "already connected" as a reason not to scan (the epic lists it; FR-4 does not; it needs a connection to exist) | 1.9 / 1.10 |
| Composing the Driver into the app and its kill switch (1.7c pattern) | the story that makes it useful, 1.9 or later |
| AccessorySetupKit | 2.1 spike, then AD-21 work |
| Fingerprint re-binding of a paired pump (FR-19) | 1.9 / 1.10 |

### Testing standards

- Swift Testing, as in the existing suites. Drive time only with `ManualClock` and
  `ManualScheduler.tick()`; never sleep.
- The engine consumes the fake central's stream on its own task, so after pushing an event, wait
  for the snapshot with `eventually` (copy the helper from
  `Tests/DomainCoreTests/ContributedCardsTests.swift`).

### Project structure notes

```
Sources/Drivers/Tandem/
  BluetoothCentral.swift        protocol + CentralEvent, PeripheralSighting, BluetoothRadioState
  CoreBluetoothCentral.swift    #if os(iOS); the only CoreBluetooth import
  TandemBluetooth.swift         the service UUID (or fold into BluetoothCentral.swift)
  TandemPumpModel.swift
  TandemScanTiming.swift
  TandemPumpDiscovery.swift     actor; snapshot types
  TandemDriver.swift            actor; Driver conformance
Tests/TandemDriverTests/
  TestDoubles.swift  TandemPumpModelTests.swift  TandemPumpDiscoveryTests.swift  TandemDriverTests.swift
```

### References

- epics.md, Epic 1, Story 1.8 (and 1.9, 1.10, 1.19, 2.1)
- prd.md §5.1 description, FR-3, FR-4, FR-8, FR-19, Feature-specific NFRs (Simulator
  reachability, hardware sign-off items), open question on the 2-minute and 10 s numbers;
  §8.1, §8.2, §8.3 (Tandem rows); PL-8, PD-3, PD-37
- ARCHITECTURE-SPINE.md AD-1, AD-3 (amended 2026-11-02), AD-4, AD-11, AD-12, AD-14, AD-16, AD-21
- sprint-change-proposal-2026-10-30.md §4.9 (Protocol-Implemented and validation debt)
- epic-1-scoping-review-2026-08-17.md, "1.8–1.11 Tandem BLE"

## Dev Agent Record

### Agent Model Used

Amelia / Senior Software Engineer (Codex)

### Debug Log References

- `swiftc -frontend -parse Sources/Drivers/Tandem/*.swift Tests/TandemDriverTests/*.swift ...` — passed.
- `git diff --check` — passed.
- `bash scripts/guards/safety_guards.sh` — passed.
- `bash scripts/guards/driver_guards.sh` — passed.
- `bash scripts/ci-local.sh --self-test` — passed.
- `swift build` and `swift test` — attempted; SwiftPM could not compile the package manifest because the environment denied writes to `~/.cache/clang/ModuleCache` and its sandbox setup failed when cache output was redirected into `.build`.
- `xcodebuild test ...` — attempted; failed because CoreSimulatorService is unavailable and SwiftPM manifest compilation hit the same cache restriction.
- `xcodebuild build ...` — attempted; failed resolving package dependencies because SwiftPM could not write its user cache; CoreSimulatorService is also unavailable.
- `bash scripts/guards/safety_guards.sh --self-test` — passed (75 cases, 2 documented bypasses, no unexpected results).
- `bash scripts/guards/driver_guards.sh --self-test` — passed (69 cases, 3 documented limits, no unexpected results).

### Completion Notes List

- Added and registered `TandemDriver`; catalog verification is `.unverified` per the final PM decision in this story.
- Added a platform-neutral Bluetooth central protocol, lazy iOS Core Bluetooth adapter, service filter, model detection, aged discovery snapshots, scan lifecycle, and fake-central tests.
- Compile-and-review pass (unsandboxed, 2026-11-02):
  - Test doubles: added `import Foundation` to the discovery tests; replaced `NSLock.lock()/unlock()` (unavailable from async code) with synchronous `withLock` helpers, matching the repo's other fakes. `ManualScheduler.tick()` now reads the live actions through a sync helper and awaits each one.
  - Adapter deadlock fixed: the `CBCentralManager` was only created inside `startScan`, which the engine never calls until the radio reports `poweredOn`, so a real scan would have waited forever. The manager and its strongly held delegate are now created in `init` (both `let`, touched only on the dedicated queue). The adapter itself is still built only on the first user `startScan`, so FR-3 holds.
  - Housekeeping no longer spawns a detached `Task` per tick; the scheduler action awaits the actor directly.
  - Scan-state mapping: `block(for:)` was reachable with `.unknown` (radio reporting unknown mid-scan or while waiting), which reported `.blocked(.resetting)`. Replaced with `blockedReason(for:) -> BluetoothBlockedReason?` returning nil for `poweredOn` and `unknown`; unknown while waiting is a no-op, unknown while scanning stops, clears and returns to `waitingForBluetooth`. Every block path now clears `scanRequested`. New tests cover both.
  - Catalog test restored to assert every capability outside Tandem's set has no provider, pins `.unverified`, and keeps a genuinely unregistered lookup. Manifest test finds `TandemDriverTests` via the `.testTarget` scan (the old lookup only searched `.target(`).
- Deliberate behaviour, radio `unknown` after `poweredOn`: while scanning, the engine stops the central scan, clears the list, cancels housekeeping and reports `waitingForBluetooth`; on the next `poweredOn` it restarts the scan by itself. This differs from the AC 8 rule that leaving `poweredOn` blocks and needs a user restart, and is intended. `unknown` means iOS has not determined the state yet, not that anything is wrong, so there is no truthful `BluetoothBlockedReason` to show, and the user's scan request is still standing. Reporting a blocked reason would invent a cause iOS did not give, and dropping the request would make a transient blip look like a failure the user has to act on. Real blocking states (`poweredOff`, `unauthorized`, `unsupported`, `resetting`) still block and still need the user to start again. Covered by `radioReturningToUnknownWaitsInsteadOfBlocking`; listed under validation debt because whether iOS ever does this is unconfirmed.
- Test-gap and lifecycle pass (2026-11-02):
  - `eventually` now records an `Issue` (at the caller's source location) when its condition never settles. That exposed `blockedRadioNeverStartsAndRadioLossClearsList`, which had been passing without testing anything after its first block: the `start` helper called `startScan()` while the radio was still `poweredOff`, so the scan re-blocked, never reached `scanning`, and the restricted-permission path and its empty-list check ran against an already-blocked engine. The test now powers the radio on and retries the user start until it scans (the radio state is not observable while blocked), asserting exactly one central `startScan`.
  - The engine's `deinit` cancels the event-loop task and the housekeeping registration. The loop holds the central strongly and the engine weakly, so cancelling it ends iteration and releases the central even when something else keeps the central's stream open.
  - `TandemDriver.deactivate()` calls the new `stopScanIfActive()`, which stops only when a scan is requested (scanning, or waiting for the radio). Idle, blocked and stopped states are left as reported, so tearing down an idle Driver no longer reports `stopped(.user)`. A scan waiting for the radio is cancelled, otherwise it would start on the next `poweredOn` after deactivation.
  - Housekeeping publishes only when an entry aged out (or the idle stop fired), not on every tick.
  - `TandemDriver` gained an internal initializer that takes the central factory, so Driver-level tests can drive a fake central.
  - New tests: equal-signal ties ordered by first-seen then arrival (with a clock that steps back); an RSSI-127 pump sorting after two pumps with signal; the "Tandem Pump" fallback name for nil and empty names, and an advertised name surviving a later nameless sighting; the central factory not called before the first `startScan`, and called only once; `snapshots()` yielding the current snapshot first and a new call finishing the previous stream; a restart clearing the list; housekeeping not publishing unchanged snapshots; a released engine ending its event loop (central held from outside, weak engine reference) and then releasing the central; `deactivate()` stopping a running scan once, leaving idle and blocked states alone, and cancelling a waiting scan; model cases "OmniPod 5", "Tandem Pump" and "" → `.unknown`. Each code fix was checked by reverting it and confirming the matching test fails.
- Diff size: 15 files; ~924 added / 7 removed lines (875 in 11 new files: 415 source, 460 tests; 49/7 in Package.swift, DriverCatalog.swift and two test files). This is over the 800-line budget, mostly from the added tests (460 test lines); NEEDS HUMAN: decide whether to ship as one change or split the test additions into a follow-up.

### Validation debt (live radio)

- Confirm a real scan finds t:slim X2 and Mobi devices under the FDFB filter.
- Confirm whether iOS supplies each advertised name or the GAP peripheral name, and verify model detection against real pump names.
- Confirm duplicate advertisements update RSSI live.
- Confirm 10-second age-out and 120-second idle stop feel right on device.
- Confirm iOS reports restricted, denied, powered-off, unsupported, and resetting states as mapped.
- Confirm the authorization prompt does not appear before the user starts scanning, and does appear on the first scan (the manager is created when the adapter is).
- Confirm whether iOS ever reports `unknown` after `poweredOn`; the engine treats it as "wait for power" rather than a blocking reason.
- Confirm `CBManager.authorization` distinguishes restricted from denied when the state is `unauthorized`.
- Confirm a `startScan` issued while the radio is still `unknown` is dropped by the adapter and re-issued by the engine on `poweredOn`.
- Confirm the list stays usable when it reorders rapidly on live RSSI with duplicates allowed (FR-4 sorts by signal on every sighting, so near-equal pumps can swap places many times a second).
- No hardware testing is claimed.

### File List

- `Package.swift`
- `Sources/DriverAPI/DriverCatalog.swift`
- `Sources/Drivers/Tandem/BluetoothCentral.swift`
- `Sources/Drivers/Tandem/CoreBluetoothCentral.swift`
- `Sources/Drivers/Tandem/TandemDriver.swift`
- `Sources/Drivers/Tandem/TandemPumpDiscovery.swift`
- `Sources/Drivers/Tandem/TandemPumpModel.swift`
- `Sources/Drivers/Tandem/TandemScanTiming.swift`
- `Tests/DriverAPITests/DriverCatalogTests.swift`
- `Tests/SafetyCoreTests/PackageManifestTests.swift`
- `Tests/TandemDriverTests/TestDoubles.swift`
- `Tests/TandemDriverTests/TandemDriverTests.swift`
- `Tests/TandemDriverTests/TandemPumpDiscoveryTests.swift`
- `Tests/TandemDriverTests/TandemPumpDiscoveryLifecycleTests.swift`
- `Tests/TandemDriverTests/TandemPumpModelTests.swift`

### PM decisions on drafting open points (2026-11-02)
- **Catalog verification status is `.unverified`** until the full protocol path (scan, pair, connect, authenticate, read) is implemented. It then moves to Protocol-Implemented, which the UI shows as unverified on hardware. It is never marked verified without a community hardware report.
- **The scan screen belongs to 1.19** (pairing from Settings). This story ships the scanning model and Driver only.
- **No hardware is available.** Every Core Bluetooth behaviour is tested through the protocol seam. Record in the Dev Agent Record which behaviours need community validation on TestFlight.
- budget: CONTINUATION_REQUIRED sha256:dedc8da6252b5cd0be864b1d8950fd23c8e445ef25a28cb9e17a63a7fc4686ee cycle 1 2026-11-02T11:15:16Z

- PM: about 924 changed lines (budget 800) is accepted. The excess is review-requested tests.
