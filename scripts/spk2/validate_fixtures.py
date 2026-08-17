#!/usr/bin/env python3
"""Validate the committed EC-JPAKE known-answer fixtures (SPK-2).

Stdlib only, no Android/JVM dependency: this gate answers "are the committed
fixtures self-consistent and complete enough for a Swift port to replay them
byte-for-byte", not "do they still match the Kotlin implementation" — that is
verify_vectors.sh's job.

Two layers:

  1. Structural — the schema below, plus the determinism rules the byte-diff in
     verify_vectors.sh depends on.
  2. Cryptographic replay (ecjpake_replay.py) — a stdlib-only P-256
     implementation rebuilds every committed payload from nothing but the
     fixture's own `secret` and `randomness.log`, and re-parses each rebuilt
     payload to check the recorded byte counts and rejections. This is what
     actually proves AC 3: if the recorded log were insufficient, or a payload
     or outcome were edited by hand, the replay would not reproduce it.

  3. Provenance consistency — the pinned Android revision in
     scripts/spk2/provenance.env, which verify_vectors.sh regenerates from, must
     be the commit named in the `Commit` row of the README's provenance table.
     That row is parsed, not searched for: the same SHA also appears in the
     README's historical evidence, and a substring match would accept a
     falsified table.

Fixture schema (one JSON object per file under Tests/Fixtures/EcJpake/):

  Common to every fixture
    schema_version  int    1
    kind            str    "handshake" | "malformed"
    description     str    human-readable scenario summary
    curve           str    "P-256"
    hash            str    "SHA-256"
    client_id       str    "client"
    server_id       str    "server"
    secret          hex    the shared JPAKE secret bytes
    randomness      obj    {scheme: str, log: [{role, purpose, bytes: hex}, ...]}
                           `log` is the full ordered list of raw values the
                           recording SecureRandom handed to EcJpake. A seed or
                           algorithm name is NOT acceptable (AC 3).

  kind == "handshake"
    rounds          obj    {client_round1, server_round1,
                            client_round2, server_round2}  all hex
    read_results    obj    {client_read_round1, client_read_round2,
                            server_read_round1, server_read_round2}  all int
                           the byte counts returned by the read* calls
    derived_secret  obj    {client: hex, server: hex} — must be equal

  kind == "malformed"
    input           obj    {call: str, role: str, payload: hex,
                            base_payload: hex, corruption: obj}
                           `base_payload` is the well-formed payload the
                           randomness log reproduces; `payload` is it after
                           `corruption` was applied. `corruption` is
                           machine-readable — {description, op, ...operands},
                           op "truncate" (length) or "xor" (offset, mask) — so
                           the replay rebuilds `payload` instead of trusting it.
    outcome         obj    {rejected: true, exception_class: str, message: str}
                           the replay re-parses `payload` and requires this
                           outcome to be the rejection it actually provokes.

Determinism rules enforced here because the regeneration gate byte-diffs the
files: keys are stored in sorted order at every level, byte fields are
lower-hex with an even length, and each file ends with exactly one newline.

Exit 0 when every fixture is structurally valid, replays byte-for-byte, and the
required scenario coverage (at least one handshake and at least one malformed
case, AC 2) is present.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

# Keep the checkout clean: importing a sibling module would otherwise drop a
# __pycache__ directory into scripts/spk2/.
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import ecjpake_replay  # noqa: E402  (sibling module, resolved via the line above)

REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURE_DIR = REPO_ROOT / "Tests" / "Fixtures" / "EcJpake"
PROVENANCE_FILE = REPO_ROOT / "scripts" / "spk2" / "provenance.env"

SCHEMA_VERSION = 1
EXPECTED_CURVE = "P-256"
EXPECTED_HASH = "SHA-256"
EXPECTED_CLIENT_ID = "client"
EXPECTED_SERVER_ID = "server"

HANDSHAKE_ROUNDS = (
    "client_round1",
    "server_round1",
    "client_round2",
    "server_round2",
)
HANDSHAKE_READ_RESULTS = (
    "client_read_round1",
    "client_read_round2",
    "server_read_round1",
    "server_read_round2",
)
HEX_DIGITS = set("0123456789abcdef")
KNOWN_CORRUPTION_OPS = ("truncate", "xor")

# The `| Commit | `<sha>` ... |` row of the README's provenance table — the one
# place the README states which revision the fixtures came from. Matched as a
# whole row rather than searched for as a substring: the SHA also appears in the
# README's historical evidence, and a substring search would let a falsified
# table pass on the strength of that unrelated mention.
README_COMMIT_ROW = re.compile(
    r"^\|\s*Commit\s*\|\s*`([0-9a-f]{40})`.*\|\s*$",
    re.MULTILINE,
)


class Errors:
    """Collects every problem so one run reports all of them, not just the first."""

    def __init__(self) -> None:
        self.messages: list[str] = []

    def add(self, where: str, message: str) -> None:
        self.messages.append(f"{where}: {message}")

    def __bool__(self) -> bool:
        return bool(self.messages)


def _load(path: Path, errors: Errors) -> dict | None:
    where = path.name
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        errors.add(where, f"unreadable ({exc})")
        return None

    if not text.endswith("\n"):
        errors.add(where, "missing trailing newline")
    elif text.endswith("\n\n"):
        errors.add(where, "more than one trailing newline")

    unsorted: list[str] = []

    def hook(pairs: list[tuple[str, object]]) -> dict:
        keys = [k for k, _ in pairs]
        if keys != sorted(keys):
            unsorted.append(", ".join(keys))
        return dict(pairs)

    try:
        obj = json.loads(text, object_pairs_hook=hook)
    except json.JSONDecodeError as exc:
        errors.add(where, f"invalid JSON ({exc})")
        return None

    for keys in unsorted:
        errors.add(where, f"object keys are not in sorted order: {keys}")

    if not isinstance(obj, dict):
        errors.add(where, "top level value must be a JSON object")
        return None
    return obj


def _require(obj: dict, key: str, kind: type, errors: Errors, where: str):
    if key not in obj:
        errors.add(where, f"missing required field {key!r}")
        return None
    value = obj[key]
    # bool is a subclass of int; an int field must never be True/False.
    if kind is int and isinstance(value, bool):
        errors.add(where, f"{key!r} must be an integer, got a boolean")
        return None
    if not isinstance(value, kind):
        errors.add(where, f"{key!r} must be {kind.__name__}, got {type(value).__name__}")
        return None
    return value


def _require_hex(obj: dict, key: str, errors: Errors, where: str, *, allow_empty=False):
    value = _require(obj, key, str, errors, where)
    if value is None:
        return None
    if not value and not allow_empty:
        errors.add(where, f"{key!r} must not be empty")
        return None
    if len(value) % 2:
        errors.add(where, f"{key!r} has an odd number of hex digits")
        return None
    bad = set(value) - HEX_DIGITS
    if bad:
        errors.add(where, f"{key!r} must be lower-case hex, found {sorted(bad)}")
        return None
    return bytes.fromhex(value)


def _require_const(obj: dict, key: str, expected: str, errors: Errors, where: str) -> None:
    value = _require(obj, key, str, errors, where)
    if value is not None and value != expected:
        errors.add(where, f"{key!r} must be {expected!r}, got {value!r}")


def _validate_randomness(obj: dict, errors: Errors, where: str) -> None:
    randomness = _require(obj, "randomness", dict, errors, where)
    if randomness is None:
        return

    scheme = _require(randomness, "scheme", str, errors, f"{where} randomness")
    if scheme is not None and not scheme.strip():
        errors.add(f"{where} randomness", "'scheme' must describe how the values were produced")

    log = _require(randomness, "log", list, errors, f"{where} randomness")
    if log is None:
        return
    if not log:
        # AC 3: a Swift port replays this log instead of reimplementing a JVM RNG.
        errors.add(f"{where} randomness", "'log' is empty; the consumed random values must be recorded")
        return

    for index, entry in enumerate(log):
        entry_where = f"{where} randomness.log[{index}]"
        if not isinstance(entry, dict):
            errors.add(entry_where, f"must be an object, got {type(entry).__name__}")
            continue
        role = _require(entry, "role", str, errors, entry_where)
        if role is not None and role not in (EXPECTED_CLIENT_ID, EXPECTED_SERVER_ID):
            errors.add(entry_where, f"'role' must be 'client' or 'server', got {role!r}")
        _require(entry, "purpose", str, errors, entry_where)
        _require_hex(entry, "bytes", errors, entry_where)


def _validate_handshake(obj: dict, errors: Errors, where: str) -> None:
    rounds = _require(obj, "rounds", dict, errors, where)
    if rounds is not None:
        for key in HANDSHAKE_ROUNDS:
            _require_hex(rounds, key, errors, f"{where} rounds")

    read_results = _require(obj, "read_results", dict, errors, where)
    if read_results is not None:
        for key in HANDSHAKE_READ_RESULTS:
            count = _require(read_results, key, int, errors, f"{where} read_results")
            if count is not None and count <= 0:
                errors.add(f"{where} read_results", f"{key!r} must be a positive byte count, got {count}")

    derived = _require(obj, "derived_secret", dict, errors, where)
    if derived is not None:
        client = _require_hex(derived, "client", errors, f"{where} derived_secret")
        server = _require_hex(derived, "server", errors, f"{where} derived_secret")
        if client is not None and server is not None and client != server:
            errors.add(
                f"{where} derived_secret",
                "client and server derived secrets differ; the captured handshake did not agree",
            )


def _validate_malformed(obj: dict, errors: Errors, where: str) -> None:
    inp = _require(obj, "input", dict, errors, where)
    if inp is not None:
        input_where = f"{where} input"
        call = _require(inp, "call", str, errors, input_where)
        if call is not None and not call.strip():
            errors.add(input_where, "'call' must name the EcJpake method that rejected the payload")
        role = _require(inp, "role", str, errors, input_where)
        if role is not None and role not in (EXPECTED_CLIENT_ID, EXPECTED_SERVER_ID):
            errors.add(input_where, f"'role' must name the rejecting side, 'client' or 'server', got {role!r}")
        # An empty payload is a legitimate malformed input, so allow it.
        payload = _require_hex(inp, "payload", errors, input_where, allow_empty=True)
        # base_payload + corruption is what makes `payload` verifiable rather than
        # merely present: the replay rebuilds it instead of reading it back.
        base = _require_hex(inp, "base_payload", errors, input_where)
        if payload is not None and base is not None and payload == base:
            errors.add(input_where, "'payload' equals 'base_payload'; nothing was corrupted")
        corruption = _require(inp, "corruption", dict, errors, input_where)
        if corruption is not None:
            corruption_where = f"{input_where} corruption"
            description = _require(corruption, "description", str, errors, corruption_where)
            if description is not None and not description.strip():
                errors.add(corruption_where, "'description' must state in prose what was corrupted")
            op = _require(corruption, "op", str, errors, corruption_where)
            if op is not None and op not in KNOWN_CORRUPTION_OPS:
                errors.add(corruption_where, f"'op' must be one of {sorted(KNOWN_CORRUPTION_OPS)}, got {op!r}")

    outcome = _require(obj, "outcome", dict, errors, where)
    if outcome is not None:
        outcome_where = f"{where} outcome"
        rejected = outcome.get("rejected")
        if rejected is not True:
            errors.add(outcome_where, f"'rejected' must be true, got {rejected!r}")
        exception_class = _require(outcome, "exception_class", str, errors, outcome_where)
        if exception_class is not None and not exception_class.strip():
            errors.add(outcome_where, "'exception_class' must name the thrown exception")
        message = _require(outcome, "message", str, errors, outcome_where)
        # The replay pins the message to the rejection it actually reproduces, so an
        # unknown one is a gate failure rather than free-form documentation.
        if message is not None and message not in ecjpake_replay.REJECTION_MESSAGES:
            errors.add(
                outcome_where,
                f"'message' {message!r} is not a rejection ecjpake_replay can reproduce "
                f"(known: {sorted(ecjpake_replay.REJECTION_MESSAGES)})",
            )


def _replay(obj: dict, kind: str, errors: Errors, where: str) -> None:
    """Rebuild the committed payloads from the fixture's own recorded randomness."""
    try:
        problems = (
            ecjpake_replay.replay_handshake(obj)
            if kind == "handshake"
            else ecjpake_replay.replay_malformed(obj)
        )
    except (ecjpake_replay.ReplayError, ecjpake_replay.Rejection, ValueError, KeyError) as exc:
        errors.add(f"{where} replay", f"could not be replayed ({type(exc).__name__}: {exc})")
        return
    for problem in problems:
        errors.add(f"{where} replay", problem)


def _validate_provenance(readme: Path, errors: Errors) -> None:
    """The regeneration pin and the documented provenance must name the same commit.

    verify_vectors.sh regenerates from provenance.env, so if the README recorded a
    different revision the documented command would no longer reproduce the
    documented source — the drift finding this check closes.
    """
    where = "provenance.env"
    try:
        text = PROVENANCE_FILE.read_text(encoding="utf-8")
    except OSError as exc:
        errors.add(where, f"unreadable ({exc}); verify_vectors.sh regenerates from this pin")
        return

    values = [
        line.split("=", 1)[1].strip()
        for line in text.splitlines()
        if line.startswith("ANDROID_SHA=")
    ]
    if len(values) != 1:
        errors.add(where, f"expected exactly one ANDROID_SHA= line, found {len(values)}")
        return

    sha = values[0]
    if len(sha) != 40 or set(sha) - HEX_DIGITS:
        errors.add(where, f"ANDROID_SHA must be a full 40-character lower-hex commit id, got {sha!r}")
        return

    if not readme.is_file():
        return  # already reported by the caller
    documented = README_COMMIT_ROW.findall(readme.read_text(encoding="utf-8"))
    if len(documented) != 1:
        errors.add(
            "README.md",
            f"expected exactly one provenance-table row of the form "
            f"'| Commit | `<sha>` ... |', found {len(documented)}; that row is what "
            f"documents the revision {PROVENANCE_FILE.name} regenerates from",
        )
        return
    if documented[0] != sha:
        errors.add(
            "README.md",
            f"the provenance table records commit {documented[0]}, but "
            f"{PROVENANCE_FILE.name} pins {sha}; verify_vectors.sh regenerates from the "
            f"pin, so the two must agree (re-pinning updates both)",
        )


def validate_fixture(path: Path, errors: Errors) -> str | None:
    """Validate one fixture file; returns its `kind` when the file is usable."""
    where = path.name
    obj = _load(path, errors)
    if obj is None:
        return None
    before = len(errors.messages)

    version = _require(obj, "schema_version", int, errors, where)
    if version is not None and version != SCHEMA_VERSION:
        errors.add(where, f"unsupported schema_version {version} (expected {SCHEMA_VERSION})")

    _require(obj, "description", str, errors, where)
    _require_const(obj, "curve", EXPECTED_CURVE, errors, where)
    _require_const(obj, "hash", EXPECTED_HASH, errors, where)
    _require_const(obj, "client_id", EXPECTED_CLIENT_ID, errors, where)
    _require_const(obj, "server_id", EXPECTED_SERVER_ID, errors, where)
    _require_hex(obj, "secret", errors, where)
    _validate_randomness(obj, errors, where)

    kind = _require(obj, "kind", str, errors, where)
    if kind == "handshake":
        _validate_handshake(obj, errors, where)
    elif kind == "malformed":
        _validate_malformed(obj, errors, where)
    elif kind is not None:
        errors.add(where, f"'kind' must be 'handshake' or 'malformed', got {kind!r}")
        return None

    # Only replay a structurally sound fixture: on a broken one the replay would
    # just restate the same problem as a confusing crypto error.
    if kind is not None and len(errors.messages) == before:
        _replay(obj, kind, errors, where)
    return kind


def main() -> int:
    errors = Errors()

    if not FIXTURE_DIR.is_dir():
        print(f"FAIL: fixture directory not found: {FIXTURE_DIR}", file=sys.stderr)
        return 1

    paths = sorted(FIXTURE_DIR.glob("*.json"))
    if not paths:
        print(f"FAIL: no fixtures found in {FIXTURE_DIR}", file=sys.stderr)
        return 1

    readme = FIXTURE_DIR / "README.md"
    if not readme.is_file():
        errors.add("README.md", "missing; provenance and the zero-prior-KATs record are required (AC 4)")
    _validate_provenance(readme, errors)

    kinds = [validate_fixture(path, errors) for path in paths]

    # AC 2: coverage, not just well-formedness.
    if "handshake" not in kinds:
        errors.add("<coverage>", "no fixture of kind 'handshake' (AC 2 requires a full client-role handshake)")
    if "malformed" not in kinds:
        errors.add("<coverage>", "no fixture of kind 'malformed' (AC 2 requires a rejection case)")

    if errors:
        print(f"FAIL: {len(errors.messages)} problem(s) in {FIXTURE_DIR}", file=sys.stderr)
        for message in errors.messages:
            print(f"  - {message}", file=sys.stderr)
        return 1

    print(f"OK: {len(paths)} fixture(s) validated in {FIXTURE_DIR}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
