# Currency Review — ARCHITECTURE-SPINE.md

**Artifact:** `_bmad-output/planning-artifacts/architecture/architecture-ios-unofficial-2026-08-03/ARCHITECTURE-SPINE.md`
**Lens:** was every committed decision web-researched or reality-checked, rather than asserted from training data?
**Review date:** 2026-08-03. All web evidence re-fetched on this date; all Android evidence read from source at `android-unofficial` @ `59e6810`.
**Method:** read the spine and `.memlog.md`, then independently re-checked *every* claim the memlog marked "VERIFIED ON THE WEB" against primary sources (upstream `Package.swift` at the exact tag, Apple technote payloads, GitHub release APIs), and checked the Android reference claims against the actual Kotlin/Gradle source rather than the spine's summary.

---

## Verdict

**Qualified pass with two must-fix findings.**

The spine is unusually well-researched for its class. Its single most load-bearing and most easily-gotten-wrong claim — AD-8's assertion that `CryptoBoringWrapper` exists, has exactly the primitives EC-JPAKE needs, and is *not* consumable by an external package — is **correct in every particular**, verified against `apple/swift-crypto` at tag `4.5.1` and again at `5.0.0-beta.2`. The memlog is a real memlog: it records checks that were actually performed, and the dates in it hold up.

But two committed decisions do not survive re-checking, and both were asserted rather than verified:

1. **AD-6 / Stack: "SQLCipher — via GRDB SPM package trait" is wrong.** There is no package trait. GRDB's own README at the pinned version says you must *fork GRDB and edit `Package.swift`*. This silently adds a **second** maintained upstream fork to a project that already commits to one (AD-8), in a distribution model where every Builder inherits both.
2. **AD-8's conformance test does not exist and cannot be written as specified.** The Android repo has **zero** JPAKE known-answer vectors. The named test file is seven tests of which the substantive one is a randomized round-trip against a second instance of the same Kotlin class, seeded from live `SecureRandom`. The stated "canary for an upstream rebase" has nothing to fire on.

A third finding is a genuine 2026-only staleness that no amount of care in 2024 would have caught: **Apple changed Bluetooth state-restoration relaunch rules in iOS 26**, and AD-11 rests entirely on the pre-26 behaviour.

---

## Counts by status

| Status | Count |
|---|---|
| VERIFIED | 14 |
| STALE | 5 |
| WRONG | 4 |
| UNVERIFIABLE | 1 |
| **Total claims assessed** | **24** |

---

## Findings

### F-1 — WRONG — "SQLCipher via GRDB SPM package trait" (Stack table; AD-6)

**Claim.** Stack table: `SQLCipher | via GRDB SPM package trait`. Memlog: *"GRDB+SQLCipher was UNBLOCKED in Feb 2026 via SPM package traits, shipped in v7.10.0."*

**Evidence (2026-08-03).**

- `https://raw.githubusercontent.com/groue/GRDB.swift/v7.11.1/Package.swift` — **contains no `traits:` array at all.** What it contains is a commented-out recipe:

  ```swift
  // GRDB+SQLCipher: Uncomment those lines
  //dependencies.append(.package(url: "https://github.com/sqlcipher/SQLCipher.swift.git", from: "4.11.0"))
  //cSettings.append(.define("SQLITE_HAS_CODEC"))
  //swiftSettings.append(.define("SQLITE_HAS_CODEC"))
  //swiftSettings.append(.define("SQLCipher"))
  ```
  plus `// GRDB+SQLCipher: Delete the GRDBSQLite library`, `// GRDB+SQLCipher: Delete the GRDBSQLite target`, `// GRDB+SQLCipher: Uncomment the GRDBSQLCipher target`.

- `https://raw.githubusercontent.com/groue/GRDB.swift/v7.11.1/README.md`, line 4592, verbatim:
  > **"To use SQLCipher with the Swift Package Manager, you must fork GRDB, and modify `Package.swift`. Instructions are in the file itself, in comments that contain 'GRDB+SQLCipher'."**

- Maintainer's own release announcement, Swift Forums, **2026-02-15** (`forums.swift.org/t/grdb-v7-10-0-android-linux-windows-and-sqlcipher-spm/84754`): users must *"fork GRDB, and modify `Package.swift`"*; *"The situation of GRDB+SQLCipher with SPM is much better, but still not all sunshine and roses."* The two named blockers are **(a) Xcode's lack of package-trait support** and (b) SPM downloading unnecessary dependencies. Traits are the thing that is **missing**, which is precisely why the mechanism is a fork.

**What is true.** GRDB **7.10.0 (Feb 2026)** did unblock GRDB+SQLCipher on SwiftPM — the memlog's headline conclusion, and its rejection of "bind GRDB 6", are both correct and were a good catch. Only the *mechanism* is mis-stated.

**Why this matters, not a nitpick.** The mechanism determines cost. A trait is a one-line opt-in with zero maintenance. A fork means:
- a **second** long-lived fork alongside AD-8's `swift-crypto` fork, each needing rebase-on-upstream discipline;
- every Builder in the Loop-style fork-and-build distribution model inherits and must trust both forks;
- AD-3's "the graph is asserted by a CI check over the resolved package manifest" now has to assert over a manifest that points at two project-controlled forks — the check gets weaker exactly where supply-chain risk gets higher;
- Xcode-side trait support is still incomplete as of Xcode 26.4 beta (multiple 2026 reports of the resolver ignoring traits), so "wait for traits" is not a near-term escape.

**Fix.** Change the Stack row to `SQLCipher — GRDB fork with the vendor's GRDB+SQLCipher manifest edit; depends on sqlcipher/SQLCipher.swift 4.11+`. Add an explicit invariant covering **fork governance for both forks** (pin policy, rebase cadence, who verifies, what CI proves about the delta). Right now AD-8 governs one fork and nothing governs the other.

---

### F-2 — WRONG — AD-8's conformance test has no vectors to run against

**Claim.** AD-8: *"A conformance test asserts byte-for-byte agreement with the Kotlin implementation over its existing vectors and is the canary for an upstream rebase."* Memlog: *"JpakeAuthenticatorTest.kt as the vector suite."*

**Evidence (Android source, read 2026-08-03).**
`android-unofficial/plugins/shipped/tandem/src/test/java/com/glycemicgpt/mobile/ble/auth/JpakeAuthenticatorTest.kt` — 204 lines, **7 `@Test` methods, zero fixed known-answer vectors**. Six are state-machine and error-path tests. The seventh, `full JPAKE handshake with simulated server`, constructs `EcJpake(EcJpake.Role.SERVER, codeBytes)` — *a second instance of the same Kotlin class* — and seeds nonces from `ByteArray(8).also { SecureRandom().nextBytes(it) }`. `EcJpake` additionally draws from a default `SecureRandom()` for every ephemeral scalar and for the 16-byte blinder in `mulSecret`. **Every run produces different bytes.** There is no `src/test/.../ble/crypto/` directory at all — the crypto primitives have no dedicated unit tests.

By contrast the same repo *does* have real captured KATs elsewhere — `MedtronicSakeSessionTest.kt:139-160` (`PUMP_KEYDB_HEX` + six 20-byte messages from a captured 780G pairing, replayed through a `QueuedRng`), `HmacHelperTest.kt`, `Crc16Test.kt`. So the spine's author plausibly generalised from those to Tandem without opening the Tandem test file.

**Consequence.** AD-8's canary is inert. The one invariant that would catch a silently-broken rebase of a **pairing handshake on a medical device** cannot be implemented from the artifact as written.

**Fix — what *is* assertable from this repo today, without new Android work:**
- **Frame geometry as fixed constants:** round 1 = 330 bytes split 165/165 at a hardcoded offset, round 2 = 165 bytes, 1a cargo = 2-byte LE `appInstanceId` + 165-byte challenge, round-3 cargo 18 bytes, round-4 cargo 50 bytes (`nonce` at 2..10, `hashDigest` at 18..50).
- **Deterministic sub-primitives with public KATs:** `Hkdf.build` against RFC 5869 vectors, HMAC-SHA256, CRC16, `Packetize`.
- **A seeded cross-language interop harness** — genuinely possible, because Kotlin's `EcJpake` accepts `rand: SecureRandom` as a constructor parameter. The Swift side needs an equivalent injectable-RNG seam, and the RNG draw *order* must match exactly (`genKeyPair` then `mulSecret`'s 16-byte blinder). **This harness does not exist and is net-new work on both sides.** AD-8 should say so.

**Also worth binding, from the same source read — four wire-format traps AD-8 is silent on:**
1. Points are **uncompressed** 65-byte encodings. The Kotlin constant is named `ENCODED_COMPRESSED = false` — the name is a trap.
2. Scalars are **fixed-width 32 bytes**. Kotlin's own comment: minimal-length encoding caused a *"rare (~1.6%) `ArrayIndexOutOfBoundsException`"* because the 1a/1b split is at a hardcoded offset. A Swift `BigInt`-style minimal encoding reproduces that intermittent ~1.6% pairing failure. This belongs in AD-5's family of "cannot hold an invalid value" invariants.
3. Identity strings are literal `"client"` / `"server"`, length-prefixed **uint32 BE** inside the ZKP hash; points are also uint32-BE length-prefixed.
4. `role == SERVER` emits a curve-ID prefix in round 2 (`type=3` named_curve, uint16 BE id 23). **iOS is the CLIENT** and must parse and reject a mismatch.

---

### F-3 — STALE — AD-11 predates Apple's iOS 26 change to state-restoration relaunch rules

**Claim.** AD-11: *"`CBCentralManager` and `CBPeripheralManager` are configured with restoration identifiers, and restoration is the only relaunch mechanism any coverage claim may rest on."*

**Evidence — Apple TN3115, "Bluetooth State Restoration app relaunch rules"** (fetched 2026-08-03 via `developer.apple.com/tutorials/data/documentation/technotes/tn3115-...json`; the technote is the live replacement for QA1962, which is dated **2017-09-08**):

| App or device state | Relaunched? |
|---|---|
| App suspended in memory | activated without relaunch |
| **App removed from memory** | **Yes** |
| **App crashed** | **Yes** |
| App Force Quit by the user | **No** (note 5) |
| Bluetooth power toggled (Settings) | **No** |
| Control Center Bluetooth button toggled | **Yes** (note 5) |
| Airplane Mode toggled | **Yes** (note 3, note 5) |
| **Device restarted** | **Yes** (note 4 — not until first unlock if a passcode is set) |

> **Note 5: "Starting in iOS 26 and iPadOS 26, only apps that use AccessorySetupKit to setup Bluetooth accessories will be relaunched."**

**Assessment, split:**

- **The core of AD-11 is VERIFIED.** Restoration genuinely does relaunch a *terminated* app — "app removed from memory: Yes", "app crashed: Yes", "device restarted: Yes". The spine is right to treat this as the only load-bearing path and right to demote `BGTaskScheduler` and background `URLSession`. That is a correct and non-obvious call.

- **The version envelope is STALE.** Note 5 attaches to three rows. On **iOS 26+**, an app that does not use **AccessorySetupKit** is **not** relaunched after a Control Center Bluetooth toggle or an Airplane Mode toggle — both routine user actions that previously produced a relaunch. The deployment floor is iOS 17.0 and current shipping iOS is 26.x, so this project's supported range **straddles the behaviour change**: identical code, identical user action, different coverage outcome depending on the user's OS. A Coverage Claim (SI-6) that is version-dependent in a way the architecture never names is exactly the "claiming coverage the system cannot deliver" failure AD-10 and AD-11 exist to prevent.

- **AccessorySetupKit appears nowhere** in the spine, the memlog, or the PRD. In 2026 it is no longer an optional nicety for a BLE-accessory app — per note 5 it is the gate on relaunch in three scenarios. Whether ASK is *usable* here (it constrains discovery to declared accessories via `ASDiscoveryDescriptor`, changes the pairing UX, and interacts poorly with a two-vendor open driver catalogue) is a real architectural question that was never asked. Adopting it may well be the wrong answer — but the decision was not made.

- **`CBPeripheralManager` is named without its constraint.** TN3115's closing rule: relaunch happens *"if and only if"* the app is waiting on a specific Bluetooth event — *"and for peripheral apps, actively advertising."* iOS background advertising is severely degraded (no local name, service UUIDs relegated to the overflow area, discoverable only by iOS devices explicitly scanning for those UUIDs). This is load-bearing for Medtronic specifically: in the Android reference the **phone is the BLE peripheral / GATT server** (`DeviceType.MOBILE_APPLICATION`; `AndroidMedtronicPeripheral.kt` advertises a GATT server). That topology is close to non-portable to iOS as-is, and AD-11 mentions `CBPeripheralManager` as though it were symmetric with `CBCentralManager`.

**Fix.** Add to AD-11: the TN3115 table as the authority; an explicit statement of what a non-ASK app loses on iOS 26+; a decision (adopt / reject with reason) on AccessorySetupKit; and the background-advertising constraint on any peripheral-role design. The "Deferred" table's `Medtronic transport viability` row should name the peripheral-role problem, not just the transport.

---

### F-4 — VERIFIED — AD-8's decisive `CryptoBoringWrapper` claim, in full

Re-checked independently against upstream source at the exact tag on 2026-08-03. **Every part holds.**

| Sub-claim | Result | Evidence |
|---|---|---|
| `swift-crypto` 4.5.1 is current | **VERIFIED** | `api.github.com/repos/apple/swift-crypto/releases/latest` → `tag_name: "4.5.1"`, `published_at: 2026-07-16T12:31:33Z`. Latest **stable**. |
| Target `CryptoBoringWrapper` exists | **VERIFIED** | Present in `Package.swift` @ `4.5.1`, depends on `CCryptoBoringSSL` + `CCryptoBoringSSLShims`. |
| It exposes EC point arithmetic | **VERIFIED** | `Sources/CryptoBoringWrapper/EC/EllipticCurvePoint.swift` @ `4.5.1`: `package struct EllipticCurvePoint: @unchecked Sendable`, with `add`, `multiply`, `invert`, `subtract` (plus mutating/consuming variants), `withPointPointer`, `affineCoordinates`. |
| It exposes arbitrary-precision integers | **VERIFIED** | `Sources/CryptoBoringWrapper/Util/ArbitraryPrecisionInteger.swift` @ `4.5.1`: `package struct ArbitraryPrecisionInteger: @unchecked Sendable`. |
| `FiniteFieldArithmeticContext` exists | **VERIFIED** | `Sources/CryptoBoringWrapper/Util/FiniteFieldArithmeticContext.swift` @ `4.5.1`: `package class FiniteFieldArithmeticContext: @unchecked Sendable`. |
| **NOT consumable by an external package** | **VERIFIED, doubly** | (a) `products:` @ `4.5.1` is exactly `.library("Crypto")`, `.library("_CryptoExtras")`, `.library("CryptoExtras")` — `CryptoBoringWrapper` is in **none** of them; (b) every needed symbol is `package` access, which is scoped to the *defining* package, so even adding a product would expose an empty module. |
| Still true on the 5.0 line | **VERIFIED** | `Package.swift` @ `5.0.0-beta.2`: same three products (`CCryptoBoringSSL` only inside a commented-out symbol-mangling block). Unchanged. |
| CryptoKit exposes no EC point arithmetic | **VERIFIED** | `developer.apple.com/documentation/cryptokit/p256` — `P256` has exactly two nested types, `P256.Signing` and `P256.KeyAgreement`. No point arithmetic, no bignum. |
| No production-grade Swift P-256 low-level EC library | **VERIFIED (unchanged)** | `swift-secp256k1` is the wrong curve; `EllipticCurveKit` self-declares as not production-ready. Re-searched 2026-08-03; nothing new. |

**Memlog nit — STALE:** the memlog states *"`Package.swift` exports ONLY `.library(name: Crypto)`."* There are **three** products. The conclusion is unaffected (`CryptoBoringWrapper` is in none of them), but the recorded evidence is more precise than the source supports, and a re-checker who trusts the memlog verbatim would find a discrepancy and be unsure which way it cuts.

---

### F-5 — STALE — AD-8 under-states the fork delta, and never mentions package-identity collision

**Claim.** AD-8: *"The maintained delta is a product declaration and an access-level change — **no cryptographic code is authored or vendored.**"*

The headline is **correct and is the right call** — BoringSSL's constant-time arithmetic stays; nothing is hand-rolled. The rejections logged in the memlog (hand-rolled P-256, vendored C EC, third-party Swift EC) are all sound. But three things follow from the source that the artifact does not account for:

1. **"An access-level change" (singular) is at least four files.** `package` → `public` across `EllipticCurvePoint.swift`, `ArbitraryPrecisionInteger.swift`, `FiniteFieldArithmeticContext.swift`, `EC/EllipticCurve.swift`, at minimum. Each is a rebase conflict surface on every upstream bump.
2. **Making `EllipticCurvePoint` public may drag `CCryptoBoringSSL` public with it.** Its `package` surface includes `withPointPointer` and initialisers that traffic in BoringSSL C pointer types. A `public` API that references types from a non-exported C target does not link for an external consumer. Either the shim widens to `CCryptoBoringSSL` — a much larger and uglier delta — or the fork must add a narrow Swift-only façade, which *is* newly authored code sitting between the caller and the crypto. That contradicts the sentence's plain reading and should be resolved before the decision is treated as closed.
3. **SPM package identity.** A fork of `apple/swift-crypto` collides on identity with any other node in the graph that depends on upstream `swift-crypto`. Today's graph looks clear, but a future dependency (anything on the `swift-nio` / `swift-asn1` axis) would produce an unresolvable graph. The spine's Consistency Conventions and AD-3's CI check should own this constraint explicitly.

**Recommend** a spike that produces a *building* fork with an external consumer importing `EllipticCurvePoint` before AD-8 is treated as settled. AD-8 is currently the only decision in the spine with no `[ASSUMPTION]` marker despite resting on an unbuilt integration.

---

### F-6 — STALE — the iOS 17 / watchOS 10 floor rationale is reasoned against the wrong comparison

**Claim.** Spine Stack: `iOS / watchOS floor | 17.0 / 10.0`, binding PRD NFR-1. PRD `prd.md:4765-4783` justifies it against **iOS 18 / watchOS 11**, and leaves an unresolved `[ASSUMPTION]` at line 4780 to verify against Apple's published lists.

**Does the floor buy what the PRD says?** Row by row (verified 2026-08-03):

| PRD row | Stated min | Actual | Result |
|---|---|---|---|
| Current magnification gesture (`MagnifyGesture`), simultaneous with drag | iOS 17 | `MagnifyGesture` is iOS 17.0+ | **VERIFIED** |
| Watch Smart Stack widgets, no face configuration | watchOS 10 | Smart Stack shipped in watchOS 10 (Sept 2023) with third-party WidgetKit widgets | **VERIFIED** |
| Observation-based view state, no back-compat shim | iOS 17 / watchOS 10 | `@Observable` / the Observation framework is iOS 17 / watchOS 10 | **VERIFIED** |
| **WidgetKit-only complication story, no legacy complication framework** | watchOS 10 | **watchOS 9** (WWDC22) introduced `accessoryCircular` / `accessoryCorner` / `accessoryRectangular` / `accessoryInline` and deprecated ClockKit | **WRONG — over-attributed by one major version** |

So three of four rows hold; the WidgetKit-complication row does not justify the floor, though **Smart Stack and Observation independently do**, so the floor number itself is unaffected. Fix the row rather than the floor.

**Does it exclude devices?** Yes, and correctly: iOS 17 excludes iPhone 8 / 8 Plus / X (A11 and earlier); watchOS 10 excludes Apple Watch Series 3 and earlier. Both are long past.

**Why the rationale is stale.** The PRD's trade-off — *"raising the phone floor to iOS 18 excludes no iPhone that iOS 17 supports, so it buys nothing"* — was written against the wrong pair. As of Aug 2026 the live comparison is against **iOS 26 / watchOS 26** (shipped Sept 2025):
- **iOS 26 dropped iPhone XS, XS Max and XR** (all A12). iOS 18 is terminal for those devices.
- **watchOS 26 requires Series 6 or later**, SE 2nd gen or later, or Ultra — i.e. it drops Series 4, 5 and SE 1st gen, which is what the PRD *predicted* of watchOS 11.

The floor therefore buys **more** than the PRD claims: it retains an entire A12 iPhone cohort and three Apple Watch generations that a 2026-current floor would exclude. That strengthens the decision — but the reasoning as recorded reads as if written before Sept 2025, and the `[ASSUMPTION]` at `prd.md:4780` is still open. A 2026 reader will notice.

**Related, and stale by Apple mandate:** the PRD pins the Simulator runtime at **iOS 18 / watchOS 11** (NFR-3), which the spine inherits. Since **2026-04-28**, Apple requires App Store Connect uploads to be **built with Xcode 26 or later against the iOS 26 / watchOS 26 SDK** (`developer.apple.com/news/upcoming-requirements/`). Xcode 26 supports deployment targets down to iOS 15 / watchOS 8, so **the 17.0 / 10.0 floor remains buildable — VERIFIED**. But the pinned toolchain and Simulator matrix are behind a requirement that is already in force, and NFR-1's demand for a Simulator destination *at the floor* depends on iOS 17.0 / watchOS 10.0 runtimes still being downloadable into Xcode 26 — which should be confirmed on a real machine, not assumed.

---

### F-7 — STALE — "Swift 6 language mode, strict concurrency complete" is 2024 framing

**Claim.** AD-4 and Stack: `Swift | 6.x (language mode 6, strict concurrency complete)`.

**Evidence.** Swift **6.3** released **2026-03-24** (`swift.org/blog`); it is the current release, with 6.2 before it. Swift 6 language mode and data-race safety are real, current, actively developed, and entirely appropriate to bind for a project of this kind. **The decision is right.** Three staleness notes:

1. **`-strict-concurrency=complete` is redundant under language mode 6** — it is the Swift 5-mode *migration* flag; language mode 6 implies complete checking. Naming both reads as if written before the 6.0 release and invites a build-settings cargo cult.
2. **Swift 6.2 (Sept 2025) changed the defaults conversation.** `defaultIsolation: MainActor`, `nonisolated(nonsending)`, and the "approachable concurrency" setting mean a new Swift project in 2026 must make an explicit, project-wide choice about default actor isolation. The spine is silent. For this architecture the choice is consequential and non-obvious: `MainActor`-by-default is the ergonomic win for `AppFeature` / `WatchFeature`, and is actively wrong for `SafetyCore`, `DomainCore`, `Persistence` and every Driver actor at the Core Bluetooth edge. That per-module split is exactly the kind of thing a spine should fix and CI should assert.
3. **Version floor unstated.** "6.x" spans 6.0 through 6.3 with materially different concurrency semantics. Given AD-3's CI check over the resolved manifest, a minimum `swift-tools-version` should be named. For reference, both current dependencies are at `swift-tools-version: 6.1` (`swift-crypto` 4.5.1 and GRDB v7.11.1), so 6.1 is already the effective floor.

---

### F-8 — VERIFIED — GRDB 7.11.1 is current (and binding GRDB 6 would have been the training-data error)

`api.github.com/repos/groue/GRDB.swift/releases/latest` → **`v7.11.1`, published 2026-06-18**. Tag list confirms no newer tag as of 2026-08-03 (`v7.11.1` > `v7.11.0` > `v7.10.0` > …).

The memlog's reasoning here is the model of what this review is looking for: it identified that the long-standing "SQLCipher users are stuck on GRDB 6" constraint — which is what a model would assert from pre-2026 training data — was lifted in **Feb 2026 by v7.10.0**, and bound the current version instead. **Correct call, correctly sourced.** Only the mechanism is mis-stated (F-1).

---

### F-9 — VERIFIED / UNVERIFIABLE — fastlane + match and the six-secret Loop pattern

- **fastlane is current and maintained — VERIFIED.** Latest release **2.237.0, published 2026-07-05**.
- **`match` + App Store Connect API key is not deprecated — VERIFIED.** Live fastlane docs (`docs.fastlane.tools/app-store-connect-api/`) recommend API-key auth; 2026-dated third-party guides cover key rotation in CI. Caveat worth carrying: a **Team Key** is required for provisioning endpoints — an *individual* key cannot use them, which is a common and confusing first-run failure for a Builder.
- **The six-secret Loop pattern — VERIFIED as documented, but the source is UNDATED (partially UNVERIFIABLE).** LoopDocs "Collect Secrets" (`loopkit.github.io/loopdocs/browser/secrets/`, fetched 2026-08-03) lists exactly six: `TEAMID`, `FASTLANE_ISSUER_ID`, `FASTLANE_KEY_ID`, `FASTLANE_KEY`, `GH_PAT`, `MATCH_PASSWORD`, with the `Match-Secrets` private repo auto-created on first Action run. **The page carries no "last updated" date**, so "still six in Aug 2026" rests on the page being maintained rather than on a dated assertion. Low risk, but this is the one item in the review that cannot be pinned to a date.
- **Gap:** the spine's Stack table says `fastlane + match | Builder-side signing` and stops. Since **2026-04-28** every upload must come from **Xcode 26+ / iOS 26 SDK** — which means the GitHub Actions `macos-*` runner image and its Xcode selection are now a *correctness* constraint on the Builder path, not a preference. The "Deferred / CI runner topology" row defers this; given a hard Apple deadline that has already passed, the Xcode-version pin deserves to be an invariant rather than deferred tooling.

---

### F-10 — WRONG — two Android-reference claims that shape scope

Checked against source, not the spine's summary.

**(a) "SAKE reimplementation" (Structural Seed: `Medtronic/  # SAKE reimplementation; Beta`) — WRONG.**
Android does **not** implement SAKE. `plugins/shipped/medtronic/.../sake/MedtronicSakeSession.kt` is a thin wrapper over **`org.openminimed:javasake` v0.2.0, a Maven Central dependency, GPL-3.0**, used with the author's permission (`build.gradle.kts:33-41` notes it was *"formerly vendored … now consumed"*). Two consequences the spine should carry: there is **no Swift equivalent to depend on**, so iOS faces a genuine from-scratch implementation or C/Java-to-Swift port — categorically larger than porting local Kotlin; and the reference implementation is **GPL-3.0**, which is a licensing question for any port that reads it. Neither appears in the artifact.
*Silver lining:* unlike Tandem, Medtronic **does** have real captured vectors — `MedtronicSakeSessionTest.kt:139-160` (`PUMP_KEYDB_HEX` + six 20-byte messages from a captured 780G pairing, replayed with a `QueuedRng`), duplicated at `tools/medtronic-ble-spike/.../SakeTestVectors.java`. AD-8's conformance-test idea is implementable **here**, just not for Tandem.

**(b) "Simulated / TraceReplay — shipped, not scaffolding" implies a port. Neither exists on Android.**
The Android repo has three plugin modules: `plugins/example`, `plugins/shipped/medtronic`, `plugins/shipped/tandem`. The only simulator is a **demo BGM** (`plugins/example/.../ReadingSimulator.kt`, an 80–180 mg/dL sine wave behind `DemoGlucometerPlugin`), capability `BGM_SOURCE` — **not a pump driver**. There is **no trace-replay driver**; the only "replay" in the repo is a deterministic RNG inside a throwaway spike and an aspirational comment in `RawHistoryLogEntity.kt:11`. The spine's framing — *"Simulated/ # shipped, not scaffolding"*, *"TraceReplay/ # shipped; recorded frames through the real parsers"* — is a good architectural decision, but it is **net-new scope**, not parity. Saying so protects the estimate.

**Android claims that did check out — VERIFIED:**
- Tandem pairing **is** EC-JPAKE over P-256, at `plugins/shipped/tandem/src/main/java/com/glycemicgpt/mobile/ble/crypto/EcJpake.kt` (293 lines; `CURVE_NAME = "P-256"`, `CURVE_ID = 23`, SHA-256), driven by `JpakeAuthenticator.kt` for *"Tandem pumps with firmware v7.7+"*.
- It uses BouncyCastle **1.84** (`bcprov-jdk18on`) as a **library, not via the JCE provider**, with exactly the four imports the memlog names, and performs raw point arithmetic that key agreement cannot express — `Xp1.add(Xp2).add(Xm1)`, `G.multiply(xm)`, `G.multiply(r).add(X.multiply(h.mod(ec.n)))`. **This is the fact AD-8 stands on, and it is solid.**
- `Hkdf.kt` exists alongside (RFC 5869, matching pumpX2).
- **Read-only w.r.t. the pump — VERIFIED**, supporting AD-12. `PumpDriver.kt`: *"This interface intentionally has NO methods for insulin delivery … All methods are strictly read-only status queries."* Zero repo-wide hits for `deliverBolus|setBasal|suspendPump|resumePump|InitiateBolus|BolusPermission|RemoteBolus`; `CONTROL_UUID` is subscribed-to but never written. **Nuance AD-12's CI scan must encode:** GATT **writes do occur** (pairing/JPAKE frames and read *requests*). "No therapeutic write" ≠ "no BLE write" — a scanner that greps for write characteristics naively will either false-positive on the pairing path or be tuned until it stops catching anything.
- **Coverage Claim — VERIFIED**, and AD-10 mirrors it faithfully. Android's `AlertFloorStatus` (`ServerActive | FloorWatching | FloorNotWatching(reason)`) is computed phone-side in `AlertFloorStatusProvider.kt`; `WearDataContract.kt:47-66` states *"The phone computes the coverage decision; the watch only renders it and locally times it out."* AD-10's phone-computes / watch-renders-and-decays split is an exact port. Note for AD-10's versioned payload: Android's wear contract requires reason strings to *"match the phone's `FloorNotWatchingReason` enum names exactly"* — the spine's explicit schema version is a strict improvement over that, and should say it is deliberately replacing a name-matching convention.
- **Persistence — Room 2.6.1 + SQLCipher 4.13.0** (`net.zetetic:sqlcipher-android`), `AppDatabase.kt` at **version 13**, exported schemas `1..5, 8..13`, passphrase 32 random bytes in `EncryptedSharedPreferences` (Keystore-backed). AD-6's *"no Android inheritance, start at v1"* is **not contradicted** — the Android DB is device-locally encrypted and unreadable off-device, so no migration path exists. But "no inheritance" reads stronger than the situation warrants: the v13 schema is still the best available reference for **entity shape**, and ignoring it risks drifting from field shapes the Backend contract already assumes. Suggest AD-6 say *"independent schema numbering; entity shapes reviewed against Android v13"*.

---

### F-11 — VERIFIED — remaining spot-checks

- **App Group + single-writer (AD-9):** consistent with GRDB's own guidance (`Documentation/SharingADatabase.md`, `AppGroupContainers.md` present at v7.11.1). Extensions reading a snapshot file rather than the database avoids the cross-process SQLCipher contention GRDB warns about. Sound, current.
- **Keychain class (AD-6):** `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` is real, long-standing, and is the correct class for "overnight reconnection while locked". Unchanged in 2026.
- **`swift test` on Linux for domain and Driver tests (Consistency Conventions):** plausible and newly *more* plausible — GRDB v7.10.0 (Feb 2026) added Linux support in the same release as the SQLCipher work. Note the interaction with F-1: Linux CI would consume the **fork**, so the fork is on the critical path for the required checks, not just for device builds.

---

## Summary table

| # | Claim | Status |
|---|---|---|
| F-1 | SQLCipher via GRDB **SPM package trait** | **WRONG** — no trait exists; fork + manifest edit required |
| F-2 | AD-8 conformance test over "existing vectors" from Kotlin | **WRONG** — no JPAKE vectors exist; test is randomized round-trip |
| F-3 | AD-11 Core Bluetooth restoration as sole relaunch path | **VERIFIED core / STALE envelope** — iOS 26 note 5, AccessorySetupKit unaddressed |
| F-4 | `CryptoBoringWrapper` exists, has EC point + bignum, not externally consumable | **VERIFIED** (4.5.1 and 5.0.0-beta.2) |
| F-4b | Memlog: "exports ONLY `.library(Crypto)`" | **STALE** — three products; conclusion unaffected |
| F-5 | AD-8 delta is "a product declaration and an access-level change" | **STALE** — ≥4 files, likely `CCryptoBoringSSL` exposure, identity collision unaddressed |
| F-6 | iOS 17 / watchOS 10 floor buys what the PRD says | **3 of 4 VERIFIED; WidgetKit-complication row WRONG (watchOS 9)**; rationale **STALE** vs iOS 26 / watchOS 26 |
| F-7 | Swift 6 language mode, strict concurrency complete | **VERIFIED real & appropriate / STALE framing** — Swift 6.3 current; 6.2 default-isolation choice unmade |
| F-8 | GRDB.swift 7.11.1 current | **VERIFIED** (2026-06-18, latest) |
| F-9 | fastlane + match; six-secret Loop pattern | **VERIFIED** (fastlane 2.237.0, 2026-07-05) / LoopDocs page **UNDATED** |
| F-10a | Medtronic "SAKE reimplementation" | **WRONG** — external GPL-3.0 Maven dependency, not local code |
| F-10b | Simulated / TraceReplay Drivers as ports | **WRONG** — neither exists on Android; net-new scope |
| F-11 | swift-crypto 4.5.1 current | **VERIFIED** (2026-07-16; 5.0.0-beta.2 in beta — review the pin) |

---

## Recommended actions, ordered

1. **Correct the SQLCipher mechanism** in the Stack table and AD-6, and add a fork-governance invariant covering **both** forks (pin, rebase cadence, CI proof of the delta, Builder trust story). — *F-1*
2. **Rewrite AD-8's conformance clause** to what is actually assertable today: frame-geometry constants, RFC 5869 / HMAC / CRC16 KATs, and a **net-new seeded interop harness** requiring an injectable-RNG seam on both sides. Bind the four wire-format traps (uncompressed points, fixed-width 32-byte scalars, uint32-BE identity prefixes, SERVER curve-ID prefix). — *F-2*
3. **Bring AD-11 to 2026:** cite TN3115, state what a non-ASK app loses on iOS 26+, make an explicit AccessorySetupKit decision, and add the background-advertising constraint on any `CBPeripheralManager` role. — *F-3*
4. **Spike the swift-crypto fork to a building external consumer** before treating AD-8 as closed; resolve whether `CCryptoBoringSSL` must also be exported. Mark AD-8 `[ASSUMPTION]` until then. — *F-5*
5. **Make the Swift concurrency decision explicit:** name a minimum toolchain (6.1 is already the effective floor from both dependencies), drop the redundant `strict-concurrency=complete`, and fix default actor isolation **per module**. — *F-7*
6. **Fix the WidgetKit-complication floor row (watchOS 9, not 10)** and re-argue the floor against iOS 26 / watchOS 26 — the decision gets *stronger*, and the open `[ASSUMPTION]` at `prd.md:4780` closes. — *F-6*
7. **Reclassify Simulated and TraceReplay as net-new**, and rewrite the Medtronic seed comment to reflect an external GPL-3.0 dependency with no Swift equivalent. — *F-10*
8. **Promote the Xcode-version pin out of "Deferred"** — the Xcode 26 / iOS 26 SDK upload requirement has been in force since 2026-04-28. — *F-9*

---

## What the memlog got right

Worth recording, because this review's lens is adversarial by construction and the base rate here was good. The memlog shows evidence of **actual verification, not recall**, in four places where training-data assertion was the likely failure and was avoided:

- Catching that **GRDB 6 + SQLCipher** was the stale answer and that v7.10.0 (Feb 2026) changed it. This is the exact error the lens exists to find, and it was pre-empted.
- Establishing the **`CryptoBoringWrapper` access-level and product situation** from the manifest and source rather than assuming, and correctly concluding that a fork is the only route.
- Confirming **CryptoKit exposes no EC point arithmetic** rather than hoping it did.
- Surveying third-party Swift EC options and **correctly rejecting all of them** for the right reasons.

The failures above are concentrated in claims the memlog does **not** cover: the SQLCipher *mechanism* (recorded as a conclusion without the manifest being opened), the Tandem *test file* (generalised from other test files in the repo), the Medtronic *dependency* (assumed local), and the two areas with **no memlog entry at all — AD-11 (background execution) and AD-15**. AD-11 is the spine's second-most load-bearing decision after AD-8 and is the one that moved under Apple's feet in iOS 26. **The pattern is clean: what was checked held; what was asserted did not.**
