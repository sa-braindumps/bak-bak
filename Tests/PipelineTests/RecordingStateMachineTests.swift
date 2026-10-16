import XCTest
@testable import Pipeline

final class RecordingStateMachineTests: XCTestCase {

    // MARK: - Hold mode

    func testHoldPressAndReleaseTranscribes() {
        var machine = RecordingStateMachine(mode: .hold)
        XCTAssertEqual(machine.handle(.hotkeyDown), .start)
        XCTAssertEqual(machine.handle(.hotkeyUp(heldFor: 2)), .stopAndTranscribe)
        XCTAssertEqual(machine.phase, .transcribing)
    }

    func testHoldQuickTapDiscardsInsteadOfLeavingMicOn() {
        // Regression: a tap under 0.3s used to start the mic and never stop it.
        var machine = RecordingStateMachine(mode: .hold)
        XCTAssertEqual(machine.handle(.hotkeyDown), .start)
        XCTAssertEqual(machine.handle(.hotkeyUp(heldFor: 0.1)), .discard(.tooShort))
        XCTAssertEqual(machine.phase, .idle)
    }

    func testHoldLimitKeepsTheRecording() {
        var machine = RecordingStateMachine(mode: .hold)
        _ = machine.handle(.hotkeyDown)
        XCTAssertEqual(machine.handle(.limitReached), .stopAndTranscribe)
        // Letting go of the key afterwards must not do anything.
        XCTAssertEqual(machine.handle(.hotkeyUp(heldFor: 61)), .none)
        XCTAssertEqual(machine.phase, .transcribing)
    }

    // MARK: - Toggle mode

    func testTogglePressTwiceTranscribes() {
        var machine = RecordingStateMachine(mode: .toggle)
        XCTAssertEqual(machine.handle(.hotkeyDown), .start)
        XCTAssertEqual(machine.handle(.hotkeyUp(heldFor: 0.1)), .none)
        XCTAssertEqual(machine.handle(.hotkeyDown), .stopAndTranscribe)
    }

    func testToggleLimitDiscardsForgottenRecording() {
        var machine = RecordingStateMachine(mode: .toggle)
        _ = machine.handle(.hotkeyDown)
        XCTAssertEqual(machine.handle(.limitReached), .discard(.limitReached))
        XCTAssertEqual(machine.phase, .idle)
    }

    func testToggleNextPressWorksAfterPreviousRunFinishes() {
        // Regression: a finishing run used to reset the toggle flag of the
        // *next* recording, so the following press was swallowed.
        var machine = RecordingStateMachine(mode: .toggle)
        _ = machine.handle(.hotkeyDown)
        _ = machine.handle(.hotkeyDown)
        _ = machine.handle(.finished)
        XCTAssertEqual(machine.handle(.hotkeyDown), .start)
        XCTAssertEqual(machine.handle(.hotkeyDown), .stopAndTranscribe)
    }

    // MARK: - Cancel

    func testCancelWhileRecordingDiscards() {
        for mode in [RecordingStateMachine.Mode.hold, .toggle] {
            var machine = RecordingStateMachine(mode: mode)
            _ = machine.handle(.hotkeyDown)
            XCTAssertEqual(machine.handle(.cancel), .discard(.cancelled), "\(mode)")
            XCTAssertEqual(machine.phase, .idle)
        }
    }

    func testHoldReleaseAfterCancelDoesNothing() {
        var machine = RecordingStateMachine(mode: .hold)
        _ = machine.handle(.hotkeyDown)
        _ = machine.handle(.cancel)
        XCTAssertEqual(machine.handle(.hotkeyUp(heldFor: 3)), .none)
    }

    func testCancelWhenNotRecordingIsIgnored() {
        var machine = RecordingStateMachine(mode: .toggle)
        XCTAssertEqual(machine.handle(.cancel), .none)
        _ = machine.handle(.hotkeyDown)
        _ = machine.handle(.hotkeyDown)
        XCTAssertEqual(machine.handle(.cancel), .none, "can't cancel once audio is sent")
        XCTAssertEqual(machine.phase, .transcribing)
    }

    // MARK: - No overlapping runs

    func testHotkeyIgnoredWhileTranscribing() {
        var machine = RecordingStateMachine(mode: .hold)
        _ = machine.handle(.hotkeyDown)
        _ = machine.handle(.hotkeyUp(heldFor: 1))
        XCTAssertEqual(machine.handle(.hotkeyDown), .none)
        XCTAssertEqual(machine.handle(.hotkeyUp(heldFor: 1)), .none)
        _ = machine.handle(.finished)
        XCTAssertEqual(machine.handle(.hotkeyDown), .start)
    }

    func testModeConfigValue() {
        XCTAssertEqual(RecordingStateMachine.Mode(configValue: "toggle"), .toggle)
        XCTAssertEqual(RecordingStateMachine.Mode(configValue: "hold"), .hold)
        XCTAssertEqual(RecordingStateMachine.Mode(configValue: "nonsense"), .hold)
    }

    // MARK: - Mic change and shortcuts

    func testMicChangeKeepsWhatWasSaid() {
        for mode in [RecordingStateMachine.Mode.hold, .toggle] {
            var machine = RecordingStateMachine(mode: mode)
            _ = machine.handle(.hotkeyDown)
            XCTAssertEqual(machine.handle(.inputChanged), .stopAndTranscribe, "\(mode)")
            XCTAssertEqual(machine.phase, .transcribing)
        }
    }

    func testShortcutWithTheHotkeyIsNotADictation() {
        // Regression: with ⌘⇧ as the hotkey, ⌘⇧4 started a recording.
        var machine = RecordingStateMachine(mode: .hold)
        _ = machine.handle(.hotkeyDown)
        XCTAssertEqual(machine.handle(.otherKeyPressed), .discard(.shortcut))
        XCTAssertEqual(machine.handle(.hotkeyUp(heldFor: 1)), .none)
        XCTAssertEqual(machine.phase, .idle)
    }

    func testMicChangeWhenIdleIsIgnored() {
        var machine = RecordingStateMachine(mode: .hold)
        XCTAssertEqual(machine.handle(.inputChanged), .none)
        XCTAssertEqual(machine.handle(.otherKeyPressed), .none)
    }
}
