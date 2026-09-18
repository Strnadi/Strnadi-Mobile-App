//
//  RecordingActivityControl.swift
//  Runner
//
//  Created by Jan Drobílek on 17.09.2026.
//

import AppIntents
import Foundation
import ActivityKit

@MainActor
enum RecordingActivityActionBridge {
    enum Action: String {
        case pause
        case resume
        case stop
    }

    enum ActionError: Error {
        case recorderUnavailable
    }

    static var handler: (
        (String, Action) async throws -> Void
    )?

    static func perform(
        sessionID: String,
        action: Action
    ) async throws {
        do {
            guard let handler else {
                throw ActionError.recorderUnavailable
            }
            try await handler(sessionID, action)
        } catch {
            // Only publish a bounded category, never raw exception text,
            // file paths, coordinates or recording identifiers.
            let code = (error as NSError).userInfo["RecordingActivityErrorCode"] as? String
            let failure: String
            switch code {
            case "RESUME_LOCATION_UNAVAILABLE": failure = "location"
            case "RESUME_LOCATION_PERMISSION": failure = "locationPermission"
            case "RESUME_MICROPHONE_PERMISSION": failure = "microphonePermission"
            case "record": failure = "microphone"
            case "RECORDING_BUSY": failure = "busy"
            case "RECORDING_NOT_AVAILABLE": failure = "unavailable"
            case "RECORDING_FINISH_FAILED": failure = "finish"
            default:
                failure = error is ActionError ? "unavailable" : "unknown"
            }
            for activity in Activity<RecordingAttributes>.activities
            where activity.attributes.sessionID == sessionID {
                var state = activity.content.state
                state.actionFailure = failure
                await activity.update(ActivityContent(state: state, staleDate: nil))
            }
            throw error
        }
    }
}

@available(iOS 18.0, *)
struct PauseRecordingIntent: AudioRecordingIntent, LiveActivityIntent {
    static var title: LocalizedStringResource = "Pause recording"
    static var isDiscoverable: Bool = false

    @Parameter(title: "Recording session")
    var sessionID: String

    init() {}

    init(sessionID: String) {
        self.sessionID = sessionID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        try await RecordingActivityActionBridge.perform(
            sessionID: sessionID,
            action: .pause
        )

        return .result()
    }
}

@available(iOS 18.0, *)
struct ResumeRecordingIntent: AudioRecordingIntent, LiveActivityIntent {
    static var title: LocalizedStringResource = "Resume recording"
    static var isDiscoverable: Bool = false

    // Legacy systems open the app before resuming. On iOS 26+, supportedModes
    // supplies the background-first behavior with a foreground fallback.
    static let openAppWhenRun: Bool = true

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { [.background, .foreground(.dynamic)] }

    @Parameter(title: "Recording session")
    var sessionID: String

    init() {}

    init(sessionID: String) {
        self.sessionID = sessionID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        do {
            try await RecordingActivityActionBridge.perform(
                sessionID: sessionID,
                action: .resume
            )
        } catch {
            let code = (error as NSError).userInfo["RecordingActivityErrorCode"] as? String
            guard code == "record" else { throw error }
            if #available(iOS 26.0, *), systemContext.currentMode.canContinueInForeground {
                try await continueInForeground(alwaysConfirm: false)
                // Retry once, only after the first capture attempt has cleaned
                // up. Dart rechecks session identity and preserves prior audio.
                try await RecordingActivityActionBridge.perform(
                    sessionID: sessionID,
                    action: .resume
                )
            } else {
                throw error
            }
        }
        return .result()
    }
}
