//
//  RecordingTimerView.swift
//  RecordingActivityExtension
//
//  Created by Jan Drobílek on 16.09.2026.
//

import Foundation
import SwiftUI

struct RecordingTimerView: View {
    let state: RecordingAttributes.ContentState

    var body: some View {
        Group {
            if let runningSince = state.runningSince {
                Text(
                    runningSince.addingTimeInterval(-state.elapsedSeconds),
                    style: .timer
                )
            } else {
                Text(verbatim: pausedTime)
            }
        }
        .monospacedDigit()
    }

    private var pausedTime: String {
        let seconds = Int(max(0, state.elapsedSeconds))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainingSeconds = seconds % 60

        if hours > 0 {
            return String(
                format: "%d:%02d:%02d",
                hours, minutes, remainingSeconds
            )
        }

        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}
