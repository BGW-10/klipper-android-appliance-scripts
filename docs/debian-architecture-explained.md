# How the OnePlus 5 Debian Setup Works

## Overview

The OnePlus 5 is still running Android, but we added a real Debian userspace alongside it. Debian is not running in a virtual machine and is not being CPU-emulated. It uses the phone's actual Linux kernel directly.

The final system looks roughly like this:

```text
OnePlus 5 hardware
│
├── Snapdragon 835 CPU / RAM / USB / Wi-Fi / display
│
└── Linux kernel used by LineageOS
    │
    ├── LineageOS / Android userspace
    │   ├── Android framework
    │   ├── touchscreen/display handling
    │   ├── Wi-Fi / USB framework
    │   ├── Termux
    │   └── Magisk
    │
    └── Debian chroot
        ├── Debian Trixie ARM64 userspace
        ├── normal Linux filesystem tree
        ├── apt
        ├── OpenSSH server
        └── future Klipper / Moonraker / Mainsail
```

The most important idea is that Android and Debian **share the same kernel**.

## 1. Why LineageOS?

The phone originally ran OxygenOS. LineageOS gives us a cleaner, current Android base with less vendor software and good support for an older device.

We kept Android because it already provides excellent support for:

- touchscreen
- display
- Wi-Fi
- charging and battery handling
- USB OTG
- Android apps
- future kiosk/browser UI

Instead of replacing Android completely, we use it as the hardware-management layer and add Debian for the Linux server side.

## 2. Why unlock the bootloader?

The stock bootloader only allows trusted vendor software to boot.

Unlocking it lets us flash modified boot and recovery images. That was required for:

- LineageOS recovery
- LineageOS itself
- the Magisk-patched boot image

Unlocking the bootloader does not itself provide root. It only gives us permission to flash software that can.

## 3. What Magisk does

Magisk gives Android root access while modifying the boot environment rather than permanently rewriting the Android system partition.

For this project, Magisk gives us two key capabilities:

### Root access

Commands such as:

```bash
su
```

can become:

```text
uid=0(root)
```

Root is necessary because a real Linux `chroot` requires privileged kernel operations such as mounts and namespace-related filesystem setup.

### Boot-time scripts

Magisk supports scripts under:

```text
/data/adb/service.d/
```

These scripts run automatically after Android boots.

We use this to mount Debian and start `sshd`, so the phone behaves like an embedded Linux appliance without needing to manually open Termux.

## 4. What Termux does

Termux is mainly our Android-side maintenance shell.

It provides a convenient terminal and Android-native command-line tools. In this setup, Termux is **not** what runs Debian and is not in the performance path for Klipper.

We mainly use it to do things like:

```bash
su
chroot-distro login debian-trixie
```

Once Debian services are running, Termux can be completely idle.

## 5. What BusyBox does

BusyBox provides a large collection of standard Unix utilities in one small package.

The Android environment does not include every conventional Linux command expected by shell scripts. `chroot-distro` uses BusyBox for low-level operations needed to prepare and manage the chroot.

The BusyBox Magisk module makes these utilities available in the rooted Android environment.

## 6. What chroot-distro does

`chroot-distro` is the component that manages the Debian filesystem and mounts.

A `chroot` changes what a process sees as `/`.

For example, Android may have:

```text
/
/system
/data
/vendor
```

while Debian sees:

```text
/
/etc
/usr
/var
/home
```

The Debian root filesystem physically lives under Android storage, roughly under:

```text
/data/local/chroot-distro/
```

but when a process is launched through the chroot, that Debian directory becomes its `/`.

`chroot-distro` also handles the important bind mounts that make Debian useful:

```text
/dev
/proc
/sys
/dev/pts
```

These are not fake copies. They expose the running Android kernel's real devices, process information, and kernel interfaces into Debian.

This is why Debian can run tools such as:

```bash
lsusb
ip addr
ps
```

and see the phone's real hardware and kernel state.

## 7. Why this has native performance

There is no virtual CPU and no guest kernel.

A Debian ARM64 process runs directly as an ARM64 process on the Snapdragon 835.

Conceptually:

```text
Debian process
    ↓ system call
Linux kernel
    ↓
Snapdragon hardware
```

There is no VM layer in between.

The chroot only changes filesystem visibility and process environment. CPU instructions still execute natively.

This is very different from:

- QEMU CPU emulation
- a full VM
- non-rooted PRoot environments

## 8. Why Android network groups mattered

Android uses Linux groups as part of its permission model.

Normal Debian assumes that users can create network sockets unless restricted otherwise. Android adds another layer: processes need certain Android-specific group IDs.

The important ones for us were:

```text
3003 = aid_inet
3004 = aid_net_raw
```

`aid_inet` allows normal internet sockets.

`aid_net_raw` allows raw sockets used by tools such as `ping`.

We created equivalent groups inside Debian and assigned users to them so Debian processes inherited the permissions Android expects.

APT required one additional fix because it intentionally drops privileges to the `_apt` user while downloading packages.

Making `aid_inet` the `_apt` user's primary group allowed package downloads to work normally:

```bash
usermod -g aid_inet _apt
```

## 9. What the "Required key not available" problem was

Modern Android encrypts application and user data using Linux filesystem encryption (`fscrypt`).

The Debian root filesystem lives under Android's encrypted `/data` partition.

Some standard Debian PAM configurations run:

```text
pam_keyinit.so force revoke
```

when creating a new login/session.

On a normal Linux computer this is reasonable session cleanup behavior. In this Android chroot, however, it could revoke the keyring context that allowed the process to access the encrypted backing files.

The result was strange-looking errors such as:

```text
Required key not available
```

when commands tried to modify files under `/etc` or when APT ran under SSH/sudo.

Commenting out the `pam_keyinit.so` session lines prevented Debian login sessions from destroying the Android encryption-key context they depended on.

For SSH, we also set:

```text
UsePAM no
```

because this is a simple dedicated appliance and we do not need the full Debian PAM login stack.

## 10. Why `/run/sshd` has to be created manually

On a normal Debian machine, systemd or another init system prepares runtime directories during boot.

Our Debian chroot does not run its own kernel and does not have a conventional Debian boot process.

Therefore directories such as:

```text
/run/sshd
```

must be created manually before starting OpenSSH.

OpenSSH also requires this directory to be owned by root and not writable by ordinary users:

```bash
mkdir -p /run/sshd
chown root:root /run/sshd
chmod 0755 /run/sshd
```

## 11. Why Debian does not "boot" normally

The phone only has one kernel and one real system boot process: Android's.

Debian does not have its own kernel or PID 1.

So "starting Debian" really means:

1. Mount the Debian root filesystem.
2. Bind the kernel interfaces into it.
3. Launch processes inside that filesystem environment.

For example:

```text
Android boots
    ↓
Magisk starts
    ↓
service.d script runs
    ↓
chroot-distro mounts Debian
    ↓
sshd starts inside Debian
```

Later we will add Klipper and Moonraker to the same boot sequence.

## 12. The role of the Magisk boot script

The script under:

```text
/data/adb/service.d/start-debian.sh
```

is what turns this from a manual experiment into an appliance.

It waits until Android has finished booting, then runs roughly:

```text
mount Debian
create /run/sshd
start sshd
```

This means that after a phone reboot, you can SSH into Debian directly without opening Termux.

Later it can be expanded to start:

```text
Klipper
Moonraker
Mainsail web server
```

## 13. Current software architecture

```text
┌───────────────────────────────────────────────┐
│                OnePlus 5 hardware             │
│ Snapdragon 835 / RAM / USB / Wi-Fi / OLED     │
└───────────────────────┬───────────────────────┘
                        │
┌───────────────────────▼───────────────────────┐
│           Linux kernel from LineageOS          │
│   shared by Android and all Debian processes   │
└───────────────────────┬───────────────────────┘
                        │
        ┌───────────────┴────────────────┐
        │                                │
┌───────▼─────────────────┐    ┌─────────▼─────────────────┐
│ LineageOS / Android      │    │ Debian Trixie chroot      │
│                          │    │                           │
│ Android framework        │    │ /etc /usr /var /home     │
│ display + touchscreen    │    │ apt                       │
│ Wi-Fi + USB framework    │    │ OpenSSH                   │
│                          │    │ future Klipper            │
│ Magisk                   │    │ future Moonraker          │
│  ├─ root                 │    │ future Mainsail backend   │
│  └─ boot scripts         │    │                           │
│                          │    │ shares:                   │
│ Termux                   │    │ /dev /proc /sys /dev/pts │
│  └─ maintenance shell    │    │ with Android kernel       │
│                          │    │                           │
│ BusyBox                  │    │                           │
│ chroot-distro ───────────────► manages rootfs + mounts    │
└──────────────────────────┘    └───────────────────────────┘
```

## 14. Why this architecture is a good fit for Klipper

Klipper needs a Linux host, but it does not need a Raspberry Pi specifically.

This phone now provides:

- native ARM64 Linux execution
- plenty of CPU and RAM
- Wi-Fi
- battery backup
- touchscreen and display
- USB OTG
- a persistent Debian userspace
- automatic service startup
- remote SSH administration

Android continues handling the phone-specific hardware, while Debian provides the conventional Linux environment expected by Klipper and Moonraker.

The remaining hardware question is the printer connection. The current LineageOS kernel does not include the common USB serial kernel drivers, so the next phase is deciding whether to use a userspace USB-UART bridge or a custom kernel with USB serial support, then connecting the OnePlus 5 to the Ender-3 V3 KE's UART interface.
