import Foundation
import Testing

@_spi(DriverPlatform) @testable import DriverAPI

/// One lifecycle, declared once, with every transition owned by the platform
/// (AD-16).
///
/// The SPI import at the top of this file is the point of the design, not a
/// detail of the test: `DriverLifecycle` is invisible to an ordinary
/// `import DriverAPI`, so this suite has to ask for it by name to test it at all.
/// A Driver target that asked the same way would compile — and fail
/// `scripts/guards/driver_guards.sh`, which refuses an `@_spi` import anywhere
/// under `Sources/Drivers/`.
@Suite("Driver lifecycle")
struct DriverLifecycleTests {

    @Test("The six states are declared, and they are these six")
    func statesAreTheDeclaredSix() {
        #expect(
            DriverLifecycleState.allCases == [
                .notActivated, .activating, .active, .degraded, .deactivating, .failed,
            ]
        )
    }

    @Test("A new lifecycle has not been activated")
    func startsNotActivated() {
        #expect(DriverLifecycle().state == .notActivated)
    }

    @Test("The happy path runs to active and back to rest")
    func happyPath() throws {
        var lifecycle = DriverLifecycle()
        try lifecycle.advance(to: .activating)
        try lifecycle.advance(to: .active)
        try lifecycle.advance(to: .deactivating)
        try lifecycle.advance(to: .notActivated)
        #expect(lifecycle.state == .notActivated)
    }

    @Test("Degraded is reachable from active and recoverable back to it")
    func degradedIsRecoverable() throws {
        var lifecycle = DriverLifecycle(restoring: .active)
        try lifecycle.advance(to: .degraded)
        try lifecycle.advance(to: .active)
        #expect(lifecycle.state == .active)
    }

    @Test("A Driver that failed can be activated again without a teardown first")
    func failedCanRetry() throws {
        var lifecycle = DriverLifecycle(restoring: .failed)
        try lifecycle.advance(to: .activating)
        #expect(lifecycle.state == .activating)
    }

    /// Teardown idempotence is a contract term on ``Driver/deactivate()``, and
    /// the state machine has to permit what the contract promises: a second
    /// teardown, and a teardown of something never activated, are no-ops rather
    /// than errors. A Core Bluetooth restoration can produce both.
    @Test("Teardown is idempotent in the state machine, not just in the doc comment")
    func teardownIsIdempotent() throws {
        var neverActivated = DriverLifecycle()
        try neverActivated.advance(to: .notActivated)
        #expect(neverActivated.state == .notActivated)

        var tearingDown = DriverLifecycle(restoring: .deactivating)
        try tearingDown.advance(to: .deactivating)
        try tearingDown.advance(to: .notActivated)
        #expect(tearingDown.state == .notActivated)
    }

    /// Re-asserting the state a Driver is already in is expected repetition,
    /// not a platform bug: a degraded Driver degrades again for a second
    /// reason, and a restoration re-entry can report a state the platform
    /// already holds. Pinned together with the one self-transition that stays
    /// refused — `activating → activating` — because a second activation while
    /// one is in flight is exactly the call ``Driver/activate()`` never has to
    /// defend against.
    @Test("Re-asserting a running state is an idempotent no-op")
    func reassertingARunningStateIsANoOp() throws {
        var active = DriverLifecycle(restoring: .active)
        try active.advance(to: .active)
        #expect(active.state == .active)

        var degraded = DriverLifecycle(restoring: .degraded)
        try degraded.advance(to: .degraded)
        #expect(degraded.state == .degraded)

        #expect(DriverLifecycleState.activating.permits(.activating) == false)
    }

    @Test("An illegal transition throws and leaves the state where it was")
    func illegalTransitionThrows() throws {
        var lifecycle = DriverLifecycle()
        #expect(throws: DriverFailure.illegalTransition(from: .notActivated, to: .active)) {
            try lifecycle.advance(to: .active)
        }
        #expect(lifecycle.state == .notActivated, "a refused transition must not partially apply")
    }

    @Test("Activation cannot be skipped and rest cannot be reached from a running state")
    func skippingStatesIsRefused() {
        let refused: [(DriverLifecycleState, DriverLifecycleState)] = [
            (.notActivated, .active),
            (.notActivated, .degraded),
            (.notActivated, .deactivating),
            (.notActivated, .failed),
            (.active, .activating),
            (.active, .notActivated),
            (.degraded, .activating),
            (.degraded, .notActivated),
            (.activating, .notActivated),
            (.deactivating, .active),
            (.deactivating, .activating),
            (.failed, .active),
            (.failed, .degraded),
            (.failed, .notActivated),
        ]
        for (from, to) in refused {
            #expect(from.permits(to) == false, "\(from) must not permit \(to)")
        }
    }

    @Test("Every state can still be torn down")
    func everyStateCanReachTeardown() {
        for state in DriverLifecycleState.allCases {
            let canRest = state == .notActivated
                || state.permits(.notActivated)
                || state.permits(.deactivating)
            #expect(canRest, "\(state) is a dead end — a Driver in it could never be torn down")
        }
    }

    /// The transition table is a property of the lifecycle, so `permits` and the
    /// mutation that uses it cannot disagree.
    @Test("advance accepts exactly what permits accepts")
    func advanceAgreesWithTheTable() {
        for from in DriverLifecycleState.allCases {
            for to in DriverLifecycleState.allCases {
                var lifecycle = DriverLifecycle(restoring: from)
                let advanced = (try? lifecycle.advance(to: to)) != nil
                #expect(advanced == from.permits(to), "\(from) -> \(to)")
            }
        }
    }

    // MARK: - The platform owns transitions

    /// A Driver has no lifecycle member to mutate — that is what "the platform
    /// owns every transition" means structurally, rather than as a rule someone
    /// remembers. The Driver protocol declares entry points and a descriptor, and
    /// nothing that reports or sets a state.
    /// The access control IS the ownership claim, so it is pinned rather than
    /// left to whoever next edits the file. Dropping the attribute would make
    /// `DriverLifecycle` visible to every Driver target at once, and nothing else
    /// in the build would notice.
    @Test("The lifecycle is SPI, so an ordinary import of DriverAPI cannot see it")
    func lifecycleIsPlatformSPI() throws {
        let file = try DriverAPISource.files()
            .first { $0.path.hasSuffix("Sources/DriverAPI/DriverLifecycle.swift") }
        let code = try #require(file?.code).filter { !$0.isWhitespace }
        #expect(code.contains("@_spi(DriverPlatform)publicstructDriverLifecycle"))
    }

    @Test("The Driver protocol declares no lifecycle state member")
    func driverProtocolExposesNoLifecycleState() throws {
        let driverProtocol = try DriverAPISource.files()
            .first { $0.path.hasSuffix("Sources/DriverAPI/Driver.swift") }
        let code = try #require(driverProtocol?.code)

        #expect(code.contains("DriverLifecycle") == false, "the Driver protocol must not name the lifecycle type")
        #expect(code.contains("DriverLifecycleState") == false)
    }

    // MARK: - When the entry points are called, exactly

    /// The re-entrancy contract, walked as the table defines it — because the
    /// cycle-1 version of this test called `activate()` twice in a row while the
    /// lifecycle sat in `.activating`, which is not a sequence the platform can
    /// produce, and asserted a doc-comment claim (`activate()` on an already-
    /// active Driver is safe) that the table flatly refuses.
    ///
    /// The story now told in one voice by ``Driver``'s doc comments, the table,
    /// and this test: `activate()` runs once per entry into `.activating`, the
    /// table permits that only from `.notActivated` and `.failed`, and the same
    /// INSTANCE is activated again after a teardown or a failure.
    @Test("activate() runs once per activation, and the same instance activates again after teardown")
    func activationRepeatsAcrossTeardown() async throws {
        let driver = StubDriver()
        var lifecycle = DriverLifecycle()

        try lifecycle.advance(to: .activating)
        try await driver.activate()
        try lifecycle.advance(to: .active)

        try lifecycle.advance(to: .deactivating)
        await driver.deactivate()
        try lifecycle.advance(to: .notActivated)

        // Second run on the same instance: a Core Bluetooth restoration or a
        // user re-enabling the Driver, not a fresh object (AD-11).
        try lifecycle.advance(to: .activating)
        try await driver.activate()
        try lifecycle.advance(to: .active)

        #expect(await driver.activateCallCount == 2)
        #expect(await driver.deactivateCallCount == 1)
        #expect(lifecycle.state == .active)
    }

    @Test("A running Driver is never re-activated: the table refuses the transition")
    func aRunningDriverIsNotReactivated() {
        #expect(DriverLifecycleState.active.permits(.activating) == false)
        #expect(DriverLifecycleState.activating.permits(.activating) == false)
        #expect(DriverLifecycleState.degraded.permits(.activating) == false)
        // …and the only two states it IS permitted from are the two the doc
        // comment on `Driver.activate()` names.
        let permitted = DriverLifecycleState.allCases.filter { $0.permits(.activating) }
        #expect(Set(permitted) == [.notActivated, .failed])
    }

    /// The other half of the same contract: `deactivate()` IS called repeatedly,
    /// including on a Driver that was never activated, and the table permits
    /// every call the doc comment promises is safe.
    @Test("deactivate() repeats, on a running Driver and on one that never ran")
    func teardownRepeats() async throws {
        let driver = StubDriver()

        var neverActivated = DriverLifecycle()
        await driver.deactivate()
        try neverActivated.advance(to: .notActivated)
        #expect(neverActivated.state == .notActivated)

        var tearingDown = DriverLifecycle(restoring: .deactivating)
        await driver.deactivate()
        try tearingDown.advance(to: .deactivating)
        await driver.deactivate()
        try tearingDown.advance(to: .notActivated)

        #expect(await driver.deactivateCallCount == 3)
        #expect(await driver.activateCallCount == 0)
    }

    @Test("A failed Driver activates again without a teardown in between")
    func failedDriverActivatesAgain() async throws {
        let driver = StubDriver()
        var lifecycle = DriverLifecycle(restoring: .failed)

        try lifecycle.advance(to: .activating)
        try await driver.activate()
        try lifecycle.advance(to: .active)

        #expect(await driver.activateCallCount == 1)
        #expect(lifecycle.state == .active)
    }
}
