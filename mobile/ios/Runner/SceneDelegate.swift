import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  private var privacyView: UIView?

  override func sceneWillResignActive(_ scene: UIScene) {
    super.sceneWillResignActive(scene)
    guard let windowScene = scene as? UIWindowScene, let window = windowScene.windows.first else {
      return
    }
    let view = UIView(frame: window.bounds)
    view.backgroundColor = .systemBackground
    view.tag = 9999
    window.addSubview(view)
    privacyView = view
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    privacyView?.removeFromSuperview()
    privacyView = nil
    guard let windowScene = scene as? UIWindowScene, let window = windowScene.windows.first else {
      return
    }
    window.viewWithTag(9999)?.removeFromSuperview()
  }
}
