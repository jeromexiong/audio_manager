//
//  AudioManager.swift
//
//  Created by Jerome Xiong on 2020/1/13.
//  Copyright © 2020 JeromeXiong. All rights reserved.
//

import UIKit
import AVFoundation
import MediaPlayer

open class AudioManager: NSObject {
    public enum Events {
        case ready(_ duration: Int), seekComplete(_ position: Int), stop, playing, buffering(Bool, Double), pause, ended, next, previous, timeupdate(_ position: Double, _ duration: Double), error(NSError), volumeChange(Float)
    }
    
    public static let `default`: AudioManager = {
        return AudioManager()
    }()
    
    private override init() {
        super.init()
        setRemoteControl()
        NotificationCenter.default.addObserver(self, selector: #selector(volumeChange(n:)), name: NSNotification.Name(rawValue: "AVSystemController_SystemVolumeDidChangeNotification"), object: nil)
    }
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    /// 事件回调  ⚠️使用weak防止内存泄露
    open var onEvents: ((Events)->Void)?
    /// 是否缓存中
    open fileprivate(set) var buffering = true {
        didSet {
            onEvents?(.buffering(buffering, buffer))
        }
    }
    /// 缓存进度
    open fileprivate(set) var buffer: Double = 0 {
        didSet {
            onEvents?(.buffering(buffering, buffer))
        }
    }
    /// 是否正在播放
    open fileprivate(set) var playing: Bool = false
    /// 最近播放的URL
    open fileprivate(set) var url: String?
    /// 标题
    open var title: String?
    /// 描述
    open var desc: String?
    /// 封面图
    open var cover: UIImageView?
    /// 播放速率
    open var rate: Float = 1 {
        didSet {
            queue.rate = rate
        }
    }
    /// 是否自动播放
    open var isAuto: Bool = true
    
    /// get total duration  /milisecond
    open var duration: Int {
        let duration = queue.currentItem?.duration ?? CMTime.zero
        if CMTimeGetSeconds(duration).isNaN {
            return 0
        }
        return Int(CMTimeGetSeconds(duration)) * 1000
    }
    /// get current position /milisecond
    open var currentTime: Int {
        guard let currentTime = queue.currentItem?.currentTime() else {
            return 0
        }
        
        if CMTimeGetSeconds(currentTime).isNaN || CMTimeGetSeconds(currentTime).isInfinite{
            return 0
        }else{
            return Int(CMTimeGetSeconds(currentTime)) * 1000
        }
    }
    fileprivate var queue = AVQueuePlayer()
    fileprivate var _playingMusic = Dictionary<String, Any>()
    fileprivate var timeObserver: Any?
    fileprivate var observeStatus: NSKeyValueObservation?
    fileprivate var observeLoaded: NSKeyValueObservation?
    fileprivate var observeBufferEmpty: NSKeyValueObservation?
    fileprivate var observeCanPlay: NSKeyValueObservation?
    
    fileprivate let session = AVAudioSession.sharedInstance()
    fileprivate var interrupterStatus = false
    
    fileprivate lazy var volumeView: MPVolumeView = {
        let volumeView = MPVolumeView()
        volumeView.frame = CGRect(x: -100, y: -100, width: 40, height: 40)
        return volumeView
    }()
    
    /// 是否显示音量视图
    open var showVolumeView: Bool = false {
        didSet {
            if showVolumeView {
                volumeView.removeFromSuperview()
            }else {
                UIApplication.shared.keyWindow?.addSubview(volumeView)
            }
        }
    }
    /// 当前音量
    open var currentVolume: Float {
        return session.outputVolume
    }
}
public extension AudioManager {
    /// 必须要调用 start method 才能进行其他操作
    func start(_ link: String, isLocal: Bool = false) {
        var playerItem: AVPlayerItem? = _playingMusic[link] as? AVPlayerItem
        if playerItem == nil {
            stop(url)
            if isLocal {
                guard let path = Bundle.main.path(forResource: link, ofType: "") else {
                    onEvents?(.error(NSError(domain: domain, code: -1, userInfo: ["msg": "link [\(link)] is invalid"])))
                    return
                }
                playerItem = AVPlayerItem(url: URL(fileURLWithPath: path))
            }else {
                guard let path = transformURLString(link)?.url else {
                    onEvents?(.error(NSError(domain: domain, code: -1, userInfo: ["msg": "link [\(link)] is invalid"])))
                    return
                }
                playerItem = AVPlayerItem(url: path)
            }
            _playingMusic[link] = playerItem
            queue.replaceCurrentItem(with: playerItem)
            queue.actionAtItemEnd = .none
            queue.rate = rate
            if #available(iOS 10.0, *) {
                queue.automaticallyWaitsToMinimizeStalling = false
            }
            url = link
            
            observingProps()
            observingTimeChanges()
            setRemoteInfo()
            
            UIApplication.shared.beginReceivingRemoteControlEvents()
            NotificationCenter.default.addObserver(self, selector: #selector(playerFinishPlaying(_:)), name: .AVPlayerItemDidPlayToEndTime, object: queue.currentItem)
        }else {
            play(link)
        }
    }
    
    func seek(to position: Double, link: String? = nil) {
        guard let _url = link ?? url, let playerItem = _playingMusic[_url] as? AVPlayerItem,
              let timescale = queue.currentItem?.asset.duration.timescale else {
            onEvents?(.error(NSError(domain: domain, code: 0, userInfo: ["msg": "you have to invoke start method first"])))
            return
        }
        if queue.currentItem?.status != .readyToPlay { return }
        
        playerItem.seek(to: CMTime(seconds: position, preferredTimescale: timescale)) {[weak self] (flag) in
            if flag {
                self?.onEvents?(.seekComplete(Int(position * 1000)))
            }
        }
    }
    
    /// 设置音量大小 0~1
    func setVolume(_ value: Float, show volume: Bool = true) {
        var value = min(value, 1)
        value = max(value, 0)
        let volumeView = MPVolumeView()
        var slider = UISlider()
        for view in volumeView.subviews {
            if NSStringFromClass(view.classForCoder) == "MPVolumeSlider" {
                slider = view as! UISlider
                break
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now()+0.01) {
            slider.value = value
        }
        if volume {
            if !showVolumeView {
                showVolumeView = true
            }
        }else {
            showVolumeView = false
        }
    }
    
    /// 播放▶️音乐🎵
    func play(_ link: String? = nil) {
        guard let _ = _playingMusic[link ?? url ?? ""] as? AVPlayerItem else {
            onEvents?(.error(NSError(domain: domain, code: 0, userInfo: ["msg": "you have to invoke start method first"])))
            return
        }
        if #available(iOS 10.0, *) {
            queue.playImmediately(atRate: rate)
        } else {
            queue.play()
            queue.rate = rate
        }
        playing = true
        onEvents?(.playing)
    }
    
    /// 暂停⏸音乐🎵
    func pause(_ link: String? = nil) {
        guard let _ = _playingMusic[link ?? url ?? ""] as? AVPlayerItem else {
            onEvents?(.error(NSError(domain: domain, code: 0, userInfo: ["msg": "you have to invoke start method first"])))
            return
        }
        queue.pause()
        playing = false
        onEvents?(.pause)
    }
    
    /// 停止⏹音乐🎵
    func stop(_ link: String? = nil) {
        if let observer = timeObserver {
            timeObserver = nil
            queue.removeTimeObserver(observer)
            NotificationCenter.default.removeObserver(self)
        }
        let playerItem = _playingMusic[link ?? url ?? ""] as? AVPlayerItem
        if let playerItem = playerItem {
            seek(to: 0, link: link ?? url ?? "")
            queue.remove(playerItem)
            _playingMusic.removeValue(forKey: link ?? url ?? "")
        }
        playing = false
        onEvents?(.stop)
    }
    
    /// 清除所有播放信息
    func clean() {
        stop()
        queue.removeAllItems()
        _playingMusic.removeAll()
        UIApplication.shared.endReceivingRemoteControlEvents()
    }
}
fileprivate extension AudioManager {
    var domain: String {
        return "\((#file as NSString).lastPathComponent)[\(#line)])"
    }
    func transformURLString(_ string: String) -> URLComponents? {
        guard let urlPath = string.components(separatedBy: "?").first else {
            return nil
        }
        
        if urlPath.contains("file:") {
            return URLComponents(url: URL(fileURLWithPath: urlPath), resolvingAgainstBaseURL: false)
        }
        
        var components = URLComponents(string: urlPath)
        if let queryString = string.components(separatedBy: "?").last {
            components?.queryItems = []
            let queryItems = queryString.components(separatedBy: "&")
            for queryItem in queryItems {
                guard let itemName = queryItem.components(separatedBy: "=").first,
                      let itemValue = queryItem.components(separatedBy: "=").last else {
                    continue
                }
                components?.queryItems?.append(URLQueryItem(name: itemName, value: itemValue))
            }
        }
        return components!
    }
    @objc func playerFinishPlaying(_ n: Notification) {
        queue.seek(to: CMTime.zero)
        pause()
        onEvents?(.ended)
    }
    /// 监听属性变化
    func observingProps() {
        observeStatus = queue.currentItem?.observe(\.status) {
            [weak self] _playerItem, change in
            guard let `self` = self else { return }
            if _playerItem.status == .readyToPlay {
                self.playing = self.isAuto
                if self.isAuto {
                    self.onEvents?(.playing)
                }else {
                    self.queue.pause()
                }
                self.onEvents?(.ready(self.duration))
            }else {
                self.playing = false
            }
        }
        
        observeLoaded = queue.currentItem?.observe(\.loadedTimeRanges) {
            [weak self] _playerItem, change in
            guard let `self` = self else { return }
            let ranges = _playerItem.loadedTimeRanges
            guard let timeRange = ranges.first as? CMTimeRange else { return }
            let start = timeRange.start.seconds
            let duration = timeRange.duration.seconds
            let cached = start + duration
            
            let total = _playerItem.duration.seconds
            self.buffer = cached / total * 100
        }
        
        observeBufferEmpty = queue.currentItem?.observe(\.isPlaybackBufferEmpty) {
            [weak self] _playerItem, change in
            self?.buffering = true
        }
        
        observeCanPlay = queue.currentItem?.observe(\.isPlaybackLikelyToKeepUp) {
            [weak self] _playerItem, change in
            self?.buffering = false
        }
    }
    /// 监听时间变化
    func observingTimeChanges() {
        if let observer = timeObserver {
            timeObserver = nil
            queue.removeTimeObserver(observer)
        }
        let time = CMTimeMake(value: 1, timescale: 1)
        timeObserver = queue.addPeriodicTimeObserver(forInterval: time, queue: DispatchQueue.main, using: {[weak self] (currentPlayerTime) in
            self?.updateLockInfo()
        })
    }
}
// MARK: system
public extension AudioManager {
    /// 注册后台播放
    /// register in application didFinishLaunchingWithOptions method
    func registerBackground(){
        do{
            try session.setActive(true)
            try session.setCategory(.playback, options: [.allowBluetooth, .mixWithOthers])
            if #available(iOS 10.0, *) {
                try session.setCategory(.playback, options: [.allowAirPlay, .allowBluetoothA2DP, .mixWithOthers])
            }
            try session.overrideOutputAudioPort(.speaker)
            
        }catch{
            onEvents?(.error(error as NSError))
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(handleRouteChange(_:)), name: AVAudioSession.routeChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(audioSessionInterrupted(_:)), name: AVAudioSession.interruptionNotification, object: nil)
    }
    
    /// 中断结束后继续播放
    /// register in application applicationDidBecomeActive
    func interrupterAction(_ isplay: Bool = false) {
        if playing {
            pause()
            interrupterStatus = true
            return
        }
        if interrupterStatus && isplay {
            play()
            interrupterStatus = false
        }
    }
}
fileprivate extension AudioManager {
    /// 锁屏操作
    func setRemoteControl() {
        let remote = MPRemoteCommandCenter.shared()
        remote.playCommand.removeTarget(self)
        remote.pauseCommand.removeTarget(self)
        remote.togglePlayPauseCommand.removeTarget(self)
        if #available(iOS 9.1, *) {
            remote.changePlaybackPositionCommand.removeTarget(self)
        }
        remote.previousTrackCommand.removeTarget(self)
        remote.nextTrackCommand.removeTarget(self)
        
        remote.playCommand.addTarget { (event) -> MPRemoteCommandHandlerStatus in
            self.play()
            return .success
        }
        remote.pauseCommand.addTarget { (event) -> MPRemoteCommandHandlerStatus in
            self.pause()
            return .success
        }
        remote.togglePlayPauseCommand.addTarget { (event) -> MPRemoteCommandHandlerStatus in
            if self.playing {
                self.pause()
            }else {
                self.play()
            }
            return .success
        }
        if #available(iOS 9.1, *) {
            remote.changePlaybackPositionCommand.addTarget { (event) -> MPRemoteCommandHandlerStatus in
                let playback = event as! MPChangePlaybackPositionCommandEvent
                self.seek(to: playback.positionTime)
                return .success
            }
        }
        remote.previousTrackCommand.addTarget { (event) -> MPRemoteCommandHandlerStatus in
            self.onEvents?(.previous)
            return .success
        }
        remote.nextTrackCommand.addTarget { (event) -> MPRemoteCommandHandlerStatus in
            self.onEvents?(.next)
            return .success
        }
    }
    
    /// 锁屏信息
    func updateLockInfo() {
        guard let _ = url, playing == true else {
            return
        }
        let duration = Double(CMTimeGetSeconds(queue.currentItem?.duration ?? .zero))
        let currentTime = Double(CMTimeGetSeconds(queue.currentTime()))
        if duration.isNaN || currentTime.isNaN { return }
        
        setRemoteInfo()
        onEvents?(.timeupdate(currentTime, duration))
    }
    func setRemoteInfo() {
        let center = MPNowPlayingInfoCenter.default()
        var infos = [String: Any]()
        
        infos[MPMediaItemPropertyTitle] = title
        infos[MPMediaItemPropertyArtist] = desc
        infos[MPMediaItemPropertyPlaybackDuration] = Double(duration / 1000)
        infos[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Double(currentTime / 1000)
        infos[MPNowPlayingInfoPropertyPlaybackRate] = queue.rate
        queue.rate = rate
        
        let image = cover?.image ?? UIImage()
        if #available(iOS 11.0, *) {
            infos[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(image: image)
        } else {
            let cover = image.withText(self.desc ?? "")!
            if #available(iOS 10.0, *) {
                infos[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: CGSize(width: 200,height: 200), requestHandler: { (size) -> UIImage in
                    return cover
                })
                
            } else {
                infos[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(image: image)
            }
        }
        
        center.nowPlayingInfo = infos
    }
}

fileprivate extension AudioManager {
    @objc func audioSessionInterrupted(_ n: Notification) {
        print("\n\n\n > > > > > Error Audio Session Interrupted \n\n\n")
        guard let userInfo = n.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        if type == .began {
            print("Interruption began, take appropriate actions")
            interrupterAction()
        }else {
            interrupterAction(true)
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    print("Interruption Ended - playback should resume")
                } else {
                    print("Interruption Ended - playback should NOT resume")
                }
            }
        }
    }
    @objc func handleRouteChange(_ n: Notification) {
        print("\n\n\n > > > > > Audio Route Changed ","\n\n\n")
        guard let userInfo = n.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue:reasonValue) else {
            return
        }
        
        let ports : [AVAudioSession.Port] = [.airPlay,.builtInMic,.bluetoothA2DP,.bluetoothHFP,.builtInReceiver,.bluetoothLE,.builtInReceiver,.headphones,.headsetMic]
        switch reason {
        case .newDeviceAvailable: //Get Notification When Device Connect
            let session = AVAudioSession.sharedInstance()
            for output in session.currentRoute.outputs where ports.contains(where: {$0 == output.portType}) {
                break
            }
        case .oldDeviceUnavailable:  //Get Notification When Device Disconnect
            if let previousRoute =
                userInfo[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription {
                for output in previousRoute.outputs where ports.contains(where: {$0 == output.portType}) {
                    //Check Player State
                    
                    break
                }
            }
        default: ()
        }
    }
    @objc func volumeChange(n: Notification){
        guard let userInfo = n.userInfo, let parameter = userInfo["AVSystemController_AudioCategoryNotificationParameter"] as? String,
              let reason = userInfo["AVSystemController_AudioVolumeChangeReasonNotificationParameter"] as? String,
              let _volume = userInfo["AVSystemController_AudioVolumeNotificationParameter"] as? NSNumber else {
            return
        }
        if (parameter == "Audio/Video") {
            if (reason == "ExplicitVolumeChange") {
                let volume = _volume.floatValue
                print("当前音量\(volume)")
                self.onEvents?(.volumeChange(volume))
            }
        }
    }
}
extension UIImage {
    func withText(_ text: String) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(self.size, false, 0.0)
        self.draw(in: CGRect(origin: .zero, size: self.size))
        
        // 将文字绘制到图片上面
        let rect = CGRect(origin: CGPoint(x: 0, y: self.size.height*0.4), size: self.size)
        
        // 设置文字样式
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        
        let dict: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key.font: UIFont.systemFont(ofSize: 20),
            NSAttributedString.Key.foregroundColor: UIColor.green,
            NSAttributedString.Key.paragraphStyle: style
        ]
        (text as NSString).draw(in: rect, withAttributes: dict)
        
        let resultImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext();
        return resultImage
    }
}

