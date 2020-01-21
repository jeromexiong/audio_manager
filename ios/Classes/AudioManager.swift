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
        case stop, playing, buffering, pause, ended, next, previous, timeupdate(_ position: Double, _ duration: Double), error(NSError)
    }
    
    public static let `default`: AudioManager = {
        return AudioManager()
    }()
    
    private override init() {
        super.init()
    }
    /// 事件回调  ⚠️使用weak防止内存泄露
    open var onEvents: ((Events)->Void)?
    /// 是否缓存中
    open fileprivate(set) var buffering = true {
        didSet {
            if buffering {
                onEvents?(.buffering)
            }
            playing = !buffering
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
    /// get total duration  /milisecond
    open var duration: Double {
        let duration = queue.currentItem?.duration ?? CMTime.zero
        if CMTimeGetSeconds(duration).isNaN {
            return 0
        }
        return CMTimeGetSeconds(duration) * 1000
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
    
    /// 注册后台播放
    /// register in application didFinishLaunchingWithOptions method
    open func registerBackground(){
        let session = AVAudioSession.sharedInstance()
        do{
            try session.setActive(true)
            try session.setCategory(AVAudioSession.Category.playback)
            try session.setCategory(.playback, options: .allowBluetooth)
            if #available(iOS 10.0, *) {
                try session.setCategory(.playback, options: .allowAirPlay)
                try session.setCategory(.playback, options: .allowBluetoothA2DP)
            }
            try session.overrideOutputAudioPort(AVAudioSession.PortOverride.speaker)
            NotificationCenter.default.addObserver(self, selector: #selector(handleRouteChange(_:)), name: AVAudioSession.routeChangeNotification, object: nil)
            
        }catch{
            onEvents?(.error(error as NSError))
        }
        NotificationCenter.default.addObserver(self, selector: #selector(audioSessionInterrupted(_:)), name: AVAudioSession.interruptionNotification, object: nil)
    }
    
    /// 必须要调用 start method 才能进行其他操作
    open func start(_ link: String, isLocal: Bool = false) {
        var playerItem: AVPlayerItem? = _playingMusic[link] as? AVPlayerItem
        if playerItem == nil {
            if isLocal {
                guard let path = Bundle.main.path(forResource: link, ofType: "") else {
                    onEvents?(.error(NSError(domain: domain, code: -1, userInfo: ["msg": "link [\(link)] is invalid"])))
                    return
                }
                playerItem = AVPlayerItem(url: URL(fileURLWithPath: path))
            }else {
                guard let path = transformURLString(link)?.url, let _ = path.host else {
                    onEvents?(.error(NSError(domain: domain, code: -1, userInfo: ["msg": "link [\(link)] is invalid"])))
                    return
                }
                playerItem = AVPlayerItem(url: path)
            }
            _playingMusic[link] = playerItem
            queue.replaceCurrentItem(with: playerItem)
            queue.actionAtItemEnd = .advance
            queue.rate = rate
            url = link
            
            pause(link)
            observingTimeChanges()
            updateLockInfo()
            setRemoteControl()
            NotificationCenter.default.addObserver(self, selector: #selector(playerFinishPlaying(_:)), name: .AVPlayerItemDidPlayToEndTime, object: nil)
        }else {
            play(link)
        }
    }
    
    open func seek(to position: Double, link: String? = nil) {
        guard let _url = link ?? url, let playerItem = _playingMusic[_url] as? AVPlayerItem,
            let timescale = queue.currentItem?.asset.duration.timescale else {
                onEvents?(.error(NSError(domain: domain, code: 0, userInfo: ["msg": "you have to invoke start method first"])))
                return
        }
        if queue.currentItem?.status != .readyToPlay { return }
        
        playerItem.seek(to: CMTime(seconds: position, preferredTimescale: timescale)) { (_) in
            self._playingMusic[_url] = playerItem
            self.play()
            self.playing = true
            self.onEvents?(.playing)
        }
    }
    
    /// 播放▶️音乐🎵
    open func play(_ link: String? = nil){
        guard let _ = _playingMusic[link ?? url ?? ""] as? AVPlayerItem else {
            onEvents?(.error(NSError(domain: domain, code: 0, userInfo: ["msg": "you have to invoke start method first"])))
            return
        }
        queue.play()
        playing = true
        onEvents?(.playing)
    }
    
    /// 暂停⏸音乐🎵
    open func pause(_ link: String? = nil) {
        guard let _ = _playingMusic[link ?? url ?? ""] as? AVPlayerItem else {
            onEvents?(.error(NSError(domain: domain, code: 0, userInfo: ["msg": "you have to invoke start method first"])))
            return
        }
        queue.pause()
        playing = false
        onEvents?(.pause)
    }
    
    /// 停止⏹音乐🎵
    open func stop(_ link: String? = nil) {
        let playerItem: AVPlayerItem? = _playingMusic[link ?? url ?? ""] as? AVPlayerItem
        if playerItem != nil {
            queue.remove(playerItem!)
        }
        if timeObserver != nil {
            NotificationCenter.default.removeObserver(Notification.Name.AVPlayerItemDidPlayToEndTime)
            timeObserver = nil
        }
        playing = false
        onEvents?(.stop)
    }
    
    /// 清除所有播放信息
    open func clean() {
        queue.removeAllItems()
        _playingMusic.removeAll()
        stop()
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
    /// 监听时间变化
    func observingTimeChanges() {
        if timeObserver != nil {
            timeObserver = nil
        }else{
            let time = CMTimeMake(value: 1, timescale: 1)
            timeObserver = queue.addPeriodicTimeObserver(forInterval: time, queue: DispatchQueue.main, using: { (currentPlayerTime) in
                self.updateLockInfo()
                self.checkAudioPlayback()
            })
        }
    }
    func checkAudioPlayback(){
        if queue.currentItem?.status == .readyToPlay {
            let playbackLikelyToKeepUp = queue.currentItem?.isPlaybackLikelyToKeepUp
            let playbackBufferFull = queue.currentItem?.isPlaybackBufferFull
            let playbackBufferEmpty = queue.currentItem?.isPlaybackBufferEmpty
            
            if playbackLikelyToKeepUp ?? false {
                self.buffering = false
            }else if playbackBufferEmpty ?? true{
                self.buffering = true
            }else if playbackBufferFull ?? false{
                self.buffering = false
            }
        }
    }
    @objc func playerFinishPlaying(_ n: Notification) {
        queue.seek(to: CMTime.zero)
        pause()
        onEvents?(.ended)
    }
    /// 锁屏信息
    func updateLockInfo() {
        guard let _ = url, playing == true else {
            return
        }
        let duration = Double(CMTimeGetSeconds(queue.currentItem?.duration ?? .zero))
        let currentTime = Double(CMTimeGetSeconds(queue.currentTime()))
        
        let center = MPNowPlayingInfoCenter.default()
        var infos = [String: Any]()
        
        infos[MPMediaItemPropertyTitle] = title
        infos[MPMediaItemPropertyArtist] = desc
        infos[MPMediaItemPropertyPlaybackDuration] = duration
        infos[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
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
        
        onEvents?(.timeupdate(currentTime, duration))
    }
    /// 锁屏操作
    func setRemoteControl() {
        let remote = MPRemoteCommandCenter.shared()
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
    @objc func audioSessionInterrupted(_ n: Notification) {
        print("\n\n\n > > > > > Error Audio Session Interrupted ","\n\n\n")
        guard let userInfo = n.userInfo,
            let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
                return
        }
        switch type {
            
        case .began:
            // Interruption began, take appropriate actions
            break
        case .ended:
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    // Interruption Ended - playback should resume
                } else {
                    // Interruption Ended - playback should NOT resume
                }
            }
            break
        @unknown default:
            break
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

