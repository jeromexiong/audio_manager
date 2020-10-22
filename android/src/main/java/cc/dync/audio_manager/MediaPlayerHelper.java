package cc.dync.audio_manager;

import android.content.Context;
import android.content.res.AssetFileDescriptor;
import android.content.res.AssetManager;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.media.MediaDataSource;
import android.media.MediaPlayer;
import android.net.wifi.WifiManager;
import android.os.Build;
import android.os.Handler;
import android.os.Message;
import android.os.PowerManager;
import android.util.Log;
import android.view.SurfaceHolder;
import android.view.SurfaceView;

import androidx.annotation.RequiresApi;

import java.io.BufferedInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.Objects;

/**
 * 多媒体播放
 */
public class MediaPlayerHelper {
    private static final String TAG = MediaPlayerHelper.class.getSimpleName();

    private String[] ext = {".3gp", ".3GP", ".mp4", ".MP4", ".mp3", ".ogg", ".OGG", ".MP3", ".wav", ".WAV"};//定义我们支持的文件格式
    private Holder uiHolder;//UI的容器
    private Context context;
    private MediaInfo mediaInfo = new MediaInfo("title", null);
    private static MediaPlayerHelper instance;
    private int delaySecondTime = 1000;//进度回调间隔
    private boolean isHolderCreate = false;//SurfaceHolder是否准备好了
    private WifiManager.WifiLock wifiLock;
    private String curUrl = "";//当前初始化url
    private boolean isPrepare = false;

    static class MediaInfo {
        String title;
        /**
         * 资源路径
         * if isAsset: true （url 名字,带后缀，比如:text.mp3
         * else url is file path or network path
         */
        String url;
        /**
         * 资源描述
         */
        String desc;
        /**
         * 封面图地址
         */
        String cover;
        /**
         * 是否是通过Assets文件名播放Assets目录下的音频
         */
        boolean isAsset = false;
        /**
         * 是否是视频播放
         */
        boolean isVideo = false;
        /**
         * 是否是自动播放
         */
        boolean isAuto = true;

        MediaInfo(String title, String url) {
            this.title = title;
            this.url = url;
        }
    }

    /**
     * 状态枚举
     */
    public enum CallBackState {
        buffering("MediaPlayer--更新流媒体缓存状态"),
        next("next"),
        previous("previous"),
        playOrPause("playOrPause"),
        stop("stop"),
        ended("播放结束"),
        error("播放错误"),
        FORMAT_NOT_SUPPORT("音视频格式可能不支持"),
        INFO("播放开始"),
        ready("准备完毕"),
        progress("播放进度回调"),
        seekComplete("拖动完成"),
        VIDEO_SIZE_CHANGE("读取视频大小"),
        SURFACE_CREATE("SurfaceView--Holder创建"),
        SURFACE_DESTROY("SurfaceView--Holder销毁"),
        SURFACE_CHANGE("SurfaceView--Holder改变"),
        SURFACE_NULL("SurfaceView--还没初始化");

        private final String state;

        CallBackState(String state) {
            this.state = state;
        }

        public String toString() {
            return this.state;
        }
    }

    /**
     * 获得静态类
     *
     * @param context 引用
     * @return 实例
     */
    public static synchronized MediaPlayerHelper getInstance(Context context) {
        if (instance == null) {
            instance = new MediaPlayerHelper(context);
        }
        return instance;
    }

    /**
     * 获得流媒体对象
     *
     * @return 实例
     */
    public MediaPlayer getMediaPlayer() {
        return uiHolder.player;
    }

    /**
     * 设置播放进度时间间隔
     *
     * @param time 时间
     * @return 实例
     */
    public MediaPlayerHelper setProgressInterval(int time) {
        delaySecondTime = time;
        return instance;
    }

    private MediaPlayerService service;

    /**
     * 绑定服务
     *
     * @return 实例
     */
    private MediaPlayerHelper bindService() {
        MediaPlayerService.bindService((events, args) -> {
            switch (events) {
                case binder:
                    service = (MediaPlayerService) args[0];
                    service.updateNotification(isPlaying(), mediaInfo.title, mediaInfo.desc);
                    if (mediaInfo.cover != null) {
                        updateCover(mediaInfo.cover);
                    }
                    break;
                case playOrPause:
                    playOrPause();
                    break;
                case next:
                    onStatusCallbackNext(CallBackState.next);
                    break;
                case previous:
                    onStatusCallbackNext(CallBackState.previous);
                    break;
                case stop:
                    release();
                    break;
            }
        });

        keepAlive();
        return instance;
    }

    /**
     * 更新锁屏信息 必须在 bindService 之后调用
     */
    MediaPlayerHelper updateLrc(String desc) {
        if (service == null) return instance;
        service.updateNotification(isPlaying(), mediaInfo.title, desc);
        return instance;
    }

    MediaPlayerHelper updateCover(String url) {
        if (service == null) return instance;
        if (url.contains("http")) {
            new Thread(() -> {
                Bitmap bitmap = getBitmapFromUrl(url);
                service.updateCover(bitmap);
            }).start();
            return instance;
        }
        try {
            AssetManager am = context.getAssets();
            InputStream inputStream = am.open(url);
            service.updateCover(BitmapFactory.decodeStream(inputStream));

        } catch (IOException e) {
            onStatusCallbackNext(CallBackState.error, e.toString());
        }
        return instance;
    }

    /**
     * 播放音视频
     */
    void start(MediaInfo info) throws Exception {
        if (info.url.equals(curUrl)) {
            play();
            return;
        }
        this.mediaInfo = info;
        if (mediaInfo.url == null) throw new Exception("you must invoke setInfo method before");

        stop();
        uiHolder.player = new MediaPlayer();
        keepAlive();
        initPlayerListener();

        if (!mediaInfo.isVideo) bindService();

        if (mediaInfo.isAsset) {
//            if (!checkAvalable(mediaInfo.url)) {
//                onStatusCallbackNext(CallBackState.FORMAT_NOT_SUPPORT, mediaInfo.url);
//                return;
//            }
            if (mediaInfo.isVideo) {
                if (isHolderCreate) {
                    beginPlayAsset(mediaInfo.url);
                } else {
                    setOnHolderCreateListener(() -> beginPlayAsset(mediaInfo.url));
                }
            } else {
                beginPlayAsset(mediaInfo.url);
            }
        } else {
            if (mediaInfo.isVideo) {
                if (isHolderCreate) {
                    beginPlayUrl(mediaInfo.url);
                } else {
                    setOnHolderCreateListener(() -> beginPlayUrl(mediaInfo.url));
                }
            } else {
                beginPlayUrl(mediaInfo.url);
            }
        }

        curUrl = mediaInfo.url;
        isPrepare = false;
    }

    /**
     * 通过Assets文件名播放Assets目录下的音频
     *
     * @param assetName 名字,带后缀，比如:text.mp3
     */
    public void playAsset(String assetName, boolean isVideo) {
//        if (!checkAvalable(assetName)) {
//            onStatusCallbackNext(CallBackState.FORMAT_NOT_SUPPORT, assetName);
//            return;
//        }
        if (isVideo) {
            if (isHolderCreate) {
                beginPlayAsset(assetName);
            } else {
                setOnHolderCreateListener(() -> beginPlayAsset(assetName));
            }
        } else {
            beginPlayAsset(assetName);
        }
    }

    /**
     * 通过文件路径播放音视频
     *
     * @param path 路径
     */
    public void playUrl(final String path, boolean isVideo) {
        if (isVideo) {
            if (isHolderCreate) {
                beginPlayUrl(path);
            } else {
                setOnHolderCreateListener(() -> beginPlayUrl(path));
            }
        } else {
            beginPlayUrl(path);
        }
    }


    /**
     * 播放流视频
     *
     * @param videoBuffer videoBuffer
     */
    @RequiresApi(api = Build.VERSION_CODES.M)
    public void playByte(byte[] videoBuffer, boolean isVideo) {
        if (isVideo) {
            if (isHolderCreate) {
                beginPlayDataSource(new ByteMediaDataSource(videoBuffer));
            } else {
                setOnHolderCreateListener(() -> beginPlayDataSource(new ByteMediaDataSource(videoBuffer)));
            }
        } else {
            beginPlayDataSource(new ByteMediaDataSource(videoBuffer));
        }
    }

    /**
     * @param speed 播放速率
     * @return 是否设置成功
     */
    boolean setSpeed(float speed) {
        if (!canPlay()) return false;
        //倍速设置，必须在23以上
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                uiHolder.player.setPlaybackParams(uiHolder.player.getPlaybackParams().setSpeed(speed));
                uiHolder.player.pause();
                uiHolder.player.start();
                return true;
            } catch (Exception e) {
                Log.e(TAG, "setPlaySpeed: ", e);
                return false;
            }
        } else {
            Log.v(TAG, "对不起请升级手机系统至Android6.0及以上");
            return false;
        }
    }

    void play() {
        if (!canPlay()) return;
        if (isPlaying()) return;
        uiHolder.player.start();
        onStatusCallbackNext(CallBackState.playOrPause, isPlaying());

        if (service != null)
            service.updateNotification(isPlaying(), mediaInfo.title, null);
    }

    void pause() {
        if (!canPlay()) return;
        if (!isPlaying()) return;
        uiHolder.player.pause();
        onStatusCallbackNext(CallBackState.playOrPause, isPlaying());

        if (service != null)
            service.updateNotification(isPlaying(), mediaInfo.title, null);
    }

    void playOrPause() {
        if (!canPlay()) return;
        if (isPlaying()) {
            uiHolder.player.pause();
        } else {
            uiHolder.player.start();
        }
        onStatusCallbackNext(CallBackState.playOrPause, isPlaying());

        if (service != null)
            service.updateNotification(isPlaying(), mediaInfo.title, null);
    }

    private boolean canPlay() {
        if (!isPrepare) {
            Log.e(TAG, "媒体资源加载失败");
            onStatusCallbackNext(CallBackState.error, "媒体资源加载失败");
        }
        return isPrepare;
    }

    boolean isPlaying() {
        if (uiHolder.player == null) return false;
        return uiHolder.player.isPlaying();
    }

    int position() {
        if (uiHolder.player == null) return 0;
        return uiHolder.player.getCurrentPosition();
    }

    int duration() {
        if (uiHolder.player == null) return 0;
        return uiHolder.player.getDuration();
    }

    boolean seekTo(int position) {
        if (uiHolder.player == null) return false;
        uiHolder.player.seekTo(position);
        return true;
    }

    /**
     * 停止资源
     */
    public void stop() {
        if (uiHolder.player != null) {
            uiHolder.player.release();
            uiHolder.player = null;
        }
        onStatusCallbackNext(CallBackState.stop);
        refress_time_handler.removeCallbacks(refress_time_Thread);

        curUrl = "";
        isPrepare = false;
    }

    /**
     * 释放资源
     */
    public void release() {
        stop();
        MediaPlayerService.unBind(context);

        if (wifiLock != null && wifiLock.isHeld())
            wifiLock.release();
    }

//    /**
//     * 重新创建MediaPlayer
//     */
//    public void reCreateMediaPlayer() {
//        if (uiHolder.player != null) {
//            if (uiHolder.player.isPlaying()) {
//                uiHolder.player.stop();
//            }
//            uiHolder.player.release();
//            uiHolder.player = new MediaPlayer();
//        } else {
//            uiHolder.player = new MediaPlayer();
//        }
//        initPlayerListener();
//    }

    /**
     * 设置SurfaceView
     *
     * @param surfaceView 控件
     * @return 实例
     */
    public MediaPlayerHelper setSurfaceView(SurfaceView surfaceView) {
        if (surfaceView == null) {
            onStatusCallbackNext(CallBackState.SURFACE_NULL, uiHolder.player);
        } else {
            uiHolder.surfaceView = surfaceView;
            uiHolder.surfaceHolder = uiHolder.surfaceView.getHolder();
            uiHolder.surfaceHolder.addCallback(new SurfaceHolder.Callback() {
                @Override
                public void surfaceCreated(SurfaceHolder holder) {
                    isHolderCreate = true;
                    if (uiHolder.player != null && holder != null) {
                        //解决部分机型/电视播放的时候有声音没画面的情况
                        if (uiHolder.surfaceView != null) {
                            uiHolder.surfaceView.post(() -> {
                                holder.setFixedSize(uiHolder.surfaceView.getWidth(), uiHolder.surfaceView.getHeight());
                                uiHolder.player.setDisplay(holder);
                            });
                        }
                    }
                    onStatusCallbackNext(CallBackState.SURFACE_CREATE, holder);
                    onHolderCreateNext();
                }

                @Override
                public void surfaceChanged(SurfaceHolder holder, int format, int width, int height) {
                    onStatusCallbackNext(CallBackState.SURFACE_CHANGE, format, width, height);
                }

                @Override
                public void surfaceDestroyed(SurfaceHolder holder) {
                    isHolderCreate = false;
                    onStatusCallbackNext(CallBackState.SURFACE_DESTROY, holder);
                }
            });
        }
        return instance;
    }

    /**
     * 构造函数
     */
    private MediaPlayerHelper(Context context) {
        if (instance == null) {
            instance = this;
        }
        this.context = context;
        this.uiHolder = new Holder();
        MediaPlayerService.registerReceiver(context);
//        uiHolder.player = new MediaPlayer();
//        keepAlive();
//        initPlayerListener();
    }

    /**
     * 时间监听
     */
    private void initPlayerListener() {
        uiHolder.player.setOnCompletionListener(mp -> {
            onStatusCallbackNext(CallBackState.progress, 100);
            onStatusCallbackNext(CallBackState.ended, mp);
        });
        uiHolder.player.setOnErrorListener((mp, what, extra) -> {
            String errorString = "what:" + what + " extra:" + extra;
            onStatusCallbackNext(CallBackState.error, errorString);
            return false;
        });
        uiHolder.player.setOnInfoListener((mp, what, extra) -> {
            onStatusCallbackNext(CallBackState.INFO, mp, what, extra);
            return false;
        });
        uiHolder.player.setOnPreparedListener(mp -> {
            try {
                if (uiHolder.surfaceView != null) {
                    //解决部分机型/电视播放的时候有声音没画面的情况
                    uiHolder.surfaceView.post(() -> {
                        uiHolder.surfaceHolder.setFixedSize(uiHolder.surfaceView.getWidth(), uiHolder.surfaceView.getHeight());
                        //设置预览区域
                        uiHolder.player.setDisplay(uiHolder.surfaceHolder);
                    });
                }
                isPrepare = true;
                if (mediaInfo.isAuto) {
                    uiHolder.player.start();
                }
                refress_time_handler.postDelayed(refress_time_Thread, delaySecondTime);
            } catch (Exception e) {
                onStatusCallbackNext(CallBackState.error, e.toString());
            }
            String holderMsg = "holder -";
            if (uiHolder.surfaceHolder != null) {
                holderMsg = holderMsg + " height：" + uiHolder.surfaceHolder.getSurfaceFrame().height();
                holderMsg = holderMsg + " width：" + uiHolder.surfaceHolder.getSurfaceFrame().width();
            }
            onStatusCallbackNext(CallBackState.ready, holderMsg);
        });
        uiHolder.player.setOnSeekCompleteListener(mp -> onStatusCallbackNext(CallBackState.seekComplete, mp));
        uiHolder.player.setOnVideoSizeChangedListener((mp, width, height) -> onStatusCallbackNext(CallBackState.VIDEO_SIZE_CHANGE, width, height));
        uiHolder.player.setOnBufferingUpdateListener((mp, percent) -> onStatusCallbackNext(CallBackState.buffering, mp, percent));
    }

    /**
     * 播放
     *
     * @param path 参数
     */
    private void beginPlayUrl(String path) {
        /*
         * 其实仔细观察优酷app切换播放网络视频时的确像是这样做的：先暂停当前视频，
         * 让mediaplayer与先前的surfaceHolder脱离“绑定”,当mediaplayer再次准备好要start时，
         * 再次让mediaplayer与surfaceHolder“绑定”在一起，显示下一个要播放的视频。
         * 注：MediaPlayer.setDisplay()的作用： 设置SurfaceHolder用于显示的视频部分媒体。
         */
        try {
            //Uri url = Uri.fromFile(new File(path));
            uiHolder.player.setDisplay(null);
            uiHolder.player.reset();
            uiHolder.player.setDataSource(path);
            uiHolder.player.prepareAsync();
        } catch (Exception e) {
            onStatusCallbackNext(CallBackState.error, e.toString());
        }
    }

    /**
     * 播放
     *
     * @param assetName 参数
     */
    private void beginPlayAsset(String assetName) {
        /*
         * 其实仔细观察优酷app切换播放网络视频时的确像是这样做的：先暂停当前视频，
         * 让mediaplayer与先前的surfaceHolder脱离“绑定”,当mediaplayer再次准备好要start时，
         * 再次让mediaplayer与surfaceHolder“绑定”在一起，显示下一个要播放的视频。
         * 注：MediaPlayer.setDisplay()的作用： 设置SurfaceHolder用于显示的视频部分媒体。
         */
        AssetManager assetMg = context.getAssets();
        try {
            uiHolder.assetDescriptor = assetMg.openFd(assetName);
            uiHolder.player.setDisplay(null);
            uiHolder.player.reset();
            uiHolder.player.setDataSource(uiHolder.assetDescriptor.getFileDescriptor(), uiHolder.assetDescriptor.getStartOffset(), uiHolder.assetDescriptor.getLength());
            uiHolder.player.prepareAsync();
        } catch (Exception e) {
            onStatusCallbackNext(CallBackState.error, e.toString());
        }
    }

    /**
     * 播放
     *
     * @param mediaDataSource 参数
     */
    @RequiresApi(api = Build.VERSION_CODES.M)
    private void beginPlayDataSource(MediaDataSource mediaDataSource) {
        /*
         * 其实仔细观察优酷app切换播放网络视频时的确像是这样做的：先暂停当前视频，
         * 让mediaplayer与先前的surfaceHolder脱离“绑定”,当mediaplayer再次准备好要start时，
         * 再次让mediaplayer与surfaceHolder“绑定”在一起，显示下一个要播放的视频。
         * 注：MediaPlayer.setDisplay()的作用： 设置SurfaceHolder用于显示的视频部分媒体。
         */
        try {
            uiHolder.player.setDisplay(null);
            uiHolder.player.reset();
            uiHolder.player.setDataSource(mediaDataSource);
            uiHolder.player.prepareAsync();
        } catch (Exception e) {
            onStatusCallbackNext(CallBackState.error, e.toString());
        }
    }

    /**
     * 检查是否可以播放
     *
     * @param path 参数
     * @return 结果
     */
    private boolean checkAvalable(String path) {
        boolean surport = false;
        for (String s : ext) {
            if (path.endsWith(s)) {
                surport = true;
            }
        }
        if (!surport) {
            onStatusCallbackNext(CallBackState.FORMAT_NOT_SUPPORT, uiHolder.player);
            return false;
        }
        return true;
    }

    private void keepAlive() {
        // 设置设备进入锁状态模式-可在后台播放或者缓冲音乐-CPU一直工作
        uiHolder.player.setWakeMode(context, PowerManager.PARTIAL_WAKE_LOCK);
        // 当播放的时候一直让屏幕变亮
//        player.setScreenOnWhilePlaying(true);

        // 如果你使用wifi播放流媒体，你还需要持有wifi锁
        wifiLock = ((WifiManager) Objects.requireNonNull(context.getApplicationContext().getSystemService(Context.WIFI_SERVICE)))
                .createWifiLock(WifiManager.WIFI_MODE_FULL, "wifilock");
        wifiLock.acquire();
    }

    /**
     * 播放进度定时器
     */
    private Handler refress_time_handler = new Handler(){
        @Override
        public void handleMessage(Message msg) {
            switch (msg.what){
                case ERROR:
                    onStatusCallbackNext(CallBackState.error, msg.obj);
                    break;
            }
        }
    };
    private Runnable refress_time_Thread = new Runnable() {
        public void run() {
            refress_time_handler.removeCallbacks(refress_time_Thread);
            try {
                if (uiHolder.player != null && uiHolder.player.isPlaying()) {
                    int duraction = uiHolder.player.getDuration();
                    if (duraction > 0) {
                        onStatusCallbackNext(CallBackState.progress, 100 * uiHolder.player.getCurrentPosition() / duraction);
                    }
                }
            } catch (IllegalStateException e) {
                onStatusCallbackNext(CallBackState.error, e.toString());
            }
            refress_time_handler.postDelayed(refress_time_Thread, delaySecondTime);
        }
    };

    // 网络获取图片
    private Bitmap getBitmapFromUrl(String urlString) {
        Bitmap bitmap;
        InputStream is;
        try {
            URL url = new URL(urlString);
            HttpURLConnection connection = (HttpURLConnection) url.openConnection();
            is = new BufferedInputStream(connection.getInputStream());
            bitmap = BitmapFactory.decodeStream(is);
            connection.disconnect();
            is.close();
            return bitmap;
        } catch (IOException e) {
            Message msg = new Message();
            msg.what = ERROR;
            msg.obj = e.toString();
            refress_time_handler.sendMessage(msg);
        }
        return null;
    }

    private static final int ERROR = 0x1;

    /* ***************************** Holder封装UI ***************************** */

    private static final class Holder {
        private SurfaceHolder surfaceHolder;
        private MediaPlayer player;
        private SurfaceView surfaceView;
        private AssetFileDescriptor assetDescriptor;
    }

    /* ***************************** StatusCallback ***************************** */

    private OnStatusCallbackListener onStatusCallbackListener;

    // 接口类 -> OnStatusCallbackListener
    public interface OnStatusCallbackListener {
        void onStatusonStatusCallbackNext(CallBackState status, Object... args);
    }

    // 对外暴露接口 -> setOnStatusCallbackListener
    public MediaPlayerHelper setOnStatusCallbackListener(OnStatusCallbackListener onStatusCallbackListener) {
        this.onStatusCallbackListener = onStatusCallbackListener;
        return instance;
    }

    // 内部使用方法 -> StatusCallbackNext
    private void onStatusCallbackNext(CallBackState status, Object... args) {
        if (onStatusCallbackListener != null) {
            onStatusCallbackListener.onStatusonStatusCallbackNext(status, args);
        }
    }

    /* ***************************** HolderCreate(内部使用) ***************************** */

    private OnHolderCreateListener onHolderCreateListener;

    // 接口类 -> OnHolderCreateListener
    private interface OnHolderCreateListener {
        void onHolderCreate();
    }

    // 内部露接口 -> setOnHolderCreateListener
    private void setOnHolderCreateListener(OnHolderCreateListener onHolderCreateListener) {
        this.onHolderCreateListener = onHolderCreateListener;
    }

    // 内部使用方法 -> HolderCreateNext
    private void onHolderCreateNext() {
        if (onHolderCreateListener != null) {
            onHolderCreateListener.onHolderCreate();
        }
    }
}
