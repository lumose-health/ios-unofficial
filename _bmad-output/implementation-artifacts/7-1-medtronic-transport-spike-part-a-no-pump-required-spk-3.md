# Story 7.1: Medtronic transport spike, part (a) — no pump required (SPK-3)

Status: ready-for-dev

## Story

As a maintainer,
I want to know whether iOS can support the Medtronic advertise-and-wait transport at all,
so that we do not build a driver on an assumption that turns out false.

**This is a spike. The deliverable is evidence, not a feature.** Ship a throwaway harness and a written finding. Do not build the Medtronic Driver.

**Why it is first:** a negative result cuts Epic 7 (4 stories) before any of it is built. Epic 7 exists as a separate epic specifically so this can happen cheaply.

## Acceptance Criteria

1. **Given** two iOS devices, or one iOS device plus a Mac acting as the BLE central
   **When** the harness runs
   **Then** it is established, with evidence, whether an iOS app hosting a `CBPeripheralManager` GATT server can complete the full SAKE-shaped exchange with a connecting central — subscribe, write, notify, disconnect
   **And** the result is recorded as VERIFIED / REFUTED / INCONCLUSIVE with the OS versions, device models and dates it was observed on

2. **Given** the epic's stated unknown is *"can Core Bluetooth return a `CBPeripheral` for a central that connected to our `CBPeripheralManager`"*
   **When** the spike answers it
   **Then** it **also** answers the question that actually matters: **is a `CBPeripheral` needed at all?** See Dev Notes — Android uses a GATT *server*, and the iOS peripheral-role API may cover the whole requirement without ever obtaining a `CBPeripheral`
   **And** if no `CBPeripheral` is needed, that is a PASS for part (a) and must be stated as such rather than left as "the original question was unanswerable"

3. **Given** iOS `CBPeripheralManager.startAdvertising` accepts only `CBAdvertisementDataLocalNameKey` and `CBAdvertisementDataServiceUUIDsKey`
   **When** advertising is exercised
   **Then** the harness confirms manufacturer-specific data **cannot** be advertised, and records what a scanning central actually sees in the advertisement
   **And** it records whether a 16-bit service UUID (`0xFE82` first-pair, `0xFE81` reconnect) is advertised in a form a non-Apple central can filter on

4. **Given** the app may be backgrounded during pairing
   **When** the harness advertises from the background
   **Then** it records what a scanning central sees — specifically whether the local name survives backgrounding (PL-6 states it does not) and whether the service UUID moves to the overflow area
   **And** this is recorded per OS version, because it bears directly on whether foreground-only pairing (FR-16) is sufficient

5. **Given** the finding
   **When** the spike closes
   **Then** a written result lands at `_bmad-output/implementation-artifacts/spikes/spk-3-medtronic-transport.md` stating: the verdict, the evidence, the OS/device matrix, and **an explicit recommendation to proceed with or cut Epic 7**
   **And** if the verdict is REFUTED, the recommendation names what Medtronic users get instead (PRD §7 records cloud-mediated support as the considered alternative)
   **And** part (b) — whether a real 780G's discovery filter accepts an iOS advertisement — is explicitly left open, because it needs hardware nobody on the team has

6. **Given** this is throwaway code
   **When** the story completes
   **Then** the harness lives under `Spikes/` and is **excluded from the app targets and from CI required checks**
   **And** it introduces no dependency, no `Package.swift` product, and no file under `Sources/`

## Tasks / Subtasks

- [ ] **Task 1: Build the peripheral-role harness** (AC: #1, #2)
  - [ ] Minimal iOS app target under `Spikes/MedtronicTransport/`, not in `Sources/`, not in any app target
  - [ ] `CBPeripheralManager` hosting a GATT service with one write characteristic and one notify characteristic, mirroring the SAKE shape
  - [ ] Implement `peripheralManager(_:central:didSubscribeTo:)`, `didReceiveWrite`, `didUnsubscribeFrom`, and `updateValue(_:for:onSubscribedCentrals:)`
  - [ ] Log every delegate callback with timestamps
- [ ] **Task 2: Build the central-role counterpart** (AC: #1)
  - [ ] Second target (or a Mac CLI using Core Bluetooth) that scans, connects, discovers, subscribes, writes and receives notifications
  - [ ] This stands in for the pump; it is **not** a protocol simulator and must not be mistaken for one
- [ ] **Task 3: Answer the CBPeripheral question directly** (AC: #2)
  - [ ] From `didSubscribeTo`, capture the `CBCentral.identifier`
  - [ ] Attempt `CBCentralManager.retrievePeripherals(withIdentifiers:)` with it; record the result
  - [ ] Record whether a round-trip exchange completes **without** ever obtaining a `CBPeripheral`
- [ ] **Task 4: Characterise advertising** (AC: #3, #4)
  - [ ] Advertise with local name + 16-bit service UUID; capture what the central sees
  - [ ] Attempt manufacturer data; record the failure mode
  - [ ] Repeat backgrounded; record local-name and overflow-area behaviour
  - [ ] Repeat on each OS version available
- [ ] **Task 5: Write the finding** (AC: #5)
  - [ ] Verdict, evidence, OS/device matrix, proceed-or-cut recommendation
  - [ ] Open part (b) explicitly
- [ ] **Task 6: Confirm exclusion** (AC: #6)
  - [ ] `Spikes/` excluded from app targets and from the required checks

## Dev Notes

### The framing correction that matters most

The epic states the unknown as *"can Core Bluetooth return a `CBPeripheral` for a central that connected to our `CBPeripheralManager`?"* **Answer the question behind it, not just the literal one.**

On Android the Medtronic driver runs a **GATT server** (`BluetoothGattServer`): the pump connects **to the phone** as central, subscribes to a characteristic and writes to it. Nothing in that flow requires the phone to hold a client-side handle on the pump.

iOS's peripheral role covers exactly that shape:
- `peripheralManager(_:central:didSubscribeTo:)` → the pump subscribing
- `peripheralManager(_:didReceiveWrite:)` → the pump writing
- `updateValue(_:for:onSubscribedCentrals:)` → notifying the pump

**So a `CBPeripheral` may simply be unnecessary.** If the round trip completes without one, part (a) is a PASS. Do not report "unanswerable" — report what is actually true.

Prior research (not yet independently confirmed — confirm it): `CBCentral.identifier` is not a `CBPeripheral` identifier, and `retrievePeripherals(withIdentifiers:)` is a `CBCentralManager` method. Expect the literal conversion to fail. **That is not automatically a REFUTED verdict.**

### Android contract to mirror (verified in source)

`plugins/shipped/medtronic/src/main/java/com/glycemicgpt/mobile/ble/connection/`

**`MedtronicPeripheral.kt`** — the interface the iOS side must eventually satisfy:

| Callback | Meaning |
|---|---|
| `onAdvertiseStarted(mode)` | advertising began |
| `onAdvertiseFailed(errorCode)` | advertising rejected |
| `onPumpConnected(address)` | a central connected |
| `onSakeSubscribed()` / `onSakeUnsubscribed()` | subscription lifecycle |
| `onSakeWrite(value)` | inbound bytes |
| `onPumpDisconnected(status)` | link lost |

`AdvertisingMode`: `FIRST_PAIR` → service `0xFE82`; `RECONNECT` → service `0xFE81`.

**`AndroidMedtronicPeripheral.kt:183-220`** — what Android advertises, and the parts iOS cannot reproduce:

- Manufacturer data, company ID **`0x01F9`**, carrying the `"Mobile …"` local name — **iOS cannot advertise manufacturer data at all**
- The 16-bit SIG service UUID for the mode
- GAP device name **deliberately excluded** to stay inside the 31-byte budget
- `RECONNECT` uses a low-latency interval (the paired pump scans infrequently); `FIRST_PAIR` uses balanced — **iOS exposes no advertising-interval control**

The Android comment records that pump-side name matching was confirmed live. On iOS the name must move into `CBAdvertisementDataLocalNameKey`, which is the substitute recorded as **PL-4** in the PRD's Parity Ledger. Whether the pump accepts it is **part (b)** and out of scope here.

### Architecture constraints that apply even to a spike

| | |
|---|---|
| **AD-1** | Hexagonal. The spike is not an adapter behind a port — it is throwaway. Keep it out of `Sources/`. |
| **AD-12** | **No therapeutic write exists.** The harness writes only spike-defined characteristics. It must not implement, or appear to implement, any pump command. |
| **AD-17** | Build composition is subtractive only. `Spikes/` is not a configuration of the app — it is a separate target. |
| **SI-9** | No health value, raw payload or credential in logs above debug. Synthetic bytes only; nothing resembling real pump data. |

### Anti-patterns — do not do these

- **Do not build the Medtronic Driver.** No `Sources/Drivers/Medtronic/`. That is Stories 7.2–7.3, gated on this result.
- **Do not implement SAKE.** The handshake is out of scope; the harness proves *transport*, not protocol.
- **Do not write a pump simulator.** The central-role counterpart is a bare BLE central, not a fake 780G. A simulator that "works" would prove nothing about a real pump and would invite exactly the false confidence this spike exists to avoid.
- **Do not add a dependency.** Core Bluetooth only.
- **Do not report a Simulator result.** Core Bluetooth does not exist in the iOS Simulator (`CBCentralManager` reports `.unsupported`). A green Simulator run is **no result** — see PRD §9 Tier 1.
- **Do not soften an inconclusive result into a pass.** INCONCLUSIVE is a legitimate verdict and is more useful than a hopeful one.

### Testing standards

Normal unit tests do not apply — the deliverable is a recorded observation. What counts as evidence:

- Delegate-callback logs with timestamps, from both roles
- The OS/device matrix each observation was made on
- For a negative result: what was tried, and why it is a platform limit rather than a harness bug

### Project Structure Notes

- New directory `Spikes/MedtronicTransport/`, outside `Sources/`
- Finding at `_bmad-output/implementation-artifacts/spikes/spk-3-medtronic-transport.md`
- No change to `Package.swift` products, and no file under `Sources/`
- **Repository state:** on branch `develop` (`f1190fe`). `Sources/` does not exist yet — Epic 1 has not started. This story creates no application code, so that is not a blocker.
- **CODEOWNERS is live** (`.github/CODEOWNERS`, added in #1/#2). Default owners are `@lumose-health/web` and `@jlengelbrecht`; `/.github/workflows/` is lead-only. It states that `develop` requires 0 reviews and that ownership is for review **request** only — see the Questions section.

### Hardware and who runs this

The lead developer has a Mac and an Apple Developer account but **no iPhone and no Apple Watch**. Two iOS devices are therefore not available in-house.

Two viable paths, in preference order:
1. **Mac as the central role**, iPhone as the peripheral role — needs one iPhone, which the maintainer has
2. **Maintainer runs both roles** on their own hardware

Either way this needs a device conversation before work starts. It is the cheapest hardware ask in the project and it retires the largest architectural unknown in Epic 7.

### References

- [Source: `_bmad-output/planning-artifacts/epics.md#Epic 7` — epic goal and Story 7.1 acceptance criteria]
- [Source: `_bmad-output/planning-artifacts/architecture/architecture-ios-unofficial-2026-08-03/ARCHITECTURE-SPINE.md#AD-12`, `#AD-17`]
- [Source: PRD §7 Parity Ledger — **PL-4** manufacturer-data advertisement, **PL-5** advertising interval/TX power control, **PL-6** background discoverability to a non-Apple central]
- [Source: PRD §9 Validation Tier Model — Tier 1 cannot prove any Core Bluetooth behaviour]
- [Source: `android-unofficial` `plugins/shipped/medtronic/.../MedtronicPeripheral.kt`, `AndroidMedtronicPeripheral.kt:183-220`]
- [Source: PRD decision 5 — Medtronic ships present-but-gated at Beta with the transport spike split into (a) and (b)]

## Notes for the implementer

**You build it; a maintainer runs it.** The lead developer has no iPhone, and that is the accepted working model — build to best effort, hand the harness to a maintainer with hardware, and record their observations as the finding. This story is complete when the harness is handed over and the finding is written from a real device run; it is not blocked on the lead owning hardware.

Ship the harness with a short README stating exactly what to run, in what order, and what to capture — the person executing it will not have this story's context.

**CODEOWNERS is intentional and needs no change.** `develop` requires 0 reviews and maintainers self-merge, deliberately, so other maintainers can build freely. Ownership is review-request only. Do not configure branch protection to require code-owner approval.

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
