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
import android.content.res.AssetManager;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.os.Binder;
import android.os.Build;
import android.os.IBinder;
import android.util.Log;
import android.widget.RemoteViews;

import androidx.annotation.Nullable;
import androidx.core.app.NotificationCompat;

import java.io.IOException;
import java.io.InputStream;
import java.net.URL;
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
    private static int smallIcon;

    // 绑定服务
    public static void bindService(Context context, ServiceEvents serviceEvents) {
        MediaPlayerService.context = context;
        MediaPlayerService.serviceEvents = serviceEvents;

        if (!MediaPlayerService.isBindService) {
            Intent intent = new Intent(context, MediaPlayerService.class);
            /*
             * Service：Service的桥梁
             * ServiceConnection：处理链接状态
             * flags：BIND_AUTO_CREATE, BIND_DEBUG_UNBIND, BIND_NOT_FOREGROUND, BIND_ABOVE_CLIENT, BIND_ALLOW_OOM_MANAGEMENT, or BIND_WAIVE_PRIORITY.
             */
            context.bindService(intent, serviceConnection, Context.BIND_AUTO_CREATE);
        }

        // 注册广播
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
        context.registerReceiver(playerReceiver, intentFilter);
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

    public static void setSmallIcon(int icon) {
        smallIcon = icon;
    }


    //    private static final int DELETE_PENDING_REQUESTS = 1022;
    private static final int CONTENT_PENDING_REQUESTS = 1023;
    private static final int NEXT_PENDING_REQUESTS = 1024;
    private static final int PLAY_PENDING_REQUESTS = 1025;
    private static final int STOP_PENDING_REQUESTS = 1026;
    private static final int NOTIFICATION_PENDING_ID = 1;

    private NotificationManager notificationManager;
    private NotificationCompat.Builder builder;
    private RemoteViews views;

    private void setupNotification() {
        // 设置点击通知结果
        Intent intent = new Intent(this, MediaPlayerService.context.getClass());
        PendingIntent contentPendingIntent = PendingIntent.getActivity(this, CONTENT_PENDING_REQUESTS, intent, PendingIntent.FLAG_UPDATE_CURRENT);
//        Intent delIntent = new Intent(this, MediaPlayerService.class);
//        PendingIntent delPendingIntent = PendingIntent.getService(this, DELETE_PENDING_REQUESTS, delIntent, PendingIntent.FLAG_UPDATE_CURRENT);

        // 自定义布局
        views = new RemoteViews(getPackageName(), R.layout.layout_mediaplayer);
        // 下一首
        Intent intentNext = new Intent(ACTION_NEXT);
        PendingIntent nextPendingIntent = PendingIntent.getBroadcast(this, NEXT_PENDING_REQUESTS, intentNext, PendingIntent.FLAG_CANCEL_CURRENT);
        views.setOnClickPendingIntent(R.id.tv_next, nextPendingIntent);

        // 暂停/播放
        Intent intentPlay = new Intent(ACTION_PLAY_OR_PAUSE);
        PendingIntent playPendingIntent = PendingIntent.getBroadcast(this, PLAY_PENDING_REQUESTS, intentPlay, PendingIntent.FLAG_CANCEL_CURRENT);
        views.setOnClickPendingIntent(R.id.tv_pause, playPendingIntent);

        // 停止
        Intent intentStop = new Intent(ACTION_STOP);
        PendingIntent stopPendingIntent = PendingIntent.getBroadcast(this, STOP_PENDING_REQUESTS, intentStop, PendingIntent.FLAG_CANCEL_CURRENT);
        views.setOnClickPendingIntent(R.id.tv_cancel, stopPendingIntent);

        builder = new NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
                // 设置状态栏小图标
                .setSmallIcon(MediaPlayerService.smallIcon != 0 ? smallIcon : R.drawable.ic_launcher)
                // 设置标题
                .setContentTitle("AudioManager")
                // 设置内容
                .setContentText("内容")
                // 点击通知后自动清除
                .setAutoCancel(false)
                // 设置点击通知效果
                .setContentIntent(contentPendingIntent)
                // 设置删除时候出发的动作
//                .setDeleteIntent(delPendingIntent)
                // 自定义视图
                .setContent(views);

        // 获取NotificationManager实例
        notificationManager = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel notificationChannel;
            notificationChannel = new NotificationChannel(NOTIFICATION_CHANNEL_ID,
                    "后台录轨迹的通知", NotificationManager.IMPORTANCE_LOW);
            notificationManager.createNotificationChannel(notificationChannel);
        }

        // 前台服务
        startForeground(NOTIFICATION_PENDING_ID, builder.build());
    }

    void updateCover(String url) {
        if (url.contains("http")) {
            new Thread(() -> {
                try {
                    URL picUrl = new URL(url);
                    Bitmap bitmap = BitmapFactory.decodeStream(picUrl.openStream());
                    views.setImageViewBitmap(R.id.image, bitmap);
                } catch (Exception e) {
                    e.printStackTrace();
                }
            }).start();
            return;
        }
        AssetManager am = context.getAssets();
        try {
            InputStream inputStream = am.open(url);
            views.setImageViewBitmap(R.id.image, BitmapFactory.decodeStream(inputStream));
        } catch (IOException e) {
            e.printStackTrace();
        }
    }

    void updateCover(int srcId) {
        views.setImageViewResource(R.id.image, srcId);
    }

    // 更新Notification
    void updateNotification(boolean isPlaying, String title, String desc) {
        if (views != null) {
            views.setTextViewText(R.id.tv_name, title);
            views.setTextViewText(R.id.tv_author, desc);
            if (isPlaying) {
                views.setTextViewText(R.id.tv_pause, "暂停");
            } else {
                views.setTextViewText(R.id.tv_pause, "播放");
            }
        }

        // 刷新notification
        notificationManager.notify(NOTIFICATION_PENDING_ID, builder.build());
    }
}
