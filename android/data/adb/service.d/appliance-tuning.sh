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
    if [ -x "$IW" ] && [ -d /sys/class/net/wlan0 ]; then
        if "$IW" dev wlan0 set power_save off >/dev/null 2>&1; then
            log "Wi-Fi power save disabled"
        fi
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

#
# Reapply Wi-Fi setting only when wlan0 changes state.
#
if command -v ip >/dev/null 2>&1; then
    (
        ip monitor link dev wlan0 2>/dev/null | while read -r event; do
            log "Wi-Fi link event: $event"

            # Give Android/driver initialization a moment to settle.
            sleep 1

            disable_wifi_power_save
        done
    ) &
fi

log "Appliance tuning complete"
