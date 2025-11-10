import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    // Register platform channels directly using the engine's registrar
    let registrar = controller.engine.registrar(forPlugin: "PitchChannelHandler")
    PitchChannelHandler.register(with: registrar!)
    print("AppDelegate: Successfully registered PitchChannelHandler")
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
