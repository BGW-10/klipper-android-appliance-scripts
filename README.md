# OnePlus 5 Appliance Userspace

This repository contains the configuration and startup scripts used to turn a rooted OnePlus 5 running LineageOS into a small always-on Linux appliance.

The phone continues to boot Android normally. Magisk runs the Android-side startup scripts, which mount the Debian chroot and launch a lightweight `runit` service supervisor inside Debian.

The goal is to keep the appliance reproducible: rather than manually configuring files under Android and Debian, the repository mirrors the important parts of each filesystem so the desired state can be installed from Git.

## Architecture

```text
OnePlus 5
└── LineageOS / Android
    ├── Android init (real PID 1)
    ├── Magisk
    │   └── /data/adb/service.d/
    │       ├── appliance-tuning.sh
    │       └── start-debian.sh
    │
    └── Debian chroot
        └── /usr/local/bin/start-services
            └── runsvdir /etc/service
                └── runsv
                    ├── sshd
                    ├── future: Klipper
                    ├── future: Moonraker
                    └── future: nginx
```

Android remains responsible for the kernel, hardware, Wi-Fi, USB, display, charging, thermal management, and normal phone hardware support. Debian provides a conventional Linux userspace for long-running appliance services.

`runit` is **not** used as PID 1. Only `runsvdir`, `runsv`, `sv`, and related tools are used as a lightweight service supervisor inside the chroot.

## Current Repository Contents

The repository currently contains:

- `appliance-tuning.sh`
  - runs from Magisk `service.d`;
  - disables Android Doze/device idle;
  - disables Battery Saver;
  - disables USB autosuspend;
  - disables Wi-Fi power saving and reapplies it when the Wi-Fi interface changes state;
  - deliberately leaves SELinux, thermal protection, CPU scaling, charging safety, and other hardware safety mechanisms enabled.

- `start-debian.sh`
  - runs from Magisk `service.d`;
  - waits for Android to finish booting;
  - mounts the Debian chroot using `chroot-distro`;
  - launches the Debian-side service entrypoint.

- `start-services`
  - runs inside Debian;
  - replaces itself with `runsvdir /etc/service`;
  - becomes the supervisor for Debian services.

- `sshd/run`
  - runit service definition for OpenSSH;
  - prepares `/run/sshd`;
  - starts `sshd` in the foreground so runit can supervise it.

## Repository Layout

The repository mirrors the target filesystems:

```text
.
├── README.md
├── android/
│   └── data/
│       └── adb/
│           └── service.d/
│               ├── appliance-tuning.sh
│               └── start-debian.sh
│
└── debian/
    ├── etc/
    │   └── sv/
    │       └── sshd/
    │           └── run
    │
    └── usr/
        └── local/
            └── bin/
                └── start-services
```

The intended installation paths are therefore obvious:

```text
android/data/adb/service.d/appliance-tuning.sh
    -> /data/adb/service.d/appliance-tuning.sh

android/data/adb/service.d/start-debian.sh
    -> /data/adb/service.d/start-debian.sh

debian/usr/local/bin/start-services
    -> /usr/local/bin/start-services

debian/etc/sv/sshd/run
    -> /etc/sv/sshd/run
```

This layout should be retained as more configuration is added.

## Prerequisites

### Android side

The phone should have:

- OnePlus 5 running LineageOS;
- unlocked bootloader;
- Magisk/root access;
- `chroot-distro` installed and working;
- a Debian chroot already created;
- working Wi-Fi;
- working USB OTG.

The distro name used by `start-debian.sh` must match the name registered with `chroot-distro`.

Check the installed command and syntax from an Android root shell:

```sh
su
command -v chroot-distro
chroot-distro --help
```

Update `start-debian.sh` if the path or command syntax differs on the installed version.

### Debian side

Inside Debian:

```bash
apt update
apt install -y runit openssh-server
```

The Debian environment should already have any Android-specific networking groups and PAM adjustments required by the chroot setup.

## Installing the Android-Side Scripts

Install the Magisk scripts into `/data/adb/service.d/`:

```sh
su

cp /path/to/repo/android/data/adb/service.d/appliance-tuning.sh \
   /data/adb/service.d/appliance-tuning.sh

cp /path/to/repo/android/data/adb/service.d/start-debian.sh \
   /data/adb/service.d/start-debian.sh

chmod 755 /data/adb/service.d/appliance-tuning.sh
chmod 755 /data/adb/service.d/start-debian.sh
```

Magisk executes executable scripts under `/data/adb/service.d` during boot.

### `appliance-tuning.sh`

This script should perform only appliance-level Android tuning.

It should **not** disable:

- SELinux;
- thermal throttling;
- CPU frequency scaling;
- CPU idle states;
- battery temperature monitoring;
- charging safety;
- filesystem synchronization;
- kernel watchdogs.

### `start-debian.sh`

The Android-side startup script should only:

1. wait until Android has finished booting;
2. mount the Debian chroot;
3. execute `/usr/local/bin/start-services` inside Debian.

It should not know about individual services such as SSH, Klipper, Moonraker, or nginx. Those are managed entirely by runit inside Debian.

## Installing the Debian-Side Files

At minimum:

```bash
sudo mkdir -p /etc/sv/sshd
sudo mkdir -p /etc/service
sudo mkdir -p /usr/local/bin
```

Install the service entrypoint:

```bash
sudo cp /path/to/repo/debian/usr/local/bin/start-services \
    /usr/local/bin/start-services
sudo chmod 755 /usr/local/bin/start-services
```

Install the SSH service:

```bash
sudo cp /path/to/repo/debian/etc/sv/sshd/run \
    /etc/sv/sshd/run
sudo chmod 755 /etc/sv/sshd/run
```

Enable SSH under runit:

```bash
sudo ln -sfn /etc/sv/sshd /etc/service/sshd
```

## Debian Service Entrypoint

`/usr/local/bin/start-services` should remain intentionally small:

```sh
#!/bin/sh
set -eu

exec /usr/bin/runsvdir /etc/service
```

`exec` replaces the shell with `runsvdir`, leaving a simple process tree and avoiding an unnecessary wrapper process.

`runsvdir` watches `/etc/service`. Each enabled directory there gets its own `runsv` supervisor.

## SSH Service Definition

The runit entrypoint for SSH is:

```text
/etc/sv/sshd/run
```

A suitable definition is:

```sh
#!/bin/sh

mkdir -p /run/sshd
chown root:root /run/sshd
chmod 0755 /run/sshd

exec /usr/sbin/sshd -D -e
```

`sshd` must remain in the foreground (`-D`) so runit can supervise the real process.

## Enabling and Disabling Services

Service definitions live permanently under:

```text
/etc/sv/
```

Enabled services are linked into:

```text
/etc/service/
```

Enable a service:

```bash
sudo ln -sfn /etc/sv/sshd /etc/service/sshd
```

Disable it:

```bash
sudo rm /etc/service/sshd
```

The service definition remains available under `/etc/sv`.

## Managing Services

Once `runsvdir` is running:

```bash
sudo sv status /etc/service/sshd
sudo sv start /etc/service/sshd
sudo sv stop /etc/service/sshd
sudo sv restart /etc/service/sshd
```

Typical running status:

```text
run: /etc/service/sshd: (pid 1234) 30s
```

## Testing Before Boot Automation

Before relying on Magisk startup, test the Debian supervisor manually.

Inside Debian:

```bash
sudo /usr/local/bin/start-services
```

Leave that shell running. In another Debian shell:

```bash
sudo sv status /etc/service/sshd
sudo sv restart /etc/service/sshd
```

Only after this works should `start-debian.sh` be used to launch the supervisor automatically at Android boot.

## Boot Flow

```text
Android boots
    |
    v
Magisk service.d starts
    |
    +--> appliance-tuning.sh
    |
    +--> start-debian.sh
            |
            v
       mount Debian
            |
            v
       /usr/local/bin/start-services
            |
            v
       runsvdir /etc/service
            |
            v
       /etc/service/sshd
            |
            v
       /etc/sv/sshd/run
            |
            v
       sshd -D -e
```

## Verifying Boot

After rebooting the phone, inspect the appliance tuning log:

```sh
su
cat /data/local/tmp/appliance-tuning.log
```

Inspect the Debian startup log if `start-debian.sh` writes one:

```sh
cat /data/local/tmp/start-debian.log
```

Then connect to Debian and check:

```bash
sudo sv status /etc/service/sshd
ps aux | grep '[r]unsvdir'
ps aux | grep '[r]unsv'
```

## Adding a New Service

For each new Debian service:

1. create `debian/etc/sv/<service>/`;
2. add an executable file named exactly `run`;
3. install it to `/etc/sv/<service>/run`;
4. symlink `/etc/sv/<service>` into `/etc/service/` to enable it.

Example:

```text
debian/etc/sv/moonraker/run
```

becomes:

```text
/etc/sv/moonraker/run
```

and is enabled with:

```bash
sudo ln -sfn /etc/sv/moonraker /etc/service/moonraker
```

The file must be called `run`, not `run.sh`; `runsv` specifically executes `./run`.

## Foreground Processes

Programs supervised by runit must remain in the foreground.

```text
sshd      -> sshd -D
nginx     -> nginx -g 'daemon off;'
Klipper   -> foreground Python process
Moonraker -> foreground Python process
```

Do not daemonize a service behind runit's back.

## Running Services as a Non-Root User

Services that do not require root should run as the dedicated appliance user.

With runit, `chpst` can switch users:

```sh
exec chpst -u klipper /path/to/program
```

This pattern should be used for future Klipper and Moonraker services rather than running them as root.

## Logging

For now, services may use their native log files or stderr/stdout.

Runit also supports supervised logging with `svlogd`:

```text
/etc/sv/example/
├── run
└── log/
    └── run
```

This can be added later if centralized runit-managed logs become useful.

## Planned Services

The intended appliance stack will likely grow to include:

```text
/etc/sv/
├── sshd/
├── klipper/
├── moonraker/
└── nginx/
```

Mainsail itself is static web content and does not need its own service; nginx will serve it.

## Design Principles

### Reproducible

Important appliance configuration should live in Git rather than exist only as manual changes on the phone.

### Mirrored

Files should generally be stored under the same path hierarchy used on the target system.

For example:

```text
debian/etc/sv/sshd/run
```

maps directly to:

```text
/etc/sv/sshd/run
```

### Idempotent

Future provisioning scripts should be safe to run repeatedly and converge on the same system state.

### Minimal

Android startup should only bring up the Debian environment. Debian's `runsvdir` should manage Debian services. Individual service definitions should contain only the setup required to launch that service.

### Safe

Appliance tuning should remove power-management behavior that interferes with an always-on host without disabling hardware safety mechanisms.

## Troubleshooting

### `runsvdir` is not running

```bash
command -v runsvdir
```

If missing:

```bash
sudo apt install runit
```

Then test:

```bash
sudo /usr/local/bin/start-services
```

### Service does not start

```bash
sudo sv status /etc/service/sshd
ls -l /etc/service/
ls -l /etc/sv/sshd/run
```

The `run` file must be executable.

### SSH repeatedly exits

Test the SSH configuration:

```bash
sudo /usr/sbin/sshd -t
```

Check `/run/sshd`:

```bash
ls -ld /run/sshd
```

Expected ownership and mode:

```text
drwxr-xr-x root root
```

### Debian mounts but services do not start

Run manually inside Debian:

```bash
/usr/local/bin/start-services
```

If that works, inspect the Android-side `start-debian.sh` and its log.

### Wi-Fi becomes sluggish after idle

```sh
su
iw dev wlan0 get power_save
```

Expected:

```text
Power save: off
```

Then inspect:

```sh
cat /data/local/tmp/appliance-tuning.log
```

### USB devices disappear or become unresponsive

```sh
su
cat /sys/module/usbcore/parameters/autosuspend
```

If supported by the kernel, appliance tuning should set it to:

```text
-1
```

## Future Provisioning

As the repository grows, add installers that copy the mirrored trees into place and ensure ownership and permissions are correct.

A future layout might include:

```text
.
├── install-android.sh
├── install-debian.sh
├── android/
│   └── data/adb/service.d/
└── debian/
    ├── etc/
    │   ├── sv/
    │   └── nginx/
    ├── usr/local/bin/
    └── home/klipper/
```

The long-term goal is approximately:

```text
install LineageOS
-> install Magisk
-> install/create Debian chroot
-> clone this repository
-> run provisioning
-> reboot
```

Everything above that base should be represented here rather than relying on undocumented manual state.

## Current Status

Working so far:

- rooted LineageOS appliance;
- Debian chroot;
- Magisk boot scripts;
- appliance power tuning;
- Debian startup at boot;
- runit service supervision design;
- SSH service definition;
- custom OnePlus 5 kernel with USB serial support;
- USB-UART loopback successfully tested.

Likely next additions:

- automated repository installer;
- Klipper service definition;
- Moonraker service definition;
- nginx + Mainsail configuration;
- USB device permission handling;
- printer UART configuration.
