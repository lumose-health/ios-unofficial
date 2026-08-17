# EC-JPAKE known-answer vectors (SPK-2)

Byte-level ground truth for the Swift EC-JPAKE port (AD-8). These vectors were
captured from the Kotlin `EcJpake` implementation that ships in the Android app,
driven by a fully recorded deterministic randomness source. The Swift port must
reproduce them **byte-for-byte**; that test is also the canary for swift-crypto
fork rebases.

Nothing here is hand-written. Every byte in every `.json` file is generated
output — see [Regenerating](#regenerating).

## Provenance

| | |
|---|---|
| Source repo | `lumose-health/android-unofficial` |
| Commit | `59e68104df17614c50173bed954843a5f56e588b` (`chore: release 0.14.0 (#38)`) |
| Implementation | `plugins/shipped/tandem/src/main/java/com/glycemicgpt/mobile/ble/crypto/EcJpake.kt` |
| Gradle module | `:tandem-pump-driver` (maps to `plugins/shipped/tandem`) |
| Harness | `scripts/spk2/harness/EcJpakeKatGeneratorTest.kt` (in **this** repo) |
| Captured | 2026-08-16 |

The Android checkout is never modified. `scripts/spk2/verify_vectors.sh` creates a
disposable `git worktree` at the commit above, copies the harness in, runs it, and
removes the worktree on every exit path. The harness uses `EcJpake`'s existing
`rand: SecureRandom` constructor parameter — no production source was changed,
and the harness is not committed to the Android repo.

## Fixtures

| File | Kind | Contents |
|---|---|---|
| `handshake-client-01.json` | `handshake` | Full client + server handshake: both round 1 and round 2 payloads in both directions, the byte counts returned by `readRound1`/`readRound2`, and the derived secret from **both** roles (they agree). |
| `malformed-round1-truncated-01.json` | `malformed` | The client round 1 payload cut to its first 100 bytes; `readRound1` throws `java.lang.RuntimeException: Unexpected end of stream`. |
| `malformed-round1-zkp-01.json` | `malformed` | The client round 1 payload with the low bit of its final ZKP scalar flipped, so it parses but the proof fails; `readRound1` throws `java.lang.RuntimeException: ZKP validation failed`. |

Parameters are constant across all fixtures: curve P-256, hash SHA-256, ids
`client` / `server`, JPAKE secret `313233343536` (the ASCII pairing code
`123456`, matching `JpakeAuthenticator.pairingCodeToBytes`).

Payload sizes are fixed: round 1 is 330 bytes for both roles, client round 2 is
165 bytes, server round 2 is 168 bytes (the extra 3 are the curve id the server
writes and the client reads).

## Prior known-answer coverage: none

Before this story the Android repo contained **zero** EC-JPAKE known-answer
vectors. The only EC-JPAKE test was `JpakeAuthenticatorTest.kt`, with **6**
`@Test` methods observed at the pinned commit:

```
$ git grep -c '@Test' 59e68104df17614c50173bed954843a5f56e588b \
    -- plugins/shipped/tandem/src/test/java/com/glycemicgpt/mobile/ble/auth/JpakeAuthenticatorTest.kt
59e6810...:plugins/shipped/tandem/src/test/java/com/glycemicgpt/mobile/ble/auth/JpakeAuthenticatorTest.kt:6
```

Those six are `initial state is IDLE`, `reset returns to IDLE`,
`buildJpake1aRequest produces valid chunks`, `processJpake1aResponse fails with
too-short cargo`, `processJpake1aResponse fails in wrong state`, and `full JPAKE
handshake with simulated server` — state-machine assertions, failure paths, and a
round-trip driven by a live `SecureRandom`. The file contains no hardcoded
payload bytes at all, so nothing downstream may assume pre-existing vectors.

> AD-8 prose says "seven tests". The observed count at the pinned commit is six.
> The discrepancy is in the prose, not in the fixtures; recorded here so the next
> reader does not go looking for a seventh.

## Replaying a fixture without a JVM

A fixture is self-contained: `secret` plus `randomness.log` is everything needed
to rebuild every payload. `randomness.log` is the complete, ordered list of byte
strings the injected `SecureRandom` returned to `EcJpake` — not a seed and not an
algorithm name, because `BigIntegers.createRandomInRange` may draw a variable
number of times.

Per role, in order: `x1`, ZKP nonce for `x1`, `x2`, ZKP nonce for `x2` (32 bytes
each, `getRound1`), then the 16-byte `mulSecret` blinding factor and the round 2
ZKP nonce (`getRound2`), then a second 16-byte blinding factor (`deriveSecret`).
Each entry's `purpose` states this, and the harness asserts the sizes and order
rather than trusting them.

The derivation rules a port needs:

- **Scalars** — a 32-byte draw becomes `BigInteger(1, bytes)`, i.e. an unsigned
  big-endian integer. (`createRandomInRange(1, n-1)` accepts the first candidate
  with overwhelming probability; if it ever rejected one, the harness's draw-count
  assertion would fail rather than emit a mislabelled fixture.) A 16-byte draw
  becomes the `mulSecret` blinding factor `b` the same way.
- **Wire format** — a point is a 1-byte length followed by the 65-byte
  uncompressed SEC1 encoding; a scalar is a 1-byte length (always 32) followed by
  32 big-endian bytes, zero-padded. The server prefixes round 2 with
  `03 00 17` (`ECCurveType.named_curve`, secp256r1).
- **ZKP** — `h = SHA-256(be32(65) || G || be32(65) || V || be32(65) || X ||
  be32(len(id)) || id) mod n` with points uncompressed, and `r = (v - x*h) mod n`.
- **Round 2 generator** — `peer.X1 + peer.X2 + own.X1`.
- **Derived secret** — `SHA-256(K.x)` where `K.x` is the affine x coordinate
  encoded big-endian with leading zero bytes stripped
  (`BigIntegers.asUnsignedByteArray`).

`scripts/spk2/ecjpake_replay.py` is a working, dependency-free implementation of
exactly the above; it reproduces every committed byte and runs as part of the
validation gate. Use it as the reference when porting.

## Regenerating

```sh
bash scripts/spk2/verify_vectors.sh --update   # rewrite the fixtures
bash scripts/spk2/verify_vectors.sh            # gate: byte-diff against the Kotlin implementation
python3 scripts/spk2/validate_fixtures.py      # gate: structure + stdlib-only replay
```

`ANDROID_REPO` overrides the Android checkout path (default
`/Users/devbox/repos/lumose-health/android-unofficial`).

If a regenerated fixture ever differs from the committed one, that is a real
signal: either `EcJpake` changed, or the capture is no longer deterministic. Do
not `--update` past a diff without understanding it — every downstream Swift
conformance test is pinned to these bytes.

## Licensing lineage

`EcJpake.kt` is a Kotlin port of `io.particle.crypto.EcJpake` from
[`particle-iot/ecjpake-java`](https://github.com/particle-iot/ecjpake-java),
Apache-2.0, Copyright 2022 Particle Industries, Inc. pumpX2 (MIT, by jwoglom) was
studied as a protocol reference. The files in this directory are **generated
data** — measurements of that implementation's behaviour, not a copy of its
source. See PRD FR-231 for the lineage requirements this satisfies.
