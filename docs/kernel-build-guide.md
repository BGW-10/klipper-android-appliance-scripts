# OnePlus 5 Custom LineageOS Kernel - Build & Install Guide

> Repository path: `docs/BUILD_INSTALL.md`
>
> This guide is for users of a prepared fork. It does **not** require a full Android or LineageOS source checkout.

## What this kernel adds

The fork stays close to the LineageOS OnePlus 5 kernel while enabling peripherals useful for a Klipper / embedded-Linux host:

- CDC ACM serial devices (`/dev/ttyACM*`);
- CH340/CH341, CP210x, FTDI, and PL2303 USB serial (`/dev/ttyUSB*`);
- SocketCAN and common `gs_usb` adapters;
- SLCAN;
- standard UVC USB webcams (`/dev/video*`);
- UAS storage;
- optional CDC ACM gadget support.

---

## 1. Phone prerequisites

Before flashing a custom kernel, the phone should already have:

- a **OnePlus 5** (`cheeseburger`);
- an unlocked bootloader;
- **LineageOS 22.2** installed and booting normally;
- the firmware required by that LineageOS installation;
- working USB debugging;
- **Magisk/root already installed and working**;
- working `adb` and `fastboot` access from a PC;
- a known-good LineageOS recovery / installation ZIP available for recovery;
- enough battery charge to safely perform the flash.

This guide assumes a normal rooted LineageOS installation. It does not assume Debian, a chroot, Klipper, or any other userspace has been installed yet.

Confirm the device:

```bash
adb devices
adb shell getprop ro.product.device
adb shell uname -a
```

The device should report `cheeseburger`.

---

## 2. Check whether you actually need the custom kernel

For USB serial, connect the adapter or Klipper MCU through USB OTG and check:

```bash
adb shell su -c 'lsusb'
adb shell su -c 'ls -l /dev/ttyUSB* /dev/ttyACM* 2>/dev/null'
```

The stock LineageOS kernel may enumerate the USB device while still lacking the driver needed to create `/dev/ttyUSB*` or `/dev/ttyACM*`.

If the required device node already exists and works, you do not need this custom kernel solely for USB serial.

---

## 3. Prepare the build machine

Supported practical environments include:

- native Debian/Ubuntu Linux;
- a Debian/Ubuntu VM;
- WSL2 with Debian or Ubuntu.

For WSL2, keep the project in the Linux filesystem:

```text
~/op5-kernel/
```

Do not build under `/mnt/c/...`.

Allow roughly **15-20 GB** of free space for source, toolchains, output, packaging, and backups.

Install the host packages:

```bash
sudo apt update
sudo apt install -y \
  bc \
  bison \
  build-essential \
  ca-certificates \
  cpio \
  curl \
  file \
  flex \
  git \
  libelf-dev \
  libncurses-dev \
  libssl-dev \
  make \
  python3 \
  rsync \
  unzip \
  wget \
  zip
```

`libssl-dev` is required for host-side kernel tools such as `scripts/extract-cert`. If it is missing, the build can fail with:

```text
fatal error: 'openssl/bio.h' file not found
```

---

## 4. Create the workspace and clone the prepared fork

```bash
mkdir -p ~/op5-kernel/{src,toolchains,package,backups}
cd ~/op5-kernel/src
```

Clone the prepared branch:

```bash
git clone -b usb-serial-enable \
  https://github.com/BGW-10/android_kernel_oneplus_msm8998

cd android_kernel_oneplus_msm8998
```

Record the exact revision you are building:

```bash
git rev-parse HEAD
git log -1 --oneline
```

---

## 5. Download and verify the pinned toolchains

Run:

```bash
./scripts/setup-toolchains.sh
```

The script downloads the pinned build dependencies into:

```text
~/op5-kernel/toolchains/
```

The important compiler paths should then exist:

```text
~/op5-kernel/toolchains/<clang-tag>/bin/clang
~/op5-kernel/toolchains/gcc64/bin/aarch64-linux-android-gcc
~/op5-kernel/toolchains/gcc32/bin/arm-linux-androideabi-gcc
```

The old MSM8998 kernel can use Clang while still requiring the Android GCC 4.9 cross-tool prefixes, so all three toolchains are intentional.

If you want to verify manually:

```bash
find ~/op5-kernel/toolchains -type f -name 'aarch64-linux-android-gcc'
find ~/op5-kernel/toolchains -type f -name 'arm-linux-androideabi-gcc'
```

---

## 6. Build the kernel

Run:

```bash
./scripts/build.sh
```

The script:

1. verifies the required compiler commands are on `PATH`;
2. generates the OnePlus 5 config from `lineage_oneplus5_defconfig`;
3. verifies that the requested Kconfig options actually resolved to `=y`;
4. builds the standalone kernel with the pinned toolchains;
5. checks for `Image.gz-dtb`;
6. prints its SHA-256 checksum.

A successful build produces:

```text
out/arch/arm64/boot/Image.gz-dtb
```

### It may build surprisingly quickly

That is normal. You are compiling only the Linux kernel tree, not Android/LineageOS itself. On a modern multi-core desktop a clean build can take only a few minutes; incremental rebuilds can be considerably faster.

The important success criteria are:

```bash
test -f out/arch/arm64/boot/Image.gz-dtb && echo 'kernel image exists'
sha256sum out/arch/arm64/boot/Image.gz-dtb
```

and a successful exit from `./scripts/build.sh`.

### Optional config verification

```bash
grep -E '^CONFIG_(USB_ACM|USB_SERIAL|USB_SERIAL_GENERIC|USB_SERIAL_CH341|USB_SERIAL_CP210X|USB_SERIAL_FTDI_SIO|USB_SERIAL_PL2303|CAN_GS_USB|MEDIA_USB_SUPPORT|VIDEO_DEV|VIDEO_V4L2|USB_VIDEO_CLASS|USB_UAS|USB_CONFIGFS_ACM)=' out/.config
```

---

## 7. Back up the currently working boot partition

Do this **before creating or flashing a custom boot image**.

The safest template for the new boot image is the boot image that is already working on the phone. That preserves the exact LineageOS boot header, ramdisk, command line, and other metadata for the installed build.

From the build PC:

```bash
adb shell su -c 'dd if=/dev/block/bootdevice/by-name/boot of=/sdcard/boot-known-good.img'
adb pull /sdcard/boot-known-good.img ~/op5-kernel/backups/
```

Verify the backup and record its checksum:

```bash
ls -lh ~/op5-kernel/backups/boot-known-good.img
sha256sum ~/op5-kernel/backups/boot-known-good.img
```

Keep this file somewhere safe. Recovery is simply:

```bash
fastboot flash boot ~/op5-kernel/backups/boot-known-good.img
fastboot reboot
```

If the phone is currently rooted with Magisk, this backup is also a copy of the currently working Magisk-patched boot image.

---

## 8. Build a complete Android `boot.img`

The kernel build produces only:

```text
out/arch/arm64/boot/Image.gz-dtb
```

That file is only the kernel payload. It is **not** a complete Android boot image and must not be flashed directly to the `boot` partition.

The simplest safe workflow for an already-rooted LineageOS phone is to use the currently running boot partition as the template. This preserves the matching LineageOS ramdisk, boot header, command line, and the existing Magisk modifications while replacing only the kernel.

All commands in this section run against ordinary rooted Android/LineageOS. No Debian environment is involved.

### 8.1 Push the newly built kernel to the phone

From the kernel repository on the PC:

```bash
adb push out/arch/arm64/boot/Image.gz-dtb /sdcard/Download/Image.gz-dtb
```

### 8.2 Open a real Android root shell

Rather than nesting every command inside `adb shell su -c`, enter the phone interactively:

```bash
adb shell
```

Then, on the phone:

```sh
su
id
```

The `id` output should show `uid=0(root)`. The remaining commands in this subsection are run from that root Android shell.

### 8.3 Prepare a boot-image workspace

```sh
rm -rf /data/local/tmp/op5-kernel-boot
mkdir -p /data/local/tmp/op5-kernel-boot
cd /data/local/tmp/op5-kernel-boot
```

Copy the currently booted image into the workspace:

```sh
dd if=/dev/block/bootdevice/by-name/boot of=original-boot.img
```

Confirm it exists:

```sh
ls -lh original-boot.img
```

### 8.4 Locate and stage `magiskboot`

A typical Magisk installation stores `magiskboot` here:

```text
/data/adb/magisk/magiskboot
```

Check for it:

```sh
ls -l /data/adb/magisk/magiskboot
```

For this workflow, copy the binary into the temporary workspace before executing it. This avoids relying on `/data/adb/magisk` itself being directly executable from the current shell context:

```sh
cp /data/adb/magisk/magiskboot ./magiskboot
chmod 0755 ./magiskboot
```

Verify it runs:

```sh
./magiskboot --help
```

If `/data/adb/magisk/magiskboot` does not exist, locate it first:

```sh
find /data/adb -type f -name magiskboot 2>/dev/null
```

Use the returned path as the source of the `cp` command above. Do not continue until `./magiskboot --help` runs successfully.

### 8.5 Unpack the currently working boot image

From `/data/local/tmp/op5-kernel-boot`:

```sh
./magiskboot unpack original-boot.img
```

Inspect the result:

```sh
ls -lh
```

There should be an extracted file named:

```text
kernel
```

There will normally also be a ramdisk and possibly other boot-image components.

### 8.6 Replace only the kernel payload

Copy the kernel you built on the PC over the extracted `kernel` file:

```sh
cp /sdcard/Download/Image.gz-dtb ./kernel
```

Confirm the replacement:

```sh
ls -lh kernel /sdcard/Download/Image.gz-dtb
```

### 8.7 Repack the complete boot image

Still in the same directory:

```sh
./magiskboot repack original-boot.img custom-boot.img
```

Verify the result:

```sh
ls -lh custom-boot.img
```

Copy it to shared storage so the PC can pull it normally:

```sh
cp custom-boot.img /sdcard/Download/op5-custom-boot.img
chmod 0644 /sdcard/Download/op5-custom-boot.img
```

Exit the root shell and Android shell:

```sh
exit
exit
```

Back on the PC, pull the complete image:

```bash
adb pull /sdcard/Download/op5-custom-boot.img ~/op5-kernel/package/op5-custom-boot.img
sha256sum ~/op5-kernel/package/op5-custom-boot.img
```

The file you will flash is now:

```text
~/op5-kernel/package/op5-custom-boot.img
```

### Why Magisk should remain installed

The template image came from the currently booted, already-Magisk-patched `boot` partition. `magiskboot repack` retains that ramdisk while you replace the kernel payload, so the resulting boot image should retain the existing Magisk setup.

If you intentionally start from a clean, unrooted LineageOS `boot.img` instead, the resulting custom image will also be unrooted unless you patch it with the Magisk app before flashing it.

### Optional structural sanity check

Before flashing, you can push the finished image back to the phone and make sure `magiskboot` can unpack it:

```bash
adb push ~/op5-kernel/package/op5-custom-boot.img /sdcard/Download/op5-custom-boot-check.img
adb shell
```

Then:

```sh
su
rm -rf /data/local/tmp/op5-kernel-check
mkdir -p /data/local/tmp/op5-kernel-check
cd /data/local/tmp/op5-kernel-check
cp /sdcard/Download/op5-custom-boot-check.img .
cp /data/adb/magisk/magiskboot ./magiskboot
chmod 0755 ./magiskboot
./magiskboot unpack op5-custom-boot-check.img
ls -lh
```

A successful unpack is a useful structural check. It cannot prove that the new kernel will boot, which is why the known-good boot backup from section 7 remains essential.

---

## 9. Flash the new boot image

Reboot the phone into the bootloader:

```bash
adb reboot bootloader
fastboot devices
```

Flash the complete image you just built:

```bash
fastboot flash boot ~/op5-kernel/package/op5-custom-boot.img
fastboot reboot
```

Do **not** flash `Image.gz-dtb` directly to the boot partition. The bootloader expects a complete Android boot image.

Keep `boot-known-good.img` available until the custom kernel has completed several successful boots and the required peripherals have been tested.

---

## 10. If the phone does not boot

Return to fastboot mode and restore the known-good image:

```bash
fastboot flash boot ~/op5-kernel/backups/boot-known-good.img
fastboot reboot
```

Because this workflow changes only the boot partition, restoring the old boot image should return the phone to the previous kernel/root state without touching `/data`.

---

## 11. Verify the custom kernel after boot

Confirm Android boots normally first:

```bash
adb wait-for-device
adb shell uname -a
```

Confirm the requested options are present in the running kernel when `/proc/config.gz` is available:

```bash
adb shell su -c "zcat /proc/config.gz | grep -E 'CONFIG_USB_ACM=|CONFIG_USB_SERIAL=|CONFIG_USB_VIDEO_CLASS=|CONFIG_CAN_GS_USB=|CONFIG_USB_UAS='"
```

Then connect the USB-UART adapter or Klipper MCU through OTG:

```bash
adb shell su -c 'lsusb'
adb shell su -c 'dmesg | tail -100'
adb shell su -c 'ls -l /dev/ttyUSB* /dev/ttyACM* 2>/dev/null'
```

Expected device-node examples are:

```text
/dev/ttyUSB0
/dev/ttyACM0
```

For a UVC webcam, check:

```bash
adb shell su -c 'ls -l /dev/video* 2>/dev/null'
```

For a `gs_usb` CAN adapter, check the kernel log and network interfaces after connecting it.

---

## 12. Recovery

If Android fails to boot or a critical hardware function stops working, return to fastboot and restore the known-good boot image:

```bash
fastboot flash boot ~/op5-kernel/backups/boot-known-good.img
fastboot reboot
```

Changing only the boot/kernel image should not erase `/data`, so the Android installation and user data normally remain intact. A boot backup is still essential because a bad kernel can prevent Android from reaching userspace.

---

## 13. Troubleshooting

### `CONFIG_USB_VIDEO_CLASS did not resolve to =y`

The UVC option has media/V4L2 dependencies. The prepared fork should already enable the required parent symbols. Inspect the resolved config:

```bash
grep -E '^CONFIG_(MEDIA_SUPPORT|MEDIA_CAMERA_SUPPORT|MEDIA_USB_SUPPORT|VIDEO_DEV|VIDEO_V4L2|USB_VIDEO_CLASS)=' out/.config
```

If the source tree was modified locally, regenerate from a clean output directory:

```bash
rm -rf out
./scripts/build.sh
```

### `aarch64-linux-android-gcc: not found`

Run:

```bash
./scripts/setup-toolchains.sh
```

Then verify:

```bash
export PATH="$HOME/op5-kernel/toolchains/gcc64/bin:$HOME/op5-kernel/toolchains/gcc32/bin:$PATH"
command -v aarch64-linux-android-gcc
command -v arm-linux-androideabi-gcc
```

The correct prefixes are:

```text
64-bit: aarch64-linux-android-
32-bit: arm-linux-androideabi-
```

### `openssl/bio.h` not found

Install:

```bash
sudo apt install -y libssl-dev
```

Then rerun the build.

### `CONFIG_CC_STACKPROTECTOR_STRONG` warning appears with a missing compiler

Fix the compiler/PATH problem first. Compiler-feature probes can fail simply because the expected cross-compiler command could not be executed.

### Adapter appears in `lsusb` but there is still no tty device

Check:

```bash
adb shell su -c 'dmesg | tail -100'
adb shell su -c 'lsusb'
```

Identify the adapter's USB VID:PID and determine which USB serial driver it requires. The fork intentionally enables the most common Klipper/embedded adapters, not every historical USB serial driver in the kernel.

### Build finishes almost immediately on a second run

That is expected for an incremental build. To prove that the complete tree can build from scratch:

```bash
rm -rf out
time ./scripts/build.sh
```

A clean standalone kernel build can still be relatively short compared with a full Android build.
