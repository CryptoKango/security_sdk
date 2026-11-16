package dev.securitysdk.window_companion;

import android.app.*;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.hardware.display.DisplayManager;
import android.hardware.display.VirtualDisplay;
import android.media.ImageReader;
import android.media.projection.MediaProjection;
import android.media.projection.MediaProjectionManager;
import android.os.*;

/** Discards every frame without reading planes, saving files, or using a network. */
public final class ProjectionService extends Service {
    private MediaProjection projection;
    private VirtualDisplay display;
    private ImageReader reader;
    private final Handler handler=new Handler(Looper.getMainLooper());
    private final MediaProjection.Callback callback=new MediaProjection.Callback() {
        @Override public void onStop() { stopSelf(); }
    };
    @Override public IBinder onBind(Intent intent) { return null; }
    @Override public int onStartCommand(Intent intent,int flags,int id) {
        if(intent==null || projection!=null) {stopSelf();return START_NOT_STICKY;}
        NotificationManager notifications=getSystemService(NotificationManager.class);
        notifications.createNotificationChannel(new NotificationChannel("projection-test","Security projection test",NotificationManager.IMPORTANCE_LOW));
        startForeground(91,new Notification.Builder(this,"projection-test").setContentTitle("Security SDK projection regression")
            .setContentText("No audio, no storage. Stop after validation.").setSmallIcon(android.R.drawable.ic_menu_view).build(), ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION);
        try {
            projection=getSystemService(MediaProjectionManager.class).getMediaProjection(intent.getIntExtra("result",0),intent.getParcelableExtra("grant"));
            projection.registerCallback(callback,handler);
            reader=ImageReader.newInstance(64,64,android.graphics.PixelFormat.RGBA_8888,2);
            reader.setOnImageAvailableListener(source -> {try(android.media.Image image=source.acquireLatestImage()) { /* discard */ }},handler);
            display=projection.createVirtualDisplay("security-sdk-validation",64,64,getResources().getDisplayMetrics().densityDpi,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,reader.getSurface(),null,handler);
        } catch (RuntimeException error) {stopSelf();}
        return START_NOT_STICKY;
    }
    @Override public void onDestroy() {
        if(display!=null) {display.release();display=null;}
        if(reader!=null) {reader.setOnImageAvailableListener(null,null);reader.close();reader=null;}
        if(projection!=null) {projection.unregisterCallback(callback);projection.stop();projection=null;}
        stopForeground(STOP_FOREGROUND_REMOVE);
        super.onDestroy();
    }
}
