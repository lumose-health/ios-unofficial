#!/usr/bin/env python3
"""Replay the committed EC-JPAKE fixtures with a stdlib-only P-256 implementation.

This is the half of the validation that proves the point of the whole story: a
non-JVM implementation, given nothing but a fixture file, can rebuild every
committed byte. If this passes, the recorded RNG log really is sufficient for the
Swift port (AC 3) — and if the Kotlin side ever changes its wire format, the
regeneration gate and this replay disagree loudly instead of quietly agreeing
with each other.

Nothing here imports from the Android side; the only inputs are the fixture's
`secret` and `randomness.log`. In particular no committed payload byte is ever
fed into a computation whose result is then compared against a committed payload:
the derived secrets are computed from the *replayed* round 2 points, and a
malformed fixture's `input.payload` is rebuilt from `input.base_payload` plus the
machine-readable `input.corruption` rather than read back.

Both directions of the protocol are exercised: the writer side (`getRound1`,
`getRound2`, `deriveSecret`) rebuilds every emitted payload, and the reader side
(`readRound1`, `readRound2`) re-parses them, so the byte counts in `read_results`
and the malformed fixtures' recorded rejections are checked against a real parse
rather than assumed.

Used by validate_fixtures.py; also runnable directly for a quick check.
"""

from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

# -- NIST P-256 ---------------------------------------------------------------

P = 0xFFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF
A = P - 3
B = 0x5AC635D8AA3A93E7B3EBBD55769886BC651D06B0CC53B0F63BCE3C3E27D2604B
N = 0xFFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551
GX = 0x6B17D1F2E12C4247F8BCE6E563A440F277037D812DEB33A0F4A13945D898C296
GY = 0x4FE342E2FE1A7F9B8EE7EB4A7C0F9E162BCE33576B315ECECBB6406837BF51F5

# Affine points; None is the point at infinity.
Point = tuple[int, int] | None
G: Point = (GX, GY)

POINT_LEN = 65  # uncompressed: 0x04 || X(32) || Y(32)
SCALAR_LEN = 32  # EcJpake.writeNum pads scalars to a fixed 32 bytes

ROLES = ("client", "server")

# EcJpake surfaces both of these as java.lang.RuntimeException; the mapping says
# which failure this replay must reproduce for a fixture recording that message.
REJECTION_EXCEPTION = "java.lang.RuntimeException"
REJECTION_MESSAGES = {
    "Unexpected end of stream": "eof",
    "ZKP validation failed": "zkp",
}


class ReplayError(Exception):
    """The fixture could not be reproduced from its own recorded inputs."""


class Rejection(Exception):
    """A payload was rejected while being parsed, mirroring an EcJpake failure.

    `category` is the machine-comparable failure kind; REJECTION_MESSAGES maps the
    JVM message a fixture recorded onto the category the replay must produce.
    """

    def __init__(self, category: str, detail: str) -> None:
        super().__init__(detail)
        self.category = category


def _add(p: Point, q: Point) -> Point:
    if p is None:
        return q
    if q is None:
        return p
    (x1, y1), (x2, y2) = p, q
    if x1 == x2:
        if (y1 + y2) % P == 0:
            return None
        lam = (3 * x1 * x1 + A) * pow(2 * y1, -1, P) % P
    else:
        lam = (y2 - y1) * pow(x2 - x1, -1, P) % P
    x3 = (lam * lam - x1 - x2) % P
    return (x3, (lam * (x1 - x3) - y1) % P)


def _mul(k: int, p: Point) -> Point:
    k %= N
    result: Point = None
    addend = p
    while k:
        if k & 1:
            result = _add(result, addend)
        addend = _add(addend, addend)
        k >>= 1
    return result


def _encode(p: Point) -> bytes:
    if p is None:
        raise ReplayError("cannot encode the point at infinity")
    x, y = p
    return b"\x04" + x.to_bytes(32, "big") + y.to_bytes(32, "big")


def _decode(data: bytes) -> Point:
    # BouncyCastle's decodePoint raises IllegalArgumentException here, which is not
    # one of the RuntimeException rejections a fixture may record; surfacing it as a
    # distinct category keeps an unexpected encoding a loud gate failure.
    if len(data) != POINT_LEN or data[0] != 0x04:
        raise Rejection(
            "point",
            f"expected a {POINT_LEN}-byte uncompressed point, got {data[:1].hex()}/{len(data)}",
        )
    x = int.from_bytes(data[1:33], "big")
    y = int.from_bytes(data[33:], "big")
    if (y * y - (x * x * x + A * x + B)) % P != 0:
        raise Rejection("point", "point is not on P-256")
    return (x, y)


# -- EcJpake wire format ------------------------------------------------------


def _be32(value: int) -> bytes:
    return value.to_bytes(4, "big")


def _write_point(p: Point) -> bytes:
    encoded = _encode(p)
    return bytes([len(encoded)]) + encoded


def _write_num(value: int) -> bytes:
    return bytes([SCALAR_LEN]) + value.to_bytes(SCALAR_LEN, "big")


def _zkp_hash(gen: Point, v: Point, x: Point, ident: bytes) -> int:
    buf = bytearray()
    for point in (gen, v, x):
        encoded = _encode(point)
        buf += _be32(len(encoded)) + encoded
    buf += _be32(len(ident)) + ident
    return int.from_bytes(hashlib.sha256(bytes(buf)).digest(), "big") % N


def _write_zkp(gen: Point, x: int, pub: Point, ident: bytes, nonce: int) -> bytes:
    """Mirror of EcJpake.writeZkp with the RNG draw supplied from the fixture log."""
    commitment = _mul(nonce, gen)
    h = _zkp_hash(gen, commitment, pub, ident)
    r = (nonce - x * h) % N
    return _write_point(commitment) + _write_num(r)


def _mul_secret(x: int, secret: int, blind: bytes, negate: bool) -> int:
    """Mirror of EcJpake.mulSecret; `blind` is the 16-byte draw from the log."""
    r = x * (int.from_bytes(blind, "big") * N + secret)
    if negate:
        r = -r
    return r % N


class _Stream:
    """Mirror of the ByteArrayInputStream reads EcJpake performs on a peer payload."""

    def __init__(self, data: bytes) -> None:
        self.data = data
        self.pos = 0

    def read(self, count: int) -> bytes:
        if self.pos + count > len(self.data):
            # readUint8/readBytes both raise RuntimeException("Unexpected end of stream").
            raise Rejection("eof", f"needed {count} byte(s) at offset {self.pos}")
        chunk = self.data[self.pos : self.pos + count]
        self.pos += count
        return chunk

    def u8(self) -> int:
        return self.read(1)[0]

    def u16(self) -> int:
        return int.from_bytes(self.read(2), "big")


def _read_point(stream: _Stream) -> Point:
    return _decode(stream.read(stream.u8()))


def _read_num(stream: _Stream) -> int:
    return int.from_bytes(stream.read(stream.u8()), "big")


def _read_zkp(stream: _Stream, gen: Point, pub: Point, ident: bytes) -> None:
    """Mirror of EcJpake.readZkp, including its rejection."""
    commitment = _read_point(stream)
    r = _read_num(stream)
    h = _zkp_hash(gen, commitment, pub, ident)
    if _add(_mul(r, gen), _mul(h, pub)) != commitment:
        raise Rejection("zkp", "ZKP validation failed")


def read_round1(payload: bytes, peer_ident: bytes) -> tuple[int, Point, Point]:
    """Mirror of EcJpake.readRound1; returns (bytes consumed, peer X1, peer X2)."""
    stream = _Stream(payload)
    x1 = _read_point(stream)
    _read_zkp(stream, G, x1, peer_ident)
    x2 = _read_point(stream)
    _read_zkp(stream, G, x2, peer_ident)
    return stream.pos, x1, x2


def read_round2(payload: bytes, gen: Point, peer_ident: bytes, *, has_curve_id: bool) -> tuple[int, Point]:
    """Mirror of EcJpake.readRound2; returns (bytes consumed, peer round 2 point)."""
    stream = _Stream(payload)
    if has_curve_id:
        curve_type = stream.u8()
        if curve_type != 3:
            raise Rejection("curve-id", f"invalid ECCurveType {curve_type}")
        curve_id = stream.u16()
        if curve_id != 23:
            raise Rejection("curve-id", f"unexpected curve id {curve_id}")
    pub = _read_point(stream)
    _read_zkp(stream, gen, pub, peer_ident)
    return stream.pos, pub


class _Role:
    """One side of the handshake, rebuilt purely from the recorded random values."""

    def __init__(self, name: str, secret: int, draws: list[bytes], *, round1_only: bool = False) -> None:
        needed = 4 if round1_only else 7
        if len(draws) != needed:
            raise ReplayError(f"{name}: expected {needed} recorded draw(s), got {len(draws)}")
        self.name = name
        self.ident = name.encode("ascii")
        self.secret = secret
        self.x1 = int.from_bytes(draws[0], "big")
        self.zkp_nonce_1 = int.from_bytes(draws[1], "big")
        self.x2 = int.from_bytes(draws[2], "big")
        self.zkp_nonce_2 = int.from_bytes(draws[3], "big")
        if not round1_only:
            self.round2_blind = draws[4]
            self.zkp_nonce_round2 = int.from_bytes(draws[5], "big")
            self.derive_blind = draws[6]
        self.X1 = _mul(self.x1, G)
        self.X2 = _mul(self.x2, G)

    def round1(self) -> bytes:
        return (
            _write_point(self.X1)
            + _write_zkp(G, self.x1, self.X1, self.ident, self.zkp_nonce_1)
            + _write_point(self.X2)
            + _write_zkp(G, self.x2, self.X2, self.ident, self.zkp_nonce_2)
        )

    def round2_generator(self, peer: "_Role") -> Point:
        """Generator this role writes round 2 against: `peer.X1 + peer.X2 + own.X1`."""
        return _add(_add(peer.X1, peer.X2), self.X1)

    def round2_read_generator(self, peer: "_Role") -> Point:
        """Generator this role reads the peer's round 2 against: `own.X1 + own.X2 + peer.X1`.

        The two formulas describe the same point from the two sides — which is exactly
        what makes the proof verify, so re-parsing checks it rather than reusing the
        writer's value.
        """
        return _add(_add(self.X1, self.X2), peer.X1)

    def round2(self, peer: "_Role", *, write_curve_id: bool) -> tuple[bytes, Point]:
        """Returns (payload, own round 2 public point) — the point feeds the peer's derivation."""
        gen = self.round2_generator(peer)
        xm = _mul_secret(self.x2, self.secret, self.round2_blind, negate=False)
        xm_pub = _mul(xm, gen)
        # The server announces the curve (ECCurveType.named_curve = 3, secp256r1 = 23).
        prefix = b"\x03\x00\x17" if write_curve_id else b""
        payload = (
            prefix
            + _write_point(xm_pub)
            + _write_zkp(gen, xm, xm_pub, self.ident, self.zkp_nonce_round2)
        )
        return payload, xm_pub

    def derived_secret(self, peer: "_Role", peer_round2_point: Point) -> bytes:
        xm2s = _mul_secret(self.x2, self.secret, self.derive_blind, negate=True)
        k = _mul(self.x2, _add(peer_round2_point, _mul(xm2s, peer.X2)))
        if k is None:
            raise ReplayError(f"{self.name}: shared point is the point at infinity")
        # BigIntegers.asUnsignedByteArray strips leading zero bytes.
        x = k[0]
        return hashlib.sha256(x.to_bytes((x.bit_length() + 7) // 8, "big")).digest()


def _draws(fixture: dict, role: str) -> list[bytes]:
    return [bytes.fromhex(e["bytes"]) for e in fixture["randomness"]["log"] if e.get("role") == role]


def replay_handshake(fixture: dict) -> list[str]:
    """Rebuild every committed byte of a handshake fixture; returns mismatch messages."""
    secret = int.from_bytes(bytes.fromhex(fixture["secret"]), "big")
    client = _Role("client", secret, _draws(fixture, "client"))
    server = _Role("server", secret, _draws(fixture, "server"))

    rounds = fixture["rounds"]
    problems: list[str] = []

    def check(label: str, expected_hex: str, actual: bytes) -> None:
        if bytes.fromhex(expected_hex) != actual:
            problems.append(f"{label} does not match the value replayed from randomness.log")

    client_round1 = client.round1()
    server_round1 = server.round1()
    client_round2, client_point = client.round2(server, write_curve_id=False)
    server_round2, server_point = server.round2(client, write_curve_id=True)

    check("rounds.client_round1", rounds["client_round1"], client_round1)
    check("rounds.server_round1", rounds["server_round1"], server_round1)
    check("rounds.client_round2", rounds["client_round2"], client_round2)
    check("rounds.server_round2", rounds["server_round2"], server_round2)

    # Both secrets come from the *replayed* round 2 points; no committed byte range
    # feeds the computation whose result is compared against derived_secret.
    check("derived_secret.client", fixture["derived_secret"]["client"], client.derived_secret(server, server_point))
    check("derived_secret.server", fixture["derived_secret"]["server"], server.derived_secret(client, client_point))

    # Reader side: re-parse each replayed payload the way the peer does, so the
    # recorded byte counts are checked against a real parse (and the same parser the
    # malformed fixtures rely on is exercised on well-formed input).
    reads = fixture["read_results"]
    for label, payload, ident in (
        ("client_read_round1", server_round1, server.ident),
        ("server_read_round1", client_round1, client.ident),
    ):
        try:
            consumed, _, _ = read_round1(payload, ident)
        except Rejection as exc:
            problems.append(f"the replayed round 1 for '{ident.decode()}' was rejected on re-parse ({exc})")
            continue
        if consumed != reads[label]:
            problems.append(f"read_results.{label} is {reads[label]}, but re-parsing consumes {consumed} bytes")

    for label, payload, reader, peer, has_curve_id in (
        ("client_read_round2", server_round2, client, server, True),
        ("server_read_round2", client_round2, server, client, False),
    ):
        try:
            consumed, _ = read_round2(
                payload, reader.round2_read_generator(peer), peer.ident, has_curve_id=has_curve_id
            )
        except Rejection as exc:
            problems.append(f"the replayed round 2 for '{peer.ident.decode()}' was rejected on re-parse ({exc})")
            continue
        if consumed != reads[label]:
            problems.append(f"read_results.{label} is {reads[label]}, but re-parsing consumes {consumed} bytes")

    return problems


def apply_corruption(base: bytes, corruption: dict) -> bytes:
    """Rebuild a malformed payload from the well-formed base and a recorded operation."""
    op = corruption.get("op")
    if op == "truncate":
        length = corruption.get("length")
        if not isinstance(length, int) or isinstance(length, bool) or not 0 <= length < len(base):
            raise ReplayError(f"corruption.length must be an integer in [0, {len(base)}), got {length!r}")
        return base[:length]
    if op == "xor":
        offset = corruption.get("offset")
        mask_hex = corruption.get("mask")
        if not isinstance(offset, int) or isinstance(offset, bool) or offset < 0:
            raise ReplayError(f"corruption.offset must be a non-negative integer, got {offset!r}")
        if not isinstance(mask_hex, str) or not mask_hex:
            raise ReplayError("corruption.mask must be a non-empty hex string")
        try:
            mask = bytes.fromhex(mask_hex)
        except ValueError as exc:
            raise ReplayError(f"corruption.mask is not valid hex ({exc})") from exc
        if offset + len(mask) > len(base):
            raise ReplayError(f"corruption at offset {offset} runs past the {len(base)}-byte base payload")
        out = bytearray(base)
        for i, m in enumerate(mask):
            out[offset + i] ^= m
        if bytes(out) == base:
            raise ReplayError("corruption.mask is all zero; it would not change the payload")
        return bytes(out)
    raise ReplayError(f"unsupported corruption.op {op!r} (known: 'truncate', 'xor')")


def replay_malformed(fixture: dict) -> list[str]:
    """Rebuild a malformed fixture end to end and re-run its recorded rejection.

    The base payload is replayed from the randomness log, the committed
    `input.payload` is reconstructed by applying `input.corruption` to it, and the
    reconstructed payload is then parsed with the same reader EcJpake uses — so the
    recorded outcome has to be the rejection the payload actually provokes.
    """
    problems: list[str] = []
    secret = int.from_bytes(bytes.fromhex(fixture["secret"]), "big")
    inp = fixture["input"]

    reader_role = inp["role"]
    if reader_role not in ROLES:
        return [f"input.role must be 'client' or 'server', got {reader_role!r}"]
    author_role = ROLES[1 - ROLES.index(reader_role)]

    logged_roles = {entry.get("role") for entry in fixture["randomness"]["log"]}
    if logged_roles != {author_role}:
        return [
            f"randomness.log must hold only the '{author_role}' draws that build the payload "
            f"read by the '{reader_role}', got {sorted(str(r) for r in logged_roles)}"
        ]

    call = inp["call"]
    if call != "readRound1":
        return [f"input.call {call!r} cannot be replayed; only 'readRound1' malformed cases are supported"]

    author = _Role(author_role, secret, _draws(fixture, author_role), round1_only=True)
    base = author.round1()
    if bytes.fromhex(inp["base_payload"]) != base:
        problems.append("input.base_payload does not match the round 1 payload replayed from randomness.log")

    # The base payload must be accepted, or the fixture would not prove that the
    # recorded corruption is what causes the rejection.
    try:
        read_round1(base, author.ident)
    except Rejection as exc:
        problems.append(f"the replayed base payload is itself rejected ({exc.category}: {exc})")

    payload = apply_corruption(base, inp["corruption"])
    if bytes.fromhex(inp["payload"]) != payload:
        problems.append("input.payload is not input.base_payload with input.corruption applied")

    outcome = fixture["outcome"]
    if outcome["exception_class"] != REJECTION_EXCEPTION:
        problems.append(
            f"outcome.exception_class {outcome['exception_class']!r} cannot be replayed "
            f"(only {REJECTION_EXCEPTION} rejections are known to this replay)"
        )
        return problems
    expected = REJECTION_MESSAGES.get(outcome["message"])
    if expected is None:
        problems.append(
            f"outcome.message {outcome['message']!r} is not a known EcJpake rejection "
            f"(known: {sorted(REJECTION_MESSAGES)})"
        )
        return problems

    try:
        read_round1(payload, author.ident)
    except Rejection as exc:
        if exc.category != expected:
            problems.append(
                f"the payload is rejected as '{exc.category}' ({exc}), but outcome.message "
                f"{outcome['message']!r} records a '{expected}' rejection"
            )
    else:
        problems.append(f"the payload parses cleanly, but outcome records {outcome['message']!r}")

    return problems


def main() -> int:
    fixture_dir = Path(__file__).resolve().parents[2] / "Tests" / "Fixtures" / "EcJpake"

    failures = 0
    for path in sorted(fixture_dir.glob("*.json")):
        fixture = json.loads(path.read_text(encoding="utf-8"))
        kind = fixture.get("kind")
        try:
            problems = replay_handshake(fixture) if kind == "handshake" else replay_malformed(fixture)
        except (ReplayError, Rejection, ValueError, KeyError) as exc:
            problems = [f"could not be replayed ({type(exc).__name__}: {exc})"]
        if problems:
            failures += 1
            print(f"FAIL {path.name}", file=sys.stderr)
            for problem in problems:
                print(f"  - {problem}", file=sys.stderr)
        else:
            print(f"OK   {path.name} ({kind})")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
