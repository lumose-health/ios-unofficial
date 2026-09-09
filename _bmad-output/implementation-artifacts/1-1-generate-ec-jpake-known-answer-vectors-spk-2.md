---
# linear: the Linear issue this story implements. EMPTY = local-only epic:
# the PM must NOT create or sync anything in Linear for it.
linear:
# agent = BMAD persona from _bmad/bmm/agents/ (symlinks to .agents/skills/bmad-agent-*):
# dev (default) | tech-writer | analyst | architect | ux-designer. NOTE: no qa persona
# is installed in this repo yet — validation stories route claude with the dev persona
# and SIMULATOR flows (orca emulator / serve-sim) named in the ACs.
route: {provider: claude, cli: claude, model: opus, effort: high, agent: dev, fallback: [openai/gpt-5.6-sol]}
# local_gpu: devbox-only subcontractor — on this Mac stamp red or use devin free models.
local_gpu: red
gates:
  - "python3 scripts/spk2/validate_fixtures.py"
  - "bash scripts/spk2/verify_vectors.sh"
max_cycles: 3
---

# Story 1.1: Generate EC-JPAKE known-answer vectors (SPK-2)

Status: done

<!-- Route rationale (for the maintainer, not the dev): strong tier (opus/high) because the
fixtures become the byte-level ground truth for ALL future Swift Tandem pairing
conformance tests — a plausible-but-wrong vector poisons every downstream story
(AD-8). Spec is otherwise tight and context small, so opus not fable; claude weekly
at 22% so no pool pressure. local_gpu red: delegate.sh not installed on this Mac. -->

## Story

As a maintainer,
I want known-answer vectors captured from the Android EC-JPAKE implementation,
So that the Swift handshake can be proven byte-identical instead of merely self-consistent.

## Acceptance Criteria

1. **Given** the Kotlin `EcJpake` implementation and a fixed, injected deterministic
   randomness source, **when** the round-1, round-2 and derived-secret payloads are
   captured for a full client-role handshake (against a server-role peer driven by the
   same recorded scheme), **then** they are committed as fixture files under
   `Tests/Fixtures/EcJpake/` in THIS repo, with the randomness scheme, every consumed
   random value, the curve parameters (P-256, SHA-256, ids `client`/`server`) and the
   JPAKE secret recorded alongside (AD-8).
2. The fixtures cover at least one full client-role handshake (round 1 out, peer round 1
   in, round 2 out, peer round 2 in, derived secret) **and** at least one
   malformed-input rejection case (a truncated or corrupted peer payload with the
   exception/rejection outcome recorded).
3. A fixture is only valid if it contains everything a Swift implementation needs to
   reproduce the payloads **byte-for-byte without reimplementing a JVM RNG**: the
   actual private scalars / random bytes consumed (or a complete recorded RNG output
   log), never merely a JVM `SecureRandom` seed or algorithm name.
4. The story records, in the fixture README, that `JpakeAuthenticatorTest.kt` contained
   **zero** known-answer vectors before this story (state-machine assertions, failure
   paths and a live-`SecureRandom` round-trip only — count the actual `@Test` methods
   at execution time and record the number), so nothing downstream assumes vectors that
   never existed (AD-8).
5. Regeneration is reproducible and verified by gates: `scripts/spk2/verify_vectors.sh`
   re-runs the capture from the Kotlin implementation in a **disposable git worktree**
   of the Android repo and byte-diffs the output against the committed fixtures;
   `scripts/spk2/validate_fixtures.py` structurally validates the committed fixtures
   with no Android/JVM dependency. Both exit 0 on the committed state.
6. The main Android checkout at `android-unofficial`
   is left untouched: no commits, no working-tree modifications, no leftover worktrees
   (`git -C <android> worktree list` shows only pre-existing entries afterwards).

## Tasks / Subtasks

- [x] Task 1: Deterministic capture harness (AC: 1, 3)
  - [x] Create a disposable worktree of the Android repo:
        `git -C android-unofficial worktree add <tmp-dir> HEAD`
        (work only inside it; remove it when done).
  - [x] In that worktree, add a JVM unit test (JUnit 4, same conventions as
        `JpakeAuthenticatorTest.kt`) in the `tandem-pump-driver` module that
        instantiates `EcJpake(Role.CLIENT, secret, rand)` and
        `EcJpake(Role.SERVER, secret, rand)` with a **recording/deterministic**
        `SecureRandom` (e.g. a subclass with a fixed-seed DRBG that logs every
        `engineNextBytes` output), drives the full handshake, asserts client and
        server derive identical secrets, and writes the fixture JSON to a path
        given by a system property or env var.
  - [x] The harness test never touches production sources — `EcJpake.kt` already
        exposes the `rand: SecureRandom` constructor parameter; use it.
- [x] Task 2: Capture and commit fixtures (AC: 1, 2, 4)
  - [x] Run the harness via
        `./gradlew :tandem-pump-driver:testDebugUnitTest --tests '*<HarnessClass>*'`
        and copy the emitted fixture files into `Tests/Fixtures/EcJpake/` here.
  - [x] Capture the malformed-input case (e.g. truncated round-1 payload →
        `readRound1` throws) with the input bytes and expected outcome in the fixture.
  - [x] Write `Tests/Fixtures/EcJpake/README.md`: provenance (repo, commit SHA of the
        Android worktree HEAD, harness description), the zero-prior-KATs fact with the
        observed `@Test` count, licensing lineage (implementation ported from
        `particle-iot/ecjpake-java`, Apache-2.0, Copyright 2022 Particle Industries,
        Inc.; pumpX2 MIT studied as reference — vectors are generated data), and the
        exact regeneration command.
  - [x] Commit the harness test source into THIS repo (e.g.
        `scripts/spk2/harness/EcJpakeKatGeneratorTest.kt`) so regeneration does not
        depend on uncommitted Android-repo state.
- [x] Task 3: Gates (AC: 5, 6)
  - [x] `scripts/spk2/validate_fixtures.py` — stdlib-only Python 3: fixtures parse,
        required fields present (curve/hash/ids/secret, random log, round1/round2 for
        both roles, derived secret, malformed case), hex fields decode, derived
        secrets of client and server match.
  - [x] `scripts/spk2/verify_vectors.sh` — `set -euo pipefail`; android repo path from
        `ANDROID_REPO` (default `android-unofficial`);
        creates a disposable worktree, copies the committed harness in, runs the Gradle
        test, byte-diffs regenerated fixtures against `Tests/Fixtures/EcJpake/`, always
        removes the worktree (trap on EXIT).
  - [x] Run both gates from the repo root and confirm exit 0.

## Dev Notes

### What this is

SPK-2 — a prerequisite spike gating **all** Tandem pairing work (stories 1.8–1.11).
The Swift EC-JPAKE port (later story, AD-8) must assert byte-for-byte reproduction of
these fixtures; that test is also the canary for swift-crypto fork rebases. This story
ships **fixtures + harness + gates only** — no Swift code, no SPM package, no changes
to any shipped code anywhere.

### Source material (Android repo, read-only)

- Implementation: `plugins/shipped/tandem/src/main/java/com/glycemicgpt/mobile/ble/crypto/EcJpake.kt`
  - `class EcJpake(role: Role, secret: ByteArray, rand: SecureRandom = SecureRandom())` —
    the injection seam already exists; **no production change needed or allowed**.
  - API: `getRound1()`, `readRound1(data): Int`, `getRound2()`, `readRound2(data): Int`,
    `deriveSecret()`. State checks via Kotlin `check()` → `IllegalStateException`;
    malformed payloads surface from `readPoint`/`readZkp` parsing.
  - Constants: curve `P-256`, hash `SHA-256`, ids `"client"`/`"server"`. Server writes a
    curve id in round 2; client reads it — capture both directions.
  - Randomness is consumed via `BigIntegers.createRandomInRange(ONE, n-1, rand)`
    (BouncyCastle) in `genKeyPair` and in ZKP nonce generation — variable bytes per
    draw, which is WHY AC 3 demands recording consumed values, not a seed.
- Existing test (the zero-KAT evidence):
  `plugins/shipped/tandem/src/test/java/com/glycemicgpt/mobile/ble/auth/JpakeAuthenticatorTest.kt`
  — JUnit 4, observed 6 `@Test` methods on 2026-08-16 (AD-8 prose says "seven tests";
  record the count you observe, note the discrepancy if it persists).
- Gradle module is `:tandem-pump-driver` (settings.gradle.kts maps it from
  `plugins/shipped/tandem`) — NOT `:plugins:shipped:tandem`.

### Verified toolchain (this Mac, 2026-08-16)

Temurin JDK 21 ✓; `./gradlew :tandem-pump-driver:testDebugUnitTest --dry-run` configures
and resolves ✓ (Android SDK present); Xcode 26.6 / Swift 6.3.3 ✓ (not needed here);
`python3` ✓. Gate scripts are story deliverables — their constituent commands are
verified; write them so they run non-interactively from a clean checkout.

Worker sandbox: this worktree ships an untracked `.claude/settings.local.json`
granting read/exec access to the Android checkout (`additionalDirectories`) and an
allowlist for `git`, `./gradlew`, `bash`, `python3` and common utils. `gh`,
`git push`, `curl`, `wget` are DENIED during implementation — commit locally on
this branch; the PM handles publishing after gates pass. Do not edit or commit
`.claude/` or `_bmad-output/` — both are gitignored and must stay out of the diff.

### Fixture design guardrails

- JSON, one file per scenario (e.g. `handshake-client-01.json`, `malformed-round1-01.json`),
  lower-hex strings for all byte fields, stable key order, trailing newline — byte-diff
  in the gate requires deterministic serialization.
- Record per scenario: jpake secret bytes, role, full ordered log of RNG outputs
  consumed, each round payload in both directions, byte counts returned by the `read*`
  calls, derived secret from BOTH roles.
- Do not "clean up" or re-encode payloads — commit exactly what `EcJpake` emitted.
- Do NOT alter `JpakeAuthenticatorTest.kt` or any Android source/test — the harness is
  a new, separate file that lives in this repo and is copied into the disposable
  worktree at regeneration time.

### Project structure notes

- This repo is greenfield (no `Package.swift` yet). Create only:
  `Tests/Fixtures/EcJpake/*` (fixtures + README), `scripts/spk2/*` (two gates +
  `harness/EcJpakeKatGeneratorTest.kt`). `Tests/` matches the architecture spine's
  structural seed, so nothing moves when the SPM package lands.
- Never commit `_bmad/`, `_bmad-output/`, `.agents/`, `.claude/` content — those stay
  untracked in this repo. The story file mirrors back to the main checkout; PR contains
  only the paths above.
- Branch from `develop`; PR targets `develop`.

### Testing standards summary

Gates ARE the tests for this story: structural validation (fast, local) + full
regeneration determinism (worktree + Gradle). There is no Swift test target yet, so do
not create one.

### References

- [Source: _bmad-output/planning-artifacts/architecture/architecture-ios-unofficial-2026-08-03/ARCHITECTURE-SPINE.md#AD-8]
- [Source: _bmad-output/planning-artifacts/epics.md#Story-1.1 and #Prerequisite-spikes SPK-2]
- [Source: _bmad-output/planning-artifacts/prds/prd-ios-unofficial-2026-08-01/prd.md#FR-231 (EC-JPAKE lineage/licensing)]

## Dev Agent Record

### Agent Model Used

claude-opus-5, effort high, BMAD `dev` persona (Amelia). Cycle 1 of 3.
Local-GPU pre-assessment: 🔴 RED — `delegate.sh` is devbox-only and not installed
on this Mac, as the story frontmatter already stamped. Cloud drove the whole story.

### Debug Log References

- Android source pinned at `59e68104df17614c50173bed954843a5f56e588b`
  (`chore: release 0.14.0 (#38)`), the HEAD of the main checkout throughout.
- Zero-prior-KATs evidence, counted at that SHA rather than from the working tree:
  `git grep -c '@Test' 59e6810 -- .../JpakeAuthenticatorTest.kt` → **6**. A
  `grep -n 'byteArrayOf\|0x\|fromHex'` over the same file returns only two hits,
  both `SecureRandom().nextBytes(...)` nonces — i.e. no hardcoded payload bytes
  anywhere, which is the substantive claim behind AC 4. AD-8 prose says "seven
  tests"; the discrepancy persists and is recorded in the fixture README.
- Negative test of the validation gate (not just a green run): flipping one hex
  nibble in `rounds.client_round1` made `validate_fixtures.py` fail with
  `handshake-client-01.json replay: rounds.client_round1 does not match the value
  replayed from randomness.log`. Reverted afterwards.
- Determinism was observed across three independent JVM runs (one `--update`, two
  verify runs), each producing byte-identical fixtures.

### Completion Notes List

**Approach.** `EcJpake` already accepts an injected `SecureRandom`, so no Android
source was touched. The harness supplies a fully specified DRBG — the byte stream
is `SHA-256(seedAscii || be32(i))` for i = 0,1,2,… consumed sequentially — and
records every value handed back. Per role the handshake consumes 7 draws
(4×32B in `getRound1`, 16B+32B in `getRound2`, 16B in `deriveSecret`).

**On AC 3 — how I convinced myself the log is actually sufficient.** A green
"fixtures parse" gate would not have caught a plausible-but-wrong vector, which
is this story's stated top risk. Two independent checks were added instead:

1. *JVM side (harness).* It asserts the draw phase/size sequence, then recomputes
   points from the logged bytes (`G * BigInteger(1, bytes)`, and for round 2 the
   generator `peer.X1 + peer.X2 + own.X1`) and compares against what `EcJpake`
   actually wrote. If BouncyCastle's rejection sampling ever drew twice, or the
   draw order changed, the harness fails loudly rather than emitting a mislabelled
   fixture.

   > **Cycle-2 correction.** As written in cycle 1 this claim was too broad, and
   > the reviewer was right to call it out: the harness covered only the four
   > round-1 points and the round-2 ZKP commitment. It parsed and discarded both
   > round-1 proof scalars, the round-2 public point `Xm` and the round-2 proof
   > scalar, and it compared the two production-derived secrets to each other
   > rather than deriving either. Cycle 2 closed the gap in the tooling instead of
   > softening the sentence — see the cycle-2 notes below.
2. *Non-JVM side (new `scripts/spk2/ecjpake_replay.py`).* A stdlib-only P-256
   implementation rebuilds **every committed byte** — both round 1 payloads, both
   round 2 payloads, both derived secrets, and the malformed cases' base payloads
   — from nothing but the fixture's own `secret` and `randomness.log`. This is
   exactly what the Swift port will have to do, executed in a second language, and
   it passes. `validate_fixtures.py` runs it as part of the gate.

   > **Cycle-2 correction.** Also overstated. The derived secrets were computed
   > from a peer point decoded out of the *committed* round 2 bytes, so that one
   > check was circular; and the malformed fixtures' `payload`, `corruption` and
   > `outcome` were never replayed at all. Both are fixed in cycle 2.

**Deliberate additions beyond the literal task list**, all inside the story's
declared file surface (`scripts/spk2/*`, `Tests/Fixtures/EcJpake/*`):

- `scripts/spk2/ecjpake_replay.py` — the replay above. The story scoped
  `validate_fixtures.py` as "structural"; structural validation alone cannot
  detect a wrong vector, and a wrong vector poisons every downstream story, so I
  added the cryptographic layer. It doubles as the reference implementation the
  Swift port can read.
- A second malformed fixture (`malformed-round1-zkp-01.json`). AC 2 requires one;
  truncation only exercises the parser, so a corrupted-ZKP case was added to cover
  proof rejection too. Both outcomes are `java.lang.RuntimeException`, with the
  distinguishing messages recorded.
- `verify_vectors.sh --update` mode, which is also the README's regeneration
  command. Verify mode is unchanged and is what the gate runs.

**Two implementation choices worth flagging for review:**

- The fixture output path reaches the forked test JVM via a Gradle **init script**
  (`-Pspk2FixtureOut=…` → `systemProperty`), not an exported environment variable.
  An exported variable is not reliable here: a Gradle daemon already running with
  a different environment would hand the test JVM the stale one, and the harness
  would write nowhere. The init script also sets `outputs.upToDateWhen { false }`
  and `cacheIf { false }`, so an UP-TO-DATE or cache-restored test task cannot
  leave the regen directory empty and silently pass the byte-diff.
- `verify_vectors.sh` copies `local.properties` into the worktree when the main
  checkout has one (git worktrees do not carry untracked files, and that is where
  the Android SDK path usually lives). This checkout has none and resolves the SDK
  from the environment, so the branch is currently inert but keeps the script
  working on a machine that does use `local.properties`.

**AC verification.**

| AC | Evidence |
|---|---|
| 1 | `Tests/Fixtures/EcJpake/handshake-client-01.json` — both rounds both directions, curve/hash/ids/secret, full RNG log. |
| 2 | 1 handshake + 2 malformed rejection fixtures; coverage is enforced by `validate_fixtures.py`, not just present. |
| 3 | Full RNG log, no seed/algorithm name; proven sufficient by the two-sided replay above. |
| 4 | Fixture README records the observed count of **6** `@Test` methods with the SHA-pinned command, names them, notes no hardcoded payload bytes, and flags the AD-8 "seven" discrepancy. |
| 5 | Both gates exit 0 on the committed state (below). |
| 6 | `git -C <android> worktree list` shows only the pre-existing main entry; `git status --short` is `?? .agents/` + `?? _bmad/`, identical to the session-start snapshot; HEAD still `59e6810`. |

**Gate evidence (run from the repo root against the committed state):**

```
$ python3 scripts/spk2/validate_fixtures.py
OK: 3 fixture(s) validated in .../Tests/Fixtures/EcJpake                      # exit 0

$ bash scripts/spk2/verify_vectors.sh
Regenerating from .../android-unofficial @ 59e68104df17614c50173bed954843a5f56e588b
BUILD SUCCESSFUL in 3s
OK: 3 regenerated fixture(s) are byte-identical to .../Tests/Fixtures/EcJpake  # exit 0
```

Committed as `8ac518a` on `jlengelbrecht/1-1-ec-jpake-kats`. Not pushed and no PR
opened — `gh`/`git push` are denied during implementation per the story's worker
sandbox note; publishing is the PM's step.

**Nothing was left out.** No Swift code, no SPM package, and no Android source
change, per the story's scope.

### File List

Added (all new; the repo had no `Tests/` or committed `scripts/` before):

- `Tests/Fixtures/EcJpake/README.md`
- `Tests/Fixtures/EcJpake/handshake-client-01.json`
- `Tests/Fixtures/EcJpake/malformed-round1-truncated-01.json`
- `Tests/Fixtures/EcJpake/malformed-round1-zkp-01.json`
- `scripts/spk2/harness/EcJpakeKatGeneratorTest.kt`
- `scripts/spk2/verify_vectors.sh`
- `scripts/spk2/validate_fixtures.py`
- `scripts/spk2/ecjpake_replay.py`

Modified: none. `scripts/spk2/validate_fixtures.py` and `verify_vectors.sh` existed
untracked in the worktree at pickup and were carried forward and extended; neither
was ever committed before, so both land as additions.

## Code Review — Cycle 1 (cross-provider: codex/gpt-5.6-sol) — VERDICT: FINDINGS

Full findings: `_bmad-output/implementation-artifacts/1-1-review-codex.md` — READ IT FIRST.
The reviewer independently rebuilt all four payloads and both derived secrets in
Ruby/OpenSSL and they MATCH the committed fixtures — do NOT regenerate or alter any
committed vector bytes. Every finding is about the verification tooling and its claims.

Cycle 2 instructions (fix ALL of 1–5; do not weaken any gate to make it pass):

1. (CRITICAL) `ecjpake_replay.py` — derive both secrets from the REPLAYED round-2
   points only; no committed byte range may feed the computation it claims to verify.
2. (CRITICAL) Replay/verify malformed fixtures end to end: rebuild `input.payload`
   from `base_payload` + `corruption`, require all fields, and verify the recorded
   outcome pins the actual rejection (a wrong payload byte or wrong message must fail
   the gate — prove it with the same corrupt-a-copy negative test used for handshakes).
3. (MAJOR) `verify_vectors.sh` — cleanup failure must exit nonzero; remove/verify only
   the worktree THIS run created; no repo-wide prune of unrelated registrations.
4. (MAJOR) Pin regeneration to the provenance SHA: create the disposable worktree at
   the README's recorded SHA (fail loudly on mismatch), and define the `--update`
   provenance-update rule in the README.
5. (MAJOR) Correct the Dev Agent Record's overstated claims (round-2 point and ZKP
   scalars are not independently recomputed JVM-side; secrets compared, not derived) —
   fix the tooling where cheap, and make every remaining written claim exactly true.

Then re-run both gates, re-run the negative tests, and record cycle-2 work in the
Dev Agent Record. Vectors are frozen; tooling and documentation are what change.

## Dev Agent Record — Cycle 2

### Agent Model Used

claude-opus-5, effort high, BMAD `dev` persona (Amelia). Cycle 2 of 3.
Local-GPU pre-assessment: 🔴 RED — `delegate.sh` is devbox-only and absent on this
Mac, as the frontmatter stamps. Cloud drove the whole cycle.

### Cycle-2 scope

All five findings fixed, no gate weakened. **No vector byte changed**: the only
fixture edit is the `corruption` field of the two malformed files becoming
machine-readable (the cycle-1 prose is preserved verbatim as its `description`),
which finding 2 requires in order to rebuild `input.payload` rather than trust it.
Proof, from `git diff` against `8ac518a` after regeneration:

```
 Tests/Fixtures/EcJpake/malformed-round1-truncated-01.json | 6 +++++-
 Tests/Fixtures/EcJpake/malformed-round1-zkp-01.json       | 7 ++++++-
-    "corruption": "truncate to the first 100 bytes",
+    "corruption": { "description": "truncate to the first 100 bytes",
+                    "length": 100, "op": "truncate" },
-    "corruption": "XOR 0x01 into the last byte (...)",
+    "corruption": { "description": "XOR 0x01 into the last byte (...)",
+                    "mask": "01", "offset": 329, "op": "xor" },
```

`handshake-client-01.json` is byte-identical to cycle 1, and every `payload`,
`base_payload`, `secret` and `randomness.log` field is untouched.

### Finding-by-finding

**1 (CRITICAL) — circular derived-secret replay.** `_Role.round2` now returns its
own round 2 public point alongside the payload, and each `derived_secret` call
takes the peer's *replayed* point. No committed byte range feeds any computation
compared against a committed byte range.

Verified with the reviewer's own probe: swapping the two point fields inside
`rounds.server_round2` and setting `derived_secret.client` to the value that
tampered range yields reproduces their exact figure —
`87123705dc1ea658f87e66cffa7db6c92b0a9d246eff79ac8356f3fea95531cd` — and the gate
now reports `derived_secret.client does not match the value replayed from
randomness.log`, which cycle 1 did not. (Both secrets were set to the forged value
so the structural equality check could not fire first; the replay alone catches it.)

**2 (CRITICAL) — malformed fixtures unverified.** `replay_malformed` is now a full
end-to-end replay: it replays the base payload from the log, rebuilds `payload` by
applying `corruption` (`apply_corruption`, ops `truncate`/`xor`), requires the
result to equal the committed `payload`, and then parses that payload with a new
stdlib mirror of `readRound1`/`readZkp`/`readRound2` — so the recorded `outcome`
must be the rejection the bytes actually provoke. `outcome.message` is pinned to a
category (`Unexpected end of stream` → `eof`, `ZKP validation failed` → `zkp`); an
unrecognised message fails the gate rather than being accepted as prose. The
harness now *applies* the same descriptor it records, so a fixture cannot claim one
corruption and contain another. `_validate_malformed` requires `role`,
`base_payload`, a structured `corruption` and `message`, and rejects
`payload == base_payload`.

Since the handshake replay now also re-parses each rebuilt payload, `read_results`
is checked against a real parse rather than against payload lengths — and the
parser the malformed cases depend on is exercised on well-formed input too. That
re-parse caught a genuine bug in my first draft: the reader's round 2 generator is
`own.X1 + own.X2 + peer.X1`, not the writer's `peer.X1 + peer.X2 + own.X1` (the
same point from the other side).

**3 (MAJOR) — cleanup could fail silently.** The trap now tracks failure, removes
only the worktree this run created (the repo-wide `worktree prune` is gone), then
*verifies* that its own registration and both temp directories are gone, and forces
a nonzero exit if not.

Writing the negative test for this exposed a real bug in my own fix, which the
cycle-1 code had been masking: `mktemp` returns `/var/folders/...` while git
registers the physical `/private/var/folders/...`, so the exact-path lookup never
matched — cleanup silently did nothing and cycle 1's blanket `prune` was what had
been sweeping up. Four stale registrations from my own runs were sitting in the
Android repo when I checked. Fixed by resolving both temp paths with `pwd -P`
before git sees them, plus an assertion right after `worktree add` that the
registration is findable, so a future path-spelling mismatch fails loudly instead
of leaking. I pruned the four stale entries by hand afterwards (all mine, all
`spk2-ecjpake-worktree.*`).

**4 (MAJOR) — regeneration not actually pinned.** New `scripts/spk2/provenance.env`
holds `ANDROID_SHA=59e6810…`; the worktree is created at that commit, not at the
checkout's `HEAD`, and the script dies if the checkout does not contain it.
`ANDROID_SHA=<sha> --update` is the documented re-pin path — it rewrites
`provenance.env` and prints what else must change; `ANDROID_SHA` is refused in
verify mode. `validate_fixtures.py` fails while `provenance.env` and the README
provenance table name different commits, so a re-pin cannot land with stale
documentation. The README's Regenerating section states this rule.

**5 (MAJOR) — overstated Dev Agent Record.** The cycle-1 claims are corrected in
place above, and the tooling was raised to meet them rather than the claims lowered
(the fix was cheap). The harness now carries an `Independent` class — the JVM twin
of the Python `_Role` — that rebuilds, from the logged draws and the JPAKE secret
only: both round 1 points, both round 1 ZKP commitments **and response scalars**,
the round 2 point `Xm`, its commitment and response scalar, and **both derived
secrets** (from the peer's recomputed `Xm`, not from the production output). Every
field parsed back out of an emitted payload is now compared against an
independently computed value; the capture fails if any differs. The fixture README
paragraph making this claim was updated to match exactly what is asserted.

### Negative tests (tamper a copy, run the gate, restore)

Every case restored the file in a `finally` block; `git status` afterwards shows
only the intended edits.

| Tamper | Gate result |
|---|---|
| one nibble flipped in `rounds.client_round1` | rc=1 `rounds.client_round1 does not match the value replayed from randomness.log` |
| `server_round2` points swapped + both derived secrets set to the forged value | rc=1 — `server_round2`, `derived_secret.client` **and** `derived_secret.server` all reported |
| malformed `payload` reverted to `base_payload` | rc=1 `'payload' equals 'base_payload'; nothing was corrupted` |
| `outcome.message` → `payload accepted` | rc=1 `not a rejection ecjpake_replay can reproduce` |
| one byte changed in `base_payload` | rc=1 `input.base_payload does not match the round 1 payload replayed from randomness.log` |
| `corruption.offset` moved by one byte | rc=1 `input.payload is not input.base_payload with input.corruption applied` |
| README SHA no longer matches the pin | rc=1 `README.md: does not record the pinned Android commit …` |
| `git worktree remove` sabotaged via a PATH stub | rc=1 — byte-diff still printed `OK`, then `FAIL: … still registers the disposable worktree …` |
| pinned commit absent from the checkout | rc=1 `the pinned revision … is not present in …` |
| `ANDROID_SHA` set in verify mode | rc=1 `only allowed with --update` |
| pin set to the parent commit, verify mode | rc=0, `Regenerating from … @ 0df897ca…` while the checkout's HEAD is `59e6810…` — the pin is honoured, not HEAD |
| `ANDROID_SHA=<parent> --update` | rc=0, `provenance.env` re-pinned + the README reminder printed; `validate_fixtures.py` then rc=1 until the README matches |

All three throwaway test artefacts (`.spk2-negtest-bin/`, `.spk2-negtest.py`,
`.spk2-repin-test.py`) were deleted; the tree holds only the deliverables.

### Gate evidence (repo root, final state)

```
$ python3 scripts/spk2/validate_fixtures.py
OK: 3 fixture(s) validated in .../Tests/Fixtures/EcJpake                      # exit 0

$ bash scripts/spk2/verify_vectors.sh
Regenerating from .../android-unofficial @ 59e68104df17614c50173bed954843a5f56e588b
BUILD SUCCESSFUL in 2s
OK: 3 regenerated fixture(s) are byte-identical to .../Tests/Fixtures/EcJpake  # exit 0
```

AC 6 re-verified after every run above: `git -C <android> worktree list` shows only
`android-unofficial 59e6810 [main]`,
`git status --short` is `?? .agents/` + `?? _bmad/` as at session start, and HEAD is
still `59e6810`.

### File List — cycle 2

Added:

- `scripts/spk2/provenance.env`

Modified:

- `scripts/spk2/ecjpake_replay.py` (findings 1, 2)
- `scripts/spk2/validate_fixtures.py` (findings 2, 4)
- `scripts/spk2/verify_vectors.sh` (findings 3, 4)
- `scripts/spk2/harness/EcJpakeKatGeneratorTest.kt` (findings 2, 5)
- `Tests/Fixtures/EcJpake/README.md` (findings 4, 5)
- `Tests/Fixtures/EcJpake/malformed-round1-*.json` — `corruption` field only; no
  vector byte changed

Not pushed and no PR opened: `gh`/`git push` remain denied during implementation
per the story's worker sandbox note.

## Code Review — Cycle 2 re-check (codex/gpt-5.6-sol) — VERDICT: FINDINGS

Findings 1, 2, 4, 5 CLOSED with re-run attack evidence; fixtures confirmed
byte-identical. Full text: `_bmad-output/implementation-artifacts/1-1-review-codex-c2.md`.
TWO items remain for cycle 3 — this is the FINAL cycle (max_cycles=3); anything
still open after it escalates to the maintainer. Vectors remain frozen.

1. (MAJOR, residual finding 3) `verify_vectors.sh` `worktree_is_registered` collapses
   "exact worktree absent" (success) with "`git worktree list` query failed" (error).
   Distinguish the two: a query error during cleanup must set `failed`/exit nonzero;
   only a confirmed absence may pass. Prove with a negative test (e.g. simulate the
   query failing) recorded in the Dev Agent Record.
2. (NEW MAJOR, finding 7) `validate_fixtures.py` `_validate_provenance` substring-checks
   the pinned SHA anywhere in the README, so falsifying the provenance TABLE's Commit
   value passes while historical text still contains the SHA. Parse the table's Commit
   field specifically (or make provenance machine-readable in one place and reference
   it), and prove with the reviewer's forty-zeroes negative test.

Re-run both gates and the negative tests; record cycle-3 work in the Dev Agent Record.

## Dev Agent Record — Cycle 3

### Agent Model Used

claude-opus-5, effort high, BMAD `dev` persona (Amelia). Cycle 3 of 3 (final).
Local-GPU pre-assessment: 🔴 RED — `delegate.sh` is devbox-only and absent on this
Mac, as the frontmatter stamps. Cloud drove the whole cycle.

### Cycle-3 scope

Both remaining findings fixed. **No fixture byte changed** — the only edit under
`Tests/Fixtures/EcJpake/` is one prose paragraph in `README.md`, which the
byte-diff excludes as documentation. `git diff --stat` against `a32a00b` touches
`scripts/spk2/validate_fixtures.py`, `scripts/spk2/verify_vectors.sh` and
`Tests/Fixtures/EcJpake/README.md` only; no `.json` file is in the diff.

### Finding-by-finding

**1 (MAJOR, residual finding 3) — cleanup collapsed "absent" with "query failed".**
`worktree_is_registered` (a boolean) is replaced by `worktree_registration_state`,
which returns three distinct states: `0` registered, `1` confirmed absent, `2` the
`git worktree list` query itself failed. All three call sites now branch on the
state rather than on truthiness:

- *Cleanup, before removal* — a query failure prints `could not list the worktrees
  of <repo>, so the disposable worktree <path> was not removed` and sets `failed`.
  Previously this path skipped removal in silence.
- *Cleanup, after removal* — a query failure prints `… removal of <path> is
  unconfirmed; check it by hand` and sets `failed`, so an unverifiable cleanup can
  never be reported as a pass. Only a confirmed absence passes.
- *Preflight* (right after `worktree add`) — "git registered it under a different
  path" and "the query is broken" now die with different messages; the run is
  refused either way, because cleanup could not do its job afterwards.

The reviewer's scenario — the Android repo becoming unreadable during EXIT while
everything else succeeded — is exactly test B below: the byte-diff prints `OK` and
the script still exits 1. Under cycle 2 it exited 0.

**2 (NEW MAJOR, finding 7) — provenance check was a whole-file substring search.**
`_validate_provenance` now parses the README provenance table's `Commit` row
(`README_COMMIT_ROW`, anchored `^\| Commit \| \`<sha>\` … \|$`, `re.MULTILINE`),
requires exactly one such row, and compares that cell to the pin. The capture is
deliberately `[0-9a-zA-Z]+` rather than 40 hex chars, so a garbage value reports
the useful "table says X, pin says Y" rather than "row not found". The README
paragraph and the module docstring that claimed this check were corrected to
describe what it now actually does, including that reformatting the row away
fails the gate.

### Negative tests

Provenance (throwaway script, README restored in a `finally`):

| Tamper | Gate result |
|---|---|
| reviewer's attack: table `Commit` → forty zeroes, historical SHA at README line ~69 left intact | rc=1 `the provenance table records commit 0000…, but provenance.env pins 59e6810…` |
| table `Commit` row deleted entirely (historical SHA still present) | rc=1 `expected exactly one provenance-table row …, found 0` |
| table `Commit` value un-backticked | rc=1 same "found 0" message |
| restored | rc=0 |

Cleanup (throwaway PATH stub for `git` that passes everything through to the real
binary except `git … worktree list`, which it fails on chosen call indexes — call 1
is the preflight, calls 2 and 3 are cleanup's two checks):

| Failing query | Gate result |
|---|---|
| call 1 (preflight) | rc=1 `could not list the worktrees of …; refusing to run, since cleanup could not confirm removal …`; the worktree was still removed (queries 2/3 worked) and `worktree list` returned to baseline |
| call 3 only (post-removal confirmation) | **the byte-diff printed `OK: 3 regenerated fixture(s) are byte-identical …` and the script still exited 1** — `… removal of <path> is unconfirmed; check it by hand` + `the Android checkout was not left clean`. No leak; this is the cycle-2 silent-pass case, now caught. |
| calls 2 and 3 (repo unreadable for the whole of cleanup) | rc=1, both messages printed; removal was correctly skipped, so the registration leaked exactly as the messages say — I removed it by hand with `git worktree remove --force <path>` and `worktree list` returned to the single baseline entry |

Cycle-2 replay negative tests re-run because `validate_fixtures.py` changed — all
still rc=1 with the same messages: nibble flipped in `rounds.client_round1`;
malformed `payload` reverted to `base_payload`; `outcome.message` → `payload
accepted`; `corruption.offset` moved by one byte. `ANDROID_SHA` in verify mode is
still refused (rc=1).

All throwaway artefacts (`.spk2-negtest-bin/`, `.spk2-negtest-cleanup.sh`,
`.spk2-negtest-provenance.py`, `.spk2-negtest-regression.py`) were deleted;
`git status --short` shows only the three deliverable files.

### Gate evidence (repo root, final state)

```
$ python3 scripts/spk2/validate_fixtures.py
OK: 3 fixture(s) validated in .../Tests/Fixtures/EcJpake                      # rc=0

$ bash scripts/spk2/verify_vectors.sh
Regenerating from .../android-unofficial @ 59e68104df17614c50173bed954843a5f56e588b
BUILD SUCCESSFUL in 2s
OK: 3 regenerated fixture(s) are byte-identical to .../Tests/Fixtures/EcJpake  # rc=0
```

AC 6 re-verified after the negative tests and the final gate run:
`git -C <android> worktree list` shows only
`android-unofficial 59e6810 [main]`,
`git status --short` there is `?? .agents/` + `?? _bmad/` as at session start, and
HEAD is still `59e68104df17614c50173bed954843a5f56e588b`.

### File List — cycle 3

Modified:

- `scripts/spk2/verify_vectors.sh` (finding 3 residual)
- `scripts/spk2/validate_fixtures.py` (finding 7)
- `Tests/Fixtures/EcJpake/README.md` — one provenance paragraph; no fixture byte
  changed and no `.json` file touched

Not pushed and no PR opened: `gh`/`git push` remain denied during implementation
per the story's worker sandbox note.

## PM Merge Record (2026-08-17)

PR #3 squash-merged to develop by the PM under standing merge authority; merge commit
`b16c26cf`. Decision made on gate evidence only: gates green cycles 1-3 + triage
commit; cross-provider adversarial review APPROVE after 3 rounds; CodeRabbit 5/5
findings fixed and replied, threads resolved; GitGuardian clean; Seer clean at
PR-open. No protected paths, no scope drift, no bypass, no external engagement.
