import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 앱이 켜져 있을 때도 알림 배너가 보이도록 알림 센터의 대리인을 앱으로 지정해요.
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // 위젯·결제·체험 기간을 다루는 연결 통로
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "HaruNative") {
      HaruNative.shared.attach(messenger: registrar.messenger())
    }
  }
}
