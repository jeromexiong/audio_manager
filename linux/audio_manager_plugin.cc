// audio_manager 的 Linux 端实现。
// 基于 GStreamer gst_player,方法通道契约与 iOS/macOS 一致。
// 阶段 P3:播放核心 + 事件;P4 将接入 MPRIS(桌面媒体控制)。

#include "audio_manager/audio_manager_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gst/gst.h>
#include <gst/player/player.h>
#include <gtk/gtk.h>

#include <cstring>
#include <string>

#include "mpris.h"

#define AUDIO_MANAGER_PLUGIN(obj)                                        \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), audio_manager_plugin_get_type(),    \
                              AudioManagerPlugin))

struct _AudioManagerPlugin {
  GObject parent_instance;
  FlMethodChannel* channel;
  GstPlayer* player;
  gchar* title;
  gchar* desc;
  gchar* current_url;
  gboolean playing;
  gboolean is_auto;
  gint64 last_position_ms;
};

G_DEFINE_TYPE(AudioManagerPlugin, audio_manager_plugin, g_object_get_type())

// MARK: - 事件下发

static void send_event(AudioManagerPlugin* self, const gchar* method,
                       FlValue* args) {
  if (self->channel == nullptr) {
    return;
  }
  fl_method_channel_invoke_method(self->channel, method, args, nullptr,
                                  nullptr, nullptr);
}

// MARK: - GStreamer 信号

static void on_state_changed(GstPlayer* player, GstPlayerState state,
                             gpointer user_data) {
  AudioManagerPlugin* self = AUDIO_MANAGER_PLUGIN(user_data);
  mpris_update_state(state);
  if (state == GST_PLAYER_STATE_PLAYING) {
    if (!self->playing) {
      self->playing = TRUE;
      send_event(self, "playstatus", fl_value_new_bool(TRUE));
      send_event(self, "ready",
                 fl_value_new_int(gst_player_get_duration(player) / 1000000));
    }
  } else if (state == GST_PLAYER_STATE_PAUSED) {
    if (self->playing) {
      self->playing = FALSE;
      send_event(self, "playstatus", fl_value_new_bool(FALSE));
    }
  }
}

static void on_position_updated(GstPlayer* player, gint64 position,
                                gpointer user_data) {
  AudioManagerPlugin* self = AUDIO_MANAGER_PLUGIN(user_data);
  gint64 pos_ms = position / 1000000;
  if (pos_ms - self->last_position_ms < 1000) {
    return;  // 节流到约 1s 一次
  }
  self->last_position_ms = pos_ms;
  mpris_emit_position();
  g_autoptr(FlValue) map = fl_value_new_map();
  fl_value_set_string_take(map, "position", fl_value_new_int(pos_ms));
  fl_value_set_string_take(map, "duration",
                           fl_value_new_int(gst_player_get_duration(player) /
                                            1000000));
  send_event(self, "timeupdate", map);
}

static void on_duration_changed(GstPlayer* player, gint64 duration,
                                gpointer user_data) {
  AudioManagerPlugin* self = AUDIO_MANAGER_PLUGIN(user_data);
  mpris_emit_metadata();
  send_event(self, "ready", fl_value_new_int(duration / 1000000));
}

static void on_buffering_changed(GstPlayer* player, gdouble percent,
                                 gpointer user_data) {
  AudioManagerPlugin* self = AUDIO_MANAGER_PLUGIN(user_data);
  g_autoptr(FlValue) map = fl_value_new_map();
  fl_value_set_string_take(map, "buffering", fl_value_new_bool(percent < 100));
  fl_value_set_string_take(map, "buffer", fl_value_new_float(percent));
  send_event(self, "buffering", map);
}

static void on_player_error(GstPlayer* player, GError* error,
                            gpointer user_data) {
  AudioManagerPlugin* self = AUDIO_MANAGER_PLUGIN(user_data);
  send_event(self, "error", fl_value_new_string(error->message));
}

static void on_end_of_stream(GstPlayer* player, gpointer user_data) {
  AudioManagerPlugin* self = AUDIO_MANAGER_PLUGIN(user_data);
  self->playing = FALSE;
  send_event(self, "ended", fl_value_new_null());
}

// MPRIS 媒体键回调
static void on_mpris_next(gpointer user_data) {
  AudioManagerPlugin* self = AUDIO_MANAGER_PLUGIN(user_data);
  send_event(self, "next", fl_value_new_null());
}

static void on_mpris_previous(gpointer user_data) {
  AudioManagerPlugin* self = AUDIO_MANAGER_PLUGIN(user_data);
  send_event(self, "previous", fl_value_new_null());
}

// MARK: - 方法通道

static gchar* get_string(FlValue* args, const gchar* key,
                         const gchar* fallback = "") {
  FlValue* value = fl_value_lookup_string(args, key);
  if (value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_STRING) {
    return g_strdup(fl_value_get_string(value));
  }
  return g_strdup(fallback);
}

static gboolean get_bool(FlValue* args, const gchar* key,
                         gboolean fallback = FALSE) {
  FlValue* value = fl_value_lookup_string(args, key);
  if (value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_BOOL) {
    return fl_value_get_bool(value);
  }
  return fallback;
}

static gdouble get_double(FlValue* args, const gchar* key,
                          gdouble fallback = 0) {
  FlValue* value = fl_value_lookup_string(args, key);
  if (value != nullptr) {
    FlValueType type = fl_value_get_type(value);
    if (type == FL_VALUE_TYPE_FLOAT) {
      return fl_value_get_float(value);
    }
    if (type == FL_VALUE_TYPE_INT) {
      return fl_value_get_int(value);
    }
  }
  return fallback;
}

static FlMethodResponse* handle_method_call(AudioManagerPlugin* self,
                                            FlMethodCall* method_call) {
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);

  if (strcmp(method, "getPlatformVersion") == 0) {
    return FL_METHOD_RESPONSE(
        fl_method_success_response_new(fl_value_new_string("Linux")));
  }

  if (strcmp(method, "start") == 0) {
    g_autofree gchar* url = get_string(args, "url");
    if (url == nullptr || url[0] == '\0') {
      return FL_METHOD_RESPONSE(
          fl_method_error_response_new("bad_args", "url 为空", nullptr));
    }
    g_clear_pointer(&self->title, g_free);
    g_clear_pointer(&self->desc, g_free);
    g_clear_pointer(&self->current_url, g_free);
    self->title = get_string(args, "title");
    self->desc = get_string(args, "desc");
    self->is_auto = get_bool(args, "isAuto", TRUE);

    // 本地资产路径暂按 file:// 处理(P3 限制:真实 asset 解析待补)
    g_autofree gchar* uri = nullptr;
    if (get_bool(args, "isLocal", FALSE)) {
      uri = g_strdup_printf("file://%s", url);
    } else {
      uri = g_strdup(url);
    }
    gst_player_stop(self->player);
    gst_player_set_uri(self->player, uri);
    if (self->is_auto) {
      gst_player_play(self->player);
    }
    self->current_url = g_strdup(url);
    mpris_set_metadata(self->title, self->desc, url);
    return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  }

  if (strcmp(method, "playOrPause") == 0) {
    if (self->playing) {
      gst_player_pause(self->player);
    } else {
      gst_player_play(self->player);
    }
    return FL_METHOD_RESPONSE(fl_method_success_response_new(
        fl_value_new_bool(self->playing)));
  }
  if (strcmp(method, "play") == 0) {
    gst_player_play(self->player);
    return FL_METHOD_RESPONSE(fl_method_success_response_new(
        fl_value_new_bool(self->playing)));
  }
  if (strcmp(method, "pause") == 0) {
    gst_player_pause(self->player);
    return FL_METHOD_RESPONSE(fl_method_success_response_new(
        fl_value_new_bool(self->playing)));
  }
  if (strcmp(method, "stop") == 0) {
    gst_player_stop(self->player);
    self->playing = FALSE;
    g_clear_pointer(&self->current_url, g_free);
    mpris_emit_playback_status();
    send_event(self, "stop", fl_value_new_null());
    return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  }
  if (strcmp(method, "release") == 0) {
    gst_player_stop(self->player);
    self->playing = FALSE;
    g_clear_pointer(&self->current_url, g_free);
    mpris_emit_playback_status();
    return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  }
  if (strcmp(method, "updateLrc") == 0) {
    g_clear_pointer(&self->desc, g_free);
    self->desc = get_string(args, "lrc");
    mpris_set_metadata(self->title, self->desc, self->current_url);
    return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  }
  if (strcmp(method, "updateInfo") == 0) {
    g_clear_pointer(&self->title, g_free);
    g_clear_pointer(&self->desc, g_free);
    self->title = get_string(args, "title");
    self->desc = get_string(args, "desc");
    mpris_set_metadata(self->title, self->desc, self->current_url);
    return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  }
  if (strcmp(method, "seekTo") == 0) {
    gint64 ms = static_cast<gint64>(get_double(args, "position"));
    gst_player_seek(self->player, ms * 1000000);
    return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  }
  if (strcmp(method, "rate") == 0) {
    gst_player_set_rate(self->player, get_double(args, "rate"));
    return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  }
  if (strcmp(method, "setVolume") == 0) {
    gdouble volume = get_double(args, "value");
    volume = volume < 0 ? 0 : (volume > 1 ? 1 : volume);
    gst_player_set_volume(self->player, volume);
    mpris_emit_volume();
    send_event(self, "volumeChange", fl_value_new_float(volume));
    return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  }
  if (strcmp(method, "currentVolume") == 0) {
    return FL_METHOD_RESPONSE(fl_method_success_response_new(
        fl_value_new_float(gst_player_get_volume(self->player))));
  }
  if (strcmp(method, "getState") == 0) {
    g_autoptr(FlValue) state = fl_value_new_map();
    fl_value_set_string_take(state, "isPlaying",
                             fl_value_new_bool(self->playing));
    fl_value_set_string_take(
        state, "position",
        fl_value_new_int(gst_player_get_position(self->player) / 1000000));
    fl_value_set_string_take(
        state, "duration",
        fl_value_new_int(gst_player_get_duration(self->player) / 1000000));
    fl_value_set_string_take(state, "title",
                             fl_value_new_string(self->title));
    fl_value_set_string_take(state, "desc", fl_value_new_string(self->desc));
    fl_value_set_string_take(state, "url",
                             fl_value_new_string(self->current_url));
    return FL_METHOD_RESPONSE(fl_method_success_response_new(state));
  }

  return FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
}

static void method_call_cb(FlMethodChannel* channel, FlMethodCall* method_call,
                           gpointer user_data) {
  AudioManagerPlugin* self = AUDIO_MANAGER_PLUGIN(user_data);
  g_autoptr(FlMethodResponse) response = handle_method_call(self, method_call);
  fl_method_call_respond(method_call, response, nullptr);
}

// MARK: - 生命周期

static void audio_manager_plugin_dispose(GObject* object) {
  AudioManagerPlugin* self = AUDIO_MANAGER_PLUGIN(object);
  mpris_shutdown();
  if (self->player != nullptr) {
    gst_player_stop(self->player);
    gst_object_unref(self->player);
    self->player = nullptr;
  }
  g_clear_pointer(&self->title, g_free);
  g_clear_pointer(&self->desc, g_free);
  g_clear_pointer(&self->current_url, g_free);
  g_clear_object(&self->channel);
  G_OBJECT_CLASS(audio_manager_plugin_parent_class)->dispose(object);
}

static void audio_manager_plugin_class_init(AudioManagerPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = audio_manager_plugin_dispose;
}

static void audio_manager_plugin_init(AudioManagerPlugin* self) {
  self->player = gst_player_new(nullptr, nullptr);
  g_signal_connect(self->player, "state-changed",
                   G_CALLBACK(on_state_changed), self);
  g_signal_connect(self->player, "position-updated",
                   G_CALLBACK(on_position_updated), self);
  g_signal_connect(self->player, "duration-changed",
                   G_CALLBACK(on_duration_changed), self);
  g_signal_connect(self->player, "buffering-changed",
                   G_CALLBACK(on_buffering_changed), self);
  g_signal_connect(self->player, "error", G_CALLBACK(on_player_error), self);
  g_signal_connect(self->player, "end-of-stream",
                   G_CALLBACK(on_end_of_stream), self);
  self->playing = FALSE;
  self->is_auto = TRUE;
  self->last_position_ms = 0;

  MprisCallbacks callbacks;
  callbacks.player = self->player;
  callbacks.on_next = on_mpris_next;
  callbacks.on_previous = on_mpris_previous;
  callbacks.user_data = self;
  GError* mpris_error = nullptr;
  mpris_init(&callbacks, &mpris_error);
  g_clear_error(&mpris_error);
}

void audio_manager_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  AudioManagerPlugin* plugin = AUDIO_MANAGER_PLUGIN(
      g_object_new(audio_manager_plugin_get_type(), nullptr));

  FlMethodChannel* channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar), "audio_manager",
      FL_METHOD_CODEC(fl_standard_method_codec_new()));
  plugin->channel = FL_METHOD_CHANNEL(g_object_ref(channel));
  fl_method_channel_set_method_call_handler(channel, method_call_cb,
                                            g_object_ref(plugin),
                                            g_object_unref);
  g_object_unref(channel);
}
