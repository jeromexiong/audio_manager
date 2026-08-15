//
//  AudioManagerPlugin.swift
//  audio_manager
//
//  macOS 端实现：基于 AVQueuePlayer，复用与 iOS 相同的方法通道契约。
//  已接入 Control Center 的 Now Playing 与媒体键（MPNowPlayingInfoCenter/MPRemoteCommandCenter），
//  轮询系统音量以同步 volumeChange。不含 iOS 专属能力：AVAudioSession / MPVolumeView / 后台播放。
//

import FlutterMacOS
import AVFoundation
import AppKit
import MediaPlayer
import CoreAudio

public class AudioManagerPlugin: NSObject, FlutterPlugin {
    public enum Events {
        case ready(_ duration: Int), seekComplete(_ position: Int), stop, playing, buffering(Bool, Double), pause, ended, next, previous, timeupdate(_ position: Double, _ duration: Double), error(NSError), volumeChange(Float)
    }

    private static let instance: AudioManagerPlugin = AudioManagerPlugin()

    private var registrar: FlutterPluginRegistrar?
    private var channel: FlutterMethodChannel?

    private var player = AVQueuePlayer()
    private var playingMusic = [String: AVPlayerItem]()
    private var currentUrl: String?
    private var title: String?
    private var desc: String?
    private var cover: NSImage?
    private var rate: Float = 1 {
        didSet { player.rate = rate }
    }
    private var isAuto = true
    private var buffering = true {
        didSet { onEvents?(.buffering(buffering, buffer)) }
    }
    private var buffer: Double = 0 {
        didSet { onEvents?(.buffering(buffering, buffer)) }
    }
    private var playing = false
    private var timeObserver: Any?
    private var observeStatus: NSKeyValueObservation?
    private var observeLoaded: NSKeyValueObservation?
    private var observeBufferEmpty: NSKeyValueObservation?
    private var observeCanPlay: NSKeyValueObservation?
    private var observeTimeControl: NSKeyValueObservation?

    private var remoteCommandsReady = false
    private var volumeTimer: Timer?
    private var lastReportedVolume: Float = -1

    public var onEvents: ((Events) -> Void)?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "audio_manager", binaryMessenger: registrar.messenger)
        instance.registrar = registrar
        instance.channel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)
        instance.onEvents = { event in
            switch event {
            case .ready(let duration):
                channel.invokeMethod("ready", arguments: duration)
            case .seekComplete(let position):
                channel.invokeMethod("seekComplete", arguments: position)
            case .buffering(let buffering, let buffer):
                channel.invokeMethod("buffering", arguments: ["buffering": buffering, "buffer": buffer])
            case .playing, .pause:
                channel.invokeMethod("playstatus", arguments: instance.playing)
            case .timeupdate(let position, let duration):
                channel.invokeMethod("timeupdate", arguments: ["position": Int(position * 1000), "duration": Int(duration * 1000)])
            case .error(let e):
                DispatchQueue.main.async { instance.clean() }
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
        let arguments = call.arguments as? [String: Any] ?? [:]
        let url = arguments["url"] as? String
        switch call.method {
        case "getPlatformVersion":
            result("macOS " + ProcessInfo.processInfo.operatingSystemVersionString)
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
            isAuto = arguments["isAuto"] as? Bool ?? true
            if let cover = cover {
                loadCover(cover, isLocalCover: isLocalCover) { image in
                    self.updateMetadata(title: title, desc: desc, cover: image)
                }
            } else {
                updateMetadata(title: title, desc: desc, cover: nil)
            }
            if isLocal {
                url = Self.instance.registrar?.lookupKey(forAsset: url) ?? url
            }
            start(url, isLocal: isLocal)
            result(nil)
        case "playOrPause":
            if playing {
                pause(url)
            } else {
                play(url)
            }
            result(playing)
        case "play":
            play(url)
            result(playing)
        case "pause":
            pause(url)
            result(playing)
        case "stop":
            stop()
            result(nil)
        case "release":
            clean()
            result(nil)
        case "updateLrc":
            updateMetadata(desc: arguments["lrc"] as? String)
            result(nil)
        case "updateInfo":
            let title = arguments["title"] as? String
            let desc = arguments["desc"] as? String
            let cover = arguments["cover"] as? String
            let isLocalCover = arguments["isLocalCover"] as? Bool ?? false
            if let cover = cover {
                loadCover(cover, isLocalCover: isLocalCover) { image in
                    self.updateMetadata(title: title, desc: desc, cover: image)
                }
            } else {
                updateMetadata(title: title, desc: desc, cover: nil)
            }
            result(nil)
        case "seekTo":
            guard let position = arguments["position"] as? Double else {
                result("参数错误")
                return
            }
            seek(to: position / 1000, link: url)
            result(nil)
        case "rate":
            guard let rate = arguments["rate"] as? Double else {
                result("参数错误")
                return
            }
            self.rate = Float(rate)
            updateNowPlaying()
            result(nil)
        case "setVolume":
            guard let value = arguments["value"] as? Double else {
                result("参数错误")
                return
            }
            setVolume(Float(value))
            result(nil)
        case "currentVolume":
            result(currentVolume)
        case "getState":
            result([
                "isPlaying": playing,
                "position": currentTime,
                "duration": duration,
                "title": title ?? "",
                "desc": desc ?? "",
                "url": currentUrl ?? "",
            ])
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - 播放核心

    private func start(_ link: String, isLocal: Bool = false) {
        var playerItem: AVPlayerItem? = playingMusic[link]
        if playerItem == nil {
            stop(currentUrl)
            if isLocal {
                // macOS 的 flutter_assets 位于 App.framework/Resources 内，lookupKey
                // 返回相对 bundle 根目录的完整路径（Contents/Frameworks/...），
                // Bundle.main.path(forResource:) 解析不了，须直接拼接 bundle 路径。
                let assetURL = URL(fileURLWithPath: Bundle.main.bundlePath)
                    .appendingPathComponent(link)
                guard FileManager.default.fileExists(atPath: assetURL.path) else {
                    onError(-1, "link [\(link)] is invalid")
                    return
                }
                playerItem = AVPlayerItem(url: assetURL)
            } else {
                guard let url = URL(string: link) else {
                    onError(-1, "link [\(link)] is invalid")
                    return
                }
                let options: [String: Any] = [
                    "AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": "audio_manager"]
                ]
                let asset = AVURLAsset(url: url, options: options)
                playerItem = AVPlayerItem(asset: asset)
            }
            playingMusic[link] = playerItem
            player.replaceCurrentItem(with: playerItem)
            player.actionAtItemEnd = .none
            player.automaticallyWaitsToMinimizeStalling = false
            // 与系统音量对齐（iOS 语义：volume 即系统音量），使 App 输出音量与 UI 一致
            player.volume = systemVolume()
            player.rate = rate
            currentUrl = link
        } else {
            play(link)
        }
        observingProps()
        observingTimeChanges()
        setupRemoteCommands()
        startVolumePoller()
        updateNowPlaying()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerFinishPlaying(_:)),
            name: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem
        )
    }

    private func play(_ link: String? = nil) {
        guard let playerItem = playingMusic[link ?? currentUrl ?? ""], playerItem.status == .readyToPlay else {
            onError(0, "not ready to play")
            return
        }
        player.playImmediately(atRate: rate)
        synchronizeState()
        updateNowPlaying()
    }

    private func pause(_ link: String? = nil) {
        guard playingMusic[link ?? currentUrl ?? ""] != nil else {
            onError(0, "not ready to play")
            return
        }
        player.pause()
        synchronizeState()
        updateNowPlaying()
    }

    private func stop(_ link: String? = nil) {
        if let observer = timeObserver {
            timeObserver = nil
            player.removeTimeObserver(observer)
            NotificationCenter.default.removeObserver(
                self,
                name: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem
            )
        }
        if let item = playingMusic[link ?? currentUrl ?? ""] {
            seek(to: 0, link: link ?? currentUrl ?? "")
            player.remove(item)
            playingMusic.removeValue(forKey: link ?? currentUrl ?? "")
        }
        playing = false
        updateNowPlaying()
        onEvents?(.stop)
    }

    private func clean() {
        stop()
        player.removeAllItems()
        playingMusic.removeAll()
        clearNowPlaying()
    }

    private func seek(to position: Double, link: String? = nil) {
        guard let url = link ?? currentUrl, let playerItem = playingMusic[url] else {
            onError(0, "not ready to play")
            return
        }
        if player.currentItem?.status != .readyToPlay { return }
        let timescale = player.currentItem?.asset.duration.timescale ?? 0
        playerItem.seek(to: CMTime(seconds: position, preferredTimescale: timescale)) { [weak self] flag in
            if flag {
                self?.onEvents?(.seekComplete(Int(position * 1000)))
            }
        }
    }

    private func setVolume(_ value: Float) {
        let clamped = min(max(value, 0), 1)
        player.volume = clamped
        setSystemVolume(clamped) // 尽力同步系统音量，失败时仍由 player.volume 生效
        reportVolumeChange(clamped)
    }

    private var currentVolume: Float {
        return player.volume
    }

    private var duration: Int {
        let duration = player.currentItem?.duration ?? .zero
        if CMTimeGetSeconds(duration).isNaN {
            return 0
        }
        return Int(CMTimeGetSeconds(duration)) * 1000
    }

    private var currentTime: Int {
        guard let currentTime = player.currentItem?.currentTime() else {
            return 0
        }
        if CMTimeGetSeconds(currentTime).isNaN || CMTimeGetSeconds(currentTime).isInfinite {
            return 0
        }
        return Int(CMTimeGetSeconds(currentTime)) * 1000
    }

    private func updateMetadata(title: String? = nil, desc: String? = nil, cover: NSImage? = nil) {
        if let title = title { self.title = title }
        if let desc = desc { self.desc = desc }
        if let cover = cover { self.cover = cover }
        updateNowPlaying()
    }

    private func synchronizeState() {
        updatePlayingState(player.timeControlStatus == .playing)
    }

    private func updatePlayingState(_ isPlaying: Bool) {
        if playing == isPlaying { return }
        playing = isPlaying
        onEvents?(isPlaying ? .playing : .pause)
    }

    @objc private func playerFinishPlaying(_ notification: Notification) {
        player.seek(to: .zero)
        stop()
        onEvents?(.ended)
    }

    private func onError(_ code: Int, _ message: String) {
        onEvents?(.error(NSError(domain: "audio_manager.macos", code: code, userInfo: ["msg": message])))
    }

    // MARK: - 监听

    private func observingProps() {
        observeStatus = player.currentItem?.observe(\.status) { [weak self] item, _ in
            guard let self = self else { return }
            if item.status == .readyToPlay {
                self.playing = self.isAuto
                if self.isAuto {
                    self.onEvents?(.playing)
                } else {
                    self.player.pause()
                }
                self.synchronizeState()
                self.onEvents?(.ready(self.duration))
            } else if item.status == .failed {
                let message = item.error?.localizedDescription ?? "player item failed"
                self.onError(-1, message)
            } else {
                self.playing = false
            }
        }

        observeLoaded = player.currentItem?.observe(\.loadedTimeRanges) { [weak self] item, _ in
            guard let self = self else { return }
            guard let timeRange = item.loadedTimeRanges.first as? CMTimeRange else { return }
            let total = item.duration.seconds
            let cached = timeRange.start.seconds + timeRange.duration.seconds
            self.buffer = total > 0 ? cached / total * 100 : 0
        }

        observeBufferEmpty = player.currentItem?.observe(\.isPlaybackBufferEmpty) { [weak self] _, _ in
            self?.buffering = true
        }

        observeCanPlay = player.currentItem?.observe(\.isPlaybackLikelyToKeepUp) { [weak self] _, _ in
            self?.buffering = false
        }

        observeTimeControl = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            self?.updatePlayingState(player.timeControlStatus == .playing)
        }
    }

    private func observingTimeChanges() {
        if let observer = timeObserver {
            timeObserver = nil
            player.removeTimeObserver(observer)
        }
        let time = CMTimeMake(value: 1, timescale: 1)
        timeObserver = player.addPeriodicTimeObserver(forInterval: time, queue: .main) { [weak self] _ in
            self?.updateLockInfo()
        }
    }

    private func updateLockInfo() {
        guard currentUrl != nil else { return }
        updatePlayingState(player.timeControlStatus == .playing)
        updateNowPlaying()
        guard playing else { return }
        let duration = CMTimeGetSeconds(player.currentItem?.duration ?? .zero)
        let currentTime = CMTimeGetSeconds(player.currentTime())
        if duration.isNaN || currentTime.isNaN { return }
        onEvents?(.timeupdate(currentTime, duration))
    }

    // MARK: - 系统集成（Now Playing / 媒体键 / 音量）

    private func setupRemoteCommands() {
        guard !remoteCommandsReady else { return }
        remoteCommandsReady = true
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)
        center.nextTrackCommand.removeTarget(nil)
        center.previousTrackCommand.removeTarget(nil)
        center.changePlaybackPositionCommand.removeTarget(nil)

        center.playCommand.addTarget { [weak self] _ in
            self?.play()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.playing ? self.pause() : self.play()
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.onEvents?(.next)
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.onEvents?(.previous)
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self?.seek(to: event.positionTime)
            return .success
        }
    }

    /// 刷新 Control Center 的 Now Playing 卡片（标题/艺术家/时长/进度/速率/封面）。
    private func updateNowPlaying() {
        guard currentUrl != nil else { return }
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = title ?? ""
        info[MPMediaItemPropertyArtist] = desc ?? ""
        info[MPMediaItemPropertyPlaybackDuration] = Double(duration) / 1000
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Double(currentTime) / 1000
        info[MPNowPlayingInfoPropertyPlaybackRate] = playing ? Double(player.rate) : 0
        if let cover = cover {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: cover.size) { _ in cover }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func clearNowPlaying() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    /// 读取系统默认输出设备音量（0~1）。CoreAudio 被标记废弃但实际仍可用；失败时回退到 AVPlayer.volume。
    private func systemVolume() -> Float {
        var defaultDevice = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMaster)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &defaultDevice
        ) == noErr, defaultDevice != kAudioObjectUnknown else {
            return player.volume
        }
        var volume: Float = 1
        size = UInt32(MemoryLayout<Float>.size)
        addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMaster)
        guard AudioObjectGetPropertyData(defaultDevice, &addr, 0, nil, &size, &volume) == noErr else {
            return player.volume
        }
        return volume
    }

    /// 尽力将系统音量设为 value；失败时静默，仍由 player.volume 生效。
    private func setSystemVolume(_ value: Float) {
        var defaultDevice = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMaster)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &defaultDevice
        ) == noErr, defaultDevice != kAudioObjectUnknown else {
            return
        }
        var volume = min(max(value, 0), 1)
        size = UInt32(MemoryLayout<Float>.size)
        addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMaster)
        AudioObjectSetPropertyData(defaultDevice, &addr, 0, nil, size, &volume)
    }

    /// 轮询系统音量并去重上报，使用户用系统音量键调节时 UI 同步。
    private func startVolumePoller() {
        guard volumeTimer == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.reportVolumeChange(self?.systemVolume() ?? 1)
        }
        RunLoop.main.add(timer, forMode: .common)
        volumeTimer = timer
    }

    private func reportVolumeChange(_ volume: Float) {
        guard volume != lastReportedVolume else { return }
        lastReportedVolume = volume
        onEvents?(.volumeChange(volume))
    }

    // MARK: - 封面

    private func loadCover(_ cover: String, isLocalCover: Bool, completion: @escaping (NSImage?) -> Void) {
        if isLocalCover {
            if let key = Self.instance.registrar?.lookupKey(forAsset: cover) {
                completion(NSImage(contentsOfFile: key))
            } else {
                completion(nil)
            }
            return
        }
        guard let url = URL(string: cover) else {
            completion(nil)
            return
        }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            DispatchQueue.main.async {
                completion(data.flatMap { NSImage(data: $0) })
            }
        }.resume()
    }
}
