package org.lineageos.wayland;

import android.app.Activity;
import android.os.Bundle;
import android.os.RemoteException;
import android.util.Log;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.SurfaceControl;
import android.view.SurfaceHolder;
import android.view.SurfaceView;

/**
 * Represents one Wayland xdg_toplevel as an Android Activity.
 * Shows up in recents, taskbar, gets focus and input like a normal app.
 * Reports its window's SurfaceControl back to the compositor for reparenting.
 * Captures touch/key input and forwards to the compositor.
 */
public class WaylandWindowActivity extends Activity {
    private static final String TAG = "WaylandWindowActivity";

    static final String EXTRA_LAYER_ID = "layer_id";
    static final String EXTRA_TITLE = "title";
    static final String EXTRA_WIDTH = "width";
    static final String EXTRA_HEIGHT = "height";

    // Linux input event codes for mouse buttons (from linux/input-event-codes.h)
    private static final int BTN_LEFT = 0x110;
    private static final int BTN_RIGHT = 0x111;
    private static final int BTN_MIDDLE = 0x112;

    private int mLayerId;
    private SurfaceView mSurfaceView;
    private boolean mPointerInside = false;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        mLayerId = getIntent().getIntExtra(EXTRA_LAYER_ID, -1);
        String title = getIntent().getStringExtra(EXTRA_TITLE);

        if (title != null && !title.isEmpty()) {
            setTitle(title);
            setTaskDescription(new android.app.ActivityManager.TaskDescription(title));
        }

        // Use a FrameLayout that respects system window insets (status bar, nav bar).
        android.widget.FrameLayout container = new android.widget.FrameLayout(this);
        container.setFitsSystemWindows(true);
        mSurfaceView = new SurfaceView(this);
        container.addView(mSurfaceView, new android.widget.FrameLayout.LayoutParams(
                android.widget.FrameLayout.LayoutParams.MATCH_PARENT,
                android.widget.FrameLayout.LayoutParams.MATCH_PARENT));
        setContentView(container);

        mSurfaceView.getHolder().addCallback(new SurfaceHolder.Callback() {
            @Override
            public void surfaceCreated(SurfaceHolder holder) {
                SurfaceControl sc = mSurfaceView.getSurfaceControl();
                if (sc != null && sc.isValid()) {
                    WaylandWindowService service = WaylandWindowService.getInstance();
                    if (service != null) {
                        service.onWindowSurfaceReady(mLayerId, sc);
                    }
                }
            }

            @Override
            public void surfaceChanged(SurfaceHolder holder, int format,
                                      int width, int height) {
                IWaylandWindowCallback callback = getCallback();
                if (callback != null) {
                    try {
                        callback.onWindowResized(mLayerId, width, height);
                    } catch (RemoteException e) {
                        Log.w(TAG, "Failed to forward resize", e);
                    }
                }
            }

            @Override
            public void surfaceDestroyed(SurfaceHolder holder) {
            }
        });

        WaylandWindowService service = WaylandWindowService.getInstance();
        if (service != null) {
            service.registerActivity(mLayerId, this);
        }

        Log.i(TAG, "onCreate: layerId=" + mLayerId + " title=" + title);
    }

    @Override
    protected void onDestroy() {
        Log.i(TAG, "onDestroy: layerId=" + mLayerId);
        WaylandWindowService service = WaylandWindowService.getInstance();
        if (service != null) {
            service.onWindowDestroyed(mLayerId);
        }
        super.onDestroy();
    }

    @Override
    public boolean dispatchTouchEvent(MotionEvent event) {
        IWaylandWindowCallback callback = getCallback();
        if (callback == null) {
            Log.w(TAG, "No callback for layerId=" + mLayerId + ", touch ignored");
            return super.dispatchTouchEvent(event);
        }

        long timeMs = event.getEventTime();
        float x = event.getX();
        float y = event.getY();

        try {
            switch (event.getActionMasked()) {
                case MotionEvent.ACTION_DOWN:
                    // Send enter + motion + button press
                    callback.onPointerMotion(mLayerId, timeMs, x, y);
                    callback.onPointerButton(mLayerId, timeMs, BTN_LEFT, true);
                    mPointerInside = true;
                    break;

                case MotionEvent.ACTION_MOVE:
                    callback.onPointerMotion(mLayerId, timeMs, x, y);
                    break;

                case MotionEvent.ACTION_UP:
                    callback.onPointerMotion(mLayerId, timeMs, x, y);
                    callback.onPointerButton(mLayerId, timeMs, BTN_LEFT, false);
                    break;

                case MotionEvent.ACTION_CANCEL:
                    callback.onPointerButton(mLayerId, timeMs, BTN_LEFT, false);
                    break;
            }
        } catch (RemoteException e) {
            Log.w(TAG, "Failed to forward touch event", e);
        }

        return true;
    }

    @Override
    public boolean onGenericMotionEvent(MotionEvent event) {
        IWaylandWindowCallback callback = getCallback();
        if (callback == null) return super.onGenericMotionEvent(event);

        // Handle hover events (mouse pointer without button press)
        if (event.getActionMasked() == MotionEvent.ACTION_HOVER_MOVE) {
            try {
                callback.onPointerMotion(mLayerId, event.getEventTime(),
                        event.getX(), event.getY());
            } catch (RemoteException e) {
                Log.w(TAG, "Failed to forward hover event", e);
            }
            return true;
        }

        return super.onGenericMotionEvent(event);
    }

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        IWaylandWindowCallback callback = getCallback();
        if (callback == null) return super.onKeyDown(keyCode, event);

        int evdevKey = androidKeyToEvdev(keyCode, event.getScanCode());
        if (evdevKey >= 0) {
            try {
                callback.onKey(mLayerId, event.getEventTime(), evdevKey, true);
            } catch (RemoteException e) {
                Log.w(TAG, "Failed to forward key down", e);
            }
            return true;
        }
        return super.onKeyDown(keyCode, event);
    }

    @Override
    public boolean onKeyUp(int keyCode, KeyEvent event) {
        IWaylandWindowCallback callback = getCallback();
        if (callback == null) return super.onKeyUp(keyCode, event);

        int evdevKey = androidKeyToEvdev(keyCode, event.getScanCode());
        if (evdevKey >= 0) {
            try {
                callback.onKey(mLayerId, event.getEventTime(), evdevKey, false);
            } catch (RemoteException e) {
                Log.w(TAG, "Failed to forward key up", e);
            }
            return true;
        }
        return super.onKeyUp(keyCode, event);
    }

    void updateTitle(String title) {
        runOnUiThread(() -> {
            setTitle(title);
            setTaskDescription(new android.app.ActivityManager.TaskDescription(title));
        });
    }

    private IWaylandWindowCallback getCallback() {
        WaylandWindowService service = WaylandWindowService.getInstance();
        return service != null ? service.getCallback(mLayerId) : null;
    }

    /**
     * Map Android KeyEvent keyCode to Linux evdev key code.
     * If scanCode > 0 (hardware keyboard), use it directly.
     * Otherwise, map from Android keyCode.
     */
    private static int androidKeyToEvdev(int keyCode, int scanCode) {
        // Hardware keyboards provide the actual evdev scan code.
        if (scanCode > 0) return scanCode;

        // Software keyboard / virtual key mapping.
        // Values from linux/input-event-codes.h
        switch (keyCode) {
            case KeyEvent.KEYCODE_ESCAPE: return 1;
            case KeyEvent.KEYCODE_1: return 2;
            case KeyEvent.KEYCODE_2: return 3;
            case KeyEvent.KEYCODE_3: return 4;
            case KeyEvent.KEYCODE_4: return 5;
            case KeyEvent.KEYCODE_5: return 6;
            case KeyEvent.KEYCODE_6: return 7;
            case KeyEvent.KEYCODE_7: return 8;
            case KeyEvent.KEYCODE_8: return 9;
            case KeyEvent.KEYCODE_9: return 10;
            case KeyEvent.KEYCODE_0: return 11;
            case KeyEvent.KEYCODE_MINUS: return 12;
            case KeyEvent.KEYCODE_EQUALS: return 13;
            case KeyEvent.KEYCODE_DEL: return 14; // Backspace
            case KeyEvent.KEYCODE_TAB: return 15;
            case KeyEvent.KEYCODE_Q: return 16;
            case KeyEvent.KEYCODE_W: return 17;
            case KeyEvent.KEYCODE_E: return 18;
            case KeyEvent.KEYCODE_R: return 19;
            case KeyEvent.KEYCODE_T: return 20;
            case KeyEvent.KEYCODE_Y: return 21;
            case KeyEvent.KEYCODE_U: return 22;
            case KeyEvent.KEYCODE_I: return 23;
            case KeyEvent.KEYCODE_O: return 24;
            case KeyEvent.KEYCODE_P: return 25;
            case KeyEvent.KEYCODE_LEFT_BRACKET: return 26;
            case KeyEvent.KEYCODE_RIGHT_BRACKET: return 27;
            case KeyEvent.KEYCODE_ENTER: return 28;
            case KeyEvent.KEYCODE_CTRL_LEFT: return 29;
            case KeyEvent.KEYCODE_A: return 30;
            case KeyEvent.KEYCODE_S: return 31;
            case KeyEvent.KEYCODE_D: return 32;
            case KeyEvent.KEYCODE_F: return 33;
            case KeyEvent.KEYCODE_G: return 34;
            case KeyEvent.KEYCODE_H: return 35;
            case KeyEvent.KEYCODE_J: return 36;
            case KeyEvent.KEYCODE_K: return 37;
            case KeyEvent.KEYCODE_L: return 38;
            case KeyEvent.KEYCODE_SEMICOLON: return 39;
            case KeyEvent.KEYCODE_APOSTROPHE: return 40;
            case KeyEvent.KEYCODE_GRAVE: return 41;
            case KeyEvent.KEYCODE_SHIFT_LEFT: return 42;
            case KeyEvent.KEYCODE_BACKSLASH: return 43;
            case KeyEvent.KEYCODE_Z: return 44;
            case KeyEvent.KEYCODE_X: return 45;
            case KeyEvent.KEYCODE_C: return 46;
            case KeyEvent.KEYCODE_V: return 47;
            case KeyEvent.KEYCODE_B: return 48;
            case KeyEvent.KEYCODE_N: return 49;
            case KeyEvent.KEYCODE_M: return 50;
            case KeyEvent.KEYCODE_COMMA: return 51;
            case KeyEvent.KEYCODE_PERIOD: return 52;
            case KeyEvent.KEYCODE_SLASH: return 53;
            case KeyEvent.KEYCODE_SHIFT_RIGHT: return 54;
            case KeyEvent.KEYCODE_ALT_LEFT: return 56;
            case KeyEvent.KEYCODE_SPACE: return 57;
            case KeyEvent.KEYCODE_CAPS_LOCK: return 58;
            case KeyEvent.KEYCODE_F1: return 59;
            case KeyEvent.KEYCODE_F2: return 60;
            case KeyEvent.KEYCODE_F3: return 61;
            case KeyEvent.KEYCODE_F4: return 62;
            case KeyEvent.KEYCODE_F5: return 63;
            case KeyEvent.KEYCODE_F6: return 64;
            case KeyEvent.KEYCODE_F7: return 65;
            case KeyEvent.KEYCODE_F8: return 66;
            case KeyEvent.KEYCODE_F9: return 67;
            case KeyEvent.KEYCODE_F10: return 68;
            case KeyEvent.KEYCODE_F11: return 87;
            case KeyEvent.KEYCODE_F12: return 88;
            case KeyEvent.KEYCODE_ALT_RIGHT: return 100;
            case KeyEvent.KEYCODE_CTRL_RIGHT: return 97;
            case KeyEvent.KEYCODE_INSERT: return 110;
            case KeyEvent.KEYCODE_FORWARD_DEL: return 111;
            case KeyEvent.KEYCODE_MOVE_HOME: return 102;
            case KeyEvent.KEYCODE_MOVE_END: return 107;
            case KeyEvent.KEYCODE_PAGE_UP: return 104;
            case KeyEvent.KEYCODE_PAGE_DOWN: return 109;
            case KeyEvent.KEYCODE_DPAD_UP: return 103;
            case KeyEvent.KEYCODE_DPAD_DOWN: return 108;
            case KeyEvent.KEYCODE_DPAD_LEFT: return 105;
            case KeyEvent.KEYCODE_DPAD_RIGHT: return 106;
            case KeyEvent.KEYCODE_META_LEFT: return 125; // KEY_LEFTMETA
            case KeyEvent.KEYCODE_META_RIGHT: return 126; // KEY_RIGHTMETA
            default: return -1;
        }
    }
}
