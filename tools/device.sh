#!/usr/bin/env bash
# Device automation helpers for N200 (dre) wayland testing
set -euo pipefail

DEVICE_SERIAL="${DEVICE_SERIAL:-504c0476}"
SCREENSHOT_DIR="/tmp/dre-screenshots"
DEVICE_TMP="/data/local/tmp"

adb_cmd() { adb -s "$DEVICE_SERIAL" "$@"; }
adb_sh() { adb_cmd shell "$@"; }

mkdir -p "$SCREENSHOT_DIR"

case "${1:-help}" in
    screenshot|ss)
        # Take screenshot, pull it, optionally convert to a viewable format
        local_name="${2:-screen_$(date +%s)}"
        adb_sh screencap -p "/data/local/tmp/ss.png"
        adb_cmd pull "/data/local/tmp/ss.png" "$SCREENSHOT_DIR/${local_name}.png" 2>/dev/null
        echo "$SCREENSHOT_DIR/${local_name}.png"
        ;;

    tap)
        # Send tap at x,y
        adb_sh input tap "${2:?x}" "${3:?y}"
        ;;

    swipe)
        # Send swipe from x1,y1 to x2,y2 over duration_ms
        adb_sh input swipe "${2:?x1}" "${3:?y1}" "${4:?x2}" "${5:?y2}" "${6:-300}"
        ;;

    key)
        # Send keyevent (e.g., KEYCODE_HOME, KEYCODE_POWER, KEYCODE_WAKEUP)
        adb_sh input keyevent "${2:?keycode}"
        ;;

    text)
        # Type text
        adb_sh input text "${2:?text}"
        ;;

    wake)
        # Wake up the device and unlock (swipe up)
        adb_sh input keyevent KEYCODE_WAKEUP
        sleep 0.5
        # Swipe up to unlock (assuming standard lock screen)
        adb_sh input swipe 540 1800 540 800 300
        ;;

    screen-state)
        # Check if screen is on
        adb_sh "dumpsys power | grep 'Display Power' | head -1"
        ;;

    resolution)
        adb_sh wm size
        ;;

    push-sf)
        # Push rebuilt surfaceflinger to device
        local sf_path="${2:-/home/psyc/projects/lineage/out/target/product/dre/system/bin/surfaceflinger}"
        adb_cmd root
        sleep 1
        adb_cmd remount
        sleep 1
        adb_cmd push "$sf_path" /system/bin/surfaceflinger
        adb_sh chmod 755 /system/bin/surfaceflinger
        echo "Pushed surfaceflinger. Restart with: $0 restart-sf"
        ;;

    restart-sf)
        # Restart surfaceflinger (will restart the whole UI)
        adb_cmd root
        sleep 0.5
        adb_sh "stop && start"
        echo "Framework restarting..."
        sleep 10
        echo "Waiting for boot..."
        adb_cmd wait-for-device
        sleep 5
        adb_sh getprop sys.boot_completed
        ;;

    check-wayland)
        # Check if wayland socket exists and surfaceflinger has wayland
        echo "=== Wayland socket ==="
        adb_sh "ls -la /data/wayland/ 2>/dev/null || echo 'No /data/wayland directory'"
        echo ""
        echo "=== SF wayland strings ==="
        adb_sh "strings /system/bin/surfaceflinger | grep -i wayland | head -10"
        echo ""
        echo "=== SF process ==="
        adb_sh "ps -A | grep surfaceflinger"
        echo ""
        echo "=== Logcat wayland ==="
        adb_sh "logcat -d -t 50 | grep -i wayland || echo 'No wayland logs'"
        ;;

    logcat-wayland)
        # Stream wayland-related logcat
        adb_sh "logcat | grep -iE 'wayland|wl_|compositor'"
        ;;

    push-test-client)
        # Push wayland test clients to device
        local out="/home/psyc/projects/lineage/out/target/product/dre"
        for bin in wayland_egl_test wayland_shm_test; do
            local path="$out/system/bin/$bin"
            if [ -f "$path" ]; then
                adb_cmd push "$path" "/data/local/tmp/$bin"
                adb_sh chmod 755 "/data/local/tmp/$bin"
                echo "Pushed $bin"
            else
                # Try vendor or other locations
                find "$out" -name "$bin" -type f 2>/dev/null | head -1 | while read -r f; do
                    adb_cmd push "$f" "/data/local/tmp/$bin"
                    adb_sh chmod 755 "/data/local/tmp/$bin"
                    echo "Pushed $bin from $f"
                done
            fi
        done
        ;;

    run-shm-test)
        # Run the SHM wayland test client
        adb_cmd root
        sleep 0.5
        adb_sh "XDG_RUNTIME_DIR=/data/wayland WAYLAND_DISPLAY=wayland-0 /data/local/tmp/wayland_shm_test" &
        echo "SHM test client started (PID: $!)"
        ;;

    run-egl-test)
        # Run the EGL wayland test client
        adb_cmd root
        sleep 0.5
        adb_sh "XDG_RUNTIME_DIR=/data/wayland WAYLAND_DISPLAY=wayland-0 /data/local/tmp/wayland_egl_test" &
        echo "EGL test client started (PID: $!)"
        ;;

    kill-test)
        # Kill wayland test clients
        adb_sh "pkill -f wayland_.*_test 2>/dev/null || echo 'No test clients running'"
        ;;

    props)
        # Show relevant system properties
        adb_sh "getprop ro.build.display.id"
        adb_sh "getprop ro.lineage.version"
        adb_sh "getprop ro.build.version.sdk"
        adb_sh "getprop sys.boot_completed"
        ;;

    full-test)
        # Full automated test sequence
        echo "=== Full Wayland Test Sequence ==="
        echo ""
        echo "1. Checking device state..."
        "$0" props
        echo ""
        echo "2. Checking wayland..."
        "$0" check-wayland
        echo ""
        echo "3. Taking baseline screenshot..."
        "$0" screenshot baseline
        echo ""
        echo "4. Running SHM test client..."
        "$0" run-shm-test
        sleep 3
        echo ""
        echo "5. Taking test screenshot..."
        "$0" screenshot after_shm_test
        echo ""
        echo "6. Killing test client..."
        "$0" kill-test
        echo ""
        echo "=== Done ==="
        ;;

    chroot|ch)
        # Run a command inside the Arch chroot (or open interactive shell)
        # Wayland env vars come from /etc/profile.d/wayland.sh via login shell
        shift
        adb_sh "sh /data/arch-mount.sh" >/dev/null 2>&1 || true
        if [ $# -eq 0 ]; then
            adb_sh "sh /data/arch-enter.sh"
        else
            adb_cmd shell "chroot /data/arch /usr/bin/env \
                HOME=/root PATH=/usr/bin:/bin:/usr/sbin:/sbin \
                /bin/bash -lc '$*'"
        fi
        ;;

    push-bar)
        # Push sample layer-shell bar to chroot
        SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
        adb_cmd push "$SCRIPT_DIR/sample-layer-bar.py" /data/arch/root/sample-layer-bar.py
        adb_cmd push "$SCRIPT_DIR/sample-layer-bar.desktop" /data/arch/usr/share/applications/sample-layer-bar.desktop
        echo "Pushed sample bar. Launch from Linux Apps or: $0 chroot python3 /root/sample-layer-bar.py"
        ;;

    help|*)
        echo "Usage: $0 <command> [args...]"
        echo ""
        echo "Commands:"
        echo "  screenshot [name]     Take and pull screenshot"
        echo "  tap <x> <y>          Send tap"
        echo "  swipe <x1> <y1> <x2> <y2> [ms]  Send swipe"
        echo "  key <keycode>        Send keyevent"
        echo "  text <string>        Type text"
        echo "  wake                 Wake + unlock device"
        echo "  screen-state         Check screen power"
        echo "  resolution           Get screen resolution"
        echo "  push-sf [path]       Push surfaceflinger binary"
        echo "  restart-sf           Restart framework"
        echo "  check-wayland        Check wayland status"
        echo "  logcat-wayland       Stream wayland logs"
        echo "  push-test-client     Push test client binaries"
        echo "  run-shm-test         Run SHM test client"
        echo "  run-egl-test         Run EGL test client"
        echo "  kill-test            Kill test clients"
        echo "  props                Show build properties"
        echo "  full-test            Run full test sequence"
        echo "  chroot [cmd]         Run command in Arch chroot (or interactive shell)"
        ;;
esac
