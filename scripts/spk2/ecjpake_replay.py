#!/usr/bin/env python3
"""Replay the committed EC-JPAKE fixtures with a stdlib-only P-256 implementation.

This is the half of the validation that proves the point of the whole story: a
non-JVM implementation, given nothing but a fixture file, can rebuild every
committed byte. If this passes, the recorded RNG log really is sufficient for the
Swift port (AC 3) — and if the Kotlin side ever changes its wire format, the
regeneration gate and this replay disagree loudly instead of quietly agreeing
with each other.

Nothing here imports from the Android side; the only inputs are the fixture's
`secret` and `randomness.log`.

Used by validate_fixtures.py; also runnable directly for a quick check.
"""

from __future__ import annotations

import hashlib
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


class ReplayError(Exception):
    """The fixture could not be reproduced from its own recorded inputs."""


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
    if len(data) != POINT_LEN or data[0] != 0x04:
        raise ReplayError(f"expected a {POINT_LEN}-byte uncompressed point, got {data[:1].hex()}/{len(data)}")
    x = int.from_bytes(data[1:33], "big")
    y = int.from_bytes(data[33:], "big")
    if (y * y - (x * x * x + A * x + B)) % P != 0:
        raise ReplayError("point is not on P-256")
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


class _Role:
    """One side of the handshake, rebuilt purely from the recorded random values."""

    def __init__(self, name: str, secret: int, draws: list[bytes]) -> None:
        if len(draws) != 7:
            raise ReplayError(f"{name}: expected 7 recorded draws for a full handshake, got {len(draws)}")
        self.name = name
        self.ident = name.encode("ascii")
        self.secret = secret
        self.x1 = int.from_bytes(draws[0], "big")
        self.zkp_nonce_1 = int.from_bytes(draws[1], "big")
        self.x2 = int.from_bytes(draws[2], "big")
        self.zkp_nonce_2 = int.from_bytes(draws[3], "big")
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

    def round2(self, peer: "_Role", *, write_curve_id: bool) -> bytes:
        gen = _add(_add(peer.X1, peer.X2), self.X1)
        xm = _mul_secret(self.x2, self.secret, self.round2_blind, negate=False)
        xm_pub = _mul(xm, gen)
        # The server announces the curve (ECCurveType.named_curve = 3, secp256r1 = 23).
        prefix = b"\x03\x00\x17" if write_curve_id else b""
        return (
            prefix
            + _write_point(xm_pub)
            + _write_zkp(gen, xm, xm_pub, self.ident, self.zkp_nonce_round2)
        )

    def derived_secret(self, peer: "_Role", peer_round2_point: Point) -> bytes:
        xm2s = _mul_secret(self.x2, self.secret, self.derive_blind, negate=True)
        k = _mul(self.x2, _add(peer_round2_point, _mul(xm2s, peer.X2)))
        if k is None:
            raise ReplayError(f"{self.name}: shared point is the point at infinity")
        # BigIntegers.asUnsignedByteArray strips leading zero bytes.
        x = k[0]
        return hashlib.sha256(x.to_bytes((x.bit_length() + 7) // 8, "big")).digest()


def _round2_point(payload: bytes, *, has_curve_id: bool) -> Point:
    offset = 3 if has_curve_id else 0
    length = payload[offset]
    return _decode(payload[offset + 1 : offset + 1 + length])


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

    check("rounds.client_round1", rounds["client_round1"], client.round1())
    check("rounds.server_round1", rounds["server_round1"], server.round1())
    check("rounds.client_round2", rounds["client_round2"], client.round2(server, write_curve_id=False))
    check("rounds.server_round2", rounds["server_round2"], server.round2(client, write_curve_id=True))

    client_k = client.derived_secret(server, _round2_point(bytes.fromhex(rounds["server_round2"]), has_curve_id=True))
    server_k = server.derived_secret(client, _round2_point(bytes.fromhex(rounds["client_round2"]), has_curve_id=False))
    check("derived_secret.client", fixture["derived_secret"]["client"], client_k)
    check("derived_secret.server", fixture["derived_secret"]["server"], server_k)

    expected_reads = {
        "client_read_round1": len(bytes.fromhex(rounds["server_round1"])),
        "client_read_round2": len(bytes.fromhex(rounds["server_round2"])),
        "server_read_round1": len(bytes.fromhex(rounds["client_round1"])),
        "server_read_round2": len(bytes.fromhex(rounds["client_round2"])),
    }
    for key, expected in expected_reads.items():
        actual = fixture["read_results"][key]
        if actual != expected:
            problems.append(f"read_results.{key} is {actual}, but the corresponding payload is {expected} bytes")

    return problems


def replay_malformed(fixture: dict) -> list[str]:
    """Check that a malformed fixture's base payload is itself replayable."""
    secret = int.from_bytes(bytes.fromhex(fixture["secret"]), "big")
    draws = _draws(fixture, "client")
    if len(draws) != 4:
        return [f"randomness.log holds {len(draws)} client draw(s); a round 1 base payload needs exactly 4"]

    # Only round 1 is replayed here, so the round 2 / derive draws are irrelevant.
    role = _Role("client", secret, draws + [b"\x00" * 32, b"\x00" * 16, b"\x00" * 32])
    base = fixture["input"].get("base_payload")
    if base is None:
        return []
    if bytes.fromhex(base) != role.round1():
        return ["input.base_payload does not match the round 1 payload replayed from randomness.log"]
    return []


def main() -> int:
    fixture_dir = Path(__file__).resolve().parents[2] / "Tests" / "Fixtures" / "EcJpake"
    import json

    failures = 0
    for path in sorted(fixture_dir.glob("*.json")):
        fixture = json.loads(path.read_text(encoding="utf-8"))
        kind = fixture.get("kind")
        problems = replay_handshake(fixture) if kind == "handshake" else replay_malformed(fixture)
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
