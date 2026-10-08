# OnePlus 5 Klipper Host Setup Guide

This guide documents the working path used to turn a OnePlus 5 into a rooted Android device capable of automatically mounting a Debian chroot and starting SSH at boot.

## 1. Prepare the OnePlus 5

### Install ADB and Fastboot on the PC

Download the current Android SDK Platform Tools from Google and extract them, for example to:

```text
C:\platform-tools
```

Open PowerShell in that directory and verify:

```powershell
.\adb.exe version
.\fastboot.exe --version
```

### Enable developer options

On the phone:

```text
Settings -> About phone -> tap Build number repeatedly
```

Then enable:

```text
Developer options -> OEM unlocking
Developer options -> USB debugging
```

Verify ADB:

```powershell
.\adb.exe devices -l
```

Accept the USB debugging prompt on the phone.

## 2. Unlock the bootloader

Reboot into fastboot:

```powershell
.\adb.exe reboot bootloader
```

Verify:

```powershell
.\fastboot.exe devices
```

Unlock:

```powershell
.\fastboot.exe oem unlock
```

Confirm on the phone. This wipes the device.

## 3. Install LineageOS

The phone was on OxygenOS 10.0.1 before flashing, which provided the required Android 10 firmware base.

Download the current LineageOS build and matching recovery for the OnePlus 5 (`cheeseburger`).

Place `recovery.img` in the platform-tools directory.

Re-enable USB debugging after the bootloader unlock reset, then:

```powershell
.\adb.exe reboot bootloader
.\fastboot.exe flash recovery recovery.img
```

Boot directly into Lineage Recovery.

In recovery:

```text
Factory Reset -> Format data / factory reset
Apply update -> Apply from ADB
```

Sideload LineageOS:

```powershell
.\adb.exe sideload .\lineage-22.2-YYYYMMDD-nightly-cheeseburger-signed.zip
```

After installation completes successfully, reboot into LineageOS and finish basic setup.

Re-enable USB debugging.

## 4. Root LineageOS with Magisk

Extract `boot.img` from the same LineageOS ZIP that was installed.

Push it to the phone:

```powershell
.\adb.exe push .\boot.img /sdcard/Download/
```

Install the current Magisk APK from the official Magisk GitHub releases.

In Magisk:

```text
Install -> Select and Patch a File
```

Choose:

```text
/storage/emulated/0/Download/boot.img
```

Pull the patched image back to the PC:

```powershell
.\adb.exe pull /sdcard/Download/magisk_patched-*.img .
```

Reboot to fastboot:

```powershell
.\adb.exe reboot bootloader
```

Flash the patched boot image:

```powershell
.\fastboot.exe flash boot .\magisk_patched-xxxxx.img
.\fastboot.exe reboot
```

Verify root:

```powershell
.\adb.exe shell
```

Then on the phone shell:

```sh
su
id
```

Expected:

```text
uid=0(root)
```

## 5. Install F-Droid and Termux

Install F-Droid from its official site.

Install Termux from F-Droid or the official Termux GitHub releases. Keep Termux and any Termux add-ons from the same source.

Open Termux and update packages:

```bash
pkg update
pkg upgrade -y
pkg install git curl wget nano -y
```

Verify root from Termux:

```bash
su
id
```

## 6. Install BusyBox for Android NDK

Install the current `BusyBox for Android NDK` Magisk module from its official release source.

In Magisk:

```text
Modules -> Install from storage
```

Install the module and reboot.

Verify in Termux:

```bash
su
busybox
```

## 7. Install chroot-distro

Use:

```text
Magisk-Modules-Alt-Repo/chroot-distro
```

Download the current release ZIP and install it through:

```text
Magisk -> Modules -> Install from storage
```

Reboot.

Verify:

```bash
su
chroot-distro help
chroot-distro list
```

## 8. Install Debian Trixie

A custom Debian Trixie ARM64 rootfs was used instead of the older built-in Debian presets.

Create a custom distro entry:

```bash
chroot-distro add debian-trixie
```

Use an ARM64 Debian Trixie `rootfs.tar.xz` from the Linux Containers image server:

```text
Debian -> trixie -> arm64 -> default -> latest build -> rootfs.tar.xz
```

Download it into the distro entry:

```bash
chroot-distro download debian-trixie <ARM64_TRIXIE_ROOTFS_URL>
```

Install:

```bash
chroot-distro install debian-trixie
```

Enter Debian:

```bash
chroot-distro login debian-trixie
```

Verify:

```bash
cat /etc/os-release
uname -m
whoami
```

Expected architecture:

```text
aarch64
```

## 9. Fix Android fscrypt/PAM keyring issues

The Debian PAM configuration contained `pam_keyinit.so force revoke`, which broke access to the Android-encrypted `/data` backing store in some sessions.

From Android root, inspect all PAM files in the Debian rootfs and comment every active line containing:

```text
pam_keyinit.so
```

Typical affected files include:

```text
/etc/pam.d/su-l
/etc/pam.d/login
/etc/pam.d/runuser-l
/etc/pam.d/sshd
/etc/pam.d/sudo
/etc/pam.d/sudo-i
/etc/pam.d/common-session
/etc/pam.d/common-session-noninteractive
```

Example edit from Termux root using nano:

```bash
/data/data/com.termux/files/usr/bin/nano /data/local/chroot-distro/debian-trixie/etc/pam.d/su-l
```

Change lines such as:

```text
session optional pam_keyinit.so force revoke
```

to:

```text
# session optional pam_keyinit.so force revoke
```

After editing, fully remount the chroot:

```bash
chroot-distro unmount debian-trixie
chroot-distro login debian-trixie
```

Test filesystem writes:

```bash
touch /etc/testfile
rm /etc/testfile
```

## 10. Fix Android network permissions inside Debian

Create Android networking groups inside Debian:

```bash
groupadd -g 3003 aid_inet
groupadd -g 3004 aid_net_raw
```

Add root and the future Klipper user:

```bash
usermod -aG aid_inet,aid_net_raw root
```

After creating the `klipper` user later, also run:

```bash
usermod -aG aid_inet,aid_net_raw klipper
```

APT drops privileges to `_apt`, so make `aid_inet` its primary group:

```bash
usermod -g aid_inet _apt
```

Verify:

```bash
id _apt
```

The primary GID should be `3003(aid_inet)`.

Test networking:

```bash
ping -4 -c 3 1.1.1.1
ping -4 -c 3 deb.debian.org
apt update
```

## 11. Update Debian and install baseline packages

```bash
apt update
apt full-upgrade -y
```

Install the required tools:

```bash
apt install -y \
  sudo \
  git \
  curl \
  wget \
  nano \
  ca-certificates \
  openssh-server \
  usbutils \
  iproute2 \
  procps \
  locales \
  less
```

## 12. Create the Klipper user

```bash
adduser klipper
usermod -aG sudo klipper
usermod -aG aid_inet,aid_net_raw klipper
```

Verify:

```bash
id klipper
```

## 13. Configure SSH

Generate SSH host keys and runtime directory:

```bash
ssh-keygen -A
mkdir -p /run/sshd
chown root:root /run/sshd
chmod 0755 /run/sshd
```

Edit:

```bash
nano /etc/ssh/sshd_config
```

For this Android chroot, disable PAM to avoid the fscrypt keyring issue:

```text
UsePAM no
```

Ensure password login is enabled while testing:

```text
PasswordAuthentication yes
```

Validate SSH configuration:

```bash
/usr/sbin/sshd -t
```

Start SSH:

```bash
/usr/sbin/sshd
```

Verify:

```bash
ss -ltnp | grep ':22'
```

From the PC:

```powershell
ssh klipper@PHONE_IP
```

Test:

```bash
whoami
sudo whoami
```

## 14. Start Debian and SSH automatically on phone boot

Use a Magisk `service.d` script.

From Termux root:

```bash
su
mkdir -p /data/adb/service.d
nano /data/adb/service.d/start-debian.sh
```

First determine the exact executable path:

```bash
command -v chroot-distro
```

Use that path in the script.

Example:

```sh
#!/system/bin/sh

LOG=/data/local/tmp/start-debian.log
exec >>"$LOG" 2>&1

echo "=== Starting Debian at $(date) ==="

while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 2
done

sleep 5

CHROOT_DISTRO=/YOUR/ACTUAL/PATH/chroot-distro

"$CHROOT_DISTRO" mount debian-trixie

"$CHROOT_DISTRO" command debian-trixie \
    "rm -rf /run/sshd && \
     mkdir -p /run/sshd && \
     chown root:root /run/sshd && \
     chmod 0755 /run/sshd && \
     /usr/sbin/sshd -t && \
     /usr/sbin/sshd"

echo "Finished at $(date)"
```

Make it executable:

```bash
chmod 755 /data/adb/service.d/start-debian.sh
```

Test manually:

```bash
/data/adb/service.d/start-debian.sh
```

Check SSH:

```bash
ps -A | grep sshd
```

Reboot:

```bash
reboot
```

After Android finishes booting, Debian should be mounted and SSH should be running automatically.

If needed, inspect the boot log:

```bash
cat /data/local/tmp/start-debian.log
```

## 15. Verify final state

After a clean phone reboot, without opening Termux manually:

```powershell
ssh klipper@PHONE_IP
```

Inside Debian:

```bash
cat /etc/os-release
uname -m
apt update
lsusb
```

At this point the phone is ready for the next phase: USB/UART integration and Klipper/Moonraker/Mainsail installation.
