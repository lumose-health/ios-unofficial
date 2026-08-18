import Foundation
import SafetyCore
import Testing

@_spi(DriverPlatform) @testable import DriverAPI

/// Safety Limits narrow the absolute bound and never widen it (FR-32, SI-11).
@Suite("Safety limits")
struct SafetyLimitsTests {

    static let absoluteLower = SafetyConstants.glucoseValidRange.lowerBound
    static let absoluteUpper = SafetyConstants.glucoseValidRange.upperBound

    @Test("The widest limits are the absolute bound itself")
    func absoluteLimitsMatchTheCanonicalBound() {
        #expect(SafetyLimits.absolute.glucoseRange == SafetyConstants.glucoseValidRange)
    }

    @Test("Limits inside the absolute bound are accepted")
    func narrowingIsAccepted() throws {
        let limits = try SafetyLimits(
            glucoseLower: Self.absoluteLower + 20,
            glucoseUpper: Self.absoluteUpper - 100
        )
        #expect(limits.glucoseRange.lowerBound == Self.absoluteLower + 20)
        #expect(limits.glucoseRange.upperBound == Self.absoluteUpper - 100)
    }

    @Test("Limits equal to the absolute bound are accepted")
    func matchingTheAbsoluteBoundIsAccepted() throws {
        let limits = try SafetyLimits(glucoseLower: Self.absoluteLower, glucoseUpper: Self.absoluteUpper)
        #expect(limits.glucoseRange == SafetyConstants.glucoseValidRange)
    }

    /// The direction that matters. A limit reaching below the absolute floor
    /// admits warm-up noise as a hypoglycaemia reading; one reaching above the
    /// ceiling admits a garbage frame as a hyperglycaemia reading. Both arrive
    /// from a remote configuration, so both are refused by the type.
    @Test("A limit that reaches outside the absolute bound is refused, either end")
    func wideningIsRefused() {
        let widened: [(Double, Double)] = [
            (Self.absoluteLower - 1, Self.absoluteUpper),
            (Self.absoluteLower, Self.absoluteUpper + 1),
            (Self.absoluteLower - 100, Self.absoluteUpper + 100),
            (0, Self.absoluteUpper),
            (Self.absoluteLower, .greatestFiniteMagnitude),
        ]
        for (lower, upper) in widened {
            #expect(throws: DriverFailure.safetyLimitRejected(.widensAbsoluteBound(lower: lower, upper: upper))) {
                _ = try SafetyLimits(glucoseLower: lower, glucoseUpper: upper)
            }
        }
    }

    @Test("An empty or inverted range is refused")
    func emptyOrInvertedIsRefused() {
        let midpoint = (Self.absoluteLower + Self.absoluteUpper) / 2
        #expect(throws: DriverFailure.safetyLimitRejected(.emptyOrInverted(lower: midpoint, upper: midpoint))) {
            _ = try SafetyLimits(glucoseLower: midpoint, glucoseUpper: midpoint)
        }
        #expect(throws: DriverFailure.safetyLimitRejected(
            .emptyOrInverted(lower: Self.absoluteUpper, upper: Self.absoluteLower)
        )) {
            _ = try SafetyLimits(glucoseLower: Self.absoluteUpper, glucoseUpper: Self.absoluteLower)
        }
    }

    @Test("A non-finite bound is refused")
    func nonFiniteIsRefused() {
        let nonFinite: [(Double, Double)] = [
            (.nan, Self.absoluteUpper),
            (Self.absoluteLower, .nan),
            (-.infinity, Self.absoluteUpper),
            (Self.absoluteLower, .infinity),
        ]
        for (lower, upper) in nonFinite {
            #expect(throws: DriverFailure.safetyLimitRejected(.notFinite)) {
                _ = try SafetyLimits(glucoseLower: lower, glucoseUpper: upper)
            }
        }
    }

    /// Nothing is clamped and nothing is substituted. Android's `safeOf` clamps
    /// out-of-range configuration into the absolute bound; that applies a safety
    /// bound the user did not configure as though they had, so there is no such
    /// factory here — the initializer is the only way in.
    @Test("A refused limit produces no value at all")
    func refusalProducesNothing() {
        let refused = try? SafetyLimits(glucoseLower: Self.absoluteLower - 50, glucoseUpper: Self.absoluteUpper)
        #expect(refused == nil, "a rejected configuration must not be clamped into a usable value")
    }

    /// SI-11: a rejected limit leaves last-known-good in force. The type carries
    /// this by being a value — a refused construction cannot touch the limits the
    /// caller is already holding, because there is nothing shared to touch.
    @Test("A refused limit leaves the limits already in force untouched")
    func refusalLeavesLastKnownGoodInForce() throws {
        let inForce = try SafetyLimits(glucoseLower: Self.absoluteLower + 50, glucoseUpper: Self.absoluteUpper - 50)
        let before = inForce.glucoseRange
        _ = try? SafetyLimits(glucoseLower: Self.absoluteLower - 1, glucoseUpper: Self.absoluteUpper + 1)
        #expect(inForce.glucoseRange == before)
    }

    // MARK: - Validation

    /// The platform's validator, started at `limits`. The SPI import at the top of
    /// this file is what makes this line possible at all — a Driver target cannot
    /// write it and pass `driver_guards.sh`.
    static func validator(_ limits: SafetyLimits) -> SafetyLimitsValidator {
        SafetyLimitsValidator(limits: limits)
    }

    @Test("A value inside the limits validates to a Glucose")
    func inRangeValueValidates() throws {
        let limits = try SafetyLimits(glucoseLower: Self.absoluteLower + 50, glucoseUpper: Self.absoluteUpper - 50)
        let validator = Self.validator(limits)
        let midpoint = (limits.glucoseRange.lowerBound + limits.glucoseRange.upperBound) / 2
        let glucose = try validator.validate(mgdl: midpoint)
        #expect(glucose.mgdl == midpoint)
    }

    @Test("The bounds themselves are inside the limits")
    func boundsAreInclusive() throws {
        let limits = try SafetyLimits(glucoseLower: Self.absoluteLower + 50, glucoseUpper: Self.absoluteUpper - 50)
        let validator = Self.validator(limits)
        #expect(try validator.validate(mgdl: limits.glucoseRange.lowerBound).mgdl == limits.glucoseRange.lowerBound)
        #expect(try validator.validate(mgdl: limits.glucoseRange.upperBound).mgdl == limits.glucoseRange.upperBound)
    }

    @Test("A value outside the limits is rejected, and the message names the bound")
    func outOfRangeValueIsRejected() throws {
        let limits = try SafetyLimits(glucoseLower: Self.absoluteLower + 50, glucoseUpper: Self.absoluteUpper - 50)
        let validator = Self.validator(limits)
        for value in [limits.glucoseRange.lowerBound - 1, limits.glucoseRange.upperBound + 1, .nan] as [Double] {
            do {
                _ = try validator.validate(mgdl: value)
                Issue.record("\(value) was admitted by \(limits.glucoseRange)")
            } catch {
                guard case .valueRejected(let bound) = error else {
                    Issue.record("wrong failure for \(value): \(error)")
                    continue
                }
                #expect(!bound.isEmpty, "the rejection must name the bound that refused the value")
            }
        }
    }

    // MARK: - Fresh means fresh

    /// The claim under test: the user narrows their range, and the NEXT reading
    /// is judged by the narrower bound, with nothing invalidated or re-injected
    /// in between.
    ///
    /// Two earlier versions of this test proved less than they looked like they
    /// proved. The first compared two explicitly chosen receivers, which shows
    /// only that two values differ. The second held one receiver but that receiver
    /// was a TEST-DEFINED conformer of `SafetyLimitsSource` — so it proved the
    /// test's own type answers freshly, not that a Driver's has to. This one holds
    /// the real ``SafetyLimitsValidator``, the same reference throughout, and the
    /// only thing that changes is what the platform adopted.
    @Test("A narrowing is observed by the next validation, on the same received reference")
    func validationReadsLimitsFresh() throws {
        let wide = try SafetyLimits(glucoseLower: Self.absoluteLower, glucoseUpper: Self.absoluteUpper)
        let narrow = try SafetyLimits(glucoseLower: Self.absoluteLower + 50, glucoseUpper: Self.absoluteUpper - 50)
        let justInsideTheWideBound = Self.absoluteLower + 1

        // What a Driver is handed: one validator, and no way to make another.
        let received: SafetyLimitsValidator = Self.validator(wide)
        #expect(try received.validate(mgdl: justInsideTheWideBound).mgdl == justInsideTheWideBound)

        received.adopt(narrow)

        #expect(throws: DriverFailure.self) {
            _ = try received.validate(mgdl: justInsideTheWideBound)
        }
        // …and widening again is observed just as immediately: the reading that
        // was refused a moment ago is admitted, same reference, no reconstruction.
        received.adopt(wide)
        #expect(try received.validate(mgdl: justInsideTheWideBound).mgdl == justInsideTheWideBound)
        #expect(received.limitsInForce == wide)
    }

    /// The half the previous shape could not state: there is no protocol here for
    /// a Driver to conform with limits it captured at `init`.
    ///
    /// `SafetyLimitsSource` was exactly that, and a conformer holding
    /// `let currentLimits: SafetyLimits` compiled, passed every gate, and validated
    /// against a bound the user had since narrowed. The replacement is a `final
    /// class` — nothing to conform to, nothing to subclass, and no reachable way
    /// to build one.
    @Test("Nothing outside DriverAPI can supply or substitute the limits")
    func limitsCannotBeSuppliedByADriver() throws {
        let declarations = try DriverAPISource.declarations()

        // No protocol supplies safety state. The only protocol in the target that
        // is not a Capability port is `Driver` itself, pinned by
        // `CapabilitySetTests.exactlySixPortsAreDeclared`.
        #expect(declarations.contains { $0.keyword == "protocol" && $0.name == "SafetyLimitsSource" } == false)

        let validator = try #require(
            declarations.first { $0.keyword == "class" && $0.name == "SafetyLimitsValidator" }
        )
        #expect(validator.path.hasSuffix("Sources/DriverAPI/SafetyLimitsValidator.swift"))

        let file = try DriverAPISource.files()
            .first { $0.path.hasSuffix("Sources/DriverAPI/SafetyLimitsValidator.swift") }
        let code = try #require(file?.code).filter { !$0.isWhitespace }

        // `final`, so validate(mgdl:) cannot be overridden by a subclass.
        #expect(code.contains("publicfinalclassSafetyLimitsValidator"))
        // Every way to create or change one is behind the platform SPI, which
        // `driver_guards.sh` rule C refuses to let a Driver target import.
        #expect(code.contains("@_spi(DriverPlatform)publicinit(limits:SafetyLimits)"))
        #expect(code.contains("@_spi(DriverPlatform)publicfuncadopt(_limits:SafetyLimits)"))
        #expect(Self.occurrences(of: "publicinit", in: code) == 1)
        // …and validation itself is not behind the SPI: a Driver must be able to
        // use what it was handed, or the invariant would be enforced by making the
        // legitimate case impossible.
        #expect(code.contains("publicfuncvalidate(mgdl:Double)throws(DriverFailure)->Glucose"))
    }

    /// The other half of "no cache": there is no publicly reachable way to
    /// validate against a `SafetyLimits` value a caller is holding. A Driver that
    /// wants to admit a reading has to go through the validator.
    @Test("Validation is reachable only through the platform's validator")
    func validationIsOnlyOnTheValidator() throws {
        let file = try DriverAPISource.files()
            .first { $0.path.hasSuffix("Sources/DriverAPI/SafetyLimits.swift") }
        let code = try #require(file?.code).filter { !$0.isWhitespace }

        // `validate` on the value type is internal, and the widest-legal-bound
        // convenience is internal too — a `public static let absolute` is a limit
        // any Driver can hold and validate against for the life of the process.
        #expect(code.contains("publicfuncvalidate(mgdl:Double)throws(DriverFailure)->Glucose") == false)
        #expect(code.contains("funcvalidate(mgdl:Double)throws(DriverFailure)->Glucose"))
        #expect(code.contains("publicstaticletabsolute") == false)
        #expect(code.contains("staticletabsolute"))
    }

    static func occurrences(of needle: String, in haystack: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        var count = 0
        var cursor = haystack.startIndex
        while let found = haystack.range(of: needle, range: cursor..<haystack.endIndex) {
            count += 1
            cursor = found.upperBound
        }
        return count
    }

    @Test("SafetyLimits stores nothing but its range, and nothing mutable")
    func theTypeHoldsNoCache() throws {
        let file = try DriverAPISource.files()
            .first { $0.path.hasSuffix("Sources/DriverAPI/SafetyLimits.swift") }
        let code = try #require(file?.code)

        // Any access modifier counts: `private let cache` is exactly the stored
        // bound this test exists to catch, and a prefix list that only knew
        // `public` would wave it through.
        var storedProperties: [String] = []
        for line in code.split(separator: "\n") {
            let collapsed = line.filter { !$0.isWhitespace }
            let modifiers = ["public", "package", "internal", "fileprivate", "private", ""]
            let isDeclaration = modifiers.contains { modifier in
                collapsed.hasPrefix(modifier + "let") || collapsed.hasPrefix(modifier + "var")
            }
            guard isDeclaration else { continue }
            storedProperties.append(String(line).trimmingCharacters(in: .whitespaces))
        }
        #expect(storedProperties.count == 1, "stored properties: \(storedProperties)")
        #expect(storedProperties.first?.contains("glucoseRange") == true)
        #expect(code.contains("var ") == false, "no mutable storage of any kind belongs in a safety bound")
    }
}
