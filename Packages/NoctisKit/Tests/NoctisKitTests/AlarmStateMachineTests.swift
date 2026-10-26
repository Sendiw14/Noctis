import Foundation
import Testing

@testable import NightKit

/// Every transition of the alarm's state machine (APP_RULES.md R30), then proof that no other
/// pair of state and event moves it.
struct AlarmStateMachineTests {
    nonisolated struct Step: Sendable, CustomTestStringConvertible {
        let from: AlarmState
        let event: AlarmEvent
        let to: AlarmState
        var testDescription: String { "\(from) + \(event) -> \(to)" }
    }

    /// The whole table: each line is a transition that exists.
    nonisolated static let steps: [Step] =
        [
            // Getting going from a resting state.
            Step(from: .off, event: .scheduleAccepted, to: .scheduled),
            Step(from: .dismissed, event: .scheduleAccepted, to: .scheduled),
            Step(from: .cancelled, event: .scheduleAccepted, to: .scheduled),
            Step(from: .error, event: .scheduleAccepted, to: .scheduled),
            Step(from: .off, event: .scheduleFailed, to: .error),
            Step(from: .dismissed, event: .scheduleFailed, to: .error),
            Step(from: .cancelled, event: .scheduleFailed, to: .error),
            Step(from: .error, event: .reset, to: .off),
            Step(from: .permissionDenied, event: .reset, to: .off),
            Step(from: .unavailable, event: .reset, to: .off),
            Step(from: .permissionDenied, event: .authorizationGranted, to: .off),
            Step(from: .error, event: .cancelRequested, to: .cancelled),
            // Waiting to ring.
            Step(from: .scheduled, event: .systemScheduled, to: .armed),
            Step(from: .scheduled, event: .systemAlerting, to: .firing),
            Step(from: .scheduled, event: .systemCountdown, to: .snoozed),
            Step(from: .scheduled, event: .systemGone, to: .dismissed),
            Step(from: .scheduled, event: .scheduleAccepted, to: .scheduled),
            Step(from: .scheduled, event: .scheduleFailed, to: .error),
            Step(from: .scheduled, event: .cancelRequested, to: .cancelled),
            Step(from: .armed, event: .systemAlerting, to: .firing),
            Step(from: .armed, event: .systemCountdown, to: .snoozed),
            Step(from: .armed, event: .systemGone, to: .dismissed),
            Step(from: .armed, event: .scheduleAccepted, to: .scheduled),
            Step(from: .armed, event: .scheduleFailed, to: .error),
            Step(from: .armed, event: .cancelRequested, to: .cancelled),
            // Ringing and snoozing.
            Step(from: .firing, event: .systemCountdown, to: .snoozed),
            Step(from: .firing, event: .systemScheduled, to: .armed),
            Step(from: .firing, event: .systemGone, to: .dismissed),
            Step(from: .firing, event: .scheduleAccepted, to: .scheduled),
            Step(from: .firing, event: .scheduleFailed, to: .error),
            Step(from: .firing, event: .cancelRequested, to: .cancelled),
            Step(from: .snoozed, event: .systemAlerting, to: .firing),
            Step(from: .snoozed, event: .systemScheduled, to: .armed),
            Step(from: .snoozed, event: .systemGone, to: .dismissed),
            Step(from: .snoozed, event: .scheduleAccepted, to: .scheduled),
            Step(from: .snoozed, event: .scheduleFailed, to: .error),
            Step(from: .snoozed, event: .cancelRequested, to: .cancelled),
        ]
        + AlarmState.allCases.filter { $0 != .permissionDenied && $0 != .unavailable }.map {
            // Permission is lost in any state but the two that already are it.
            Step(from: $0, event: .authorizationDenied, to: .permissionDenied)
        }
        + AlarmState.allCases.filter { $0 != .unavailable }.map {
            // A device that can't schedule alarms can't, in any state.
            Step(from: $0, event: .alarmsUnavailable, to: .unavailable)
        }

    @Test(arguments: AlarmStateMachineTests.steps)
    func everyTransitionThatExists(step: Step) {
        let transition = AlarmStateMachine.reduce(step.from, step.event)
        #expect(transition.state == step.to)
        #expect(transition.changed == (step.from != step.to))
    }

    @Test func everyOtherPairIsIgnored() {
        var listed = Set<String>()
        for step in Self.steps { listed.insert("\(step.from)|\(step.event)") }
        var ignored = 0
        for state in AlarmState.allCases {
            for event in AlarmEvent.allCases where !listed.contains("\(state)|\(event)") {
                let transition = AlarmStateMachine.reduce(state, event)
                #expect(transition.state == state, Comment(rawValue: "\(state) + \(event) moved to \(transition.state)"))
                #expect(!transition.changed)
                ignored += 1
            }
        }
        // 10 states x 11 events = 110 pairs; what the table lists is the rest.
        #expect(ignored + listed.count == AlarmState.allCases.count * AlarmEvent.allCases.count)
    }

    @Test func aLateReportCannotRaiseTheDead() {
        // A cancelled or dismissed alarm stays that way whatever the system says afterwards.
        for state in [AlarmState.cancelled, .dismissed, .off] {
            for event in [AlarmEvent.systemScheduled, .systemAlerting, .systemCountdown, .systemGone] {
                #expect(AlarmStateMachine.reduce(state, event).state == state, Comment(rawValue: "\(state) + \(event)"))
            }
        }
    }

    @Test func aWholeNightOfAOneShotAlarm() {
        var state = AlarmState.off
        for (event, expected) in [
            (AlarmEvent.scheduleAccepted, AlarmState.scheduled), (.systemScheduled, .armed), (.systemAlerting, .firing),
            (.systemCountdown, .snoozed), (.systemAlerting, .firing), (.systemGone, .dismissed),
        ] {
            state = AlarmStateMachine.reduce(state, event).state
            #expect(state == expected)
        }
    }

    @Test func aRepeatingAlarmGoesBackToWaiting() {
        var state = AlarmState.armed
        for (event, expected) in [(AlarmEvent.systemAlerting, AlarmState.firing), (.systemScheduled, .armed)] {
            state = AlarmStateMachine.reduce(state, event).state
            #expect(state == expected)
        }
    }

    @Test func onlyAPendingAlarmIsOn() {
        let on = AlarmState.allCases.filter(\.isActive)
        #expect(Set(on) == [.scheduled, .armed, .snoozed, .firing])
    }
}
