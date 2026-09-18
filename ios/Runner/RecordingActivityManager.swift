//
//  RecordingActivityManager.swift
//  Runner
//
//  Created by Jan Drobílek on 16.09.2026.
//

import ActivityKit
import Foundation

@MainActor
final class RecordingActivityManager {
    enum ActivityError: Error {
        case activitiesDisabled
        case recordingAlreadyActive
        case activityNotFound
    }

    func start(sessionID: String) throws -> String {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            throw ActivityError.activitiesDisabled
        }

        guard Activity<RecordingAttributes>.activities.isEmpty else {
            throw ActivityError.recordingAlreadyActive
        }

        let attributes = RecordingAttributes(sessionID: sessionID)
        let state = RecordingAttributes.ContentState(
            elapsedSeconds: 0,
            runningSince: Date()
        )

        let activity = try Activity<RecordingAttributes>.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: nil),
            pushType: nil
        )

        return activity.id
    }
    
    func update(
        sessionID: String,
        elapsedSeconds: TimeInterval,
        runningSince: Date?
    ) async throws {
        guard let activity = Activity<RecordingAttributes>.activities.first(
            where: { $0.attributes.sessionID == sessionID }
        ) else {
            throw ActivityError.activityNotFound
        }

        let state = RecordingAttributes.ContentState(
            elapsedSeconds: elapsedSeconds,
            runningSince: runningSince
        )

        await activity.update(
            ActivityContent(state: state, staleDate: nil)
        )
    }

    func end(sessionID: String) async {
        for activity in Activity<RecordingAttributes>.activities {
            guard activity.attributes.sessionID == sessionID else {
                continue
            }

            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
