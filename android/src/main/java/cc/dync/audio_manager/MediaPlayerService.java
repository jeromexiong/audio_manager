package cc.dync.audio_manager;

import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.BroadcastReceiver;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.ServiceConnection;
import android.content.pm.ServiceInfo;
import android.graphics.Bitmap;
import android.os.Binder;
import android.os.Build;
import android.os.IBinder;
import android.util.Log;
import android.view.View;
import android.widget.RemoteViews;

import androidx.annotation.Nullable;
import androidx.core.app.NotificationCompat;
import androidx.media.app.NotificationCompat.MediaStyle;
import android.support.v4.media.MediaMetadataCompat;
import android.support.v4.media.session.MediaSessionCompat;
import android.support.v4.media.session.PlaybackStateCompat;

import java.util.ArrayList;
import java.util.List;
import java.util.Objects;

public class MediaPlayerService extends Service {
    private static final String ACTION_NEXT = "MediaPlayerService_next";
    private static final String ACTION_PREVIOUS = "MediaPlayerService_previous";
    private static final String ACTION_PLAY_OR_PAUSE = "MediaPlayerService_playOrPause";
    private static final String ACTION_STOP = "MediaPlayerService_stop";
    private static final String NOTIFICATION_CHANNEL_ID = "MediaPlayerService_1100";

    @Nullable
    @Override
    public IBinder onBind(Intent intent) {
        return serviceBinder;
    }

    @Override
    public void onDestroy() {
        super.onDestroy();
        // 取消Notification
        if (notificationManager != null)
            notificationManager.cancel(NOTIFICATION_PENDING_ID);
        if (mediaSession != null) {
            mediaSession.setActive(false);
            mediaSession.release();
        }
        stopForeground(true);
        // 停止服务
        stopSelf();
    }

    @Override
    public void onCreate() {
        super.onCreate();
        setupNotification();
    }

    // 定义Binder类-当然也可以写成外部类
    private ServiceBinder serviceBinder = new ServiceBinder();

    public class ServiceBinder extends Binder {
        Service getService() {
            return MediaPlayerService.this;
        }
    }


    public enum Events {
        next, previous, playOrPause, stop, binder
    }

    public interface ServiceEvents {
        void onEvents(Events events, Object... args);
    }

    private static ServiceEvents serviceEvents;
    private static MediaPlayerService bindService;
    private static boolean isBindService = false;
    private static Context context;

    // 绑定服务 必须先调用 registerReceiver
    public static void bindService(ServiceEvents serviceEvents) {
        MediaPlayerService.serviceEvents = serviceEvents;

        if (!MediaPlayerService.isBindService) {
            Intent intent = new Intent(context, MediaPlayerService.class);
            /*
             * Service：Service的桥梁
             * ServiceConnection：处理链接状态
             * flags：BIND_AUTO_CREATE, BIND_DEBUG_UNBIND, BIND_NOT_FOREGROUND, BIND_ABOVE_CLIENT, BIND_ALLOW_OOM_MANAGEMENT, or BIND_WAIVE_PRIORITY.
             */
            context.bindService(intent, serviceConnection, Context.BIND_AUTO_CREATE);
        } else {
            if (serviceEvents != null) serviceEvents.onEvents(Events.binder, bindService);
        }

    }

    /// 通知事件处理，只能加载一次，否则会重复
    public static void registerReceiver(Context context) {
        MediaPlayerService.context = context;
        BroadcastReceiver playerReceiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context context, Intent intent) {
                Log.d("action", intent.getAction());
                switch (Objects.requireNonNull(intent.getAction())) {
                    case ACTION_NEXT:
                        serviceEvents.onEvents(Events.next);
                        break;
                    case ACTION_PREVIOUS:
                        serviceEvents.onEvents(Events.previous);
                        break;
                    case ACTION_PLAY_OR_PAUSE:// 暂停/播放
                        serviceEvents.onEvents(Events.playOrPause);
                        break;
                    case ACTION_STOP:
                        serviceEvents.onEvents(Events.stop);
                        break;
                }
            }
        };
        IntentFilter intentFilter = new IntentFilter();
        intentFilter.addAction(ACTION_NEXT);
        intentFilter.addAction(ACTION_PREVIOUS);
        intentFilter.addAction(ACTION_PLAY_OR_PAUSE);
        intentFilter.addAction(ACTION_STOP);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(playerReceiver, intentFilter, Context.RECEIVER_NOT_EXPORTED);
        } else {
            context.registerReceiver(playerReceiver, intentFilter);
        }
    }

    // 解除绑定
    public static void unBind(Context context) {
        if (isBindService) {
            bindService.onDestroy();
            context.unbindService(serviceConnection);
            isBindService = false;
        }
    }

    /**
     * serviceConnection是一个ServiceConnection类型的对象，它是一个接口，用于监听所绑定服务的状态
     */
    private static ServiceConnection serviceConnection = new ServiceConnection() {
        /**
         * 该方法用于处理与服务已连接时的情况。
         */
        @Override
        public void onServiceConnected(ComponentName name, IBinder service) {
            ServiceBinder binder = (ServiceBinder) service;
            bindService = (MediaPlayerService) binder.getService();
            isBindService = true;
            if (serviceEvents != null) serviceEvents.onEvents(Events.binder, bindService);
        }

        /**
         * 该方法用于处理与服务断开连接时的情况。
         */
        @Override
        public void onServiceDisconnected(ComponentName name) {
            bindService = null;
        }

    };

    //    private static final int DELETE_PENDING_REQUESTS = 1022;
    private static final int CONTENT_PENDING_REQUESTS = 1023;
    private static final int NEXT_PENDING_REQUESTS = 1024;
    private static final int PLAY_PENDING_REQUESTS = 1025;
    private static final int STOP_PENDING_REQUESTS = 1026;
    private static final int PREVIOUS_PENDING_REQUESTS = 1027;
    private static final int NOTIFICATION_PENDING_ID = 1;

    private NotificationManager notificationManager;
    private NotificationCompat.Builder builder;
    private RemoteViews views;
    private MediaSessionCompat mediaSession;
    private PendingIntent contentPendingIntent;
    private PendingIntent previousPendingIntent;
    private PendingIntent playPendingIntent;
    private PendingIntent nextPendingIntent;
    private PendingIntent stopPendingIntent;
    private String currentTitle = "";
    private String currentDesc = "";
    private boolean currentPlaying = false;
    private int notificationTitleMaxLines = 1;
    private boolean showPreviousButton = false;
    private boolean showNextButton = true;
    private boolean showStopButton = true;

    private void setupNotification() {
        Intent contentIntent = getPackageManager().getLaunchIntentForPackage(getPackageName());
        if (contentIntent == null) {
            contentIntent = new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER);
        }
        int contentFlags = pendingIntentFlags(PendingIntent.FLAG_UPDATE_CURRENT);
        contentPendingIntent = PendingIntent.getActivity(this, CONTENT_PENDING_REQUESTS, contentIntent, contentFlags);

        mediaSession = new MediaSessionCompat(this, "audio_manager");
        mediaSession.setFlags(MediaSessionCompat.FLAG_HANDLES_MEDIA_BUTTONS
                | MediaSessionCompat.FLAG_HANDLES_TRANSPORT_CONTROLS);
        mediaSession.setCallback(new MediaSessionCompat.Callback() {
            @Override
            public void onPlay() {
                dispatchAction(ACTION_PLAY_OR_PAUSE);
            }

            @Override
            public void onPause() {
                dispatchAction(ACTION_PLAY_OR_PAUSE);
            }

            @Override
            public void onSkipToNext() {
                dispatchAction(ACTION_NEXT);
            }

            @Override
            public void onSkipToPrevious() {
                dispatchAction(ACTION_PREVIOUS);
            }

            @Override
            public void onStop() {
                dispatchAction(ACTION_STOP);
            }
        });
        mediaSession.setActive(true);

        // 自定义布局
        views = new RemoteViews(getPackageName(), R.layout.layout_mediaplayer);
        int broadcastFlags = pendingIntentFlags(PendingIntent.FLAG_CANCEL_CURRENT);
        // 上一首
        Intent intentPrevious = new Intent(ACTION_PREVIOUS).setPackage(getPackageName());
        previousPendingIntent = PendingIntent.getBroadcast(this, PREVIOUS_PENDING_REQUESTS, intentPrevious, broadcastFlags);
        views.setOnClickPendingIntent(R.id.iv_previous, previousPendingIntent);

        // 下一首
        Intent intentNext = new Intent(ACTION_NEXT).setPackage(getPackageName());
        nextPendingIntent = PendingIntent.getBroadcast(this, NEXT_PENDING_REQUESTS, intentNext, broadcastFlags);
        views.setOnClickPendingIntent(R.id.iv_next, nextPendingIntent);

        // 暂停/播放
        Intent intentPlay = new Intent(ACTION_PLAY_OR_PAUSE).setPackage(getPackageName());
        playPendingIntent = PendingIntent.getBroadcast(this, PLAY_PENDING_REQUESTS, intentPlay, broadcastFlags);
        views.setOnClickPendingIntent(R.id.iv_pause, playPendingIntent);

        // 停止
        Intent intentStop = new Intent(ACTION_STOP).setPackage(getPackageName());
        stopPendingIntent = PendingIntent.getBroadcast(this, STOP_PENDING_REQUESTS, intentStop, broadcastFlags);
        views.setOnClickPendingIntent(R.id.iv_cancel, stopPendingIntent);

        // 获取NotificationManager实例
        notificationManager = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel notificationChannel;
            notificationChannel = new NotificationChannel(NOTIFICATION_CHANNEL_ID,
                    "Notification display", NotificationManager.IMPORTANCE_LOW);
            notificationManager.createNotificationChannel(notificationChannel);
        }

        applyNotificationConfig();
        refreshNotification(false, "", "");
        updateSessionState(false);

        // 前台服务
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_PENDING_ID, builder.build(), ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK);
        } else {
            startForeground(NOTIFICATION_PENDING_ID, builder.build());
        }
    }

    private void dispatchAction(String action) {
        Intent intent = new Intent(action).setPackage(getPackageName());
        sendBroadcast(intent);
    }

    private NotificationCompat.Builder buildNotification(boolean isPlaying, String title, String desc) {
        NotificationCompat.Action previousAction = new NotificationCompat.Action(
                android.R.drawable.ic_media_previous, "Previous", previousPendingIntent);
        NotificationCompat.Action playAction = new NotificationCompat.Action(
                isPlaying ? android.R.drawable.ic_media_pause : android.R.drawable.ic_media_play,
                isPlaying ? "Pause" : "Play", playPendingIntent);
        NotificationCompat.Action nextAction = new NotificationCompat.Action(
                android.R.drawable.ic_media_next, "Next", nextPendingIntent);
        NotificationCompat.Action stopAction = new NotificationCompat.Action(
                android.R.drawable.ic_menu_close_clear_cancel, "Stop", stopPendingIntent);

        MediaStyle mediaStyle = new MediaStyle()
                .setMediaSession(mediaSession.getSessionToken());
        List<NotificationCompat.Action> actions = new ArrayList<>();
        if (showPreviousButton) actions.add(previousAction);
        actions.add(playAction);
        if (showNextButton) actions.add(nextAction);
        if (showStopButton) actions.add(stopAction);
        if (showPreviousButton) {
            mediaStyle.setShowActionsInCompactView(0, 1, 2);
        } else {
            mediaStyle.setShowActionsInCompactView(0, 1);
        }

        NotificationCompat.Builder builder = new NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_launcher)
                .setContentTitle(title)
                .setContentText(desc)
                .setAutoCancel(false)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setContentIntent(contentPendingIntent)
                .setContent(views)
                .setStyle(mediaStyle);
        for (NotificationCompat.Action action : actions) {
            builder.addAction(action);
        }
        return builder;
    }

    void updateNotificationConfig(int titleMaxLines, boolean showPrevious,
                                  boolean showNext, boolean showStop) {
        notificationTitleMaxLines = Math.max(1, titleMaxLines);
        showPreviousButton = showPrevious;
        showNextButton = showNext;
        showStopButton = showStop;
        applyNotificationConfig();
        refreshNotification(currentPlaying, currentTitle, currentDesc);
    }

    private void applyNotificationConfig() {
        if (views == null) return;
        views.setInt(R.id.tv_name, "setMaxLines", notificationTitleMaxLines);
        views.setViewVisibility(R.id.iv_previous,
                showPreviousButton ? View.VISIBLE : View.GONE);
        views.setViewVisibility(R.id.iv_next,
                showNextButton ? View.VISIBLE : View.GONE);
        views.setViewVisibility(R.id.iv_cancel,
                showStopButton ? View.VISIBLE : View.GONE);
    }

    private int pendingIntentFlags(int baseFlags) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            return baseFlags | PendingIntent.FLAG_IMMUTABLE;
        }
        return baseFlags;
    }

    private void refreshNotification(boolean isPlaying, String title, String desc) {
        currentPlaying = isPlaying;
        currentTitle = title;
        currentDesc = desc;
        builder = buildNotification(isPlaying, title, desc);
        if (notificationManager != null) {
            notificationManager.notify(NOTIFICATION_PENDING_ID, builder.build());
        }
    }

    private void updateSessionState(boolean isPlaying) {
        if (mediaSession == null) return;
        MediaMetadataCompat metadata = new MediaMetadataCompat.Builder()
                .putString(MediaMetadataCompat.METADATA_KEY_TITLE, currentTitle)
                .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, currentDesc)
                .build();
        mediaSession.setMetadata(metadata);

        PlaybackStateCompat state = new PlaybackStateCompat.Builder()
                .setActions(PlaybackStateCompat.ACTION_PLAY
                        | PlaybackStateCompat.ACTION_PAUSE
                        | PlaybackStateCompat.ACTION_PLAY_PAUSE
                        | PlaybackStateCompat.ACTION_SKIP_TO_NEXT
                        | PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS
                        | PlaybackStateCompat.ACTION_STOP)
                .setState(isPlaying ? PlaybackStateCompat.STATE_PLAYING
                                : PlaybackStateCompat.STATE_PAUSED,
                        PlaybackStateCompat.PLAYBACK_POSITION_UNKNOWN, 1f)
                .build();
        mediaSession.setPlaybackState(state);
    }

    void updateCover(Bitmap bitmap) {
        views.setImageViewBitmap(R.id.image, bitmap);
        refreshNotification(currentPlaying, currentTitle, currentDesc);
    }

    void updateCover(int srcId) {
        views.setImageViewResource(R.id.image, srcId);
        refreshNotification(currentPlaying, currentTitle, currentDesc);
    }

    // 更新Notification
    void updateNotification(boolean isPlaying, String title, String desc) {
        if (views != null) {
            views.setTextViewText(R.id.tv_name, title);
            if (desc != null) views.setTextViewText(R.id.tv_author, desc);
            if (isPlaying) {
                views.setImageViewResource(R.id.iv_pause, android.R.drawable.ic_media_pause);
            } else {
                views.setImageViewResource(R.id.iv_pause, android.R.drawable.ic_media_play);
            }
        }

        refreshNotification(isPlaying, title, desc);
        updateSessionState(isPlaying);
    }
}
