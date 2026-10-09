#!/system/bin/sh

#
# OnePlus 5 / LineageOS appliance tuning
#
# Intended to run from Magisk service.d.
#

LOG=/data/local/tmp/appliance-tuning.log
IW=/system/bin/iw

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"
}

disable_wifi_power_save() {
    if [ ! -x "$IW" ] || [ ! -d /sys/class/net/wlan0 ]; then
        return 1
    fi

    if "$IW" dev wlan0 set power_save off >/dev/null 2>&1; then
        state=$("$IW" dev wlan0 get power_save 2>/dev/null)
        case "$state" in
            *"Power save: off"*)
                log "Wi-Fi power save disabled"
                return 0
                ;;
            *)
                log "WARNING: Wi-Fi power save state: ${state:-unknown}"
                return 1
                ;;
        esac
    else
        log "WARNING: Failed to set Wi-Fi power save OFF"
        return 1
    fi
}

log "Starting appliance tuning"

#
# Wait until Android has completed booting.
#
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 2
done

sleep 5

#
# Disable Android Doze / device idle.
#
cmd deviceidle disable >/dev/null 2>&1 || \
    dumpsys deviceidle disable >/dev/null 2>&1 || true

log "Device idle / Doze disabled"

#
# Disable Battery Saver and automatic low-power triggering.
#
cmd power set-mode 0 >/dev/null 2>&1 || true
settings put global low_power_trigger_level 0 >/dev/null 2>&1 || true

log "Battery Saver disabled"

#
# Disable global USB autosuspend.
#
if [ -w /sys/module/usbcore/parameters/autosuspend ]; then
    echo -1 > /sys/module/usbcore/parameters/autosuspend
    log "USB autosuspend disabled"
fi

#
# Keep currently attached USB devices awake.
#
for control in /sys/bus/usb/devices/*/power/control; do
    [ -w "$control" ] || continue
    echo on > "$control" 2>/dev/null || true
done

#
# Disable Wi-Fi power saving initially.
#
disable_wifi_power_save

# Monitor wlan0 and reapply Wi-Fi power-save setting when it reaches state UP.
(
    while true; do
        log "Starting wlan0 link monitor"

        /system/bin/ip monitor link dev wlan0 2>&1 |
        while IFS= read -r event; do
            case "$event" in
                *"state UP"*)
                    log "wlan0 reached state UP; checking Wi-Fi power save"
                    sleep 2
                    disable_wifi_power_save
                    ;;
            esac
        done

        log "Wi-Fi link monitor exited; restarting in 5 seconds"
        sleep 5
    done
) &

log "Appliance tuning complete"
