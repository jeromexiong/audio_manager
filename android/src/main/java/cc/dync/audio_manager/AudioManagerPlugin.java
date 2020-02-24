package cc.dync.audio_manager;

import android.content.Context;
import android.util.Log;

import androidx.annotation.NonNull;

import java.util.HashMap;
import java.util.Map;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.common.PluginRegistry.Registrar;

/**
 * AudioManagerPlugin
 */
public class AudioManagerPlugin implements FlutterPlugin, MethodCallHandler, ActivityAware {

    private Context context;
    private static AudioManagerPlugin instance;
    private static MethodChannel channel;

    private static FlutterAssets flutterAssets;
    private static Registrar registrar;

    private static synchronized AudioManagerPlugin getInstance() {
        if (instance == null) {
            instance = new AudioManagerPlugin();
        }
        return instance;
    }

    public AudioManagerPlugin() {
        if (instance == null) {
            instance = this;
        }
    }

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding flutterPluginBinding) {
        final MethodChannel channel = new MethodChannel(flutterPluginBinding.getBinaryMessenger(), "audio_manager");
        channel.setMethodCallHandler(getInstance());
        AudioManagerPlugin.channel = channel;
        AudioManagerPlugin.flutterAssets = flutterPluginBinding.getFlutterAssets();
    }

    // This static function is optional and equivalent to onAttachedToEngine. It
    // supports the old
    // pre-Flutter-1.12 Android projects. You are encouraged to continue supporting
    // plugin registration via this function while apps migrate to use the new
    // Android APIs
    // post-flutter-1.12 via https://flutter.dev/go/android-project-migration.
    //
    // It is encouraged to share logic between onAttachedToEngine and registerWith
    // to keep
    // them functionally equivalent. Only one of onAttachedToEngine or registerWith
    // will be called
    // depending on the user's project. onAttachedToEngine or registerWith must both
    // be defined
    // in the same class.
    public static void registerWith(Registrar registrar) {
        channel = new MethodChannel(registrar.messenger(), "audio_manager");
        channel.setMethodCallHandler(getInstance());
        AudioManagerPlugin.registrar = registrar;
    }

    private void setupPlayer(MethodChannel channel) {
        MediaPlayerHelper helper = MediaPlayerHelper.getInstance(context);
        helper.setOnStatusCallbackListener((status, args) -> {
            Log.v(TAG, "--" + status.toString());
            switch (status) {
                case PREPARE:
                    channel.invokeMethod("ready", helper.duration());
                    break;
                case buffering:
                    if (args.length == 0) return;
                    Log.v(TAG, "网络缓冲:" + args[1] + "%");

                    Map map = new HashMap();
                    map.put("buffering", !helper.isPlaying());
                    map.put("buffer", args[1]);
                    channel.invokeMethod("buffering", map);
                    break;
                case playOrPause:
                    if (args.length == 0) return;
                    channel.invokeMethod("playstatus", args[0]);
                    break;
                case progress:
                    if (args.length == 0) return;
                    Log.v(TAG, "进度:" + args[0] + "%");

                    Map map2 = new HashMap();
                    map2.put("position", helper.position());
                    map2.put("duration", helper.duration());
                    channel.invokeMethod("timeupdate", map2);
                    break;
                case error:
                    Log.v(TAG, "播放错误:" + args[0]);
                    channel.invokeMethod("error", args[0]);
                    helper.stop();
                    break;
                case next:
                    channel.invokeMethod("next", null);
                    break;
                case previous:
                    channel.invokeMethod("previous", null);
                    break;
                case ended:
                    channel.invokeMethod("ended", null);
                    break;
            }
        });
    }

    private static final String TAG = "AudioManagerPlugin";

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
        MediaPlayerHelper helper = MediaPlayerHelper.getInstance(context);
        switch (call.method) {
            case "getPlatformVersion":
                result.success("Android " + android.os.Build.VERSION.RELEASE);
                break;
            case "start":
                String url = call.argument("url");
                String title = call.argument("title");
                String desc = call.argument("desc");
                String cover = call.argument("cover");

                boolean isLocal = call.hasArgument("isLocal") ? call.argument("isLocal") : false;
                boolean isLocalCover = call.hasArgument("isLocalCover") ? call.argument("isLocalCover") : false;
                boolean isAuto = call.hasArgument("isAuto") ? call.argument("isAuto") : false;
                MediaPlayerHelper.MediaInfo info = new MediaPlayerHelper.MediaInfo(title, url);
                info.desc = desc;
                info.isAsset = isLocal;
                info.isAuto = isAuto;
                if (isLocal) {
                    if (registrar != null) {
                        info.url = registrar.lookupKeyForAsset(url);
                    } else if (flutterAssets != null) {
                        info.url = AudioManagerPlugin.flutterAssets.getAssetFilePathByName(url);
                    }
                }
                info.cover = cover;
                if (isLocalCover) {
                    if (registrar != null) {
                        info.cover = registrar.lookupKeyForAsset(cover);
                    } else if (flutterAssets != null) {
                        info.cover = AudioManagerPlugin.flutterAssets.getAssetFilePathByName(cover);
                    }
                }

                try {
                    helper.start(info);
                } catch (Exception e) {
                    result.success(e.getMessage());
                }
                break;
            case "playOrPause":
                helper.playOrPause();
                result.success(helper.isPlaying());
                break;
            case "stop":
                helper.stop();
                break;
            case "updateLrc":
                helper.updateLrc(call.argument("lrc"));
                break;
            case "seekTo":
                if (!call.hasArgument("position")) {
                    result.success("参数错误");
                    return;
                }
                int position = (int) call.argument("position");
                helper.seekTo(position);
                break;
            case "rate":
                if (!call.hasArgument("rate")) {
                    result.success("参数错误");
                    return;
                }
                float rate = (float) call.argument("rate");
                helper.setSpeed(rate);
                break;
            default:
                result.notImplemented();
                break;
        }
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    }

    @Override
    public void onAttachedToActivity(ActivityPluginBinding binding) {
        context = binding.getActivity();
        instance.setupPlayer(channel);
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() {

    }

    @Override
    public void onReattachedToActivityForConfigChanges(ActivityPluginBinding binding) {

    }

    @Override
    public void onDetachedFromActivity() {

    }
}
