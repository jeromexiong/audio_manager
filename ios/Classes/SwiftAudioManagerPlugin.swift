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
            case .ready(let duration):
                channel.invokeMethod("ready", arguments: duration)
            case .seekComplete(let position):
                channel.invokeMethod("seekComplete", arguments: position)
            case .buffering(let buffering, let buffer):
                channel.invokeMethod("buffering", arguments: ["buffering": buffering, "buffer": buffer])
            case .playing, .pause:
                channel.invokeMethod("playstatus", arguments: AudioManager.default.playing)
            case .timeupdate(let position, let duration):
                channel.invokeMethod("timeupdate", arguments: ["position": Int(position*1000), "duration": Int(duration*1000)])
            case .error(let e):
                DispatchQueue.main.async {
                    AudioManager.default.clean()
                }
                channel.invokeMethod("error", arguments: e.description)
            case .next:
                channel.invokeMethod("next", arguments: nil)
            case .previous:
                channel.invokeMethod("previous", arguments: nil)
            case .ended:
                channel.invokeMethod("ended", arguments: nil)
            case .stop:
                channel.invokeMethod("stop", arguments: nil)
            case .volumeChange(let value):
                channel.invokeMethod("volumeChange", arguments: value)
            }
        }
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? Dictionary<String,Any> ?? [:]
        let url = arguments["url"] as? String
        print("arguments: ", arguments)
        switch call.method {
        case "getPlatformVersion":
            result("iOS " + UIDevice.current.systemVersion)
        case "start":
            guard var url = url else {
                result("参数错误")
                return
            }
            let title = arguments["title"] as? String
            let desc = arguments["desc"] as? String
            let cover = arguments["cover"] as? String
            let isLocalCover = arguments["isLocalCover"] as? Bool ?? false
            let isLocal = arguments["isLocal"] as? Bool ?? false
            let isAuto = arguments["isAuto"] as? Bool ?? true
            AudioManager.default.isAuto = isAuto
            if let cover = cover {
                loadCover(cover, isLocalCover: isLocalCover) { coverView in
                    AudioManager.default.updateMetadata(title: title, desc: desc, cover: coverView)
                }
            } else {
                AudioManager.default.updateMetadata(title: title, desc: desc, cover: nil)
            }
            if isLocal {
                url = SwiftAudioManagerPlugin.instance.registrar.lookupKey(forAsset: url)
            }
            AudioManager.default.start(url, isLocal: isLocal)
            result(nil)
        case "playOrPause":
            if AudioManager.default.playing {
                AudioManager.default.pause(url)
            }else {
                AudioManager.default.play(url)
            }
            result(AudioManager.default.playing)
        case "play":
            AudioManager.default.play(url)
            result(AudioManager.default.playing)
        case "pause":
            AudioManager.default.pause(url)
            result(AudioManager.default.playing)
        case "stop":
            AudioManager.default.stop()
        case "release":
            AudioManager.default.clean()
        case "updateLrc":
            AudioManager.default.updateMetadata(desc: arguments["lrc"] as? String)
        case "updateInfo":
            guard let title = arguments["title"] as? String,
                  let desc = arguments["desc"] as? String,
                  let cover = arguments["cover"] as? String else {
                result("参数错误")
                return
            }
            let isLocalCover = arguments["isLocalCover"] as? Bool ?? false
            loadCover(cover, isLocalCover: isLocalCover) { coverView in
                AudioManager.default.updateMetadata(title: title, desc: desc, cover: coverView)
            }
            result(nil)
        case "seekTo":
            guard let position = arguments["position"] as? Double else {
                result("参数错误")
                return
            }
            AudioManager.default.seek(to: position/1000, link: url)
        case "rate":
            guard let rate = arguments["rate"] as? Double else {
                result("参数错误")
                return
            }
            AudioManager.default.rate = Float(rate)
        case "setVolume":
            guard let value = arguments["value"] as? Double else {
                result("参数错误")
                return
            }
            let showVolume = arguments["showVolume"] as? Bool ?? false
            AudioManager.default.setVolume(Float(value), show: showVolume)
        case "currentVolume":
            result(AudioManager.default.currentVolume)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    func getLocal(_ registrar: FlutterPluginRegistrar, path: String) -> String? {
        let key = registrar.lookupKey(forAsset: path)
        return Bundle.main.path(forResource: key, ofType: nil)
    }

    private func loadCover(_ cover: String, isLocalCover: Bool, completion: @escaping (UIImageView?) -> Void) {
        if isLocalCover {
            if let path = self.getLocal(SwiftAudioManagerPlugin.instance.registrar, path: cover) {
                completion(UIImageView(image: UIImage(contentsOfFile: path)))
            } else {
                completion(nil)
            }
            return
        }
        guard let url = URL(string: cover) else {
            completion(nil)
            return
        }
        let request = URLRequest(url: url)
        NSURLConnection.sendAsynchronousRequest(request, queue: OperationQueue.main) { (_, data, error) in
            if let data = data {
                completion(UIImageView(image: UIImage(data: data)))
            } else {
                completion(nil)
            }
        }
    }
    
    public func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [AnyHashable : Any] = [:]) -> Bool {
        AudioManager.default.registerBackground()
        return true
    }
    
//    public func applicationWillResignActive(_ application: UIApplication) {
//        backTaskId = backgroundPlayerID(backTaskId)
//    }
    
    private var backTaskId: UIBackgroundTaskIdentifier = .invalid
    /// 设置后台任务ID
    private func backgroundPlayerID(_ backTaskId: UIBackgroundTaskIdentifier) -> UIBackgroundTaskIdentifier {
        var taskId = UIBackgroundTaskIdentifier.invalid;
        taskId = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
        if taskId != .invalid && backTaskId != .invalid {
            UIApplication.shared.endBackgroundTask(backTaskId)
        }
        return taskId
    }
}
