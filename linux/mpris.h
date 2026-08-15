#ifndef AUDIO_MANAGER_MPRIS_H_
#define AUDIO_MANAGER_MPRIS_H_

#include <glib-object.h>
#include <gst/player/player.h>

G_BEGIN_DECLS

// MPRIS 桌面媒体控制(org.mpris.MediaPlayer2.audio_manager)。
// 由插件在 init 时调用 mpris_init 注册 D-Bus 服务,状态变化时调用 emit 系列上报。

typedef struct {
  GstPlayer* player;
  void (*on_next)(gpointer user_data);
  void (*on_previous)(gpointer user_data);
  gpointer user_data;
} MprisCallbacks;

gboolean mpris_init(const MprisCallbacks* callbacks, GError** error);

void mpris_shutdown(void);

// 更新元数据(title/artist/当前 URL),内部会拷贝字符串。
void mpris_set_metadata(const gchar* title, const gchar* artist,
                        const gchar* url);

// 属性变化时向 D-Bus 广播 PropertiesChanged。
void mpris_emit_playback_status(void);
void mpris_emit_metadata(void);
void mpris_emit_position(void);
void mpris_emit_volume(void);

G_END_DECLS

#endif  // AUDIO_MANAGER_MPRIS_H_
