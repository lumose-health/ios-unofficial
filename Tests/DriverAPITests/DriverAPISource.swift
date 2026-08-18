import Foundation

/// Reads `Sources/DriverAPI/` as text, with comments removed and string contents
/// elided.
///
/// Several of this target's assertions are about what the source does NOT
/// contain — no calibration member, no settable protocol requirement, no runtime
/// registration path. Those are structural claims, and the only way to assert
/// them is to read the source. Doing that on the raw text would be worse than
/// useless: the doc comments explain at length WHY calibration is absent, so a
/// raw scan for "calibration" fails on the very comment that documents the rule.
///
/// So the scan runs over stripped code, the same posture
/// `scripts/guards/safety_guards.sh` takes: naming a thing in a comment or a
/// string is not declaring it.
///
/// ## What this stripper does and does not model
///
/// Models: line comments, NESTED block comments, ordinary strings, multi-line
/// strings, and the raw variants of both with any number of `#`s — including the
/// rule that a raw string's escapes and its terminator carry the same hash count,
/// so an inner `"#` inside a `##"…"##` literal does not end it.
///
/// Does NOT model: interpolated expressions, which are elided along with the rest
/// of the string rather than scanned as the code they are. That is a real gap
/// and it is the same one `safety_guards.sh` documents; it does not matter here
/// because these assertions are about DECLARATIONS, and a declaration cannot be
/// written inside an interpolation.
enum DriverAPISource {

    /// The repository root, from this file's location: Tests/DriverAPITests/<this>.
    static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // DriverAPITests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // repo root

    static let targetRoot = repositoryRoot
        .appendingPathComponent("Sources")
        .appendingPathComponent("DriverAPI")

    /// Every Swift file in the target, path-sorted, as `(relative path, code)`.
    ///
    /// - Throws: ``StripError`` if any file has an unterminated comment or string.
    ///   A file that cannot be stripped is a file that was not read, and an
    ///   assertion over source it never read is an assertion that always passes.
    static func files(under subdirectory: String? = nil) throws -> [(path: String, code: String)] {
        var directory = targetRoot
        if let subdirectory { directory = directory.appendingPathComponent(subdirectory) }

        let enumerated = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil
        )
        var urls: [URL] = []
        while let entry = enumerated?.nextObject() as? URL {
            if entry.pathExtension == "swift" { urls.append(entry) }
        }
        precondition(!urls.isEmpty, "no Swift files under \(directory.path) — nothing would be scanned")

        return try urls
            .sorted { $0.path < $1.path }
            .map { url in
                let source = try String(contentsOf: url, encoding: .utf8)
                let relative = url.path.replacingOccurrences(of: repositoryRoot.path + "/", with: "")
                return (relative, try stripped(source))
            }
    }

    /// Every declaration line in the target, as `(relative path, line)`.
    static func lines(under subdirectory: String? = nil) throws -> [(path: String, line: String)] {
        try files(under: subdirectory).flatMap { file in
            file.code
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { (file.path, String($0)) }
        }
    }

    enum StripError: Error, Equatable {
        case unterminatedBlockComment
        case unterminatedString
    }

    // MARK: - Declarations

    /// One type-ish declaration: its keyword, its name, and what it inherits from
    /// or conforms to.
    struct Declaration: Hashable {
        let path: String
        let keyword: String
        let name: String
        let inherited: [String]

        var description: String { "\(keyword) \(name) (\(path))" }
    }

    /// Every `protocol` / `enum` / `struct` / `class` / `actor` / `extension`
    /// declaration in the target.
    ///
    /// ## Why this is not a per-line scan
    ///
    /// The first version of these tests matched declarations one line at a time
    /// and required the conformance to sit on the same line as the keyword. That
    /// is not a check, it is a formatting preference: `public protocol ExtraSource:`
    /// with `DriverCapability` on the next line — which is what swift-format
    /// produces for a long inheritance list — walked straight past a test whose
    /// entire job was to notice a seventh port. A second `Error` enum did the
    /// same.
    ///
    /// So the whole stripped file is collapsed to one whitespace-normalised token
    /// stream first, and declarations are read from that. Where the line breaks
    /// fall stops being a variable.
    static func declarations() throws -> [Declaration] {
        try files().flatMap { declarations(inStripped: $0.code, path: $0.path) }
    }

    /// The same scan over one source string, so the scan itself can be tested
    /// against the shapes it is supposed to catch.
    static func declarations(in source: String, path: String = "<literal>") throws -> [Declaration] {
        declarations(inStripped: try stripped(source), path: path)
    }

    private static func declarations(inStripped code: String, path: String) -> [Declaration] {
        let keywords: Set<String> = ["protocol", "enum", "struct", "class", "actor", "extension"]
        var found: [Declaration] = []
        let tokens = tokenize(code)
        var index = 0

        while index < tokens.count {
            defer { index += 1 }
            guard keywords.contains(tokens[index]), index + 1 < tokens.count else { continue }
            // `case protocolCompatible` tokenizes as one identifier, so a keyword
            // token here really is the keyword. A member access is the one thing
            // that can precede it and change its meaning.
            if index > 0, tokens[index - 1] == "." { continue }
            let name = tokens[index + 1]
            guard isIdentifier(name) else { continue }

            var cursor = skipGenericClause(tokens, from: index + 2)
            var inherited: [String] = []
            if cursor < tokens.count, tokens[cursor] == ":" {
                cursor += 1
                var current = ""
                while cursor < tokens.count, tokens[cursor] != "{", tokens[cursor] != "where" {
                    if tokens[cursor] == "," {
                        if !current.isEmpty { inherited.append(current) }
                        current = ""
                    } else if tokens[cursor] == "<" {
                        cursor = skipGenericClause(tokens, from: cursor) - 1
                    } else if isIdentifier(tokens[cursor]) {
                        current = tokens[cursor]
                    }
                    cursor += 1
                }
                if !current.isEmpty { inherited.append(current) }
            }
            found.append(Declaration(path: path, keyword: tokens[index], name: name, inherited: inherited))
        }
        return found
    }

    /// Identifiers and single punctuation characters, in source order.
    static func tokenize(_ code: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        for character in code {
            if character.isLetter || character.isNumber || character == "_" {
                current.append(character)
                continue
            }
            if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
            if !character.isWhitespace { tokens.append(String(character)) }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    private static func isIdentifier(_ token: String) -> Bool {
        guard let first = token.first else { return false }
        return first.isLetter || first == "_"
    }

    /// The index just past a `<…>` clause starting at `from`, or `from` itself.
    private static func skipGenericClause(_ tokens: [String], from start: Int) -> Int {
        guard start < tokens.count, tokens[start] == "<" else { return start }
        var depth = 0
        var index = start
        while index < tokens.count {
            if tokens[index] == "<" { depth += 1 }
            if tokens[index] == ">" {
                depth -= 1
                if depth == 0 { return index + 1 }
            }
            index += 1
        }
        return index
    }

    /// `source` with comments removed and every string literal replaced by `""`.
    ///
    /// The replacement is a token rather than nothing so that the text either side
    /// of an elided literal cannot fuse into an identifier that was never written.
    static func stripped(_ source: String) throws -> String {
        let characters = Array(source)
        var output = ""
        var index = 0

        while index < characters.count {
            if matches("//", characters, index) {
                while index < characters.count, characters[index] != "\n" { index += 1 }
                continue
            }
            if matches("/*", characters, index) {
                index = try skipBlockComment(characters, from: index)
                continue
            }
            if let after = try skipStringLiteral(characters, from: index) {
                output += "\"\""
                index = after
                continue
            }
            output.append(characters[index])
            index += 1
        }
        return output
    }

    private static func matches(_ token: String, _ characters: [Character], _ index: Int) -> Bool {
        let token = Array(token)
        guard index + token.count <= characters.count else { return false }
        return Array(characters[index..<(index + token.count)]) == token
    }

    /// Swift block comments NEST, so a `/*` inside one is not decoration.
    private static func skipBlockComment(_ characters: [Character], from start: Int) throws -> Int {
        var index = start + 2
        var depth = 1
        while index < characters.count {
            if matches("/*", characters, index) {
                depth += 1
                index += 2
            } else if matches("*/", characters, index) {
                depth -= 1
                index += 2
                if depth == 0 { return index }
            } else {
                index += 1
            }
        }
        throw StripError.unterminatedBlockComment
    }

    /// The index just past the string literal starting at `start`, or `nil` if no
    /// literal starts there.
    ///
    /// A `#` run is only a literal opener when a quote follows it — otherwise it is
    /// a directive such as `#filePath`, and swallowing one as a string would elide
    /// the rest of the file.
    private static func skipStringLiteral(_ characters: [Character], from start: Int) throws -> Int? {
        var index = start
        var hashes = 0
        while index < characters.count, characters[index] == "#" {
            hashes += 1
            index += 1
        }
        guard index < characters.count, characters[index] == "\"" else { return nil }

        let hashSuffix = String(repeating: "#", count: hashes)
        let multiline = matches("\"\"\"", characters, index)
        let terminator = (multiline ? "\"\"\"" : "\"") + hashSuffix
        index += multiline ? 3 : 1

        while index < characters.count {
            // An escape in a raw string carries the same hash count as its
            // delimiter: `\#(` in a `#"…"#`, `\##(` in a `##"…"##`.
            if characters[index] == "\\", matches(hashSuffix, characters, index + 1) {
                index += 1 + hashes + 1
                continue
            }
            if matches(terminator, characters, index) {
                return index + terminator.count
            }
            if !multiline, characters[index] == "\n" {
                throw StripError.unterminatedString
            }
            index += 1
        }
        throw StripError.unterminatedString
    }
}
