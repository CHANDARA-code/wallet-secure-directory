import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var privacyView: UIView?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    setupBackupExclusionChannel(binaryMessenger: engineBridge.applicationRegistrar.messenger())
  }

  private func setupBackupExclusionChannel(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "com.example.wallet_app/backup_exclusion", binaryMessenger: binaryMessenger)
    channel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
      if call.method == "excludeFromBackup" {
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String else {
          result(FlutterError(code: "INVALID_ARGS", message: "Path is required", details: nil))
          return
        }
        var url = URL(fileURLWithPath: path)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        do {
          try url.setResourceValues(resourceValues)
          result(true)
        } catch {
          result(FlutterError(code: "EXCLUSION_FAILED", message: error.localizedDescription, details: nil))
        }
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  override func applicationWillResignActive(_ application: UIApplication) {
    super.applicationWillResignActive(application)
    guard let window = window else { return }
    let view = UIView(frame: window.bounds)
    view.backgroundColor = .systemBackground
    view.tag = 9999
    window.addSubview(view)
    privacyView = view
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    privacyView?.removeFromSuperview()
    privacyView = nil
    window?.viewWithTag(9999)?.removeFromSuperview()
  }
}
