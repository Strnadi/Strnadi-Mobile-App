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

        // Use the global function so no context is captured.
        WorkmanagerPlugin.setPluginRegistrantCallback(registerPlugins)

        // Register background tasks
        WorkmanagerPlugin.registerBGProcessingTask(withIdentifier: "com.delta.strnadi.sendRecording")

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}