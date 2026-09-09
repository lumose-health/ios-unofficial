# Adversarial review: Driver catalog and closed Capability set (cycle 1)

- MAJOR — The Capability surface is open, not structurally closed/read-only: `DriverCapability` is a public marker and `Driver.capability(_:)` returns `any DriverCapability`, and an isolated Driver target carrying an extra `ExtraCapability.enactTherapy()` compiled and passed `driver_guards.sh` after the existential was downcast and invoked.
- MAJOR — Catalog completeness accepts descriptors that are not catalog entries: `catalog_entries.awk` treats any `targetName` line in `DriverCatalog.swift` as registration, and a fake manifest target plus a disconnected `static let FakeEntry` passed the guard while `DriverCatalog.entries` remained `[]`; the built-in positive self-test uses this same disconnected shape.
- MAJOR — Lifecycle ownership is not structural: `DriverLifecycle.init`, `init(restoring:)`, and `advance(to:)` are public, and an isolated Driver target stored its own `DriverLifecycle`, advanced it from Driver code, compiled, and passed `driver_guards.sh`.
- MAJOR — The six-port count test is bypassable by ordinary Swift formatting: an isolated seventh `public protocol ExtraSource:` with `DriverCapability` on the next line compiled and all six `CapabilitySetTests` passed because `portName(declaredIn:)` requires `protocol` and `:DriverCapability` on one source line.
- MAJOR — Fresh Safety Limits are not enforced by the API: validation is an instance method and `SafetyLimits.absolute` is public, so an isolated Driver stored `private let cachedLimits = SafetyLimits.absolute` and reused it indefinitely while compiling and passing the guard; `validationReadsLimitsFresh` only compares two explicitly chosen receiver values and proves no fresh read from the current limits source.
- MAJOR — The single failure-taxonomy regression test is formatting-vacuous: an isolated second `OtherFailure` enum with `Error` on the following line compiled and all six `DriverFailureTests` passed because `errorTypeName(declaredIn:)` only recognizes same-line conformances.
- MAJOR — Activation re-entrancy is internally inconsistent and untested: `Driver.activate()` says an already-active call is safe and that the platform transitions to `.activating` first, but `.active` forbids both `.activating` and `.active`, while `entryPointsAreRepeatable` calls `activate()` twice before the lifecycle ever reaches `.active`.

Gate evidence: `swift build --disable-sandbox`, `swift test --disable-sandbox` (130 tests), both guards, and both guard self-tests passed with module caches redirected into `.build`; an isolated added `DriverAPI` dependency correctly failed the manifest assertion, and no new `#if`/build-configuration branch was found.

VERDICT: CHANGES-REQUIRED
Reason: AD-12 and AD-16 are not structural, and the catalog, closed-set, fresh-limit, and taxonomy checks all admit compiling counterexamples.

## Cycle 2 re-review

- Original finding 1, open Capability surface — COMPILE ERROR for the original
  counterexample: an ordinary Driver import can no longer find
  `DriverCapability`. However, the replacement does not close the downcast seam.
  A Driver-defined `ExtraTherapyPort` conformed to `DoseCategoryProvider`, was
  wrapped in `.doseCategoryProvider`, extracted from `CapabilityPort`, downcast
  from `any DoseCategoryProvider` to `ExtraTherapyPort`, and its extra
  `enactTherapy()` method was invoked. The real isolated `Probe` target compiled,
  and `driver_guards.sh --root <probe-tree>` exited 0. **MAJOR:** the public enum
  merely moves the erased existential behind a case; a concrete Driver port can
  still smuggle and expose surface outside the closed six, using the same
  downcast mechanism as cycle 1 and vocabulary the deny-list does not catch.
- Original finding 2, disconnected catalog descriptor — GATE CATCH. Recreated a
  manifest `Fake` Driver target while leaving `entries == []` and appending a
  disconnected `static let fakeEntry = DriverDescriptor(targetName: "Fake", …)`.
  `driver_guards.sh` exited 1 because `Fake` was not a member of
  `DriverCatalog.entries`. The guard self-test also catches the same shape.
- Original finding 3, Driver-owned lifecycle — COMPILE ERROR under ordinary
  `import DriverAPI`: `DriverLifecycle` is not in scope. The only direct escape,
  `@_spi(DriverPlatform) import DriverAPI`, compiled, but the reconstructed Driver
  target then failed `driver_guards.sh` on the SPI-import rule. No open finding.
- Original finding 4, line-wrapped seventh port — TEST CATCH. Added a compiling
  `public protocol ExtraSource:` with `Sendable` on the following line under
  `Sources/DriverAPI/Capabilities`; `exactlySixPortsAreDeclared` failed and named
  all seven ports. No open finding.
- Original finding 5, cached Safety Limits — COMPILE ERROR for both original
  doors: `SafetyLimits.absolute` and instance `validate(mgdl:)` are inaccessible
  to a Driver. However, the new public source seam admits the equivalent cache.
  A Driver-defined `CapturedLimitsSource` stored a `let currentLimits` supplied at
  initialization and reused `source.validate(mgdl:)` indefinitely. That isolated
  Driver target compiled and `driver_guards.sh` exited 0. **MAJOR:** reading a
  protocol property on every call does not make the value fresh when a conformer
  may capture it once; the API and gates still permit exactly the stale-limit
  behavior AC 7 forbids.
- Original finding 6, line-wrapped second failure taxonomy — TEST CATCH. Added a
  compiling `public enum OtherFailure:` with `Error` on the following line;
  `exactlyOneErrorType` failed with `declared.count == 2` and named both enums. No
  open finding.
- Original finding 7, activation re-entrancy — the raw duplicate
  `activate(); activate()` call STILL COMPILES because the protocol and lifecycle
  operations are not coupled. It no longer contradicts the declared contract:
  docs now say activation is repeatable across teardown/failure but not
  re-entrant, the table refuses `.activating` from `.activating`, `.active`, and
  `.degraded`, and `aRunningDriverIsNotReactivated` plus
  `activationRepeatsAcrossTeardown` pin those exact sequences. No new severity
  under the requested contract-reconciliation criterion.

Baseline evidence: `swift build --disable-sandbox`, `swift test --disable-sandbox`
(138 tests), both guards, and both guard self-tests passed with module caches
redirected into `.build`. The cycle-1 manifest and AD-17 findings were spot-checked
only as directed.

VERDICT: CHANGES-REQUIRED
Reason: `CapabilityPort` still permits a Driver-specific downcast escape, and `SafetyLimitsSource` still permits a Driver to validate forever against captured limits.

## Cycle 3 re-review

- Original finding 1, `CapabilityPort` downcast seam — COMPILE + GATE CATCH for
  the requested counterexample. An isolated Driver target with
  `ExtraTherapyPort: DoseCategoryProvider`, `port as? ExtraTherapyPort`, and
  `enactTherapy()` compiled, while `driver_guards.sh` exited 1 on `therapy`,
  `enact`, and the concrete-type `as?`. With the consumer/downcast removed and
  the arbitrary member renamed `performStepTwo()`, the target compiled and the
  guard exited 0. The guard header states that exact residual, and
  `known-limit-arbitrary-member-on-a-driver-type` pins it as an expected PASS.
- Original finding 5, captured limits — COMPILE ERROR. Under ordinary
  `import DriverAPI`, the reconstructed `CapturedLimitsSource` cannot find
  `SafetyLimitsSource`, direct `SafetyLimitsValidator(limits:)` construction and
  `adopt(_:)` are inaccessible due to `@_spi`, and subclassing fails because the
  validator is final. The real `validationReadsLimitsFresh` test holds one
  `SafetyLimitsValidator` reference, validates under wide limits, adopts narrow
  limits, and observes rejection on the next call; adopting wide limits again
  makes the following call succeed on that same reference. No new validator
  surface permits a Driver to supply or mutate the limits.
- **MAJOR — Rule D is bypassable through a generic narrowing helper.** In an
  isolated two-target probe, a Driver target publicly returned
  `.doseCategoryProvider(ExtraPort())`; a separate consumer target implemented
  `narrow<T>(_ value: Any, to: T.Type) -> T? { value as? T }`, instantiated it
  with `ExtraPort.self`, and called `performStepTwo()`. The package compiled and
  `driver_guards.sh` exited 0 because `consumer_casts.awk` sees only the generic
  target `T`. This is a consumer downcast that reaches the arbitrary member while
  passing the rule the header says forbids it, so the stated residual bound does
  not hold.

Gate evidence: `swift build --disable-sandbox`, `swift test --disable-sandbox`
(139 tests), both guards, and both guard self-tests passed with module caches
redirected into `.build`.

VERDICT: CHANGES-REQUIRED
Reason: the captured-limits seam is closed and direct concrete casts are caught, but a compiling cross-target generic downcast still reaches the smuggled Driver surface while the guard passes.
