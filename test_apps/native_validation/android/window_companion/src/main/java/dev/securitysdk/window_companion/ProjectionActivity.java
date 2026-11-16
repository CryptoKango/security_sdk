package dev.securitysdk.window_companion;

import android.app.Activity;
import android.content.Intent;
import android.media.projection.MediaProjectionManager;
import android.media.projection.MediaProjectionConfig;
import android.os.Bundle;
import android.widget.TextView;

/** Test APK only. System consent is mandatory; never captures audio or writes frames. */
public final class ProjectionActivity extends Activity {
    private boolean full;
    @Override public void onCreate(Bundle saved) {
        super.onCreate(saved);
        TextView view=new TextView(this);view.setText("Security projection fixture: no storage / no audio");setContentView(view);
        String action=getIntent().getStringExtra("mode");
        if("stop".equals(action)) { stopService(new Intent(this,ProjectionService.class));finish();return; }
        if(saved!=null)return;
        if(android.os.Build.VERSION.SDK_INT<34) { finish();return; }
        full="full".equals(action);
        MediaProjectionManager manager=getSystemService(MediaProjectionManager.class);
        startActivityForResult(full ? manager.createScreenCaptureIntent(MediaProjectionConfig.createConfigForDefaultDisplay()) : manager.createScreenCaptureIntent(), 91);
    }
    @Override protected void onActivityResult(int request,int result,Intent data) {
        super.onActivityResult(request,result,data);
        if(request==91 && result==RESULT_OK && data!=null) startForegroundService(new Intent(this,ProjectionService.class)
            .putExtra("result",result).putExtra("grant",data).putExtra("full",full));
        finish();
    }
}
