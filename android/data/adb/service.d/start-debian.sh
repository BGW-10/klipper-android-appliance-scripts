#!/system/bin/sh

LOG=/data/local/tmp/start-debian.log

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"
}

while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 2
done

sleep 5

CHROOT_DISTRO="$(command -v chroot-distro)"
DISTRO=debian-trixie

log "Mounting Debian"

"$CHROOT_DISTRO" mount "$DISTRO" >>"$LOG" 2>&1

log "Starting Debian service supervisor"

"$CHROOT_DISTRO" command "$DISTRO" \
    "/usr/local/bin/start-services" >>"$LOG" 2>&1 &

log "Startup complete"
