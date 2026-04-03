package org.lineageos.wayland;

import android.app.ListActivity;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.os.Bundle;
import android.util.Log;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ArrayAdapter;
import android.widget.ImageView;
import android.widget.ListView;
import android.widget.TextView;
import android.widget.Toast;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.io.IOException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * Shows installed Linux apps from .desktop files in the configured chroot.
 * Appears as "Linux Apps" in any Android launcher.
 */
public class WaylandAppLauncherActivity extends ListActivity {
    private static final String TAG = "WaylandAppLauncher";

    private List<DesktopEntry> mApps = new ArrayList<>();

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setTitle("Linux Apps");
        scanApps();
    }

    @Override
    protected void onResume() {
        super.onResume();
        scanApps();
    }

    @Override
    protected void onListItemClick(ListView l, View v, int position, long id) {
        if (position >= 0 && position < mApps.size()) {
            launchApp(mApps.get(position));
        }
    }

    private void scanApps() {
        mApps.clear();

        String chrootPath = WaylandConfig.getChrootPath(this);
        File appsDir = new File(chrootPath, "usr/share/applications");
        if (!appsDir.isDirectory()) {
            Log.w(TAG, "No applications directory at " + appsDir);
            setListAdapter(null);
            return;
        }

        File[] desktopFiles = appsDir.listFiles((dir, name) -> name.endsWith(".desktop"));
        if (desktopFiles == null) return;

        for (File f : desktopFiles) {
            DesktopEntry entry = parseDesktopEntry(f, chrootPath);
            if (entry != null && !entry.noDisplay && entry.exec != null) {
                mApps.add(entry);
            }
        }

        Collections.sort(mApps, (a, b) -> a.name.compareToIgnoreCase(b.name));

        setListAdapter(new ArrayAdapter<DesktopEntry>(this,
                android.R.layout.simple_list_item_1, mApps) {
            @Override
            public View getView(int position, View convertView, ViewGroup parent) {
                View view = super.getView(position, convertView, parent);
                DesktopEntry entry = mApps.get(position);
                TextView text = view.findViewById(android.R.id.text1);
                text.setText(entry.name);
                text.setCompoundDrawablePadding(24);

                if (entry.iconPath != null && entry.iconPath.endsWith(".png")) {
                    Bitmap bmp = BitmapFactory.decodeFile(entry.iconPath);
                    if (bmp != null) {
                        Bitmap scaled = Bitmap.createScaledBitmap(bmp, 72, 72, true);
                        android.graphics.drawable.BitmapDrawable d =
                                new android.graphics.drawable.BitmapDrawable(getResources(), scaled);
                        text.setCompoundDrawablesRelativeWithIntrinsicBounds(d, null, null, null);
                    }
                }

                return view;
            }
        });

        Log.i(TAG, "Found " + mApps.size() + " apps in " + appsDir);
    }

    private DesktopEntry parseDesktopEntry(File file, String chrootPath) {
        DesktopEntry entry = new DesktopEntry();
        entry.desktopFile = file.getAbsolutePath();
        boolean inDesktopEntry = false;

        try (BufferedReader reader = new BufferedReader(new FileReader(file))) {
            String line;
            while ((line = reader.readLine()) != null) {
                line = line.trim();
                if (line.equals("[Desktop Entry]")) {
                    inDesktopEntry = true;
                    continue;
                }
                if (line.startsWith("[") && line.endsWith("]")) {
                    inDesktopEntry = false;
                    continue;
                }
                if (!inDesktopEntry) continue;

                if (line.startsWith("Name=")) {
                    entry.name = line.substring(5);
                } else if (line.startsWith("Exec=")) {
                    // Strip field codes (%f, %u, etc.)
                    entry.exec = line.substring(5).replaceAll("%[fFuUdDnNickvm]", "").trim();
                } else if (line.startsWith("Icon=")) {
                    entry.iconName = line.substring(5);
                } else if (line.startsWith("NoDisplay=true")) {
                    entry.noDisplay = true;
                } else if (line.startsWith("Type=") && !line.equals("Type=Application")) {
                    return null; // Only show applications
                } else if (line.startsWith("Terminal=true")) {
                    entry.terminal = true;
                }
            }
        } catch (IOException e) {
            return null;
        }

        if (entry.name == null) {
            entry.name = file.getName().replace(".desktop", "");
        }

        if (entry.iconName != null) {
            entry.iconPath = resolveIconPath(chrootPath, entry.iconName);
        }

        return entry;
    }

    private String resolveIconPath(String chrootPath, String iconName) {
        if (iconName.startsWith("/")) {
            return chrootPath + iconName;
        }

        String[] sizes = {"48x48", "64x64", "128x128", "scalable"};
        String[] themes = {"hicolor", "Adwaita"};
        String[] categories = {"apps", "categories", "mimetypes"};
        String[] exts = {".png", ".svg", ".xpm"};

        for (String theme : themes) {
            for (String size : sizes) {
                for (String cat : categories) {
                    for (String ext : exts) {
                        String path = chrootPath + "/usr/share/icons/" + theme + "/"
                                + size + "/" + cat + "/" + iconName + ext;
                        if (new File(path).exists()) return path;
                    }
                }
            }
        }

        for (String ext : exts) {
            String path = chrootPath + "/usr/share/pixmaps/" + iconName + ext;
            if (new File(path).exists()) return path;
        }

        return null;
    }

    private void launchApp(DesktopEntry entry) {
        String chrootPath = WaylandConfig.getChrootPath(this);
        String exec = entry.exec;

        if (entry.terminal) {
            exec = "foot -e " + exec;
        }

        Log.i(TAG, "Launching: " + entry.name + " exec=" + exec);
        Toast.makeText(this, "Launching " + entry.name + "...", Toast.LENGTH_SHORT).show();

        final String cmd = exec;
        new Thread(() -> {
            try {
                String fullCmd = "chroot " + chrootPath + " /usr/bin/env"
                    + " PATH=/usr/bin:/bin:/usr/sbin:/sbin"
                    + " HOME=/root"
                    + " SHELL=/usr/bin/bash"
                    + " XDG_RUNTIME_DIR=/run/wayland"
                    + " WAYLAND_DISPLAY=wayland-0"
                    + " LANG=C.UTF-8"
                    + " TERM=xterm-256color"
                    + " " + cmd;
                Log.i(TAG, "Full command: su 0 sh -c '" + fullCmd + "'");
                // Don't use & — the su daemon keeps the process alive.
                // This thread blocks until the app exits, which is fine.
                Process p = Runtime.getRuntime().exec(new String[]{
                    "su", "0", "sh", "-c", fullCmd
                });
                p.waitFor();
            } catch (IOException | InterruptedException e) {
                Log.e(TAG, "Failed to launch " + entry.name, e);
            }
        }).start();
    }

    static class DesktopEntry {
        String name;
        String exec;
        String iconName;
        String iconPath;
        String desktopFile;
        boolean noDisplay;
        boolean terminal;

        @Override
        public String toString() {
            return name;
        }
    }
}
