#!/system/bin/sh

LOG=/data/local/tmp/start-debian.log

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"
}

log "Waiting for Android boot"

while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 2
done

sleep 5

log "Starting Debian"

CHROOT_DISTRO=/data/adb/modules/chroot-distro/system/bin/chroot-distro
DISTRO=debian-trixie

"$CHROOT_DISTRO" mount "$DISTRO" >>"$LOG" 2>&1

log "Debian mounted"

"$CHROOT_DISTRO" exec "$DISTRO" -- \
    /usr/local/bin/start-services >>"$LOG" 2>&1 &

log "Debian service supervisor started"
