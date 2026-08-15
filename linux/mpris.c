// MPRIS 桌面媒体控制实现。
// 在 session bus 注册 org.mpris.MediaPlayer2.audio_manager,暴露标准媒体接口,
// 使 GNOME/KDE 的媒体控制、媒体键与 Now Playing 卡片可操作播放器。

#include "mpris.h"

#include <gio/gio.h>
#include <gst/player/player.h>
#include <string.h>

#define MPRIS_BUS_NAME "org.mpris.MediaPlayer2.audio_manager"
#define MPRIS_OBJECT_PATH "/org/mpris/MediaPlayer2"

typedef struct {
  GstPlayer* player;
  void (*on_next)(gpointer);
  void (*on_previous)(gpointer);
  gpointer user_data;
  GDBusConnection* connection;
  guint name_owner_id;
  gchar* title;
  gchar* artist;
  gchar* url;
} MprisState;

static MprisState g_state = {0};

// MPRIS 接口 introspection
static const gchar introspection_xml[] =
    "<node>"
    "<interface name='org.freedesktop.DBus.Properties'>"
    "<method name='Get'><arg name='interface_name' type='s' direction='in'/>"
    "<arg name='property_name' type='s' direction='in'/>"
    "<arg name='value' type='v' direction='out'/></method>"
    "<method name='GetAll'><arg name='interface_name' type='s' direction='in'/>"
    "<arg name='properties' type='a{sv}' direction='out'/></method>"
    "<method name='Set'><arg name='interface_name' type='s' direction='in'/>"
    "<arg name='property_name' type='s' direction='in'/>"
    "<arg name='value' type='v' direction='in'/></method>"
    "<signal name='PropertiesChanged'>"
    "<arg name='interface_name' type='s'/>"
    "<arg name='changed_properties' type='a{sv}'/>"
    "<arg name='invalidated_properties' type='as'/></signal>"
    "</interface>"
    "<interface name='org.mpris.MediaPlayer2'>"
    "<method name='Raise'/><method name='Quit'/>"
    "<property name='CanQuit' type='b' access='read'/>"
    "<property name='CanRaise' type='b' access='read'/>"
    "<property name='HasTrackList' type='b' access='read'/>"
    "<property name='Identity' type='s' access='read'/>"
    "<property name='DesktopEntry' type='s' access='read'/>"
    "<property name='SupportedUriSchemes' type='as' access='read'/>"
    "<property name='SupportedMimeTypes' type='as' access='read'/>"
    "</interface>"
    "<interface name='org.mpris.MediaPlayer2.Player'>"
    "<method name='Next'/><method name='Previous'/>"
    "<method name='Pause'/><method name='PlayPause'/><method name='Stop'/>"
    "<method name='Play'/>"
    "<method name='Seek'><arg name='Offset' type='x' direction='in'/></method>"
    "<method name='SetPosition'>"
    "<arg name='TrackId' type='o' direction='in'/>"
    "<arg name='Position' type='x' direction='in'/></method>"
    "<method name='OpenUri'><arg name='Uri' type='s' direction='in'/></method>"
    "<property name='PlaybackStatus' type='s' access='read'/>"
    "<property name='LoopStatus' type='s' access='readwrite'/>"
    "<property name='Rate' type='d' access='readwrite'/>"
    "<property name='Shuffle' type='b' access='readwrite'/>"
    "<property name='Metadata' type='a{sv}' access='read'/>"
    "<property name='Volume' type='d' access='readwrite'/>"
    "<property name='Position' type='x' access='read'/>"
    "<property name='MinimumRate' type='d' access='read'/>"
    "<property name='MaximumRate' type='d' access='read'/>"
    "<property name='CanGoNext' type='b' access='read'/>"
    "<property name='CanGoPrevious' type='b' access='read'/>"
    "<property name='CanPlay' type='b' access='read'/>"
    "<property name='CanPause' type='b' access='read'/>"
    "<property name='CanSeek' type='b' access='read'/>"
    "<property name='CanControl' type='b' access='read'/>"
    "</interface>"
    "</node>";

static const gchar* playback_status(void) {
  GstPlayerState state = gst_player_get_state(g_state.player);
  if (state == GST_PLAYER_STATE_PLAYING) {
    return "Playing";
  }
  if (state == GST_PLAYER_STATE_PAUSED) {
    return "Paused";
  }
  return "Stopped";
}

// 构建 Metadata a{sv}
static GVariant* build_metadata(void) {
  GVariantBuilder builder;
  g_variant_builder_init(&builder, G_VARIANT_TYPE("a{sv}"));
  if (g_state.title != nullptr) {
    g_variant_builder_add(&builder, "{sv}", "xesam:title",
                          g_variant_new_string(g_state.title));
  }
  if (g_state.artist != nullptr) {
    GVariantBuilder artists;
    g_variant_builder_init(&artists, G_VARIANT_TYPE("as"));
    g_variant_builder_add(&artists, "s", g_state.artist);
    g_variant_builder_add(&builder, "{sv}", "xesam:artist",
                          g_variant_builder_end(&artists));
  }
  if (g_state.url != nullptr) {
    g_variant_builder_add(&builder, "{sv}", "xesam:url",
                          g_variant_new_string(g_state.url));
  }
  gint64 duration = gst_player_get_duration(g_state.player);
  if (duration > 0) {
    g_variant_builder_add(&builder, "{sv}", "mpris:length",
                          g_variant_new_int64(duration / 1000));  // µs
  }
  g_variant_builder_add(&builder, "{sv}", "mpris:trackid",
                        g_variant_new_object_path("/audio_manager/track/0"));
  return g_variant_builder_end(&builder);
}

// 属性取值
static GVariant* get_property(const gchar* interface_name,
                              const gchar* property_name) {
  if (strcmp(interface_name, "org.mpris.MediaPlayer2") == 0) {
    if (strcmp(property_name, "CanQuit") == 0) {
      return g_variant_new_boolean(FALSE);
    }
    if (strcmp(property_name, "CanRaise") == 0) {
      return g_variant_new_boolean(FALSE);
    }
    if (strcmp(property_name, "HasTrackList") == 0) {
      return g_variant_new_boolean(FALSE);
    }
    if (strcmp(property_name, "Identity") == 0) {
      return g_variant_new_string("audio_manager");
    }
    if (strcmp(property_name, "DesktopEntry") == 0) {
      return g_variant_new_string("audio_manager");
    }
    if (strcmp(property_name, "SupportedUriSchemes") == 0) {
      const gchar* schemes[] = {"http", "https", "file", nullptr};
      return g_variant_new_strv(schemes, -1);
    }
    if (strcmp(property_name, "SupportedMimeTypes") == 0) {
      return g_variant_new_strv(nullptr, 0);
    }
    return nullptr;
  }
  if (strcmp(interface_name, "org.mpris.MediaPlayer2.Player") == 0) {
    if (strcmp(property_name, "PlaybackStatus") == 0) {
      return g_variant_new_string(playback_status());
    }
    if (strcmp(property_name, "LoopStatus") == 0) {
      return g_variant_new_string("None");
    }
    if (strcmp(property_name, "Rate") == 0) {
      return g_variant_new_double(gst_player_get_rate(g_state.player));
    }
    if (strcmp(property_name, "Shuffle") == 0) {
      return g_variant_new_boolean(FALSE);
    }
    if (strcmp(property_name, "Metadata") == 0) {
      return build_metadata();
    }
    if (strcmp(property_name, "Volume") == 0) {
      return g_variant_new_double(gst_player_get_volume(g_state.player));
    }
    if (strcmp(property_name, "Position") == 0) {
      return g_variant_new_int64(gst_player_get_position(g_state.player) /
                                 1000);  // µs
    }
    if (strcmp(property_name, "MinimumRate") == 0) {
      return g_variant_new_double(0.5);
    }
    if (strcmp(property_name, "MaximumRate") == 0) {
      return g_variant_new_double(2.0);
    }
    if (strcmp(property_name, "CanGoNext") == 0 ||
        strcmp(property_name, "CanGoPrevious") == 0 ||
        strcmp(property_name, "CanPlay") == 0 ||
        strcmp(property_name, "CanPause") == 0 ||
        strcmp(property_name, "CanSeek") == 0 ||
        strcmp(property_name, "CanControl") == 0) {
      return g_variant_new_boolean(TRUE);
    }
    return nullptr;
  }
  return nullptr;
}

static void emit_properties_changed(const gchar* interface_name,
                                    GVariant* changed) {
  if (g_state.connection == nullptr) {
    return;
  }
  g_dbus_connection_emit_signal(
      g_state.connection, nullptr, MPRIS_OBJECT_PATH,
      "org.freedesktop.DBus.Properties", "PropertiesChanged",
      g_variant_new("(sa{sv}as)", interface_name, changed, nullptr), nullptr);
}

// MARK: - 方法

static void on_method_call(GDBusConnection* connection, const gchar* sender,
                           const gchar* object_path,
                           const gchar* interface_name,
                           const gchar* method_name, GVariant* parameters,
                           GDBusMethodInvocation* invocation,
                           gpointer user_data) {
  (void)connection;
  (void)sender;
  (void)object_path;
  (void)user_data;

  // org.freedesktop.DBus.Properties
  if (strcmp(interface_name, "org.freedesktop.DBus.Properties") == 0) {
    if (strcmp(method_name, "Get") == 0) {
      const gchar* iface = nullptr;
      const gchar* prop = nullptr;
      g_variant_get(parameters, "(&s&s)", &iface, &prop);
      GVariant* value = get_property(iface, prop);
      if (value == nullptr) {
        g_dbus_method_invocation_return_dbus_error(
            invocation, "org.freedesktop.DBus.Error.InvalidArgs",
            "Unknown property");
        return;
      }
      g_dbus_method_invocation_return_value(invocation,
                                            g_variant_new("(v)", value));
      return;
    }
    if (strcmp(method_name, "GetAll") == 0) {
      const gchar* iface = nullptr;
      g_variant_get(parameters, "(&s)", &iface);
      GVariantBuilder builder;
      g_variant_builder_init(&builder, G_VARIANT_TYPE("a{sv}"));
      const gchar* props[] = {
          "PlaybackStatus", "LoopStatus", "Rate",      "Shuffle",
          "Metadata",       "Volume",     "Position",  "MinimumRate",
          "MaximumRate",    "CanGoNext",  "CanGoPrevious", "CanPlay",
          "CanPause",       "CanSeek",    "CanControl"};
      for (gsize i = 0; i < G_N_ELEMENTS(props); i++) {
        GVariant* value = get_property(iface, props[i]);
        if (value != nullptr) {
          g_variant_builder_add(&builder, "{sv}", props[i], value);
        }
      }
      g_dbus_method_invocation_return_value(
          invocation, g_variant_new("(a{sv})", g_variant_builder_end(&builder)));
      return;
    }
    if (strcmp(method_name, "Set") == 0) {
      g_dbus_method_invocation_return_dbus_error(
          invocation, "org.freedesktop.DBus.Error.PropertyReadOnly",
          "Read-only");
      return;
    }
  }

  // org.mpris.MediaPlayer2
  if (strcmp(interface_name, "org.mpris.MediaPlayer2") == 0) {
    g_dbus_method_invocation_return_value(invocation, nullptr);
    return;
  }

  // org.mpris.MediaPlayer2.Player
  if (strcmp(interface_name, "org.mpris.MediaPlayer2.Player") == 0) {
    if (strcmp(method_name, "Play") == 0) {
      gst_player_play(g_state.player);
      mpris_emit_playback_status();
    } else if (strcmp(method_name, "Pause") == 0) {
      gst_player_pause(g_state.player);
      mpris_emit_playback_status();
    } else if (strcmp(method_name, "PlayPause") == 0) {
      GstPlayerState state = gst_player_get_state(g_state.player);
      if (state == GST_PLAYER_STATE_PLAYING) {
        gst_player_pause(g_state.player);
      } else {
        gst_player_play(g_state.player);
      }
      mpris_emit_playback_status();
    } else if (strcmp(method_name, "Stop") == 0) {
      gst_player_stop(g_state.player);
      mpris_emit_playback_status();
    } else if (strcmp(method_name, "Next") == 0) {
      if (g_state.on_next != nullptr) {
        g_state.on_next(g_state.user_data);
      }
    } else if (strcmp(method_name, "Previous") == 0) {
      if (g_state.on_previous != nullptr) {
        g_state.on_previous(g_state.user_data);
      }
    } else if (strcmp(method_name, "Seek") == 0) {
      gint64 offset = 0;
      g_variant_get(parameters, "(x)", &offset);
      gst_player_seek(g_state.player,
                      gst_player_get_position(g_state.player) + offset * 1000);
      mpris_emit_position();
    } else if (strcmp(method_name, "SetPosition") == 0) {
      gint64 position = 0;
      g_variant_get(parameters, "(ox)", nullptr, &position);
      gst_player_seek(g_state.player, position * 1000);
      mpris_emit_position();
    } else if (strcmp(method_name, "OpenUri") == 0) {
      const gchar* uri = nullptr;
      g_variant_get(parameters, "(&s)", &uri);
      gst_player_stop(g_state.player);
      gst_player_set_uri(g_state.player, uri);
      gst_player_play(g_state.player);
    } else {
      g_dbus_method_invocation_return_dbus_error(
          invocation, "org.freedesktop.DBus.Error.UnknownMethod",
          "Unknown method");
      return;
    }
    g_dbus_method_invocation_return_value(invocation, nullptr);
    return;
  }

  g_dbus_method_invocation_return_dbus_error(
      invocation, "org.freedesktop.DBus.Error.UnknownMethod", "Unknown method");
}

static GVariant* on_get_property(GDBusConnection* connection,
                                 const gchar* sender,
                                 const gchar* object_path,
                                 const gchar* interface_name,
                                 const gchar* property_name, GError** error,
                                 gpointer user_data) {
  (void)connection;
  (void)sender;
  (void)object_path;
  (void)user_data;
  (void)error;
  return get_property(interface_name, property_name);
}

static gboolean on_set_property(GDBusConnection* connection,
                                const gchar* sender,
                                const gchar* object_path,
                                const gchar* interface_name,
                                const gchar* property_name, GVariant* value,
                                GError** error, gpointer user_data) {
  (void)connection;
  (void)sender;
  (void)object_path;
  (void)interface_name;
  (void)property_name;
  (void)value;
  (void)user_data;
  (void)error;
  // 仅支持 Volume / Rate 写入,其余只读
  if (strcmp(property_name, "Volume") == 0) {
    gdouble volume = g_variant_get_double(value);
    gst_player_set_volume(g_state.player, volume);
    mpris_emit_volume();
    return TRUE;
  }
  if (strcmp(property_name, "Rate") == 0) {
    gst_player_set_rate(g_state.player, g_variant_get_double(value));
    return TRUE;
  }
  g_set_error(error, G_DBUS_ERROR, G_DBUS_ERROR_PROPERTY_READ_ONLY,
              "Read-only property");
  return FALSE;
}

static const GDBusInterfaceVTable vtable = {
    on_method_call, on_get_property, on_set_property, nullptr};

// MARK: - 公共接口

gboolean mpris_init(const MprisCallbacks* callbacks, GError** error) {
  g_state.player = callbacks->player;
  g_state.on_next = callbacks->on_next;
  g_state.on_previous = callbacks->on_previous;
  g_state.user_data = callbacks->user_data;

  GDBusNodeInfo* node =
      g_dbus_node_info_new_for_xml(introspection_xml, error);
  if (node == nullptr) {
    return FALSE;
  }

  g_state.connection = g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, error);
  if (g_state.connection == nullptr) {
    g_dbus_node_info_unref(node);
    return FALSE;
  }

  // register_object 一次只注册一个接口,循环注册 Properties / MediaPlayer2 / Player
  for (guint i = 0; node->interfaces[i] != nullptr; i++) {
    GError* register_error = nullptr;
    g_dbus_connection_register_object(g_state.connection, MPRIS_OBJECT_PATH,
                                      node->interfaces[i], &vtable, nullptr,
                                      nullptr, &register_error);
    g_clear_error(&register_error);
  }

  g_state.name_owner_id = g_bus_own_name_on_connection(
      g_state.connection, MPRIS_BUS_NAME, G_BUS_NAME_OWNER_FLAGS_NONE, nullptr,
      nullptr, nullptr, nullptr);
  g_dbus_node_info_unref(node);
  return TRUE;
}

void mpris_shutdown(void) {
  if (g_state.name_owner_id != 0) {
    g_bus_unown_name(g_state.name_owner_id);
    g_state.name_owner_id = 0;
  }
  g_clear_object(&g_state.connection);
  g_clear_pointer(&g_state.title, g_free);
  g_clear_pointer(&g_state.artist, g_free);
  g_clear_pointer(&g_state.url, g_free);
}

void mpris_set_metadata(const gchar* title, const gchar* artist,
                        const gchar* url) {
  g_clear_pointer(&g_state.title, g_free);
  g_clear_pointer(&g_state.artist, g_free);
  g_clear_pointer(&g_state.url, g_free);
  if (title != nullptr) {
    g_state.title = g_strdup(title);
  }
  if (artist != nullptr) {
    g_state.artist = g_strdup(artist);
  }
  if (url != nullptr) {
    g_state.url = g_strdup(url);
  }
  mpris_emit_metadata();
}

void mpris_emit_playback_status(void) {
  GVariantBuilder builder;
  g_variant_builder_init(&builder, G_VARIANT_TYPE("a{sv}"));
  g_variant_builder_add(&builder, "{sv}", "PlaybackStatus",
                        g_variant_new_string(playback_status()));
  emit_properties_changed("org.mpris.MediaPlayer2.Player",
                          g_variant_builder_end(&builder));
}

void mpris_emit_metadata(void) {
  GVariantBuilder builder;
  g_variant_builder_init(&builder, G_VARIANT_TYPE("a{sv}"));
  g_variant_builder_add(&builder, "{sv}", "Metadata", build_metadata());
  emit_properties_changed("org.mpris.MediaPlayer2.Player",
                          g_variant_builder_end(&builder));
}

void mpris_emit_position(void) {
  GVariantBuilder builder;
  g_variant_builder_init(&builder, G_VARIANT_TYPE("a{sv}"));
  g_variant_builder_add(&builder, "{sv}", "Position",
                        g_variant_new_int64(
                            gst_player_get_position(g_state.player) / 1000));
  emit_properties_changed("org.mpris.MediaPlayer2.Player",
                          g_variant_builder_end(&builder));
}

void mpris_emit_volume(void) {
  GVariantBuilder builder;
  g_variant_builder_init(&builder, G_VARIANT_TYPE("a{sv}"));
  g_variant_builder_add(&builder, "{sv}", "Volume",
                        g_variant_new_double(
                            gst_player_get_volume(g_state.player)));
  emit_properties_changed("org.mpris.MediaPlayer2.Player",
                          g_variant_builder_end(&builder));
}
