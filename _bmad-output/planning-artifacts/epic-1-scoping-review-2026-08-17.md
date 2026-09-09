# Epic 1 scoping review — 2026-08-17 (PM, standard pass)

Context: run during the GitHub outage hold; 1-1 merged, 1-2 at PR #4 (awaiting outage
resolution + the maintainer's protected-path merge), 1-3 drafted/parked. This review scopes the
remaining stories so each dispatches cleanly. No new stories dispatched; no scope
changed without the maintainer — items marked AMEND are recommendations applied at
story-creation time.

## Protected-path map (merge authority planning)

| Story | Protected? | Why |
|---|---|---|
| 1.2 | YES (the maintainer merges) | defines safety constants |
| 1.6 | YES (the maintainer merges) | adds GRDB dependency (Package.swift dep change) + numbered data migrations |
| 1.9 | YES (the maintainer merges) | adds pinned swift-crypto fork dependency; pairing auth/crypto |
| all others | No | PM merge authority applies if gates/evidence clean |

## Story-by-story

- **1.3 Freshness (drafted, sonnet/high):** ready; blocked only on 1-2 merge.
- **1.4 Driver Catalog + Capability set (opus/high):** two spec bugs to fix at
  creation: (a) ACs cite "iOS Gate Required Check" and "CI symbol scan" — no CI
  exists until epic 8; recast as LOCAL guard scripts (symbol scan over Driver
  targets, manifest-dependency assertion) that epic 8 later wires into CI, same
  pattern as 1.2's guards. (b) "Drivers screen lists every Driver" is UI — no UI
  target until 1.13; AMEND: split the screen AC into the settings/UI phase (1.19
  or 1.13 follow-up), keep 1.4 to DriverAPI + catalog + guards + tests.
- **1.5 Simulated Driver (sonnet/high):** clean; depends on 1.4. Simulator-friendly
  by design. Compile-time exclusion (not #if DEBUG) per AD-17 — gate: build matrix
  proof both with/without the target included.
- **1.6 Encrypted store (opus/high, PROTECTED):** GRDB 7.11.1 pinned; forward-only
  migrations from v1; Data Protection class AC is device-behavior — unit-verifiable
  parts (schema, invariant rejects, retention bounds) gate locally; the protection
  class is asserted via attribute check in tests where the simulator allows, else
  documented as device-validation debt. Epic-1-only tables — watch scope creep.
- **1.7 Trace-Replay Driver (sonnet/high):** VERIFY at creation that de-identifiable
  source traces exist (Android repo or captures); if none exist yet this story needs
  a synthesis step — do that check before stamping gates.
- **1.8–1.11 Tandem BLE (opus; 1.9 opus/xhigh + heavy review):** Core Bluetooth is
  absent in the simulator. Scope each as: full logic implementation behind an
  injectable transport (CB wrapper protocol), unit/KAT/trace gates locally, and an
  EXPLICIT validation-debt entry: live-radio behaviors (scan aging, restoration
  relaunch, background reconnect, real pump handshake) verified with the maintainer + hardware
  later. 1.9's handshake must reproduce 1.1's vectors byte-for-byte — that IS
  unit-gateable. 1.10's restoration/backgrounding semantics are the classic
  subtle-BLE-concurrency profile (CLAUDE.md would say Fable; budget rule → opus +
  flag, review escalation to fable available after a failed cycle). Keychain
  accessibility (SI-10) unit-assertable via attribute constants.
- **1.12 Driver selection persistence (opus/high):** pure logic, deterministic
  slot derivation, well-specified; depends on 1.4. Good autonomous candidate.
- **1.13 Home dashboard (opus/high):** FIRST UI story — bootstraps Apps/ shell +
  AppFeature target + simulator test gates. Before stamping: verify an
  `xcodebuild test -destination 'iOS Simulator'` gate actually runs on this Mac
  (Xcode 26.6 + iOS 26.5 sims installed; orca emulator flow available for visual
  validation). Expect this story to be the slowest gate; consider splitting shell
  bootstrap from hero card if cycle 1 struggles.
- **1.14–1.16, 1.18, 1.19 (sonnet/high):** contained UI stories on the 1.13 shell;
  standard tier with the dev-loop gates as net.
- **1.17 First-run onboarding (opus/high):** PRD's declared thin area; the story
  itself mandates flagging invented design — keep the `[ASSUMPTION]` AC verbatim
  and require the Dev Agent Record to list every invention for the maintainer's review.
- **1.20 Snapshot record + Live Activity (opus/high):** defines the AD-9 shared
  snapshot contract in SafetyCore (schema version, atomic write-temp-rename, sole
  writer) — epic-3 consumes it, so the record's shape gets cross-provider review
  attention; Live Activity presentation is partially simulator-verifiable, rest is
  validation debt.

## Sequencing (unchanged from epic order, with dependency notes)

1.3 → 1.4 → {1.5, 1.7} → 1.6 → 1.12 → 1.8 → 1.9 → 1.10 → 1.11 → 1.13 →
{1.14, 1.15, 1.16, 1.18} → 1.17 → 1.19 → 1.20.
(1.5/1.7 parallelizable after 1.4 in principle; flow stays one-at-a-time.)

## Standing flow rules reaffirmed

- One story in flight; no pushes/dispatches during the GitHub outage.
- CI-referencing ACs are recast as local guards until epic 8 exists (recurring
  spec-bug class — caught in 1.2 and 1.4 now).
- Physical-surface stories carry explicit validation-debt entries; simulator
  validation via orca emulator where possible; live-radio/device validation is
  maintainer-run.
- Guard tooling stays interim awk until 8-6 (swift-syntax) — do not re-litigate
  per story; xfail ledger in `scripts/guards/safety_guards.sh` is the record.
