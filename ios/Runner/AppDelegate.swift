import UIKit
import Flutter
import workmanager
import geolocator_apple
import file_picker
import firebase_core
import firebase_messaging
import flutter_local_notifications
import flutter_secure_storage
import path_provider_foundation
import sentry_flutter
import sqflite_darwin
import AVFoundation
import app_links

// Global function for registering plugins
func registerPlugins(registry: FlutterPluginRegistry) {
    GeneratedPluginRegistrant.register(with: registry)
}

@main
@objc class AppDelegate: FlutterAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        GeneratedPluginRegistrant.register(with: self)

        if let controller = window?.rootViewController as? FlutterViewController {
            let audioChannel = FlutterMethodChannel(name: "com.delta.strnadi/audio", binaryMessenger: controller.binaryMessenger)
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
        }
        
        // Retrieve the link from parameters
        if let url = AppLinks.shared.getLink(launchOptions: launchOptions) {
          // We have a link, propagate it to your Flutter app or not
          AppLinks.shared.handleLink(url: url)
          return true // Returning true will stop the propagation to other packages
        }

        // Use the global function so no context is captured.
        WorkmanagerPlugin.setPluginRegistrantCallback(registerPlugins)

        // Register background tasks
        WorkmanagerPlugin.registerBGProcessingTask(withIdentifier: "com.delta.strnadi.sendRecording")

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
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
