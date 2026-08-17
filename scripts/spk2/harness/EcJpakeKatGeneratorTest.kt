package com.glycemicgpt.mobile.ble.crypto

import org.bouncycastle.jce.ECNamedCurveTable
import org.bouncycastle.jce.spec.ECParameterSpec
import org.bouncycastle.math.ec.ECPoint
import org.bouncycastle.util.BigIntegers
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.io.File
import java.math.BigInteger
import java.security.MessageDigest
import java.security.SecureRandom

/**
 * SPK-2 known-answer vector generator.
 *
 * This file lives in the iOS repo (`scripts/spk2/harness/`) and is copied into a
 * disposable worktree of the Android repo by `scripts/spk2/verify_vectors.sh`; it is
 * never committed to the Android repo and never touches production sources. `EcJpake`
 * already accepts an injected `SecureRandom`, which is the only seam it needs.
 *
 * It drives a full CLIENT/SERVER handshake against a fully specified deterministic byte
 * stream, records **every value the RNG handed out** (AC 3 — a seed or algorithm name is
 * explicitly not enough, because `BigIntegers.createRandomInRange` may draw a variable
 * number of times), and writes one JSON fixture per scenario into the directory named by
 * the `spk2.fixture.out` system property.
 *
 * The generator also *proves* the rules a Swift port needs in order to turn the recorded
 * bytes back into payloads. Independently of `EcJpake`, and from nothing but the logged
 * draws and the JPAKE secret, it recomputes every field it then parses back out of the
 * emitted payloads — both round 1 public points, both round 1 ZKP commitments and
 * response scalars, the round 2 point, commitment and response scalar, and both derived
 * secrets — and asserts each equals what `EcJpake` produced. If BouncyCastle's rejection
 * sampling ever draws more than once, or the draw order or wire format changes, the
 * assertions below fail loudly instead of producing a mislabelled fixture.
 *
 * Output is byte-stable: sorted keys at every level, lower-hex byte fields, two-space
 * indent, exactly one trailing newline — `verify_vectors.sh` byte-diffs it.
 */
class EcJpakeKatGeneratorTest {

    // -- Deterministic randomness ---------------------------------------------

    /** One recorded `SecureRandom.nextBytes` call. */
    private data class Draw(val role: String, val phase: String, val bytes: ByteArray)

    /**
     * A `SecureRandom` whose output is the concatenation of `SHA-256(seed || be32(i))`
     * for i = 0, 1, 2, ... consumed sequentially, and which records every value it hands
     * out. Deliberately reproducible in any language — but a port should replay the
     * recorded `log` rather than reimplement this.
     */
    private class RecordingRandom(val role: String, val seed: String) : SecureRandom() {
        private val digest = MessageDigest.getInstance("SHA-256")
        private val seedBytes = seed.toByteArray(Charsets.US_ASCII)
        private var block = ByteArray(0)
        private var blockOffset = 0
        private var counter = 0

        val draws = mutableListOf<Draw>()

        /** Label applied to draws made from here on; set by the harness before each call. */
        var phase: String = "<unset>"

        override fun nextBytes(bytes: ByteArray) {
            for (i in bytes.indices) {
                if (blockOffset == block.size) {
                    digest.reset()
                    digest.update(seedBytes)
                    digest.update(be32(counter))
                    block = digest.digest()
                    counter++
                    blockOffset = 0
                }
                bytes[i] = block[blockOffset++]
            }
            draws += Draw(role, phase, bytes.copyOf())
        }
    }

    /** The draw sequence `EcJpake` is expected to make, per role, for a full handshake. */
    private data class DrawSpec(val phase: String, val size: Int, val purpose: String)

    private val expectedDraws = listOf(
        DrawSpec("getRound1", 32, "getRound1: private scalar x1, createRandomInRange(1, n-1) -> BigInteger(1, bytes)"),
        DrawSpec("getRound1", 32, "getRound1: ZKP nonce v proving x1, createRandomInRange(1, n-1) -> BigInteger(1, bytes)"),
        DrawSpec("getRound1", 32, "getRound1: private scalar x2, createRandomInRange(1, n-1) -> BigInteger(1, bytes)"),
        DrawSpec("getRound1", 32, "getRound1: ZKP nonce v proving x2, createRandomInRange(1, n-1) -> BigInteger(1, bytes)"),
        DrawSpec("getRound2", 16, "getRound2: mulSecret blinding factor b -> BigInteger(1, bytes)"),
        DrawSpec("getRound2", 32, "getRound2: ZKP nonce v proving xm, createRandomInRange(1, n-1) -> BigInteger(1, bytes)"),
        DrawSpec("deriveSecret", 16, "deriveSecret: mulSecret blinding factor b -> BigInteger(1, bytes)"),
    )

    /** Draws consumed by `getRound1` alone — the prefix the malformed fixtures need. */
    private val round1DrawCount = expectedDraws.count { it.phase == "getRound1" }

    // -- Scenario capture ------------------------------------------------------

    @Test
    fun generatesKnownAnswerVectors() {
        val outDir = resolveOutputDir()
        val ec = ECNamedCurveTable.getParameterSpec(CURVE)
            ?: error("Unsupported curve: $CURVE")

        val clientRand = RecordingRandom(CLIENT_ID, CLIENT_SEED)
        val serverRand = RecordingRandom(SERVER_ID, SERVER_SEED)
        val client = EcJpake(EcJpake.Role.CLIENT, SECRET, clientRand)
        val server = EcJpake(EcJpake.Role.SERVER, SECRET, serverRand)

        clientRand.phase = "getRound1"
        val clientRound1 = client.getRound1()
        serverRand.phase = "getRound1"
        val serverRound1 = server.getRound1()

        val clientReadRound1 = client.readRound1(serverRound1)
        val serverReadRound1 = server.readRound1(clientRound1)

        clientRand.phase = "getRound2"
        val clientRound2 = client.getRound2()
        serverRand.phase = "getRound2"
        val serverRound2 = server.getRound2()

        val clientReadRound2 = client.readRound2(serverRound2)
        val serverReadRound2 = server.readRound2(clientRound2)

        clientRand.phase = "deriveSecret"
        val clientSecret = client.deriveSecret()
        serverRand.phase = "deriveSecret"
        val serverSecret = server.deriveSecret()

        assertArrayEquals(
            "client and server derived different secrets; the captured handshake is not a valid vector",
            clientSecret,
            serverSecret,
        )

        // The read* return values are the byte counts a port must also reproduce.
        assertEquals("client did not consume all of the server round 1", serverRound1.size, clientReadRound1)
        assertEquals("server did not consume all of the client round 1", clientRound1.size, serverReadRound1)
        assertEquals("client did not consume all of the server round 2", serverRound2.size, clientReadRound2)
        assertEquals("server did not consume all of the client round 2", clientRound2.size, serverReadRound2)

        assertDrawsMatchSpec(clientRand)
        assertDrawsMatchSpec(serverRand)

        // Everything below is computed from the recorded draws and the secret alone, then
        // compared against what EcJpake emitted — so the log is *shown* to be sufficient to
        // rebuild every payload field, not merely asserted to be (AC 3).
        val clientSide = Independent(ec, clientRand)
        val serverSide = Independent(ec, serverRand)

        verifyRound1(clientRound1, clientSide)
        verifyRound1(serverRound1, serverSide)
        val clientXm = verifyRound2(clientRound2, clientSide, serverSide, hasCurveId = false)
        val serverXm = verifyRound2(serverRound2, serverSide, clientSide, hasCurveId = true)
        verifyDerivedSecret(clientSecret, clientSide, serverSide, peerXm = serverXm)
        verifyDerivedSecret(serverSecret, serverSide, clientSide, peerXm = clientXm)

        val written = mutableListOf<File>()

        written += write(
            outDir,
            "handshake-client-01.json",
            common(
                kind = "handshake",
                description = "Full P-256 EC-JPAKE handshake: client and server driven by the recorded " +
                    "deterministic byte stream, both roles reaching the same derived secret.",
                log = logEntries(clientRand) + logEntries(serverRand),
            ) + mapOf(
                "rounds" to mapOf(
                    "client_round1" to hex(clientRound1),
                    "client_round2" to hex(clientRound2),
                    "server_round1" to hex(serverRound1),
                    "server_round2" to hex(serverRound2),
                ),
                "read_results" to mapOf(
                    "client_read_round1" to clientReadRound1,
                    "client_read_round2" to clientReadRound2,
                    "server_read_round1" to serverReadRound1,
                    "server_read_round2" to serverReadRound2,
                ),
                "derived_secret" to mapOf(
                    "client" to hex(clientSecret),
                    "server" to hex(serverSecret),
                ),
            ),
        )

        // Malformed cases: a fresh SERVER instance reads a damaged client round 1. The
        // recorded randomness is the client's getRound1 prefix — exactly what a port needs
        // to rebuild the base payload before applying the corruption.
        val round1Log = logEntries(clientRand).take(round1DrawCount)

        // The corruption is described in machine-readable form and then *applied* from
        // that description, so a fixture cannot claim one corruption and record another;
        // the validation gate rebuilds `payload` the same way (see ecjpake_replay.py).
        val truncation = mapOf(
            "description" to "truncate to the first 100 bytes",
            "op" to "truncate",
            "length" to 100,
        )
        val truncated = corrupt(clientRound1, truncation)
        written += write(
            outDir,
            "malformed-round1-truncated-01.json",
            common(
                kind = "malformed",
                description = "Truncated peer round 1: the client round 1 payload cut to " +
                    "${truncated.size} of its ${clientRound1.size} bytes, so the second point runs " +
                    "off the end of the stream.",
                log = round1Log,
            ) + rejection(
                call = "readRound1",
                payload = truncated,
                basePayload = clientRound1,
                corruption = truncation,
                outcome = captureRejection { EcJpake(EcJpake.Role.SERVER, SECRET, freshRand()).readRound1(truncated) },
            ),
        )

        // Flipping the low bit of the final ZKP scalar keeps the payload structurally
        // valid, so the rejection comes from the proof check rather than the parser.
        val bitFlip = mapOf(
            "description" to "XOR 0x01 into the last byte (the low byte of the second ZKP scalar r)",
            "op" to "xor",
            "offset" to clientRound1.size - 1,
            "mask" to "01",
        )
        val corrupted = corrupt(clientRound1, bitFlip)
        written += write(
            outDir,
            "malformed-round1-zkp-01.json",
            common(
                kind = "malformed",
                description = "Corrupted peer round 1: the client round 1 payload with the low bit of " +
                    "its final ZKP scalar flipped, so the payload parses but the proof does not verify.",
                log = round1Log,
            ) + rejection(
                call = "readRound1",
                payload = corrupted,
                basePayload = clientRound1,
                corruption = bitFlip,
                outcome = captureRejection { EcJpake(EcJpake.Role.SERVER, SECRET, freshRand()).readRound1(corrupted) },
            ),
        )

        println("SPK-2: wrote ${written.size} fixture(s) to $outDir")
        written.forEach { println("SPK-2:   ${it.name} (${it.length()} bytes)") }
    }

    // -- Verification helpers --------------------------------------------------

    /**
     * One side of the handshake rebuilt from the recorded draws and the JPAKE secret,
     * with no reference to anything `EcJpake` emitted. This is the same computation the
     * Swift port (and `scripts/spk2/ecjpake_replay.py`) has to perform.
     */
    private class Independent(val ec: ECParameterSpec, rand: RecordingRandom) {
        val role: String = rand.role
        val id: ByteArray = rand.role.toByteArray(Charsets.US_ASCII)
        private val s = BigInteger(1, SECRET)

        val x1: BigInteger = scalar(rand, 0)
        val v1: BigInteger = scalar(rand, 1)
        val x2: BigInteger = scalar(rand, 2)
        val v2: BigInteger = scalar(rand, 3)
        private val round2Blind: ByteArray = rand.draws[4].bytes
        val vRound2: BigInteger = scalar(rand, 5)
        private val deriveBlind: ByteArray = rand.draws[6].bytes

        val X1: ECPoint = ec.g.multiply(x1)
        val X2: ECPoint = ec.g.multiply(x2)

        /** Round 2 uses the generator `peer.X1 + peer.X2 + own.X1`. */
        fun round2Generator(peer: Independent): ECPoint = peer.X1.add(peer.X2).add(X1)

        /** Mirror of `EcJpake.mulSecret`, with the blinding factor taken from the log. */
        fun mulSecret(blind: ByteArray, negate: Boolean): BigInteger {
            val bN = BigInteger(1, blind).multiply(ec.n).add(s)
            val r = x2.multiply(bN)
            return (if (negate) r.negate() else r).mod(ec.n)
        }

        fun round2Scalar(): BigInteger = mulSecret(round2Blind, negate = false)

        fun deriveScalar(): BigInteger = mulSecret(deriveBlind, negate = true)

        /** Mirror of `EcJpake.zkpHash`. */
        fun zkpHash(gen: ECPoint, commitment: ECPoint, pub: ECPoint): BigInteger {
            val out = ByteArrayOutputStream()
            for (point in listOf(gen, commitment, pub)) {
                val encoded = point.normalize().getEncoded(false)
                out.write(be32(encoded.size))
                out.write(encoded)
            }
            out.write(be32(id.size))
            out.write(id)
            val digest = MessageDigest.getInstance(HASH).digest(out.toByteArray())
            return BigInteger(1, digest).mod(ec.n)
        }

        /** Mirror of `EcJpake.writeZkp`'s response scalar `r = v - x*h mod n`. */
        fun zkpResponse(gen: ECPoint, priv: BigInteger, pub: ECPoint, nonce: BigInteger): BigInteger {
            val commitment = gen.multiply(nonce)
            val h = zkpHash(gen, commitment, pub)
            return nonce.subtract(priv.multiply(h)).mod(ec.n)
        }

        private fun scalar(rand: RecordingRandom, index: Int): BigInteger =
            BigInteger(1, rand.draws[index].bytes)
    }

    private fun assertDrawsMatchSpec(rand: RecordingRandom) {
        assertEquals(
            "unexpected number of RNG draws for role '${rand.role}'; EcJpake's randomness use changed",
            expectedDraws.size,
            rand.draws.size,
        )
        expectedDraws.forEachIndexed { index, spec ->
            val draw = rand.draws[index]
            assertEquals("draw $index for '${rand.role}' came from the wrong phase", spec.phase, draw.phase)
            assertEquals("draw $index for '${rand.role}' had an unexpected size", spec.size, draw.bytes.size)
        }
    }

    /**
     * Checks every field of an emitted round 1 payload — both public points, both ZKP
     * commitments and both response scalars — against values recomputed from the log.
     */
    private fun verifyRound1(round1: ByteArray, side: Independent) {
        val ec = side.ec
        val reader = Reader(round1)
        val x1 = reader.point(ec)
        val v1 = reader.point(ec)
        val r1 = reader.num()
        val x2 = reader.point(ec)
        val v2 = reader.point(ec)
        val r2 = reader.num()
        assertEquals("round 1 for '${side.role}' had trailing bytes", round1.size, reader.pos)

        assertSamePoint("${side.role} X1", side.X1, x1)
        assertSamePoint("${side.role} ZKP V for X1", ec.g.multiply(side.v1), v1)
        assertEquals(
            "${side.role} ZKP response r for X1 does not match the value recomputed from the log",
            side.zkpResponse(ec.g, side.x1, side.X1, side.v1),
            r1,
        )
        assertSamePoint("${side.role} X2", side.X2, x2)
        assertSamePoint("${side.role} ZKP V for X2", ec.g.multiply(side.v2), v2)
        assertEquals(
            "${side.role} ZKP response r for X2 does not match the value recomputed from the log",
            side.zkpResponse(ec.g, side.x2, side.X2, side.v2),
            r2,
        )
    }

    /**
     * Checks every field of an emitted round 2 payload — the curve id the server writes,
     * the public point `Xm`, the ZKP commitment and the response scalar — against values
     * recomputed from the log and the JPAKE secret. Returns the recomputed `Xm`, which
     * feeds the peer's derived-secret check.
     */
    private fun verifyRound2(
        round2: ByteArray,
        side: Independent,
        peer: Independent,
        hasCurveId: Boolean,
    ): ECPoint {
        val ec = side.ec
        val reader = Reader(round2)
        if (hasCurveId) {
            assertEquals("round 2 for '${side.role}' must start with ECCurveType.named_curve", 3, reader.u8())
            assertEquals("round 2 for '${side.role}' must name curve 23 (secp256r1)", 23, reader.u16())
        }
        val xmPoint = reader.point(ec)
        val v = reader.point(ec)
        val r = reader.num()
        assertEquals("round 2 for '${side.role}' had trailing bytes", round2.size, reader.pos)

        val gen = side.round2Generator(peer)
        val xm = side.round2Scalar()
        val expectedXm = gen.multiply(xm)
        assertSamePoint("${side.role} round 2 Xm", expectedXm, xmPoint)
        assertSamePoint("${side.role} round 2 ZKP V", gen.multiply(side.vRound2), v)
        assertEquals(
            "${side.role} round 2 ZKP response r does not match the value recomputed from the log",
            side.zkpResponse(gen, xm, expectedXm, side.vRound2),
            r,
        )
        return expectedXm
    }

    /**
     * Recomputes a role's derived secret from the log, the JPAKE secret and the peer's
     * *recomputed* round 2 point, then checks it against the secret `EcJpake` derived.
     * Nothing emitted by the implementation feeds this computation.
     */
    private fun verifyDerivedSecret(
        produced: ByteArray,
        side: Independent,
        peer: Independent,
        peerXm: ECPoint,
    ) {
        val k = peerXm.add(peer.X2.multiply(side.deriveScalar())).multiply(side.x2)
        val expected = MessageDigest.getInstance(HASH)
            .digest(BigIntegers.asUnsignedByteArray(k.normalize().xCoord.toBigInteger()))
        assertArrayEquals(
            "${side.role} derived secret does not match the value recomputed from the log",
            expected,
            produced,
        )
    }

    private fun assertSamePoint(what: String, expected: ECPoint, actual: ECPoint) {
        assertArrayEquals(
            "$what does not match the point recomputed from the recorded RNG log",
            expected.normalize().getEncoded(false),
            actual.normalize().getEncoded(false),
        )
    }

    /** Minimal reader mirroring `EcJpake`'s wire format, used to check the payloads. */
    private class Reader(private val data: ByteArray) {
        var pos = 0
            private set

        fun u8(): Int = data[pos++].toInt() and 0xFF

        fun u16(): Int = (u8() shl 8) or u8()

        fun bytes(count: Int): ByteArray {
            val slice = data.copyOfRange(pos, pos + count)
            pos += count
            return slice
        }

        fun point(ec: ECParameterSpec): ECPoint = ec.curve.decodePoint(bytes(u8()))

        fun num(): BigInteger = BigInteger(1, bytes(u8()))
    }

    /** A `SecureRandom` for instances that must not consume randomness at all. */
    private fun freshRand(): SecureRandom = object : SecureRandom() {
        override fun nextBytes(bytes: ByteArray) =
            error("the malformed-input scenarios must not consume randomness")
    }

    private fun captureRejection(block: () -> Unit): Throwable {
        val thrown = try {
            block()
            null
        } catch (e: Throwable) {
            e
        }
        assertTrue("the malformed payload was accepted; it is not a rejection vector", thrown != null)
        return thrown!!
    }

    // -- Fixture assembly ------------------------------------------------------

    private fun common(kind: String, description: String, log: List<Any>): Map<String, Any?> = mapOf(
        "schema_version" to 1,
        "kind" to kind,
        "description" to description,
        "curve" to CURVE,
        "hash" to HASH,
        "client_id" to CLIENT_ID,
        "server_id" to SERVER_ID,
        "secret" to hex(SECRET),
        "randomness" to mapOf(
            "scheme" to SCHEME,
            "log" to log,
        ),
    )

    /**
     * Applies a machine-readable corruption descriptor — the same operations
     * `ecjpake_replay.apply_corruption` implements — to a well-formed payload.
     */
    private fun corrupt(base: ByteArray, corruption: Map<String, Any?>): ByteArray =
        when (val op = corruption["op"]) {
            "truncate" -> {
                val length = corruption["length"] as Int
                require(length in 0 until base.size) { "truncation length $length is not inside the payload" }
                base.copyOfRange(0, length)
            }
            "xor" -> {
                val offset = corruption["offset"] as Int
                val mask = unhex(corruption["mask"] as String)
                require(offset >= 0 && offset + mask.size <= base.size) { "xor at $offset runs off the payload" }
                val out = base.copyOf()
                for (i in mask.indices) {
                    out[offset + i] = (out[offset + i].toInt() xor mask[i].toInt()).toByte()
                }
                require(!out.contentEquals(base)) { "the mask is all zero; it would not corrupt anything" }
                out
            }
            else -> error("unsupported corruption op: $op")
        }

    private fun rejection(
        call: String,
        payload: ByteArray,
        basePayload: ByteArray,
        corruption: Map<String, Any?>,
        outcome: Throwable,
    ): Map<String, Any?> = mapOf(
        "input" to mapOf(
            "call" to call,
            "role" to SERVER_ID,
            "payload" to hex(payload),
            "base_payload" to hex(basePayload),
            "corruption" to corruption,
        ),
        "outcome" to mapOf(
            "rejected" to true,
            "exception_class" to outcome.javaClass.name,
            "message" to (outcome.message ?: ""),
        ),
    )

    /** Labels one role's draws with the purposes asserted by [assertDrawsMatchSpec]. */
    private fun logEntries(rand: RecordingRandom): List<Any> = rand.draws.mapIndexed { index, draw ->
        mapOf(
            "role" to draw.role,
            "purpose" to expectedDraws[index].purpose,
            "bytes" to hex(draw.bytes),
        )
    }

    private fun write(outDir: File, name: String, fixture: Map<String, Any?>): File {
        val file = File(outDir, name)
        file.writeText(renderJson(fixture, "") + "\n", Charsets.UTF_8)
        return file
    }

    private fun resolveOutputDir(): File {
        val configured = System.getProperty(OUT_PROPERTY)?.takeIf { it.isNotBlank() }
            ?: System.getenv(OUT_ENV)?.takeIf { it.isNotBlank() }
            ?: error(
                "no fixture output directory: set -D$OUT_PROPERTY=<dir> (or $OUT_ENV). " +
                    "scripts/spk2/verify_vectors.sh does this for you.",
            )
        val dir = File(configured)
        dir.mkdirs()
        assertTrue("fixture output directory is not usable: $dir", dir.isDirectory)
        return dir
    }

    // -- Deterministic JSON ----------------------------------------------------

    private fun renderJson(value: Any?, indent: String): String = when (value) {
        null -> "null"
        is String -> quote(value)
        is Boolean -> value.toString()
        is Int, is Long -> value.toString()
        is Map<*, *> -> if (value.isEmpty()) "{}" else {
            val inner = "$indent  "
            value.entries
                .sortedBy { it.key as String }
                .joinToString(",\n", "{\n", "\n$indent}") { (key, entry) ->
                    "$inner${quote(key as String)}: ${renderJson(entry, inner)}"
                }
        }
        is List<*> -> if (value.isEmpty()) "[]" else {
            val inner = "$indent  "
            value.joinToString(",\n", "[\n", "\n$indent]") { "$inner${renderJson(it, inner)}" }
        }
        else -> error("unsupported JSON value type: ${value.javaClass.name}")
    }

    private fun quote(value: String): String {
        val out = StringBuilder("\"")
        for (c in value) {
            when {
                c == '"' -> out.append("\\\"")
                c == '\\' -> out.append("\\\\")
                c == '\n' -> out.append("\\n")
                c == '\r' -> out.append("\\r")
                c == '\t' -> out.append("\\t")
                c < ' ' -> out.append(String.format("\\u%04x", c.code))
                else -> out.append(c)
            }
        }
        return out.append('"').toString()
    }

    private fun hex(bytes: ByteArray): String {
        val out = StringBuilder(bytes.size * 2)
        for (b in bytes) out.append(String.format("%02x", b.toInt() and 0xFF))
        return out.toString()
    }

    private fun unhex(value: String): ByteArray {
        require(value.length % 2 == 0) { "not a hex string: $value" }
        return ByteArray(value.length / 2) { value.substring(it * 2, it * 2 + 2).toInt(16).toByte() }
    }

    private companion object {

        /** Big-endian uint32, as `EcJpake.writeUint32Be` emits into the ZKP hash input. */
        fun be32(value: Int): ByteArray = byteArrayOf(
            ((value ushr 24) and 0xFF).toByte(),
            ((value ushr 16) and 0xFF).toByte(),
            ((value ushr 8) and 0xFF).toByte(),
            (value and 0xFF).toByte(),
        )

        const val OUT_PROPERTY = "spk2.fixture.out"
        const val OUT_ENV = "SPK2_FIXTURE_OUT"

        const val CURVE = "P-256"
        const val HASH = "SHA-256"
        const val CLIENT_ID = "client"
        const val SERVER_ID = "server"

        /** Matches JpakeAuthenticator.pairingCodeToBytes("123456"). */
        val SECRET: ByteArray = "123456".toByteArray(Charsets.US_ASCII)

        const val CLIENT_SEED = "SPK-2/EC-JPAKE/client/v1"
        const val SERVER_SEED = "SPK-2/EC-JPAKE/server/v1"

        const val SCHEME =
            "Deterministic SHA-256 counter stream. Each role's SecureRandom returns the " +
                "concatenation of SHA-256(seedAscii || be32(i)) for i = 0, 1, 2, ..., consumed " +
                "sequentially across calls; seedAscii is \"$CLIENT_SEED\" for the client and " +
                "\"$SERVER_SEED\" for the server. A port does not need to reimplement this: " +
                "'log' below lists, in call order, every byte string SecureRandom.nextBytes " +
                "returned to EcJpake."
    }
}
