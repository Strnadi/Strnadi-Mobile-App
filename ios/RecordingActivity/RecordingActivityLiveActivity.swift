//
//  RecordingActivityLiveActivity.swift
//  RecordingActivity
//
//  Created by Jan Drobílek on 16.09.2026.
//

import ActivityKit
import SwiftUI
import WidgetKit

struct RecordingActivityLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingAttributes.self) { context in
            VStack(spacing: 8) {
                recordingRow(context: context)
                failureLabel(context.state.actionFailure)
            }
            .padding(16)
            .activityBackgroundTint(.black)
            .activitySystemActionForegroundColor(RecordingActivityStyle.yellow)
        } dynamicIsland: { context in
            DynamicIsland {
                // Place the shared row below the system camera region. The
                // camera cutout and outer capsule belong to iOS, not our view.
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        recordingRow(context: context)
                        failureLabel(context.state.actionFailure)
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
            } compactLeading: {
                RecordingStatusRing(isPaused: context.state.runningSince == nil)
            } compactTrailing: {
                RecordingTimerView(state: context.state)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(RecordingActivityStyle.yellow)
                    .frame(width: 62, alignment: .trailing)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } minimal: {
                RecordingStatusRing(isPaused: context.state.runningSince == nil)
            }
            .keylineTint(RecordingActivityStyle.yellow)
        }
    }

    private func recordingRow(context: ActivityViewContext<RecordingAttributes>) -> some View {
        RecordingActivityRow(sessionID: context.attributes.sessionID, state: context.state)
    }

    @ViewBuilder
    private func failureLabel(_ failure: String?) -> some View {
        if let failure {
            Text(verbatim: failureMessage(failure))
                .font(.caption)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func failureMessage(_ failure: String) -> String {
        switch failure {
        case "location":
            return String(localized: "streamRec.activityFailure.location", defaultValue: "Location unavailable. Open Strnadi to resume.")
        case "locationPermission":
            return String(localized: "streamRec.activityFailure.locationPermission", defaultValue: "Location access is missing. Open Strnadi.")
        case "microphonePermission":
            return String(localized: "streamRec.activityFailure.microphonePermission", defaultValue: "Microphone access is missing. Open Strnadi.")
        case "microphone":
            return String(localized: "streamRec.activityFailure.microphone", defaultValue: "The recorder could not restart. Open Strnadi.")
        case "finish":
            return String(localized: "streamRec.activityFailure.finish", defaultValue: "Could not finish recording. Open Strnadi to retry.")
        case "busy":
            return String(localized: "streamRec.activityFailure.busy", defaultValue: "Recording is still processing. Try again shortly.")
        case "unavailable":
            return String(localized: "streamRec.activityFailure.unavailable", defaultValue: "Recording controls are unavailable. Open Strnadi.")
        default:
            return String(localized: "streamRec.activityFailure.unknown", defaultValue: "Recording command failed. Open Strnadi.")
        }
    }


}

struct RecordingActivityLiveActivity_Previews: PreviewProvider {
    static let attributes = RecordingAttributes(sessionID: "preview")

    static let running = RecordingAttributes.ContentState(
        elapsedSeconds: 30,
        runningSince: Date()
    )

    static let paused = RecordingAttributes.ContentState(
        elapsedSeconds: 90,
        runningSince: nil
    )

    static var previews: some View {
        attributes.previewContext(running, viewKind: .content)
            .previewDisplayName("Lock Screen — Recording")

        attributes.previewContext(paused, viewKind: .content)
            .previewDisplayName("Lock Screen — Paused")

        attributes.previewContext(
            running,
            viewKind: .dynamicIsland(.compact)
        )
        .previewDisplayName("Dynamic Island — Compact")

        attributes.previewContext(
            running,
            viewKind: .dynamicIsland(.expanded)
        )
        .previewDisplayName("Dynamic Island — Expanded")
    }
}
