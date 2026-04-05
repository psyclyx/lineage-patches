#!/usr/bin/env python3
"""Sample layer-shell status bar for testing zwlr_layer_shell_v1."""

import gi, time, subprocess, threading
gi.require_version('Gtk', '3.0')
gi.require_version('GtkLayerShell', '0.1')
from gi.repository import Gtk, Gdk, GtkLayerShell, GLib, Pango

BAR_HEIGHT = 48

class LayerBar(Gtk.Window):
    def __init__(self):
        super().__init__()

        GtkLayerShell.init_for_window(self)
        GtkLayerShell.set_layer(self, GtkLayerShell.Layer.TOP)
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.TOP, True)
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.LEFT, True)
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.RIGHT, True)
        GtkLayerShell.set_exclusive_zone(self, BAR_HEIGHT)
        GtkLayerShell.set_namespace(self, "sample-bar")

        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        box.set_size_request(-1, BAR_HEIGHT)

        # Left: title
        self.title_label = Gtk.Label(label="Linux Shell")
        self.title_label.modify_font(Pango.FontDescription("Sans Bold 14"))
        self.title_label.modify_fg(Gtk.StateFlags.NORMAL, Gdk.color_parse("white"))
        box.pack_start(self.title_label, False, False, 16)

        # Center: clock
        self.clock_label = Gtk.Label()
        self.clock_label.modify_font(Pango.FontDescription("Sans 13"))
        self.clock_label.modify_fg(Gtk.StateFlags.NORMAL, Gdk.color_parse("white"))
        box.set_center_widget(self.clock_label)

        # Right: battery
        self.battery_label = Gtk.Label()
        self.battery_label.modify_font(Pango.FontDescription("Sans 13"))
        self.battery_label.modify_fg(Gtk.StateFlags.NORMAL, Gdk.color_parse("white"))
        box.pack_end(self.battery_label, False, False, 16)

        # Style the background
        self.override_background_color(
            Gtk.StateFlags.NORMAL, Gdk.RGBA(0.12, 0.12, 0.18, 0.92))

        self.add(box)
        self.update_clock()
        self.update_battery()
        GLib.timeout_add_seconds(1, self.update_clock)
        GLib.timeout_add_seconds(30, self.update_battery)

    def update_clock(self):
        self.clock_label.set_text(time.strftime("%H:%M:%S"))
        return True

    def update_battery(self):
        try:
            with open("/sys/class/power_supply/battery/capacity") as f:
                pct = f.read().strip()
            with open("/sys/class/power_supply/battery/status") as f:
                status = f.read().strip()
            icon = "⚡" if status == "Charging" else "🔋"
            self.battery_label.set_text(f"{icon} {pct}%")
        except Exception:
            self.battery_label.set_text("")
        return True


if __name__ == "__main__":
    Gtk.init([])
    if not GtkLayerShell.is_supported():
        print("ERROR: layer-shell not supported by compositor")
        raise SystemExit(1)

    bar = LayerBar()
    bar.show_all()
    bar.connect("destroy", Gtk.main_quit)
    Gtk.main()
