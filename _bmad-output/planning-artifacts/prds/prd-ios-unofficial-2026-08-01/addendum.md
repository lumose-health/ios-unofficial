# PRD Addendum — GlycemicGPT for iOS and Apple Watch

Material that surfaced during PRD discovery and belongs to a downstream document — architecture, solution design, or the docs tooling — rather than to the PRD itself. The PRD states capabilities and constraints; this file holds mechanism, rejected alternatives, and the evidence behind decisions that would otherwise have to be rediscovered.

Companion to `prd.md`. Full subsystem evidence is in `research/` (14 subsystem maps and port analyses, plus three critic passes).

---

## 1. Mechanism findings that constrain architecture

### 1.1 Tandem pairing needs elliptic-curve arithmetic CryptoKit does not expose

Tandem's pairing handshake is **EC-JPAKE**, which requires raw P-256 **point addition** and **arbitrary-base scalar multiplication**. CryptoKit exposes neither — it offers key agreement and signing over P-256, not the underlying group operations. The realistic options are swift-crypto/BoringSSL, or a hand-written implementation over a bignum library.

This is the single largest unknown in the port. It sits underneath roughly 10,400 lines of safety-critical protocol and crypto, and it is the gate on Tandem working at all.

**Verification requirement carried into the PRD:** the Swift implementation must produce byte-identical output to the Kotlin one against pumpX2's test vectors. Those vectors validate parser and handshake correctness only; they are not a licence to import code (see §3.1).

### 1.2 Core Bluetooth in the Simulator

`CBCentralManager` reports `.unsupported` in the iOS Simulator. There is no host-Bluetooth passthrough and no supported workaround. Every BLE-dependent behaviour is Tier 3 or Tier 4 in the PRD's validation model.

The watchOS Simulator **does** pair with the iOS Simulator, so WatchConnectivity message routing is exercisable without hardware. That is a meaningful amount of the watch surface.

### 1.3 The Medtronic transport question, split

Medtronic pairing requires the *phone* to advertise as a BLE peripheral under a human-readable name the user selects from the pump's own menu. Two independent unknowns:

- **(a) Can Core Bluetooth return a `CBPeripheral` for a central that connected to our `CBPeripheralManager`?** There is no documented API for this. **Answerable without a pump** — two iOS devices, or a Mac acting as peripheral. This is the first Medtronic work item because a negative answer invalidates the driver architecture before it is built.
- **(b) Does the 780G's discovery filter accept an iOS advertisement?** iOS ignores `CBAdvertisementDataLocalNameKey` while backgrounded and handles advertised service data differently from Android. **Requires the hardware.**

### 1.4 Bond removal has no iOS equivalent

Android calls `BluetoothDevice.removeBond()` via reflection on three Tandem trust-recovery paths and both drivers' unpair paths. iOS exposes no API — public or private — to enumerate, inspect, or delete a Bluetooth pairing. Private-API use would also be caught on TestFlight upload, breaking the distribution model.

Architecture must therefore treat bond state as **unobservable and unmodifiable**, detect the *symptoms* with the same counters Android uses, and route to a guided user procedure. Similarly, `BluetoothGatt.refresh()` has no counterpart: handle `peripheral(_:didModifyServices:)`, re-discover on every fresh connection, and never cache characteristic handles across sessions.

### 1.5 Swift-specific translation traps

Two idiomatic Swift constructions would silently violate a safety invariant:

- **`require` → `precondition` (SI-2).** Kotlin's `require` throws a catchable exception; Swift's `precondition` traps the process. A literal transcription turns an out-of-range glucose value into a crash — potentially a crash loop during a background Bluetooth wake the user never sees. Use failable or throwing initializers.
- **Synthesized `Codable` (SI-12).** Swift's default decoder throws on a missing key and ignores unknown ones, which is the opposite of the asymmetry ADR-0002 depends on. The tolerant-reader behaviour must be written explicitly.

Both warrant a lint rule, not only a test.

### 1.6 Shared module and target topology

The PRD states the *data contract*; the target list is architecture. Fragments worth carrying forward: a shared safety module must build for iOS, watchOS, and the widget extension, since SI-4 requires one definition of each Safety Constant across every target that renders or validates a glucose value. App Group container identifiers are templated on the Builder's Team ID, because App IDs are globally unique across all Apple accounts and nothing can be shared between Builders.

---

## 2. Options considered and rejected

### 2.1 Server-generated alerts

| Option | Why not chosen |
|---|---|
| Project-operated APNs relay | Puts the project in the data path for every user's alerts. Incompatible with the no-project-infrastructure posture. |
| Distribute a shared APNs key to self-hosters | Anyone holding it can push to every user of every build. Unacceptable. |
| Per-deployment APNs (each Builder mints their own key for their own bundle ID) | **The right eventual design** — no relay, no shared secret, nobody in the data path. Deferred only because it requires work in the platform repository, which this PRD cannot discharge. |
| SSE while alive + on-device Alert Floor (**chosen for v1**) | Self-contained. Cost: Backend-generated alerts do not reach a suspended or terminated app, so caregiver alerting is degraded versus Android. Recorded as a forced loss. |

### 2.2 Critical Alerts

| Option | Why not chosen |
|---|---|
| Treat as a launch blocker | The entitlement is granted per Team ID on individual review, and under fork-and-build every user signs with their own personal team. Blocking on it blocks indefinitely. |
| Require every Builder to request it | Most will not obtain it, producing a userbase split across two alarm behaviours — and the people who skip the step believe they are covered. Inconsistent silent coverage is worse than a uniform documented limit. |
| `.timeSensitive` with runtime upgrade (**chosen**) | Uniform, honest, and free to upgrade if the entitlement ever appears. |

### 2.3 Distribution

Project-published binaries were rejected on two independent grounds, either sufficient. GPL-3.0-only conflicts with Apple's Developer Program License Agreement, which governs TestFlight as well as the App Store. And the Medtronic driver derives from OpenMinimed work whose copyright the project does not hold, so the project could not relicense it even if it wanted to.

Fork-and-build resolves both: the project conveys no binary and accepts no terms on anyone's behalf, and every Builder provably holds the corresponding source. It is strictly *stronger* for GPL compliance than the Android sideload model.

### 2.4 Alert sounds

Android uses the system `RingtoneManager` picker across the entire system sound library and ships no `res/raw` directory. iOS has no equivalent API — notification sounds must be bundled or in `Library/Sounds`. A bundled curated set is therefore the forced substitute, not a preference. User-imported audio with CAF transcoding was considered and deferred: it adds a failure mode to an alarm path, and it restores a capability Android delivers by a mechanism that does not exist here.

---

## 3. Provenance and licensing constraints

### 3.1 Tandem — studied, not ported

`jwoglom/pumpX2` and `jwoglom/controlX2` (MIT, James Woglom) are **architectural reference only**. The Swift driver is an independent implementation; no code is imported. pumpX2 test vectors are used to validate parser and handshake correctness, which is a use of test data, not of implementation.

### 3.2 Medtronic — a direct port, under explicit permission

The Medtronic driver derives from OpenMinimed work (GPL-3.0), relied on under explicit relicensing permission from palmarci (Pál Marci). Android consumes `org.openminimed:javasake` as a Maven artifact; Swift cannot link a Java library, so iOS needs a clean-room reimplementation of the SAKE state machine.

**Standing constraint:** the project does not own that copyright. Any future project-published binary would require permission from every holder — which is a second, independent reason the fork-and-build model is not merely convenient but load-bearing.

### 3.3 The manufacturer framing

`MEDICAL-DISCLAIMER.md` currently reserves its *"users become the manufacturer of their own personal medical device"* framing for third-party forks that add device control. Under fork-and-build, **every iOS user compiles their own binary**, so that sentence arguably now describes all of them. Flagged for counsel before the build instructions publish. Cheap to fix now; expensive later.

---

## 4. Reference — how docs reach the website

Out of scope for the PRD (the `website` repository owns it), recorded here so nobody re-derives it.

`lumose-health/website` is a Fumadocs/Next.js site on Cloudflare Pages. `scripts/sync-docs.ts` runs as `prebuild`, reads `docs-sources.yaml`, downloads each registered source repository's tarball, and extracts its `docsPath` into `content/docs/<targetPath>/`. Each source gets its own namespace, so basenames never collide between repositories.

Three behaviours worth knowing when authoring pages:

- The target directory is **deleted and replaced** on every sync, so a source repository is the sole author of its namespace.
- `defaultOpen` is injected website-side; the script's own comment says not to push it back into a source repo's `_meta.json`.
- `rewriteLinks` rewrites `](../FILE.md)` to a GitHub blob URL, but **only** for filenames listed in that source's `externalLinks`, and it keys on **filename**, not resolved path.

The PRD sidesteps all three by requiring one in-repo rule instead: relative links stay inside `docs/`, and every link that leaves it is absolute. That holds regardless of how the site is configured.

**Observation, not a requirement:** as of 2026-08-01 `docs-sources.yaml` registers only `GlycemicGPT/GlycemicGPT` → `platform/` and `GlycemicGPT/.github` → `about/`. `android-unofficial` ships `notify-docs-update.yml` and dispatches on every docs change, but has no entry. Worth a look in the `website` repository if its documentation is expected to be live.

---

## 5. Deliberately not carried over

Verified absent from the Android client, and therefore **not** hidden scope inside the parity mandate:

- **No localization.** `strings.xml` holds 6 strings; all other copy is inline in Kotlin. A single `values/` directory.
- **No deep links,** no `ACTION_VIEW` intent filters, no `AppWidgetProvider`, no `TileService`, no `ShortcutManager`. Widget and complication entry points on iOS are net-new scope, not a port.
- **`plugins/example` is not a built module.** It is absent from `settings.gradle.kts`. Promoting the Simulated Driver to a shipped, first-class target is new work, not a port.
