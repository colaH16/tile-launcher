import XCTest
@testable import DeckCore

final class MenuDeferredCaptureTests: XCTestCase {
    func testNormalClosePreservesConfirmedSelectionBeyondNotificationGate() throws {
        var policy = MenuDeferredCapture()
        let ticket = try XCTUnwrap(policy.confirm(generation: 7, at: 100))
        policy.menuClosed()
        policy.menuClosed()
        XCTAssertEqual(ticket.confirmedAt, 100)
        XCTAssertEqual(ticket.expiresAt, 102)
        // Native row/release confirmation has already happened. Resolver time is
        // its own bounded lifetime, not a second 0.8-second notification gate.
        XCTAssertTrue(policy.isCurrent(ticket, generation: 7, at: 100.9))
        XCTAssertTrue(policy.take(ticket, generation: 7, at: 101.8))
        XCTAssertNil(policy.pending)
        XCTAssertFalse(policy.take(ticket, generation: 7, at: 101.9))
    }

    func testNewSelectionSupersedesOldResultWithoutConsumingNewTicket() throws {
        var policy = MenuDeferredCapture()
        let first = try XCTUnwrap(policy.confirm(generation: 3, at: 1))
        let second = try XCTUnwrap(policy.confirm(generation: 3, at: 1.2))
        XCTAssertGreaterThan(second.id, first.id)
        XCTAssertFalse(policy.isCurrent(first, generation: 3, at: 1.3))
        XCTAssertFalse(policy.take(first, generation: 3, at: 1.3))
        XCTAssertEqual(policy.pending, second)
        XCTAssertTrue(policy.take(second, generation: 3, at: 1.4))
        XCTAssertFalse(policy.take(second, generation: 3, at: 1.5))
        let third = try XCTUnwrap(policy.confirm(generation: 4, at: 2))
        XCTAssertGreaterThan(third.id, second.id, "A generation change must not reset request IDs")
    }

    func testCancelInvalidatesWhenGenerationDoesNotChangeAndDoesNotResetIDs() throws {
        var policy = MenuDeferredCapture()
        let first = try XCTUnwrap(policy.confirm(generation: 9, at: 10))
        // New input, settings cancellation, explicit cancel and stop all use
        // this transition, even if the same app/process remains frontmost.
        policy.cancel()
        XCTAssertNil(policy.pending)
        policy.menuClosed()
        XCTAssertFalse(policy.isCurrent(first, generation: 9, at: 10.1))
        XCTAssertFalse(policy.take(first, generation: 9, at: 10.1))
        let next = try XCTUnwrap(policy.confirm(generation: 9, at: 11))
        XCTAssertGreaterThan(next.id, first.id)
        XCTAssertTrue(policy.take(next, generation: 9, at: 11.1))
    }

    func testProcessGenerationMismatchAndAppSwitchRejectStaleCompletion() throws {
        var policy = MenuDeferredCapture()
        let old = try XCTUnwrap(policy.confirm(generation: 40, at: 20))
        XCTAssertFalse(policy.isCurrent(old, generation: 41, at: 20.1))
        XCTAssertFalse(policy.take(old, generation: 41, at: 20.1))
        // The native adapter calls cancel on process/generation changes.
        policy.cancel()
        let current = try XCTUnwrap(policy.confirm(generation: 41, at: 20.2))
        XCTAssertFalse(policy.take(old, generation: 40, at: 20.3))
        XCTAssertEqual(policy.pending, current)
        XCTAssertTrue(policy.take(current, generation: 41, at: 20.4))
    }

    func testConfirmationAndExpiryBoundariesAreInclusive() throws {
        let before = TimeInterval(10).nextDown
        let after = TimeInterval(12).nextUp
        for (now, expected) in [(before, false), (10.0, true), (11.0, true), (12.0, true), (after, false)] {
            var policy = MenuDeferredCapture()
            let ticket = try XCTUnwrap(policy.confirm(generation: 2, at: 10))
            XCTAssertEqual(policy.isCurrent(ticket, generation: 2, at: now), expected)
            XCTAssertEqual(policy.take(ticket, generation: 2, at: now), expected)
        }
    }

    func testInvalidNewConfirmationFailsClosedRatherThanLeavingOldTicketAlive() throws {
        let invalid: [(TimeInterval, TimeInterval)] = [
            (.nan, 2), (.infinity, 2), (-.infinity, 2), (-1, 2),
            (2, .nan), (2, .infinity), (2, -.infinity), (2, 0), (2, -1),
            (.greatestFiniteMagnitude, .greatestFiniteMagnitude),
            (.greatestFiniteMagnitude, 1), // Rounded expiry would equal confirmation.
        ]
        for (time, duration) in invalid {
            var policy = MenuDeferredCapture()
            let old = try XCTUnwrap(policy.confirm(generation: 1, at: 1))
            XCTAssertNil(policy.confirm(generation: 1, at: time, duration: duration))
            XCTAssertNil(policy.pending)
            XCTAssertFalse(policy.take(old, generation: 1, at: 1.1))
            let next = try XCTUnwrap(policy.confirm(generation: 1, at: 2))
            XCTAssertGreaterThan(next.id, old.id)
        }
    }

    func testInvalidCompletionTimeCannotConsumeAnOtherwiseCurrentRequest() throws {
        var policy = MenuDeferredCapture()
        let ticket = try XCTUnwrap(policy.confirm(generation: 8, at: 1))
        for now: TimeInterval in [.nan, .infinity, -.infinity, -1, 0] {
            XCTAssertFalse(policy.isCurrent(ticket, generation: 8, at: now))
            XCTAssertFalse(policy.take(ticket, generation: 8, at: now))
            XCTAssertEqual(policy.pending, ticket)
        }
        XCTAssertTrue(policy.take(ticket, generation: 8, at: 1.1))
    }

    func testCopiedIDCannotExtendDeadlineOrChangeConfirmationMetadata() throws {
        var policy = MenuDeferredCapture()
        let ticket = try XCTUnwrap(policy.confirm(generation: 5, at: 10))
        let altered = MenuDeferredCapture.Ticket(id: ticket.id, generation: ticket.generation,
                                                confirmedAt: ticket.confirmedAt, expiresAt: ticket.expiresAt + 100)
        XCTAssertFalse(policy.isCurrent(altered, generation: 5, at: 11))
        XCTAssertFalse(policy.take(altered, generation: 5, at: 11))
        XCTAssertEqual(policy.pending, ticket)
        XCTAssertTrue(policy.take(ticket, generation: 5, at: 11))
    }
}
