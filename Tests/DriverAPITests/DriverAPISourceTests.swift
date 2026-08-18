import Foundation
import Testing

@testable import DriverAPI

/// The structural assertions in this target are only as good as the stripper
/// underneath them, and every one of them is a claim that something is ABSENT — a
/// stripper that elides too much makes all of them pass over an empty string.
///
/// So the stripper is exercised against source this repository does not have,
/// in both directions: what it must remove, and what it must NOT.
@Suite("DriverAPI source scanning")
struct DriverAPISourceTests {

    @Test("Line and nested block comments are removed")
    func commentsAreRemoved() throws {
        #expect(try DriverAPISource.stripped("let a = 1 // calibration\n").contains("calibration") == false)
        #expect(try DriverAPISource.stripped("/* calibration */ let a = 1").contains("calibration") == false)
        #expect(
            try DriverAPISource.stripped("/* outer /* inner */ calibration */ let a = 1")
                .contains("calibration") == false,
            "Swift block comments nest; treating the first `*/` as the end leaves the tail scanned as code."
        )
    }

    @Test("Code around a comment survives")
    func codeAroundCommentsSurvives() throws {
        let code = try DriverAPISource.stripped("let before = 1 /* c */ + after // trailing\nlet next = 2")
        #expect(code.contains("before"))
        #expect(code.contains("after"))
        #expect(code.contains("next"))
    }

    @Test("String contents are elided, in every string form")
    func stringContentsAreElided() throws {
        let forms = [
            #"let s = "calibration""#,
            ##"let s = #"calibration"#"##,
            ###"let s = ##"calibration"##"###,
            "let s = \"\"\"\ncalibration\n\"\"\"",
        ]
        for form in forms {
            #expect(try DriverAPISource.stripped(form).contains("calibration") == false, "not elided: \(form)")
        }
    }

    @Test("A string cannot end early and leave its tail scanned as text")
    func rawStringDelimitersAreCounted() throws {
        // The inner `"#` would close a `#"…"#` literal but must not close a
        // `##"…"##` one. If it did, `calibration` would land outside the string.
        let code = try DriverAPISource.stripped(###"let s = ##"a "# calibration"##; let real = 1"###)
        #expect(code.contains("calibration") == false)
        #expect(code.contains("real"), "the declaration after the literal must still be visible")
    }

    @Test("A hash directive is not a string opener")
    func hashDirectivesAreNotStrings() throws {
        let code = try DriverAPISource.stripped("let path = #filePath\nlet calibrationCount = 1")
        #expect(code.contains("calibrationCount"), "swallowing `#filePath` as a string would elide the rest of the file")
    }

    @Test("An unterminated comment or string is refused, not scanned")
    func unterminatedInputIsRefused() {
        #expect(throws: DriverAPISource.StripError.unterminatedBlockComment) {
            try DriverAPISource.stripped("/* open\nlet a = 1")
        }
        #expect(throws: DriverAPISource.StripError.unterminatedString) {
            try DriverAPISource.stripped("let s = \"open\n")
        }
        #expect(throws: DriverAPISource.StripError.unterminatedString) {
            try DriverAPISource.stripped("let s = \"\"\"\nopen\n")
        }
    }

    @Test("The target's own source parses, and there is source to parse")
    func targetSourceParses() throws {
        let files = try DriverAPISource.files()
        #expect(files.count >= 10, "found \(files.count) file(s) under Sources/DriverAPI — the scans below would be near-empty")
        #expect(files.allSatisfy { !$0.code.isEmpty })
    }
}
