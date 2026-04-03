package org.lineageos.wayland;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.util.Log;

import java.io.File;
import java.io.IOException;

public class BootReceiver extends BroadcastReceiver {
    private static final String TAG = "WaylandBootReceiver";

    @Override
    public void onReceive(Context context, Intent intent) {
        context.startService(new Intent(context, WaylandWindowService.class));

        // Set up chroot mounts in background
        String chrootPath = WaylandConfig.getChrootPath(context);
        if (new File(chrootPath, "usr").isDirectory()) {
            new Thread(() -> setupChrootMounts(chrootPath)).start();
        }
    }

    private void setupChrootMounts(String chrootPath) {
        try {
            String[] cmds = {
                "mount -t proc proc " + chrootPath + "/proc 2>/dev/null",
                "mount -o bind /dev " + chrootPath + "/dev 2>/dev/null",
                "mount -o bind /dev/pts " + chrootPath + "/dev/pts 2>/dev/null",
                "mount -t tmpfs tmpfs " + chrootPath + "/tmp 2>/dev/null",
                "mkdir -p " + chrootPath + "/run/wayland",
                "mount -o bind /data/wayland " + chrootPath + "/run/wayland 2>/dev/null",
            };
            for (String cmd : cmds) {
                Runtime.getRuntime().exec(new String[]{"su", "0", "sh", "-c", cmd}).waitFor();
            }
            Log.i(TAG, "Chroot mounts set up for " + chrootPath);
        } catch (IOException | InterruptedException e) {
            Log.e(TAG, "Failed to set up chroot mounts", e);
        }
    }
}
