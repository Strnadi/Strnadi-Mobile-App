import UIKit
import Flutter
#if canImport(workmanager_apple)
import workmanager_apple
#endif
import AVFoundation
import app_links
import ActivityKit

// Global function for registering plugins
func registerPlugins(registry: FlutterPluginRegistry) {
    GeneratedPluginRegistrant.register(with: registry)
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

    private var recordingActivityCleanup: Task<Void, Never>?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let previousActivities = Activity<RecordingAttributes>.activities

        recordingActivityCleanup = Task { @MainActor in
            for activity in previousActivities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }

#if canImport(workmanager_apple)
        // Use the global function so no context is captured.
        WorkmanagerPlugin.setPluginRegistrantCallback(registerPlugins)

        // Register background tasks
        WorkmanagerPlugin.registerBGProcessingTask(withIdentifier: "com.delta.strnadi.sendRecording")
#endif

        // Flutter must always finish registering plugins, even when the app was
        // launched by a universal link.
        let didFinishLaunching = super.application(
            application,
            didFinishLaunchingWithOptions: launchOptions
        )

        ColdStartLinkForwarder.forward(
            AppLinks.shared.getLink(launchOptions: launchOptions)
        ) { url in
            AppLinks.shared.handleLink(url: url)
        }

        return didFinishLaunching
    }

    func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
        GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
        engineBridge.applicationRegistrar.register(
            NativeControlsFactory(messenger: engineBridge.applicationRegistrar.messenger()),
            withId: "com.delta.strnadi/native-controls"
        )

        let audioChannel = FlutterMethodChannel(
            name: "com.delta.strnadi/audio",
            binaryMessenger: engineBridge.applicationRegistrar.messenger()
        )

        audioChannel.setMethodCallHandler { (call, result) in
            if call.method == "getBestAudioSettings" {
                do {
                    let audioSession = AVAudioSession.sharedInstance()
                    try audioSession.setCategory(.record, mode: .measurement, options: [])
                    try audioSession.setActive(true)
                    let sampleRate = audioSession.sampleRate
                    let settings: [String: Any] = [
                        "sampleRate": Int(sampleRate),
                        "bitRate": 128000
                    ]
                    result(settings)
                } catch {
                    result(FlutterError(code: "UNAVAILABLE", message: "Cannot load microphone settings", details: error.localizedDescription))
                }
            } else {
                result(FlutterMethodNotImplemented)
            }
        }

        let recordingActivityChannel = FlutterMethodChannel(
            name: "com.delta.strnadi/recording-activity",
            binaryMessenger: engineBridge.applicationRegistrar.messenger()
        )

        let startupCleanup = recordingActivityCleanup

        RecordingActivityActionBridge.handler = { sessionID, action in
            await startupCleanup?.value

            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in

                recordingActivityChannel.invokeMethod(
                    "performRecordingAction",
                    arguments: [
                        "sessionID": sessionID,
                        "action": action.rawValue
                    ]
                ) { response in
                    if let error = response as? FlutterError {
                        continuation.resume(throwing: NSError(
                            domain: "RecordingActivity",
                            code: 1,
                            userInfo: [
                                "RecordingActivityErrorCode": error.code,
                                NSLocalizedDescriptionKey:
                                    error.message ?? error.code
                            ]
                        ))
                    } else if response == nil || response is NSNull {
                        continuation.resume(returning: ())
                    } else {
                        continuation.resume(throwing: NSError(
                            domain: "RecordingActivity",
                            code: 2,
                            userInfo: [
                                NSLocalizedDescriptionKey:
                                    "The recording command was not handled."
                            ]
                        ))
                    }
                }
            }
        }

        recordingActivityChannel.setMethodCallHandler { call, result in
            guard ["start", "update", "end"].contains(call.method) else {
                result(FlutterMethodNotImplemented)
                return
            }

            guard
                let arguments = call.arguments as? [String: Any],
                let sessionID = arguments["sessionID"] as? String,
                !sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                result(FlutterError(
                    code: "INVALID_ARGUMENTS",
                    message: "A non-empty sessionID is required.",
                    details: nil
                ))
                return
            }

            Task { @MainActor in
                await startupCleanup?.value

                let manager = RecordingActivityManager()

                do {
                    switch call.method {
                    case "start":
                        let activityID = try manager.start(sessionID: sessionID)
                        result(activityID)

                    case "update":
                        guard
                            let elapsedSeconds = arguments["elapsedSeconds"] as? Double,
                            elapsedSeconds.isFinite,
                            elapsedSeconds >= 0
                        else {
                            result(FlutterError(
                                code: "INVALID_ARGUMENTS",
                                message: "elapsedSeconds must be a finite, non-negative number.",
                                details: nil
                            ))
                            return
                        }

                        let runningSince: Date?

                        if let rawTimestamp = arguments["runningSinceMs"],
                           !(rawTimestamp is NSNull) {
                            guard
                                let milliseconds = rawTimestamp as? Double,
                                milliseconds.isFinite
                            else {
                                result(FlutterError(
                                    code: "INVALID_ARGUMENTS",
                                    message: "runningSinceMs must be a finite number or null.",
                                    details: nil
                                ))
                                return
                            }

                            runningSince = Date(
                                timeIntervalSince1970: milliseconds / 1000
                            )
                        } else {
                            runningSince = nil
                        }

                        try await manager.update(
                            sessionID: sessionID,
                            elapsedSeconds: elapsedSeconds,
                            runningSince: runningSince
                        )
                        result(nil)

                    case "end":
                        await manager.end(sessionID: sessionID)
                        result(nil)

                    default:
                        result(FlutterMethodNotImplemented)
                    }
                } catch RecordingActivityManager.ActivityError.activitiesDisabled {
                    result(FlutterError(
                        code: "ACTIVITIES_DISABLED",
                        message: "Live Activities are disabled.",
                        details: nil
                    ))
                } catch RecordingActivityManager.ActivityError.recordingAlreadyActive {
                    result(FlutterError(
                        code: "ACTIVITY_ALREADY_ACTIVE",
                        message: "A recording activity already exists.",
                        details: nil
                    ))
                } catch RecordingActivityManager.ActivityError.activityNotFound {
                    result(FlutterError(
                        code: "ACTIVITY_NOT_FOUND",
                        message: "No activity exists for this recording session.",
                        details: nil
                    ))
                } catch {
                    result(FlutterError(
                        code: "ACTIVITY_FAILED",
                        message: error.localizedDescription,
                        details: nil
                    ))
                }
            }
        }
    }

    override func applicationWillTerminate(_ application: UIApplication) {
        let activities = Activity<RecordingAttributes>.activities

        Task.detached(priority: .high) {
            for activity in activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }

        super.applicationWillTerminate(application)
    }

    // Forward Universal Links (NSUserActivity) to Flutter/plugins and return whether it was handled.
    override func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
    ) -> Bool {
        return super.application(application, continue: userActivity, restorationHandler: restorationHandler)
    }
}
