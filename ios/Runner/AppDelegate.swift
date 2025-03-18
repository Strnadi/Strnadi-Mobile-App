import Flutter
import UIKit
import workmanager

@main
@objc class AppDelegate: FlutterAppDelegate {

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        // Register background tasks inside the method
        WorkmanagerPlugin.registerBGProcessingTask(withIdentifier: "com.delta.strnadi.sendRecording")
        //WorkmanagerPlugin.registerPeriodicTask(withIdentifier: "com.delta.strnadi.sendRecording", frequency: NSNumber(value: 20 * 60))

        //UIApplication.shared.setMinimumBackgroundFetchInterval(TimeInterval(60 * 15))
        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}
