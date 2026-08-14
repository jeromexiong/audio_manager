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
        setupVolumeObservation()
    }
    deinit {
        volumeTimer?.invalidate()
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
    fileprivate var observeTimeControl: NSKeyValueObservation?
    fileprivate var observeVolume: NSKeyValueObservation?
    fileprivate var lastReportedVolume: Float = -1
    fileprivate var volumeTimer: Timer?

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
                if volumeView.superview == nil {
                    keyWindow?.addSubview(volumeView)
                }
            } else {
                volumeView.removeFromSuperview()
            }
        }
    }
    /// 当前音量
    open var currentVolume: Float {
        return session.outputVolume
    }
}
public extension AudioManager {
    /// 更新锁屏/通知信息
    func updateMetadata(title: String? = nil, desc: String? = nil, cover: UIImageView? = nil) {
        if let title = title {
            self.title = title
        }
        if let desc = desc {
            self.desc = desc
        }
        if let cover = cover {
            self.cover = cover
        }
        setRemoteInfo()
    }

    /// 必须要调用 start method 才能进行其他操作
    func start(_ link: String, isLocal: Bool = false) {
        var playerItem: AVPlayerItem? = _playingMusic[link] as? AVPlayerItem
        if playerItem == nil {
            stop(url)
            if isLocal {
                guard let path = Bundle.main.path(forResource: link, ofType: "") else {
                    onError(.custom(-1, "link [\(link)] is invalid"))
                    return
                }
                playerItem = AVPlayerItem(url: URL(fileURLWithPath: path))
            }else {
                guard let path = transformURLString(link)?.url else {
                    onError(.custom(-1, "link [\(link)] is invalid"))
                    return
                }
                let options: [String: Any] = [
                    "AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": "audio_manager"]
                ]
                let asset = AVURLAsset(url: path, options: options)
                playerItem = AVPlayerItem(asset: asset)
            }
            _playingMusic[link] = playerItem
            queue.replaceCurrentItem(with: playerItem)
            queue.actionAtItemEnd = .none
            queue.rate = rate
            if #available(iOS 10.0, *) {
                queue.automaticallyWaitsToMinimizeStalling = false
            }
            url = link
        }else {
            play(link)
        }

        activateSession()
        UIApplication.shared.beginReceivingRemoteControlEvents()
        observingProps()
        observingTimeChanges()
        setRemoteInfo()
        NotificationCenter.default.addObserver(self, selector: #selector(playerFinishPlaying(_:)), name: .AVPlayerItemDidPlayToEndTime, object: queue.currentItem)
    }

    func seek(to position: Double, link: String? = nil) {
        guard let _url = link ?? url, let playerItem = _playingMusic[_url] as? AVPlayerItem else {
            onError(.notReady)
            return
        }
        if queue.currentItem?.status != .readyToPlay { return }
        let timescale = queue.currentItem?.asset.duration.timescale ?? 0
        playerItem.seek(to: CMTime(seconds: position, preferredTimescale: timescale)) {[weak self] (flag) in
            if flag {
                self?.onEvents?(.seekComplete(Int(position * 1000)))
            }
        }
    }

    /// 设置音量大小 0~1
    func setVolume(_ value: Float, show volume: Bool = true) {
        let value = min(max(value, 0), 1)
        // MPVolumeSlider 只有挂载到窗口上才会被系统创建，不能每次 new 一个 MPVolumeView，
        // 否则 subviews 为空，音量写不进系统
        if volumeView.superview == nil {
            keyWindow?.addSubview(volumeView)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self = self else { return }
            for view in self.volumeView.subviews {
                if NSStringFromClass(view.classForCoder) == "MPVolumeSlider",
                   let slider = view as? UISlider {
                    slider.value = value
                    break
                }
            }
            self.showVolumeView = volume
        }
    }

    /// iOS 13+ UIApplication.keyWindow 已废弃，需要从 scene 取主窗口
    fileprivate var keyWindow: UIWindow? {
        if #available(iOS 13.0, *) {
            return UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }
        } else {
            return UIApplication.shared.keyWindow
        }
    }

    /// 播放▶️音乐🎵
    func play(_ link: String? = nil) {
        guard let playerItem = _playingMusic[link ?? url ?? ""] as? AVPlayerItem, playerItem.status == .readyToPlay else {
            onError(.notReady)
            return
        }
        if #available(iOS 10.0, *) {
            queue.playImmediately(atRate: rate)
        } else {
            queue.play()
            queue.rate = rate
        }
        synchronizeState()
    }

    /// 暂停⏸音乐🎵
    func pause(_ link: String? = nil) {
        guard let _ = _playingMusic[link ?? url ?? ""] as? AVPlayerItem else {
            onError(.notReady)
            return
        }
        queue.pause()
        synchronizeState()
    }

    /// 停止⏹音乐🎵
    func stop(_ link: String? = nil) {
        if let observer = timeObserver {
            timeObserver = nil
            queue.removeTimeObserver(observer)
            NotificationCenter.default.removeObserver(self,
                name: .AVPlayerItemDidPlayToEndTime,
                object: queue.currentItem)
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

    /// 以播放器的真实状态刷新 UI 状态
    func synchronizeState() {
        if #available(iOS 10.0, *) {
            updatePlayingState(queue.timeControlStatus == .playing)
        } else {
            updatePlayingState(queue.rate > 0)
        }
        setRemoteInfo()
    }
}
private enum AudioError {
    case notReady
    case custom(Int, String)

    var description: (Int, String) {
        switch self {
        case .notReady:
            return (0, "not ready to play")
        case let .custom(code, msg):
            return (code, msg)
        }
    }
}
fileprivate extension AudioManager {
    func onError(_ error: AudioError) {
        onEvents?(.error(NSError(domain: domain, code: error.description.0, userInfo: ["msg": error.description.1])))
    }
    var domain: String {
        return "\((#file as NSString).lastPathComponent)[\(#line)])"
    }
    func transformURLString(_ string: String) -> URLComponents? {
        return URLComponents(string: string)
    }
    @objc func playerFinishPlaying(_ n: Notification) {
        queue.seek(to: CMTime.zero)
        stop()
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
                } else {
                    self.queue.pause()
                }
                self.synchronizeState()
                self.onEvents?(.ready(self.duration))
            } else if _playerItem.status == .failed {
                let message = _playerItem.error?.localizedDescription ?? "player item failed"
                self.onError(.custom(-1, message))
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
        if #available(iOS 10.0, *) {
            observeTimeControl = queue.observe(\.timeControlStatus, options: [.new]) {
                [weak self] player, change in
                self?.updatePlayingState(player.timeControlStatus == .playing)
            }
        }
    }

    private func updatePlayingState(_ isPlaying: Bool) {
        if playing == isPlaying { return }
        playing = isPlaying
        onEvents?(isPlaying ? .playing : .pause)
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
        NotificationCenter.default.addObserver(self, selector: #selector(handleRouteChange(_:)), name: AVAudioSession.routeChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(audioSessionInterrupted(_:)), name: AVAudioSession.interruptionNotification, object: nil)
        // 应用被终止/场景断开时清除通知中心与控制中心的播放信息
        NotificationCenter.default.addObserver(self, selector: #selector(appWillTerminate),
                                               name: UIApplication.willTerminateNotification, object: nil)
        if #available(iOS 13.0, *) {
            NotificationCenter.default.addObserver(self, selector: #selector(appWillTerminate),
                                                   name: UIScene.didDisconnectNotification, object: nil)
        }
    }

    /// 应用被终止（含 UIScene 场景断开）时清除锁屏/控制中心的播放信息，
    /// 避免"正在播放"卡片残留在通知中心
    @objc func appWillTerminate() {
        // 终止阶段不应再向 Flutter 触发事件，直接清理本地状态
        if let observer = timeObserver {
            timeObserver = nil
            queue.removeTimeObserver(observer)
        }
        queue.removeAllItems()
        _playingMusic.removeAll()
        playing = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        // 停用音频会话，使系统不再认为有活跃播放
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("AudioManager: failed to deactivate session on terminate: \(error)")
        }
    }

    /// 应用回到前台时同步状态
    /// （由插件注册的 UIApplication.didBecomeActiveNotification 触发）
    @objc func appDidBecomeActive() {
        synchronizeState()
        // 后台/控制中心改过音量的话，回前台立即同步（reportVolumeChange 内部去重）
        reportVolumeChange(session.outputVolume)
    }

    func activateSession() {
        do{
            if #available(iOS 10.0, *) {
                try session.setCategory(.playback, mode: .default, policy: .longForm, options: [.allowAirPlay, .allowBluetoothA2DP, .duckOthers])
            } else {
                try session.setCategory(.playback, options: [.allowBluetooth, .duckOthers])
            }
            try session.setActive(true)
            try session.overrideOutputAudioPort(.speaker)
        }catch{
            print("AudioManager: failed to activate session: \(error)")
        }
        // outputVolume 的 KVO/轮询都依赖 session 激活；无论上面的配置是否抛错都要注册，
        // 否则音量永远监听不到
        startObservingVolume()
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
        guard let _ = url else {
            return
        }
        if #available(iOS 10.0, *) {
            updatePlayingState(queue.timeControlStatus == .playing)
        } else {
            updatePlayingState(queue.rate > 0)
        }
        guard playing == true else { return }
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
        // 路由变化（插拔耳机/蓝牙切换）后 outputVolume 的 KVO 可能停止回调，重注册刷新
        startObservingVolume()
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
    /// 监听系统媒体音量变化（硬音量键 / 控制中心 / 路由切换）
    private func setupVolumeObservation() {
        // 兜底：私有通知 AVSystemController_SystemVolumeDidChangeNotification
        // （iOS 15 之前可靠，iOS 15+ 可能不再触发）
        NotificationCenter.default.addObserver(self, selector: #selector(volumeChange(n:)),
                                               name: NSNotification.Name(rawValue: "AVSystemController_SystemVolumeDidChangeNotification"),
                                               object: nil)
    }

    /// 注册 outputVolume 的 KVO 并启动轮询兜底。
    /// KVO 依赖 audio session 激活，且不同 iOS 版本上可靠性不一；
    /// 轮询保证任何情况下都能同步系统音量
    private func startObservingVolume() {
        if #available(iOS 11.0, *) {
            observeVolume = nil
            observeVolume = session.observe(\.outputVolume, options: [.new]) { [weak self] session, _ in
                self?.reportVolumeChange(session.outputVolume)
            }
        }
        startVolumePoller()
    }

    /// 定时读取 outputVolume 作为最终保障（KVO/私有通知失效时兜底）
    private func startVolumePoller() {
        guard volumeTimer == nil else { return }
        if #available(iOS 10.0, *) {
            let timer = Timer(timeInterval: 0.3, repeats: true) { [weak self] _ in
                self?.volumePollTick()
            }
            RunLoop.main.add(timer, forMode: .common)
            volumeTimer = timer
        }
    }

    @objc private func volumePollTick() {
        reportVolumeChange(session.outputVolume)
    }

    fileprivate func reportVolumeChange(_ volume: Float) {
        guard volume != lastReportedVolume else { return }
        lastReportedVolume = volume
        print("audio_manager volume change: \(volume)")
        onEvents?(.volumeChange(volume))
    }

    @objc func volumeChange(n: Notification) {
        guard let userInfo = n.userInfo,
              let parameter = userInfo["AVSystemController_AudioCategoryNotificationParameter"] as? String,
              parameter == "Audio/Video",
              let volume = userInfo["AVSystemController_AudioVolumeNotificationParameter"] as? NSNumber else {
            return
        }
        // 只按音频类别过滤；不再强卡 reason == "ExplicitVolumeChange"，
        // 否则路由切换 / 系统调整等非显式音量变化会被丢弃，导致音量不同步
        reportVolumeChange(volume.floatValue)
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
