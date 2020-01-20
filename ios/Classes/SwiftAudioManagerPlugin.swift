import Flutter
import UIKit

public class SwiftAudioManagerPlugin: NSObject, FlutterPlugin {
    fileprivate var registrar: FlutterPluginRegistrar!
    fileprivate static let instance: SwiftAudioManagerPlugin = {
        return SwiftAudioManagerPlugin()
    }()
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "audio_manager", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(instance, channel: channel)
        registrar.addApplicationDelegate(instance)
        
        instance.registrar = registrar
        AudioManager.default.onEvents = { event in
            switch event {
            case .buffering:
                channel.invokeMethod("buffering", arguments: nil)
            case .playing, .pause:
                channel.invokeMethod("playstatus", arguments: AudioManager.default.playing)
            case .timeupdate(let position, let duration):
                channel.invokeMethod("timeupdate", arguments: ["position": Int(position*1000), "duration": Int(duration*1000)])
            case .error(let e):
                channel.invokeMethod("error", arguments: e.description)
            case .next:
                channel.invokeMethod("next", arguments: nil)
            case .previous:
                channel.invokeMethod("previous", arguments: nil)
            default:
                break
            }
        }
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? Dictionary<String,Any> ?? [:]
        let url = arguments["url"] as? String
        print(arguments)
        switch call.method {
        case "getPlatformVersion":
            result("iOS " + UIDevice.current.systemVersion)
        case "start":
            guard let url = url else {
                result("参数错误")
                return
            }
            AudioManager.default.title = arguments["title"] as? String
            AudioManager.default.desc = arguments["desc"] as? String
            if let cover = arguments["cover"] as? String, let isLocalCover = arguments["isLocalCover"] as? Bool {
                if !isLocalCover, let _cover = URL(string: cover), let data = try? Data(contentsOf: _cover) {
                    AudioManager.default.cover = UIImageView(image: UIImage(data: data))
                }else if let path = self.getLocal(SwiftAudioManagerPlugin.instance.registrar, path: cover) {
                    AudioManager.default.cover = UIImageView(image: UIImage(contentsOfFile: path))
                }
            }
            let isLocal = arguments["isLocal"] as? Bool ?? false
            AudioManager.default.start(url, isLocal: isLocal)
        case "playOrPause":
            if AudioManager.default.playing {
                AudioManager.default.pause(url)
            }else {
                AudioManager.default.play(url)
            }
            result(AudioManager.default.playing)
        case "updateLrc":
            AudioManager.default.desc = arguments["lrc"] as? String
        case "seekTo":
            guard let position = arguments["position"] as? Double else {
                result("参数错误")
                return
            }
            AudioManager.default.seek(to: position/1000, link: url)
        case "rate":
            guard let rate = arguments["rate"] as? Float else {
                result("参数错误")
                return
            }
            AudioManager.default.rate = rate
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    func getLocal(_ registrar: FlutterPluginRegistrar, path: String) -> String? {
        let key = registrar.lookupKey(forAsset: path)
        return Bundle.main.path(forResource: key, ofType: nil)
    }
    
    public func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [AnyHashable : Any] = [:]) -> Bool {
        AudioManager.default.registerBackground()
        return true
    }
}
