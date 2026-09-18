//
//  RecordingAttributes.swift
//  Runner
//
//  Created by Jan Drobílek on 16.09.2026.
//

import ActivityKit
import Foundation

struct RecordingAttributes: ActivityAttributes {
    let sessionID: String

    struct ContentState: Codable, Hashable {
        var elapsedSeconds: TimeInterval
        var runningSince: Date?
        var actionFailure: String? = nil
    }
}
