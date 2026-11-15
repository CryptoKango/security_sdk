package dev.securitysdk.window_companion;

import android.app.Activity;
import android.content.Intent;
import android.content.res.Configuration;
import android.os.Bundle;
import android.os.ResultReceiver;
import android.widget.TextView;

/** Offline companion APK for two-application split-screen validation only. */
public final class CompanionActivity extends Activity {
    private ResultReceiver receiver;
    private boolean resumed;
    private final ResultReceiver control = new ResultReceiver(new android.os.Handler(android.os.Looper.getMainLooper())) {
        @Override protected void onReceiveResult(int code, Bundle data) { if (code == 2) finishAndRemoveTask(); }
    };
    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        TextView view = new TextView(this);
        view.setText("Security SDK split-screen companion\nTap either app to switch focus");
        view.setTextSize(24); view.setBackgroundColor(0xffd8e8f5);
        setContentView(view); accept(getIntent());
    }
    @SuppressWarnings("deprecation")
    private void accept(Intent intent) {
        if (intent.getBooleanExtra("finishFixture", false)) { finishAndRemoveTask(); return; }
        receiver = intent.getParcelableExtra("report");
        report();
    }
    @Override protected void onNewIntent(Intent intent) { super.onNewIntent(intent); accept(intent); }
    @Override protected void onResume() { super.onResume(); resumed = true; report(); }
    @Override protected void onPause() { resumed = false; report(); super.onPause(); }
    @Override public void onWindowFocusChanged(boolean focus) { super.onWindowFocusChanged(focus); report(); }
    @Override public void onMultiWindowModeChanged(boolean value, Configuration config) { super.onMultiWindowModeChanged(value, config); report(); }
    private void report() {
        if (receiver == null) return;
        Bundle state = new Bundle();
        android.os.Parcel parcel = android.os.Parcel.obtain();
        try {
            control.writeToParcel(parcel, 0); parcel.setDataPosition(0);
            state.putParcelable("control", ResultReceiver.CREATOR.createFromParcel(parcel));
        } finally { parcel.recycle(); }
        state.putBoolean("multiWindow", isInMultiWindowMode());
        state.putBoolean("focus", hasWindowFocus()); state.putBoolean("resumed", resumed);
        state.putInt("width", getWindow().getDecorView().getWidth());
        state.putInt("height", getWindow().getDecorView().getHeight());
        receiver.send(1, state);
    }
    @Override protected void onDestroy() {
        if (receiver != null) { Bundle state = new Bundle(); state.putBoolean("closed", true); receiver.send(1,state); }
        receiver = null; super.onDestroy();
    }
}
