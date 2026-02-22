import Foundation
import Testing
@testable import Telocare

struct MuseSessionServiceCoreTests {
    @Test func scanTimeoutUsesConfiguredWindow() {
        var core = MuseSessionServiceCore(scanTimeout: 8)
        let start = Date(timeIntervalSince1970: 1_000)

        _ = core.beginScan(at: start)

        #expect(core.isScanTimedOut(at: start.addingTimeInterval(7.9)) == false)
        #expect(core.isScanTimedOut(at: start.addingTimeInterval(8.0)) == true)
    }

    @Test func connectFlowAlwaysStopsListeningBeforeConnect() {
        var core = MuseSessionServiceCore()

        let actions = core.beginConnectFlow()

        #expect(actions.count == 2)
        #expect(actions[0] == .stopListening)
        #expect(actions[1] == .connect(.preset1031))
    }

    @Test func adaptivePresetFallsBackFrom1031To1021Once() {
        var core = MuseSessionServiceCore()

        let firstDecision = core.registerConnectOutcome(.disconnected)
        #expect(firstDecision == .retry([.stopListening, .connect(.preset1021)]))

        let secondDecision = core.registerConnectOutcome(.disconnected)
        #expect(secondDecision == .fail(.notConnected))
    }

    @Test func connectionStateMappingReturnsExpectedErrors() {
        #expect(MuseSDKConnectionMapper.error(for: .needsLicense) == .needsLicense)
        #expect(MuseSDKConnectionMapper.error(for: .needsUpdate) == .needsUpdate)
        #expect(MuseSDKConnectionMapper.error(for: .connected) == nil)
        #expect(MuseSDKConnectionMapper.error(for: .disconnected) == nil)
    }

    @Test func recordingStateTransitionsEnforceStartStopSemantics() {
        var core = MuseSessionServiceCore()

        #expect(throws: MuseSessionServiceError.self) {
            try core.stopRecording()
        }

        do {
            try core.startRecording()
        } catch {
            #expect(Bool(false))
        }

        #expect(throws: MuseSessionServiceError.self) {
            try core.startRecording()
        }

        do {
            try core.stopRecording()
        } catch {
            #expect(Bool(false))
        }
    }
}
