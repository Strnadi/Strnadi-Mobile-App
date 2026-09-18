// Offscreen visual test: production views, fake intents, no recorder or database.
import AppKit
import SwiftUI
import AppIntents

struct RecordingAttributes {
    struct ContentState {
        var elapsedSeconds: TimeInterval
        var runningSince: Date?
    }
}
struct PauseRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Pause"
    var sessionID: String
    init() { sessionID = "" }
    init(sessionID: String) { self.sessionID = sessionID }
    func perform() async throws -> some IntentResult { .result() }
}
struct ResumeRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Resume"
    var sessionID: String
    init() { sessionID = "" }
    init(sessionID: String) { self.sessionID = sessionID }
    func perform() async throws -> some IntentResult { .result() }
}
struct StopRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop"
    var sessionID: String
    init() { sessionID = "" }
    init(sessionID: String) { self.sessionID = sessionID }
    func perform() async throws -> some IntentResult { .result() }
}
@main struct Render {
    @MainActor static func main() throws {
        let content = VStack(spacing: 24) {
            ForEach([34.0, 3661.0], id: \.self) { elapsed in
                RecordingActivityRow(sessionID: "preview", state: .init(elapsedSeconds: elapsed, runningSince: nil))
                    .padding(16).frame(width: 320).background(.black, in: Capsule())
            }
            HStack(spacing: 8) {
                RecordingStatusRing(isPaused: false)
                Color.clear.frame(width: 112, height: 20)
                RecordingTimerView(state: .init(elapsedSeconds: 34, runningSince: nil))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(RecordingActivityStyle.yellow)
            }.padding(10).background(.black, in: Capsule())
        }.padding(32).background(Color(white: 0.92))
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.cgImage else { fatalError("No image") }
        let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
        try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
}
