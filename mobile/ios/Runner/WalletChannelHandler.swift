import Flutter
import Foundation
import PassKit
import UIKit

class WalletChannelHandler: NSObject, PKAddPassesViewControllerDelegate {
  private static var instance: WalletChannelHandler?

  private var pendingResult: FlutterResult?
  private var pendingPass: PKPass?

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "com.example.wallet_app/wallet", binaryMessenger: messenger)
    let handler = WalletChannelHandler()
    self.instance = handler
    channel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
      handler.handle(call, result: result)
    }
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "addPass" {
      addPass(call: call, result: result)
    } else {
      result(FlutterMethodNotImplemented)
    }
  }

  private func addPass(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard self.pendingResult == nil else {
      result(FlutterError(code: "busy", message: "Pass addition already in progress", details: nil))
      return
    }

    guard PKAddPassesViewController.canAddPasses() else {
      result(FlutterError(code: "unavailable", message: "PassKit cannot add passes on this device", details: nil))
      return
    }

    let passData: Data
    if let typedData = call.arguments as? FlutterStandardTypedData {
      passData = typedData.data
    } else if let rawData = call.arguments as? Data {
      passData = rawData
    } else {
      result(FlutterError(code: "invalid_args", message: "Pass bytes are required", details: nil))
      return
    }

    let pass: PKPass
    do {
      pass = try PKPass(data: passData)
    } catch {
      result(FlutterError(code: "invalid_pass", message: error.localizedDescription, details: nil))
      return
    }

    let library = PKPassLibrary()
    if library.containsPass(pass) {
      result(true)
      return
    }

    guard let addPassesVC = PKAddPassesViewController(pass: pass) else {
      result(FlutterError(code: "invalid_pass", message: "Failed to initialize pass view controller", details: nil))
      return
    }

    guard let rootVC = topViewController() else {
      result(FlutterError(code: "unavailable", message: "No active view controller to present pass", details: nil))
      return
    }

    self.pendingResult = result
    self.pendingPass = pass
    addPassesVC.delegate = self
    rootVC.present(addPassesVC, animated: true, completion: nil)
  }

  func addPassesViewControllerDidFinish(_ controller: PKAddPassesViewController) {
    let pass = self.pendingPass
    let res = self.pendingResult
    self.pendingPass = nil
    self.pendingResult = nil

    controller.dismiss(animated: true) {
      guard let res = res else { return }
      guard let pass = pass else {
        res(false)
        return
      }
      let library = PKPassLibrary()
      let added = library.containsPass(pass)
      res(added)
    }
  }

  private func topViewController() -> UIViewController? {
    var root: UIViewController?
    for scene in UIApplication.shared.connectedScenes {
      if let windowScene = scene as? UIWindowScene,
         windowScene.activationState == .foregroundActive {
        for window in windowScene.windows where window.isKeyWindow {
          root = window.rootViewController
          break
        }
      }
      if root != nil { break }
    }
    if root == nil {
      root = UIApplication.shared.windows.first(where: { $0.isKeyWindow })?.rootViewController
    }
    var current = root
    while let presented = current?.presentedViewController {
      current = presented
    }
    return current
  }
}
