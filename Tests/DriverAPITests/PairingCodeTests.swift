import Testing
import DriverAPI

@Suite("Pairing code")
struct PairingCodeTests {
    @Test("Length is accepted from 6 to 16 characters inclusive")
    func lengthBounds() {
        #expect(PairingCode("") == nil)
        #expect(PairingCode("12345") == nil)
        #expect(PairingCode("123456") != nil)
        #expect(PairingCode(String(repeating: "x", count: 16)) != nil)
        #expect(PairingCode(String(repeating: "x", count: 17)) == nil)
    }

    @Test("Length is counted in characters, not bytes or scalars")
    func lengthUsesCharacters() {
        // "e" + combining acute accent: one Character, two scalars, three UTF-8 bytes.
        let accented = "e\u{301}"
        #expect(PairingCode(String(repeating: accented, count: 5)) == nil)
        #expect(PairingCode(String(repeating: accented, count: 6))?.characterCount == 6)
        #expect(PairingCode(String(repeating: accented, count: 16)) != nil)
        #expect(PairingCode(String(repeating: accented, count: 17)) == nil)
    }

    @Test("The code is kept verbatim: spaces, case and punctuation")
    func keptVerbatim() throws {
        let spaced = try #require(PairingCode(" 1234 "))
        #expect(spaced.utf8Bytes == Array(" 1234 ".utf8))
        #expect(spaced.characterCount == 6)
        let mixed = try #require(PairingCode("aBcDeF"))
        #expect(mixed.utf8Bytes == Array("aBcDeF".utf8))
        #expect(mixed != PairingCode("abcdef"))
        let punctuated = try #require(PairingCode("a-b.c!d?"))
        #expect(punctuated.utf8Bytes == Array("a-b.c!d?".utf8))
    }

    @Test("The secret bytes are the UTF-8 encoding, matching the committed vector")
    func codeBytesMatchFixtureSecret() throws {
        // `secret` in Tests/Fixtures/EcJpake/handshake-client-01.json.
        let code = try #require(PairingCode("123456"))
        #expect(code.utf8Bytes == [0x31, 0x32, 0x33, 0x34, 0x35, 0x36])
    }

    @Test("Identity follows the secret bytes, not Unicode canonical equivalence")
    func identityIsBytewise() throws {
        // Precomposed and decomposed e-acute: equal as Strings, different secrets.
        let composed = try #require(PairingCode("\u{E9}12345"))
        let decomposed = try #require(PairingCode("e\u{301}12345"))
        #expect("\u{E9}12345" == "e\u{301}12345")
        #expect(composed.utf8Bytes != decomposed.utf8Bytes)
        #expect(composed != decomposed)

        let distinct = Set([composed, decomposed])
        #expect(distinct.contains(composed))
        #expect(distinct.contains(decomposed))
        let distinctCount = distinct.count
        #expect(distinctCount == 2)

        let repeated = Set([composed, try #require(PairingCode("\u{E9}12345"))])
        let repeatedCount = repeated.count
        #expect(repeatedCount == 1)
    }

    @Test("Descriptions, reflection and dumps never show the code")
    func neverPrinted() throws {
        let code = try #require(PairingCode("987654"))
        #expect(code.description == "pairing code")
        #expect(code.debugDescription == "pairing code")
        #expect(String(describing: code) == "pairing code")
        #expect(String(reflecting: code) == "pairing code")
        #expect("\(code)" == "pairing code")
        #expect(Mirror(reflecting: code).children.isEmpty)
        var dumped = ""
        dump(code, to: &dumped)
        #expect(!dumped.contains("987654"))
    }
}
