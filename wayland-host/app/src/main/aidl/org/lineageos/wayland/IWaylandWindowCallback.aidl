package org.lineageos.wayland;

import android.view.SurfaceControl;

interface IWaylandWindowCallback {
    // Called when the Activity's window Surface is ready.
    void onWindowReady(int layerId, in SurfaceControl windowSc);

    // Called when the Activity window is destroyed.
    void onWindowClosed(int layerId);
}
