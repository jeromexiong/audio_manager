// audio_manager 的 Windows 端实现。
// 基于 Windows.Media.Playback.MediaPlayer,方法通道契约与 iOS/macOS 一致。
// 阶段 P1:播放核心 + 事件;P2 将接入 SMTC(系统媒体传输控制)。

#include "audio_manager_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <windows.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.Core.h>
#include <winrt/Windows.Media.Playback.h>
#include <winrt/Windows.Media.h>
#include <winrt/Windows.Storage.Streams.h>

#include <algorithm>
#include <chrono>
#include <memory>
#include <string>

namespace {

using winrt::Windows::Media::Core::MediaSource;
using winrt::Windows::Media::Playback::MediaPlayer;
using winrt::Windows::Media::Playback::MediaPlaybackState;
using winrt::Windows::Media::MediaPlaybackStatus;
using winrt::Windows::Media::MediaPlaybackType;
using winrt::Windows::Media::SystemMediaTransportControls;
using winrt::Windows::Media::SystemMediaTransportControlsButton;
using winrt::Windows::Media::SystemMediaTransportControlsTimelineProperties;
using winrt::Windows::Storage::Streams::RandomAccessStreamReference;

// WinRT apartment 一次性初始化(Flutter 宿主可能已初始化,重复调用会抛异常)。
void EnsureWinRtApartment() {
  static bool initialized = []() {
    try {
      winrt::init_apartment(winrt::apartment_type::multi_threaded);
    } catch (...) {
      // 已初始化则忽略
    }
    return true;
  }();
  (void)initialized;
}

// 忽略结果的 MethodResult,用于 native -> Dart 的事件下发。
class IgnoreResult : public flutter::MethodResult<flutter::EncodableValue> {
 public:
  void SuccessInternal(const flutter::EncodableValue* /*result*/) override {}
  void ErrorInternal(const std::string& /*error_code*/,
                     const std::string& /*error_message*/,
                     const flutter::EncodableValue* /*details*/) override {}
  void NotImplementedInternal() override {}
};

class AudioManagerPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar) {
    EnsureWinRtApartment();
    auto channel =
        std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
            registrar->messenger(), "audio_manager",
            &flutter::StandardMethodCodec::GetInstance());
    auto plugin = std::make_unique<AudioManagerPlugin>(registrar, std::move(channel));
    plugin->channel_->SetMethodCallHandler(
        [plugin_pointer = plugin.get()](const auto& call, auto result) {
          plugin_pointer->HandleMethodCall(call, std::move(result));
        });
    registrar->AddPlugin(std::move(plugin));
  }

  AudioManagerPlugin(
      flutter::PluginRegistrarWindows* registrar,
      std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel)
      : registrar_(registrar), channel_(std::move(channel)), player_(MediaPlayer()) {
    WirePlayerEvents();
    SetupSmtc();
  }

  virtual ~AudioManagerPlugin() {
    try {
      player_.Pause();
      player_.Source(nullptr);
    } catch (...) {
    }
  }

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    const std::string& method = method_call.method_name();
    const auto* args =
        std::get_if<flutter::EncodableMap>(method_call.arguments());

    if (method == "getPlatformVersion") {
      result->Success(flutter::EncodableValue(std::string("Windows")));
      return;
    }

    if (method == "start") {
      if (!args) {
        result->Error("bad_args", "start 需要参数");
        return;
      }
      auto url = GetString(*args, "url");
      if (url.empty()) {
        result->Error("bad_args", "url 为空");
        return;
      }
      title_ = GetString(*args, "title");
      desc_ = GetString(*args, "desc");
      cover_url_ = GetString(*args, "cover");
      bool is_local = GetBool(*args, "isLocal");
      bool is_auto = GetBool(*args, "isAuto", true);
      is_auto_ = is_auto;
      Start(url, is_local);
      if (is_auto_) {
        player_.Play();
      }
      UpdateSmtcMetadata();
      UpdateSmtcStatus(is_auto_ ? MediaPlaybackStatus::Playing
                                : MediaPlaybackStatus::Paused);
      UpdateSmtcTimeline();
      result->Success();
      return;
    }

    if (method == "playOrPause") {
      if (playing_) {
        player_.Pause();
      } else {
        player_.Play();
      }
      UpdateSmtcStatus(playing_ ? MediaPlaybackStatus::Playing
                                : MediaPlaybackStatus::Paused);
      UpdateSmtcTimeline();
      result->Success(flutter::EncodableValue(playing_));
      return;
    }
    if (method == "play") {
      player_.Play();
      UpdateSmtcStatus(MediaPlaybackStatus::Playing);
      UpdateSmtcTimeline();
      result->Success(flutter::EncodableValue(playing_));
      return;
    }
    if (method == "pause") {
      player_.Pause();
      UpdateSmtcStatus(MediaPlaybackStatus::Paused);
      UpdateSmtcTimeline();
      result->Success(flutter::EncodableValue(playing_));
      return;
    }
    if (method == "stop") {
      Stop();
      result->Success();
      return;
    }
    if (method == "release") {
      Stop();
      player_.Source(nullptr);
      result->Success();
      return;
    }
    if (method == "updateLrc") {
      desc_ = GetString(*args, "lrc");
      UpdateSmtcMetadata();
      result->Success();
      return;
    }
    if (method == "updateInfo") {
      if (args) {
        title_ = GetString(*args, "title");
        desc_ = GetString(*args, "desc");
        cover_url_ = GetString(*args, "cover");
      }
      UpdateSmtcMetadata();
      result->Success();
      return;
    }
    if (method == "seekTo") {
      if (args) {
        double ms = GetDouble(*args, "position");
        player_.PlaybackSession().Position(
            winrt::Windows::Foundation::TimeSpan(
                std::chrono::milliseconds(static_cast<long long>(ms))));
        UpdateSmtcTimeline();
      }
      result->Success();
      return;
    }
    if (method == "rate") {
      if (args) {
        double rate = GetDouble(*args, "rate");
        player_.PlaybackRate(rate);
      }
      result->Success();
      return;
    }
    if (method == "setVolume") {
      if (args) {
        double volume = GetDouble(*args, "value");
        player_.Volume(volume < 0 ? 0 : (volume > 1 ? 1 : volume));
        SendEvent("volumeChange", flutter::EncodableValue(player_.Volume()));
      }
      result->Success();
      return;
    }
    if (method == "currentVolume") {
      result->Success(flutter::EncodableValue(player_.Volume()));
      return;
    }
    if (method == "getState") {
      flutter::EncodableMap state;
      state[flutter::EncodableValue("isPlaying")] =
          flutter::EncodableValue(playing_);
      state[flutter::EncodableValue("position")] =
          flutter::EncodableValue(static_cast<int>(PositionMs()));
      state[flutter::EncodableValue("duration")] =
          flutter::EncodableValue(static_cast<int>(DurationMs()));
      state[flutter::EncodableValue("title")] =
          flutter::EncodableValue(title_);
      state[flutter::EncodableValue("desc")] =
          flutter::EncodableValue(desc_);
      state[flutter::EncodableValue("url")] =
          flutter::EncodableValue(current_url_);
      result->Success(flutter::EncodableValue(state));
      return;
    }

    result->NotImplemented();
  }

  // MARK: - 播放核心

  void Start(const std::string& url, bool is_local) {
    Stop();
    try {
      if (is_local) {
        // Flutter Windows 未提供插件侧资产 API,手动从 exe 目录解析
        std::string asset_path = ResolveAssetPath(url);
        if (asset_path.empty()) {
          SendEvent("error", flutter::EncodableValue("找不到资源 " + url));
          return;
        }
        std::string file_uri = "file:///" + asset_path;
        std::replace(file_uri.begin(), file_uri.end(), '\\', '/');
        player_.Source(MediaSource::CreateFromUri(
            winrt::Windows::Foundation::Uri(winrt::to_hstring(file_uri))));
      } else {
        player_.Source(MediaSource::CreateFromUri(
            winrt::Windows::Foundation::Uri(winrt::to_hstring(url))));
      }
      current_url_ = url;
    } catch (...) {
      SendEvent("error", flutter::EncodableValue("无法打开链接"));
    }
  }

  void Stop() {
    try {
      if (player_.Source() != nullptr) {
        player_.Pause();
        player_.Source(nullptr);
      }
    } catch (...) {
    }
    playing_ = false;
    current_url_.clear();
    UpdateSmtcStatus(MediaPlaybackStatus::Stopped);
    SendEvent("stop", flutter::EncodableValue());
  }

  // Flutter Windows 插件无资产 API;资产位于 <exe_dir>\data\flutter_assets\<asset>
  static std::string ResolveAssetPath(const std::string& asset) {
    wchar_t exe[MAX_PATH] = {0};
    if (GetModuleFileNameW(nullptr, exe, MAX_PATH) == 0) {
      return "";
    }
    std::wstring wpath(exe);
    auto slash = wpath.find_last_of(L"\\/");
    if (slash == std::wstring::npos) {
      return "";
    }
    std::wstring full =
        wpath.substr(0, slash) + L"\\data\\flutter_assets\\" +
        winrt::to_hstring(asset).c_str();
    return winrt::to_string(full);
  }

  double PositionMs() const {
    try {
      auto span = player_.PlaybackSession().Position();
      return static_cast<double>(
          std::chrono::duration_cast<std::chrono::milliseconds>(span).count());
    } catch (...) {
      return 0;
    }
  }

  double DurationMs() const {
    try {
      auto span = player_.PlaybackSession().NaturalDuration();
      if (span == std::chrono::milliseconds(0)) {
        return 0;
      }
      return static_cast<double>(
          std::chrono::duration_cast<std::chrono::milliseconds>(span).count());
    } catch (...) {
      return 0;
    }
  }

  // MARK: - 事件

  void WirePlayerEvents() {
    auto session = player_.PlaybackSession();

    session.PlaybackStateChanged(
        [this](const auto& /*sender*/, const auto& /*args*/) {
          auto state = player_.PlaybackSession().PlaybackState();
          if (state == MediaPlaybackState::Playing) {
            bool was = playing_;
            playing_ = true;
            if (!was) {
              SendEvent("playstatus", flutter::EncodableValue(true));
              SendEvent("ready",
                        flutter::EncodableValue(static_cast<int>(DurationMs())));
            }
          } else if (state == MediaPlaybackState::Paused) {
            bool was = playing_;
            playing_ = false;
            if (was) {
              SendEvent("playstatus", flutter::EncodableValue(false));
            }
          }
        });

    session.BufferingStarted([this](const auto&, const auto&) {
      buffering_ = true;
      SendBuffer();
    });
    session.BufferingEnded([this](const auto&, const auto&) {
      buffering_ = false;
      SendBuffer();
    });

    session.NaturalDurationChanged([this](const auto&, const auto&) {
      SendEvent("ready",
                flutter::EncodableValue(static_cast<int>(DurationMs())));
    });

    session.PositionChanged([this](const auto&, const auto&) {
      // 节流到约 1s 一次
      auto now = GetTickCount64();
      if (now - last_timeupdate_ < 1000) {
        return;
      }
      last_timeupdate_ = now;
      flutter::EncodableMap map;
      map[flutter::EncodableValue("position")] =
          flutter::EncodableValue(static_cast<int>(PositionMs()));
      map[flutter::EncodableValue("duration")] =
          flutter::EncodableValue(static_cast<int>(DurationMs()));
      SendEvent("timeupdate", flutter::EncodableValue(map));
      UpdateSmtcTimeline();
    });

    player_.MediaEnded([this](const auto&, const auto&) {
      playing_ = false;
      UpdateSmtcStatus(MediaPlaybackStatus::Stopped);
      SendEvent("ended", flutter::EncodableValue());
    });

    player_.MediaFailed([this](const auto&, const auto& args) {
      auto message = args.ErrorMessage().c_str();
      SendEvent("error", flutter::EncodableValue(std::string(message)));
    });
  }

  // MARK: - SMTC(系统媒体传输控制)

  void SetupSmtc() {
    try {
      smtc_ = player_.SystemMediaTransportControls();
      smtc_.IsEnabled(true);
      smtc_.IsPlayEnabled(true);
      smtc_.IsPauseEnabled(true);
      smtc_.IsNextEnabled(true);
      smtc_.IsPreviousEnabled(true);
      smtc_.IsStopEnabled(true);

      smtc_.ButtonPressed([this](const auto&, const auto& args) {
        auto button = args.Button();
        switch (button) {
          case SystemMediaTransportControlsButton::Play:
            player_.Play();
            break;
          case SystemMediaTransportControlsButton::Pause:
            player_.Pause();
            break;
          case SystemMediaTransportControlsButton::Next:
            SendEvent("next", flutter::EncodableValue());
            break;
          case SystemMediaTransportControlsButton::Previous:
            SendEvent("previous", flutter::EncodableValue());
            break;
          case SystemMediaTransportControlsButton::Stop:
            Stop();
            break;
          default:
            break;
        }
      });

      smtc_.PlaybackPositionChangeRequested(
          [this](const auto&, const auto& args) {
            try {
              player_.PlaybackSession().Position(
                  args.RequestedPlaybackPosition());
            } catch (...) {
            }
          });
    } catch (...) {
    }
  }

  void UpdateSmtcMetadata() {
    try {
      auto updater = smtc_.DisplayUpdater();
      updater.Type(MediaPlaybackType::Music);
      auto props = updater.MusicProperties();
      props.Title(winrt::to_hstring(title_));
      props.Artist(winrt::to_hstring(desc_));
      if (!cover_url_.empty()) {
        try {
          updater.Thumbnail(RandomAccessStreamReference::CreateFromUri(
              winrt::Windows::Foundation::Uri(
                  winrt::to_hstring(cover_url_))));
        } catch (...) {
        }
      }
      updater.Update();
    } catch (...) {
    }
  }

  void UpdateSmtcStatus(MediaPlaybackStatus status) {
    try {
      smtc_.PlaybackStatus(status);
    } catch (...) {
    }
  }

  void UpdateSmtcTimeline() {
    try {
      auto timeline = SystemMediaTransportControlsTimelineProperties();
      long long end = static_cast<long long>(DurationMs());
      long long pos = static_cast<long long>(PositionMs());
      timeline.StartTime(winrt::Windows::Foundation::TimeSpan(
          std::chrono::milliseconds(0)));
      timeline.EndTime(winrt::Windows::Foundation::TimeSpan(
          std::chrono::milliseconds(end)));
      timeline.MinSeekTime(winrt::Windows::Foundation::TimeSpan(
          std::chrono::milliseconds(0)));
      timeline.MaxSeekTime(winrt::Windows::Foundation::TimeSpan(
          std::chrono::milliseconds(end)));
      timeline.Position(winrt::Windows::Foundation::TimeSpan(
          std::chrono::milliseconds(pos)));
      smtc_.UpdateTimelineProperties(timeline);
    } catch (...) {
    }
  }

  void SendBuffer() {
    flutter::EncodableMap map;
    map[flutter::EncodableValue("buffering")] =
        flutter::EncodableValue(buffering_);
    map[flutter::EncodableValue("buffer")] = flutter::EncodableValue(
        player_.PlaybackSession().BufferingProgress());
    SendEvent("buffering", flutter::EncodableValue(map));
  }

  void SendEvent(const std::string& method, flutter::EncodableValue args) {
    if (!channel_) {
      return;
    }
    channel_->InvokeMethod(method, std::make_unique<flutter::EncodableValue>(std::move(args)),
                           std::make_unique<IgnoreResult>());
  }

  // MARK: - 参数提取

  static std::string GetString(const flutter::EncodableMap& args,
                               const std::string& key,
                               const std::string& fallback = "") {
    auto it = args.find(flutter::EncodableValue(key));
    if (it != args.end() && std::holds_alternative<std::string>(it->second)) {
      return std::get<std::string>(it->second);
    }
    return fallback;
  }

  static bool GetBool(const flutter::EncodableMap& args,
                      const std::string& key,
                      bool fallback = false) {
    auto it = args.find(flutter::EncodableValue(key));
    if (it != args.end() && std::holds_alternative<bool>(it->second)) {
      return std::get<bool>(it->second);
    }
    return fallback;
  }

  static double GetDouble(const flutter::EncodableMap& args,
                          const std::string& key,
                          double fallback = 0) {
    auto it = args.find(flutter::EncodableValue(key));
    if (it != args.end()) {
      const auto& v = it->second;
      if (std::holds_alternative<double>(v)) {
        return std::get<double>(v);
      }
      if (std::holds_alternative<int>(v)) {
        return static_cast<double>(std::get<int>(v));
      }
      if (std::holds_alternative<int64_t>(v)) {
        return static_cast<double>(std::get<int64_t>(v));
      }
    }
    return fallback;
  }

  flutter::PluginRegistrarWindows* registrar_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  MediaPlayer player_;
  SystemMediaTransportControls smtc_{nullptr};
  std::string title_;
  std::string desc_;
  std::string cover_url_;
  std::string current_url_;
  bool is_auto_ = true;
  bool playing_ = false;
  bool buffering_ = false;
  uint64_t last_timeupdate_ = 0;
};

}  // namespace

void AudioManagerPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  AudioManagerPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
