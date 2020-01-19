package cc.dync.audio_manager;

import android.media.MediaDataSource;
import android.os.Build;

import androidx.annotation.RequiresApi;

/**
 * MediaPlayer播放字节流的工具类，可用于视频加密解密播放方案
 * Created by haide.yin(haide.yin@tcl.com) on 2019/12/13 8:56.
 */
@RequiresApi(api = Build.VERSION_CODES.M)
public class ByteMediaDataSource extends MediaDataSource {

    private volatile byte[] videoBuffer;

    public ByteMediaDataSource(byte[] videoBuffer) {
        this.videoBuffer = videoBuffer;
    }

    @Override
    public int readAt(long position, byte[] buffer, int offset, int size) {
        synchronized (videoBuffer) {
            int length = videoBuffer.length;
            if (position >= length) {
                return -1; // -1 indicates EOF
            }
            if (position + size > length) {
                size -= (position + size) - length;
            }
            System.arraycopy(videoBuffer, (int) position, buffer, offset, size);
            return size;
        }
    }

    @Override
    public long getSize() {
        synchronized (videoBuffer) {
            return videoBuffer.length;
        }
    }

    @Override
    public void close() {

    }
}