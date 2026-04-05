#!/usr/bin/env python3
"""
Rockwell Retroturboencabulator Mark II - Diagnostic Interface

A totally legitimate piece of industrial monitoring software for the
turbo-encabulator's prefamulated amulite baseplate and spurving bearings.
"""

import gi, math, sys, os
gi.require_version('Gtk', '4.0')
from gi.repository import Gtk, GLib, Gdk, Pango


class EncabulatorGauge(Gtk.DrawingArea):
    """A sweeping analog gauge."""
    def __init__(self, label, unit, min_val, max_val, warn_frac=0.75):
        super().__init__()
        self.label = label
        self.unit = unit
        self.min_val = min_val
        self.max_val = max_val
        self.warn_frac = warn_frac
        self.value = min_val
        self.target = min_val
        self.set_content_width(220)
        self.set_content_height(170)
        self.set_draw_func(self._draw)
        self.set_hexpand(True)

    def _draw(self, area, cr, w, h):
        cx, cy = w / 2, h * 0.78
        radius = min(w, h) * 0.40

        cr.set_line_width(10)
        cr.set_source_rgba(0.3, 0.3, 0.35, 1)
        cr.arc(cx, cy, radius, math.pi * 1.15, math.pi * -0.15)
        cr.stroke()

        warn_angle = math.pi * 1.15 + (math.pi * -0.15 - math.pi * 1.15) * self.warn_frac
        cr.set_source_rgba(0.9, 0.3, 0.2, 0.5)
        cr.arc(cx, cy, radius, warn_angle, math.pi * -0.15)
        cr.stroke()

        frac = (self.value - self.min_val) / max(self.max_val - self.min_val, 1)
        frac = max(0, min(1, frac))
        val_angle = math.pi * 1.15 + (math.pi * -0.15 - math.pi * 1.15) * frac
        if frac > self.warn_frac:
            cr.set_source_rgba(0.95, 0.3, 0.15, 1)
        else:
            cr.set_source_rgba(0.2, 0.8, 0.4, 1)
        cr.set_line_width(10)
        cr.arc(cx, cy, radius, math.pi * 1.15, val_angle)
        cr.stroke()

        # Needle
        cr.set_source_rgba(0.95, 0.95, 0.95, 1)
        cr.set_line_width(2.5)
        nx = cx + (radius - 18) * math.cos(val_angle)
        ny = cy + (radius - 18) * math.sin(val_angle)
        cr.move_to(cx, cy)
        cr.line_to(nx, ny)
        cr.stroke()
        cr.arc(cx, cy, 5, 0, math.pi * 2)
        cr.fill()

        # Value text
        cr.set_source_rgba(1, 1, 1, 1)
        cr.select_font_face("monospace", 0, 1)
        cr.set_font_size(22)
        val_str = f"{self.value:.1f}"
        ext = cr.text_extents(val_str)
        cr.move_to(cx - ext.width / 2, cy - 16)
        cr.show_text(val_str)

        # Unit
        cr.set_font_size(12)
        ext = cr.text_extents(self.unit)
        cr.move_to(cx - ext.width / 2, cy + 2)
        cr.show_text(self.unit)

        # Label
        cr.set_source_rgba(0.7, 0.7, 0.75, 1)
        cr.set_font_size(13)
        ext = cr.text_extents(self.label)
        cr.move_to(cx - ext.width / 2, h - 4)
        cr.show_text(self.label)


class WaveformDisplay(Gtk.DrawingArea):
    """Scrolling waveform trace."""
    def __init__(self, label, color=(0.2, 0.9, 0.4)):
        super().__init__()
        self.label = label
        self.color = color
        self.data = [0.0] * 200
        self.set_content_height(90)
        self.set_hexpand(True)
        self.set_draw_func(self._draw)

    def push(self, val):
        self.data.append(val)
        if len(self.data) > 200:
            self.data.pop(0)

    def _draw(self, area, cr, w, h):
        cr.set_source_rgba(0.06, 0.06, 0.10, 1)
        cr.rectangle(0, 0, w, h)
        cr.fill()

        cr.set_source_rgba(0.18, 0.18, 0.22, 1)
        cr.set_line_width(0.5)
        for i in range(1, 4):
            y = h * i / 4
            cr.move_to(0, y); cr.line_to(w, y); cr.stroke()
        for i in range(1, 10):
            x = w * i / 10
            cr.move_to(x, 0); cr.line_to(x, h); cr.stroke()

        # Label
        cr.set_source_rgba(0.45, 0.45, 0.5, 1)
        cr.select_font_face("sans-serif", 0, 0)
        cr.set_font_size(11)
        cr.move_to(6, 14)
        cr.show_text(self.label)

        if len(self.data) < 2:
            return
        cr.set_source_rgba(*self.color, 1)
        cr.set_line_width(2)
        n = len(self.data)
        for i, val in enumerate(self.data):
            x = w * i / (n - 1)
            y = h * (1 - max(0, min(1, val)))
            if i == 0:
                cr.move_to(x, y)
            else:
                cr.line_to(x, y)
        cr.stroke()


class StatusLED(Gtk.DrawingArea):
    """A small round status LED."""
    def __init__(self, color=(0.2, 0.9, 0.3)):
        super().__init__()
        self.color = color
        self.on = True
        self.set_content_width(20)
        self.set_content_height(20)
        self.set_draw_func(self._draw)

    def _draw(self, area, cr, w, h):
        cx, cy = w / 2, h / 2
        r = min(w, h) / 2 - 1
        if self.on:
            cr.set_source_rgba(*self.color, 1)
        else:
            cr.set_source_rgba(0.25, 0.25, 0.25, 1)
        cr.arc(cx, cy, r, 0, math.pi * 2)
        cr.fill()
        if self.on:
            cr.set_source_rgba(1, 1, 1, 0.35)
            cr.arc(cx - r * 0.2, cy - r * 0.2, r * 0.35, 0, math.pi * 2)
            cr.fill()


class EncabulatorWindow(Gtk.ApplicationWindow):
    def __init__(self, **kwargs):
        super().__init__(**kwargs, title="Retroturboencabulator Mk.II")
        self.set_default_size(540, 900)
        self.t = 0

        css = Gtk.CssProvider()
        css.load_from_string("""
            window { background-color: #151520; }
            label { color: #c8c8d0; }
            .header { font-size: 20px; font-weight: bold; color: #e0e0f0;
                       letter-spacing: 1px; }
            .path-label { font-size: 14px; color: #60ff80; font-family: monospace;
                          font-weight: bold; }
            .section { font-size: 13px; font-weight: bold; color: #8888a0;
                       letter-spacing: 2px; }
            .readout-name { color: #707088; font-size: 12px; }
            .readout-val { font-family: monospace; font-size: 18px; color: #40e060; }
            .readout-warn { font-family: monospace; font-size: 18px; color: #ff5030; }
            .led-label { color: #909098; font-size: 13px; }
            .ctrl-label { color: #707088; font-size: 12px; }
            .uptime { color: #505068; font-size: 12px; font-family: monospace; }
            separator { background-color: #2a2a38; min-height: 1px; }
            progressbar trough { min-height: 10px; background-color: #252530; border-radius: 5px; }
            progressbar progress { min-height: 10px; background-color: #30a050; border-radius: 5px; }
            scale trough { min-height: 8px; background-color: #252530; border-radius: 4px; }
            scale highlight { background-color: #3080d0; border-radius: 4px; }
        """)
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        self.set_child(scroll)

        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        root.set_margin_top(16)
        root.set_margin_bottom(16)
        root.set_margin_start(16)
        root.set_margin_end(16)
        scroll.set_child(root)

        # Header
        title = Gtk.Label(label="RETROTURBOENCABULATOR Mk.II")
        title.add_css_class("header")
        root.append(title)

        subtitle = Gtk.Label(label="ROCKWELL AUTOMATION")
        subtitle.add_css_class("section")
        root.append(subtitle)

        # Render path indicator
        render_path = os.environ.get("ENCABULATOR_PATH", "unknown")
        path_label = Gtk.Label(label=f"[{render_path}]")
        path_label.add_css_class("path-label")
        root.append(path_label)

        root.append(Gtk.Separator())

        # Gauges — 3 across
        gauge_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4, homogeneous=True)
        root.append(gauge_box)

        self.gauge_amulite = EncabulatorGauge("Amulite Flux", "mWb", 0, 100)
        self.gauge_spurving = EncabulatorGauge("Spurving Load", "kPa", 0, 250, 0.8)
        self.gauge_dingle = EncabulatorGauge("Dingle Arm", "RPM", 0, 8000, 0.85)
        gauge_box.append(self.gauge_amulite)
        gauge_box.append(self.gauge_spurving)
        gauge_box.append(self.gauge_dingle)

        # Waveforms
        self.wave1 = WaveformDisplay("PANAMETRIC FAN", color=(0.3, 1.0, 0.5))
        self.wave2 = WaveformDisplay("MARZELVANE PHASE", color=(0.4, 0.7, 1.0))
        root.append(self.wave1)
        root.append(self.wave2)

        root.append(Gtk.Separator())

        # Status LEDs — 2 columns
        led_grid = Gtk.Grid(column_spacing=20, row_spacing=6)
        led_grid.set_margin_top(4)
        root.append(led_grid)

        self.leds = []
        status_items = [
            ("Prefamulated Baseplate", (0.2, 0.9, 0.3)),
            ("Logarithmic Casing", (0.2, 0.9, 0.3)),
            ("Tremie Pipe Seal", (0.9, 0.9, 0.2)),
            ("Diff. Girdlespring", (0.2, 0.9, 0.3)),
            ("Drawn Reciprocation", (0.2, 0.9, 0.3)),
            ("Stator Winding", (0.3, 0.5, 1.0)),
        ]
        for i, (name, color) in enumerate(status_items):
            led = StatusLED(color)
            self.leds.append(led)
            col = (i % 2) * 2
            row = i // 2
            led_grid.attach(led, col, row, 1, 1)
            lbl = Gtk.Label(label=name, xalign=0)
            lbl.add_css_class("led-label")
            led_grid.attach(lbl, col + 1, row, 1, 1)

        root.append(Gtk.Separator())

        # Readouts row
        readout_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8,
                              homogeneous=True)
        readout_box.set_margin_top(4)
        root.append(readout_box)

        self.readouts = []
        for name in ["Malleable\nCorrosion", "Sinusoidal\nDeplanaration", "Stator\nReluctance"]:
            vb = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2,
                         halign=Gtk.Align.CENTER)
            lbl = Gtk.Label(label=name, justify=Gtk.Justification.CENTER)
            lbl.add_css_class("readout-name")
            val = Gtk.Label(label="0.00")
            val.add_css_class("readout-val")
            vb.append(val)
            vb.append(lbl)
            readout_box.append(vb)
            self.readouts.append(val)

        root.append(Gtk.Separator())

        # Controls row
        ctrl_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=20)
        ctrl_box.set_margin_top(4)
        root.append(ctrl_box)

        # Switch
        sw_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4,
                         halign=Gtk.Align.CENTER)
        sw_lbl = Gtk.Label(label="Modial Interaction")
        sw_lbl.add_css_class("ctrl-label")
        self.modial_switch = Gtk.Switch(halign=Gtk.Align.CENTER)
        self.modial_switch.set_active(True)
        sw_box.append(sw_lbl)
        sw_box.append(self.modial_switch)
        ctrl_box.append(sw_box)

        # Slider
        sl_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        sl_box.set_hexpand(True)
        sl_lbl = Gtk.Label(label="Semiboloid Gain")
        sl_lbl.add_css_class("ctrl-label")
        self.gain_slider = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, 100, 1)
        self.gain_slider.set_value(63)
        sl_box.append(sl_lbl)
        sl_box.append(self.gain_slider)
        ctrl_box.append(sl_box)

        # Progress bar
        bar_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        bar_box.set_hexpand(True)
        bar_lbl = Gtk.Label(label="Cap. Duractance")
        bar_lbl.add_css_class("ctrl-label")
        self.progress = Gtk.ProgressBar()
        bar_box.append(bar_lbl)
        bar_box.append(self.progress)
        ctrl_box.append(bar_box)

        # Uptime
        self.uptime_label = Gtk.Label(label="UPTIME 0:00:00", halign=Gtk.Align.CENTER)
        self.uptime_label.add_css_class("uptime")
        self.uptime_label.set_margin_top(6)
        root.append(self.uptime_label)

        GLib.timeout_add(50, self._tick)  # ~20fps

    def _tick(self):
        self.t += 0.05
        gain = self.gain_slider.get_value() / 100.0
        modial = self.modial_switch.get_active()

        base_flux = 45 + 20 * math.sin(self.t * 0.7) + 5 * math.sin(self.t * 2.1)
        self.gauge_amulite.target = base_flux * (gain + 0.3)
        self.gauge_spurving.target = 120 + 60 * math.sin(self.t * 0.3) + 12 * math.sin(self.t * 1.7)
        self.gauge_dingle.target = (3500 + 1500 * math.sin(self.t * 0.5) + 400 * math.sin(self.t * 1.3)) * (1 if modial else 0.3)

        for g in [self.gauge_amulite, self.gauge_spurving, self.gauge_dingle]:
            g.value += (g.target - g.value) * 0.08
            g.queue_draw()

        w1 = 0.5 + 0.3 * math.sin(self.t * 2.3) * gain + 0.1 * math.sin(self.t * 7.1) + 0.06 * math.sin(self.t * 13.3)
        w2 = 0.5 + 0.25 * math.sin(self.t * 1.1 + 1.5) + 0.15 * math.cos(self.t * 3.7) + 0.05 * math.sin(self.t * 9.7)
        if not modial:
            w1 = 0.5 + 0.03 * math.sin(self.t * 5.0)
        self.wave1.push(w1)
        self.wave2.push(w2)
        self.wave1.queue_draw()
        self.wave2.queue_draw()

        for i, led in enumerate(self.leds):
            if i == 2:  # tremie pipe: slow blink
                led.on = math.sin(self.t * 3.0) > -0.3
            elif i == 5:  # stator: steady pulse
                led.on = (int(self.t * 2) % 2) == 0
            else:
                led.on = True
            led.queue_draw()

        vals = [
            12.7 + 3 * math.sin(self.t * 1.3) + 0.4 * math.sin(self.t * 4.1),
            0.042 + 0.01 * math.sin(self.t * 0.9) + 0.002 * math.sin(self.t * 3.3),
            187.3 + 40 * math.sin(self.t * 0.4) + 8 * math.sin(self.t * 1.9),
        ]
        fmts = ["{:.2f}", "{:.4f}", "{:.1f}"]
        units = [" ohm-cm", " Wb/m", " H"]
        for lbl, v, fmt, u in zip(self.readouts, vals, fmts, units):
            lbl.set_text(fmt.format(v) + u)
            is_warn = (v > 14.5) or (v > 210)
            lbl.remove_css_class("readout-warn" if not is_warn else "readout-val")
            lbl.add_css_class("readout-warn" if is_warn else "readout-val")

        self.progress.set_fraction(0.5 + 0.4 * math.sin(self.t * 0.6))

        s = int(self.t)
        self.uptime_label.set_text(f"UPTIME {s//3600}:{(s%3600)//60:02d}:{s%60:02d}")

        return True


app = Gtk.Application(application_id="org.rockwell.retroturboencabulator")
app.connect("activate", lambda a: EncabulatorWindow(application=a).present())
app.run(None)
