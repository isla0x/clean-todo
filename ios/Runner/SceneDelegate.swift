import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  // 잠긴 위젯을 눌러 앱이 처음 켜질 때
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    if let url = connectionOptions.urlContexts.first?.url {
      HaruNative.shared.handleLink(url)
    }
    super.scene(scene, willConnectTo: session, options: connectionOptions)
  }

  // 앱이 이미 켜져 있을 때 위젯을 눌렀을 때
  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    if let url = URLContexts.first?.url {
      HaruNative.shared.handleLink(url)
    }
    super.scene(scene, openURLContexts: URLContexts)
  }
}
