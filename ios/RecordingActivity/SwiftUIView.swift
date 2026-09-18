import SwiftUI
import AppIntents

/// Colors shared by the Lock Screen and Dynamic Island presentations.
enum RecordingActivityStyle {
    static let yellow = Color(red: 1, green: 0.85, blue: 0.15)
    static let pauseBackground = Color(red: 0.24, green: 0.20, blue: 0.03)
    static let stopBackground = Color(white: 0.20)
}

@available(iOS 18.0, *)
struct RecordingPauseButton: View {
    let sessionID: String
    let isPaused: Bool

    var body: some View {
        Group {
            if isPaused {
                Button(intent: ResumeRecordingIntent(sessionID: sessionID)) {
                    controlIcon
                }
            } else {
                Button(intent: PauseRecordingIntent(sessionID: sessionID)) {
                    controlIcon
                }
            }
        }
        .id(isPaused)
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: isPaused
            ? String(localized: "streamRec.buttons.resumeRecording", defaultValue: "Resume recording")
            : String(localized: "streamRec.buttons.pauseRecording", defaultValue: "Pause recording")))
    }

    private var controlIcon: some View {
        Image(systemName: isPaused ? "play.fill" : "pause.fill")
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(RecordingActivityStyle.yellow)
            .frame(width: 48, height: 48)
            .background(RecordingActivityStyle.pauseBackground, in: Circle())
            .contentShape(Circle())
    }
}

@available(iOS 18.0, *)
struct RecordingStopButton: View {
    let sessionID: String

    private var finishURL: URL {
        var components = URLComponents()
        components.scheme = "com.delta.strnadi"
        components.host = "recording"
        components.path = "/finish"
        components.queryItems = [URLQueryItem(name: "sessionID", value: sessionID)]
        return components.url!
    }

    var body: some View {
        Link(destination: finishURL) {
            Image(systemName: "xmark")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(RecordingActivityStyle.stopBackground, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: String(
            localized: "streamRec.buttons.finishAndSaveRecording",
            defaultValue: "Finish recording and open save form"
        )))
    }
}

struct RecordingActivityControls: View {
    let sessionID: String
    let isPaused: Bool

    var body: some View {
        HStack(spacing: 6) {
            if #available(iOS 18.0, *) {
                RecordingPauseButton(sessionID: sessionID, isPaused: isPaused)
                RecordingStopButton(sessionID: sessionID)
            } else {
                // On systems without these intents, tapping the activity opens
                // the recorder, where all recording controls remain available.
                RecordingStatusRing(isPaused: isPaused)
            }
        }
    }
}

struct RecordingStatusRing: View {
    let isPaused: Bool

    var body: some View {
        ZStack {
            Circle().strokeBorder(RecordingActivityStyle.yellow, lineWidth: 2)
            if isPaused {
                Image(systemName: "pause.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(RecordingActivityStyle.yellow)
            } else {
                Circle().fill(RecordingActivityStyle.yellow).padding(5)
            }
        }
        .frame(width: 18, height: 18)
        .accessibilityLabel(Text(verbatim: isPaused
            ? String(localized: "streamRec.status.paused", defaultValue: "Paused")
            : String(localized: "streamRec.status.recording", defaultValue: "Recording")))
    }
}

struct RecordingActivityRow: View {
    let sessionID: String
    let state: RecordingAttributes.ContentState

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            RecordingActivityControls(
                sessionID: sessionID,
                isPaused: state.runningSince == nil
            )
            Spacer(minLength: 0)
            RecordingTimerView(state: state)
                .font(.system(size: 32, weight: .regular))
                .foregroundStyle(RecordingActivityStyle.yellow)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .frame(maxWidth: 170, alignment: .trailing)
                .accessibilityLabel(Text(verbatim: String(
                    localized: "streamRec.activity.elapsedTime",
                    defaultValue: "Recording duration"
                )))
        }
    }
}
