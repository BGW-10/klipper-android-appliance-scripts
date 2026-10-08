# OnePlus 5 LineageOS Kernel - Maintainer / Fork Setup Guide

> Repository path: `docs/MAINTAINER_SETUP.md`
>
> Companion user guide: `docs/BUILD_INSTALL.md`
>
> Target: OnePlus 5 (`cheeseburger`, Snapdragon 835 / MSM8998)
>
> Base: LineageOS `android_kernel_oneplus_msm8998`, branch `lineage-22.2`

## Purpose

This guide is for the maintainer of a small LineageOS kernel fork intended to make the OnePlus 5 a better Klipper / embedded-Linux host. It keeps the actual kernel change easy to audit while also providing a repeatable standalone build environment.

The fork should contain:

- the small defconfig change that enables the required peripheral drivers;
- pinned compiler/toolchain metadata;
- scripts that download the exact toolchains and build the kernel;
- maintainer and user-facing documentation.

The fork should **not** contain downloaded toolchains, build output, boot-image backups, or other generated binaries.

---

## 1. Create the workspace first

Keep the Git checkout separate from downloaded toolchains and generated artifacts.

```bash
mkdir -p ~/op5-kernel/{src,toolchains,package,backups}
cd ~/op5-kernel
```

The intended workspace layout is:

```text
~/op5-kernel/
├── src/
│   └── android_kernel_oneplus_msm8998/   # Git checkout
├── toolchains/                            # downloaded; never committed
├── package/                               # generated packages/images
└── backups/                               # local known-good boot images
```

The repository itself will eventually contain:

```text
android_kernel_oneplus_msm8998/
├── README.md
├── docs/
│   ├── MAINTAINER_SETUP.md
│   └── BUILD_INSTALL.md
├── scripts/
│   ├── setup-toolchains.sh
│   └── build.sh
├── toolchains.conf
├── arch/arm64/configs/
│   └── lineage_oneplus5_defconfig
└── ...normal kernel source...
```

---

## 2. Fork and clone LineageOS

Fork this repository on GitHub:

```text
https://github.com/LineageOS/android_kernel_oneplus_msm8998
```

Then clone **your fork** into the workspace:

```bash
cd ~/op5-kernel/src

git clone -b lineage-22.2 \
  https://github.com/YOUR_GITHUB_USERNAME/android_kernel_oneplus_msm8998.git

cd android_kernel_oneplus_msm8998
```

Add the original LineageOS repository as `upstream`:

```bash
git remote add upstream https://github.com/LineageOS/android_kernel_oneplus_msm8998.git
git remote -v
```

Create a dedicated branch for the changes:

```bash
git checkout -b printer-host-support
```

Confirm that the working tree is clean before modifying anything:

```bash
git status
```

Do **not** make a commit merely for cloning or creating directories outside the repository. The first commit should represent an actual repository change.

---

## 3. Create the repository directories and ignore generated files

Create the documentation and automation directories immediately so it is obvious where project-specific files belong:

```bash
mkdir -p docs scripts
```

Append appropriate generated files to `.gitignore` if they are not already covered:

```gitignore
/out/
*.img
*.zip
```

Do not ignore `docs/`, `scripts/`, or `toolchains.conf`; those are part of the source repository.

Do not commit:

- `~/op5-kernel/toolchains/`;
- `out/`;
- boot images;
- AnyKernel output ZIPs;
- personal phone backups.

At this stage it is fine to leave `docs/` and `scripts/` empty. Git does not track empty directories, so there is no reason to make a directory-only commit.

---

## 4. Install maintainer build dependencies

On Debian/Ubuntu/WSL2:

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

`libssl-dev` is required because this kernel builds host tools such as `scripts/extract-cert`, which includes OpenSSL headers such as `openssl/bio.h`.

For WSL2, keep the workspace under the Linux filesystem (`~/op5-kernel`), not `/mnt/c/...`.

---

## 5. Modify the OnePlus 5 defconfig

The device defconfig is:

```text
arch/arm64/configs/lineage_oneplus5_defconfig
```

Edit it:

```bash
nano arch/arm64/configs/lineage_oneplus5_defconfig
```

Enable the following focused set of features:

```text
# ------------------------------------------------------------------
# USB serial / Klipper MCU support
# ------------------------------------------------------------------
CONFIG_USB_ACM=y
CONFIG_USB_SERIAL=y
CONFIG_USB_SERIAL_GENERIC=y
CONFIG_USB_SERIAL_CH341=y
CONFIG_USB_SERIAL_CP210X=y
CONFIG_USB_SERIAL_FTDI_SIO=y
CONFIG_USB_SERIAL_PL2303=y

# ------------------------------------------------------------------
# Klipper / SocketCAN support
# ------------------------------------------------------------------
CONFIG_CAN=y
CONFIG_CAN_RAW=y
CONFIG_CAN_DEV=y
CONFIG_CAN_GS_USB=y
CONFIG_CAN_SLCAN=y

# ------------------------------------------------------------------
# V4L2 / USB webcam support
# USB_VIDEO_CLASS will not resolve unless its media/V4L2 parents do.
# ------------------------------------------------------------------
CONFIG_MEDIA_SUPPORT=y
CONFIG_MEDIA_CAMERA_SUPPORT=y
CONFIG_MEDIA_USB_SUPPORT=y
CONFIG_VIDEO_DEV=y
CONFIG_VIDEO_V4L2=y
CONFIG_USB_VIDEO_CLASS=y
CONFIG_USB_VIDEO_CLASS_INPUT_EVDEV=y

# ------------------------------------------------------------------
# Modern USB storage bridges / SSDs
# ------------------------------------------------------------------
CONFIG_USB_UAS=y

# ------------------------------------------------------------------
# Optional: expose the phone itself as a CDC ACM USB gadget
# ------------------------------------------------------------------
CONFIG_USB_CONFIGFS_ACM=y
```

If the file contains disabled forms such as:

```text
# CONFIG_USB_ACM is not set
# CONFIG_USB_SERIAL is not set
```

replace those lines rather than leaving contradictory entries in the defconfig.

Use `=y` rather than modules for these additions so module loading does not become another Android-specific dependency.

### Why the UVC dependencies are explicit

Adding only:

```text
CONFIG_USB_VIDEO_CLASS=y
```

may silently disappear when Kconfig resolves the defconfig. This old kernel tree requires the relevant media/V4L2 parent options to be enabled. The build script below checks the **resolved** `out/.config`, rather than assuming that a line placed in the defconfig survived dependency resolution.

---

## 6. Commit the functional kernel change by itself

Review only the config change:

```bash
git diff -- arch/arm64/configs/lineage_oneplus5_defconfig
```

Then commit it separately:

```bash
git add arch/arm64/configs/lineage_oneplus5_defconfig
git commit -m 'oneplus5: enable printer host peripheral support'
```

Keeping the functional kernel change isolated makes it easy to audit, revert, or rebase independently from build tooling and documentation.

---

## 7. Add pinned toolchain metadata

Create `toolchains.conf` in the repository root:

```bash
nano toolchains.conf
```

Example pinned metadata:

```sh
LLVM_TAG=clang-r530567
AARCH64_GCC_REV=5e030eafe024784a73cdf47e6936ac0dbfc763dc
ARM_GCC_REV=111258a10e017f067b27e6cfcea7619d753f3309
BUILD_TOOLS_REV=f61cfbcb609173e1040753a2b9e8fbe8517343f9
```

The exact revisions are intentionally recorded in the repository. If they are changed later, treat that as a build-environment change and validate the resulting kernel again.

---

## 8. Add a robust toolchain setup script

Create:

```bash
nano scripts/setup-toolchains.sh
```

Use fixed local directory names instead of depending on GitHub archive extraction names. This avoids the failure mode where the archive downloads correctly but `build.sh` searches a differently named directory.

Suggested script:

```sh
#!/bin/sh
set -eu

REPO_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WORKSPACE=${WORKSPACE:-$HOME/op5-kernel}
TOOLCHAINS="$WORKSPACE/toolchains"

. "$REPO_DIR/toolchains.conf"

CLANG="$TOOLCHAINS/$LLVM_TAG"
GCC64="$TOOLCHAINS/gcc64"
GCC32="$TOOLCHAINS/gcc32"
BUILD_TOOLS="$TOOLCHAINS/build-tools"

mkdir -p "$TOOLCHAINS"

if [ ! -x "$CLANG/bin/clang" ]; then
  echo "Downloading $LLVM_TAG..."
  rm -rf "$CLANG"
  mkdir -p "$CLANG"
  curl -fL \
    "https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/main/${LLVM_TAG}.tar.gz" \
    | tar -xz -C "$CLANG"
fi

if [ ! -x "$GCC64/bin/aarch64-linux-android-gcc" ]; then
  echo "Downloading AArch64 GCC 4.9..."
  rm -rf "$GCC64"
  mkdir -p "$GCC64"
  curl -fL \
    "https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-android-4.9/archive/${AARCH64_GCC_REV}.tar.gz" \
    | tar -xz --strip-components=1 -C "$GCC64"
fi

if [ ! -x "$GCC32/bin/arm-linux-androideabi-gcc" ]; then
  echo "Downloading ARM GCC 4.9..."
  rm -rf "$GCC32"
  mkdir -p "$GCC32"
  curl -fL \
    "https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_arm_arm-linux-androideabi-4.9/archive/${ARM_GCC_REV}.tar.gz" \
    | tar -xz --strip-components=1 -C "$GCC32"
fi

if [ ! -d "$BUILD_TOOLS/path/linux-x86" ]; then
  echo "Downloading LineageOS build tools..."
  rm -rf "$BUILD_TOOLS"
  mkdir -p "$BUILD_TOOLS"
  curl -fL \
    "https://github.com/LineageOS/android_prebuilts_build-tools/archive/${BUILD_TOOLS_REV}.tar.gz" \
    | tar -xz --strip-components=1 -C "$BUILD_TOOLS"
fi

# Validate the files that the build actually needs. A directory merely existing
# is not sufficient proof that a toolchain was downloaded/extracted correctly.
for tool in \
  "$CLANG/bin/clang" \
  "$GCC64/bin/aarch64-linux-android-gcc" \
  "$GCC32/bin/arm-linux-androideabi-gcc"; do
  if [ ! -x "$tool" ]; then
    echo "ERROR: required compiler is missing or not executable: $tool" >&2
    exit 1
  fi
done

printf '\nToolchains ready under:\n%s\n' "$TOOLCHAINS"
```

Make it executable:

```bash
chmod +x scripts/setup-toolchains.sh
```

The important fix here is that the script validates the **actual compiler executable**, not merely the existence of an extracted directory.

---

## 9. Add the standalone build script

Create:

```bash
nano scripts/build.sh
```

Suggested contents:

```sh
#!/bin/sh
set -eu

REPO_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WORKSPACE=${WORKSPACE:-$HOME/op5-kernel}
TOOLCHAINS="$WORKSPACE/toolchains"
OUT=${OUT:-$REPO_DIR/out}

. "$REPO_DIR/toolchains.conf"

CLANG="$TOOLCHAINS/$LLVM_TAG"
GCC64="$TOOLCHAINS/gcc64"
GCC32="$TOOLCHAINS/gcc32"
BUILD_TOOLS="$TOOLCHAINS/build-tools"

export PATH="$CLANG/bin:$GCC64/bin:$GCC32/bin:$BUILD_TOOLS/path/linux-x86:$PATH"
export ARCH=arm64
export SUBARCH=arm64
export CROSS_COMPILE=aarch64-linux-android-
export CROSS_COMPILE_ARM32=arm-linux-androideabi-
export CLANG_TRIPLE=aarch64-linux-gnu-

# Fail before entering Kbuild if a toolchain was not set up correctly.
for tool in clang aarch64-linux-android-gcc arm-linux-androideabi-gcc; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "ERROR: required build tool not found on PATH: $tool" >&2
    echo "Run ./scripts/setup-toolchains.sh first." >&2
    exit 1
  }
done

printf 'Compiler setup:\n'
printf '  clang: %s\n' "$(command -v clang)"
printf '  gcc64: %s\n' "$(command -v aarch64-linux-android-gcc)"
printf '  gcc32: %s\n' "$(command -v arm-linux-androideabi-gcc)"

cd "$REPO_DIR"
mkdir -p "$OUT"

make O="$OUT" \
  ARCH=arm64 \
  SUBARCH=arm64 \
  LLVM=1 \
  lineage_oneplus5_defconfig

# Check the resolved config, not just the source defconfig.
for option in \
  CONFIG_USB_ACM \
  CONFIG_USB_SERIAL \
  CONFIG_USB_SERIAL_GENERIC \
  CONFIG_USB_SERIAL_CH341 \
  CONFIG_USB_SERIAL_CP210X \
  CONFIG_USB_SERIAL_FTDI_SIO \
  CONFIG_USB_SERIAL_PL2303 \
  CONFIG_CAN \
  CONFIG_CAN_RAW \
  CONFIG_CAN_DEV \
  CONFIG_CAN_GS_USB \
  CONFIG_CAN_SLCAN \
  CONFIG_MEDIA_SUPPORT \
  CONFIG_MEDIA_CAMERA_SUPPORT \
  CONFIG_MEDIA_USB_SUPPORT \
  CONFIG_VIDEO_DEV \
  CONFIG_VIDEO_V4L2 \
  CONFIG_USB_VIDEO_CLASS \
  CONFIG_USB_UAS \
  CONFIG_USB_CONFIGFS_ACM; do
  grep -q "^${option}=y$" "$OUT/.config" || {
    echo "ERROR: ${option} did not resolve to =y" >&2
    exit 1
  }
done

make -j"$(nproc)" O="$OUT" \
  ARCH=arm64 \
  SUBARCH=arm64 \
  CROSS_COMPILE=aarch64-linux-android- \
  CROSS_COMPILE_ARM32=arm-linux-androideabi- \
  CLANG_TRIPLE=aarch64-linux-gnu- \
  LLVM=1

IMAGE="$OUT/arch/arm64/boot/Image.gz-dtb"
[ -f "$IMAGE" ] || {
  echo "ERROR: expected kernel image not found: $IMAGE" >&2
  exit 1
}

printf '\nBuilt kernel:\n%s\n' "$IMAGE"
sha256sum "$IMAGE"
```

Make it executable:

```bash
chmod +x scripts/build.sh
```

This follows the standalone Clang/LLVM build pattern used by existing OnePlus 5 kernel build projects while retaining the Android GCC 4.9 cross-toolchains required by this old kernel tree.

---

## 10. Commit the build automation separately

Before committing, run the toolchain script and confirm the three compiler executables exist:

```bash
./scripts/setup-toolchains.sh

~/op5-kernel/toolchains/$LLVM_TAG/bin/clang --version | head -1
~/op5-kernel/toolchains/gcc64/bin/aarch64-linux-android-gcc --version | head -1
~/op5-kernel/toolchains/gcc32/bin/arm-linux-androideabi-gcc --version | head -1
```

Then commit the reproducible build machinery:

```bash
git add .gitignore toolchains.conf scripts/setup-toolchains.sh scripts/build.sh
git commit -m 'build: add reproducible standalone kernel workflow'
```

At this point the history should contain two clean logical changes:

```text
1. oneplus5: enable printer host peripheral support
2. build: add reproducible standalone kernel workflow
```

---

## 11. Perform a clean validation build

Remove any previous output so the validation is not accidentally relying on stale objects:

```bash
rm -rf out
./scripts/build.sh
```

A successful build should produce:

```text
out/arch/arm64/boot/Image.gz-dtb
```

Validate the resulting config manually if desired:

```bash
grep -E '^CONFIG_(USB_ACM|USB_SERIAL|USB_SERIAL_GENERIC|USB_SERIAL_CH341|USB_SERIAL_CP210X|USB_SERIAL_FTDI_SIO|USB_SERIAL_PL2303|CAN|CAN_RAW|CAN_DEV|CAN_GS_USB|CAN_SLCAN|MEDIA_USB_SUPPORT|VIDEO_DEV|VIDEO_V4L2|USB_VIDEO_CLASS|USB_UAS|USB_CONFIGFS_ACM)=' out/.config
```

### A fast build is normal

This is only a standalone Linux 4.4 kernel build, not a full Android/LineageOS build. On a modern multi-core desktop it can finish in only a few minutes, and an incremental rebuild can be much faster. The meaningful success checks are that `make` exits successfully, the validation checks pass, and `Image.gz-dtb` is produced.

---

## 12. Add the documentation last

Create or update:

```text
docs/MAINTAINER_SETUP.md
docs/BUILD_INSTALL.md
```

The maintainer guide should explain repository creation, config changes, toolchain pinning, scripts, and commit structure.

The user guide should assume those repository changes already exist and should only explain how to clone, build, create a complete Android `boot.img`, flash, verify, and recover.

Be explicit that `scripts/build.sh` stops at `out/arch/arm64/boot/Image.gz-dtb`. That output is only the kernel payload and is **not** directly flashable to the Android boot partition. The companion user guide must contain the complete boot-image construction flow: copy the currently working boot partition, unpack it with Magisk `magiskboot`, replace only the unpacked `kernel` file with `Image.gz-dtb`, repack it, pull the resulting `custom-boot.img`, and only then flash it.

For a phone that is already rooted with Magisk, using the currently running boot partition as the repack template preserves the existing Magisk-patched ramdisk. This is preferable to inventing boot-header parameters or rebuilding the ramdisk from scratch.

Commit the documentation separately:

```bash
git add docs/MAINTAINER_SETUP.md docs/BUILD_INSTALL.md
git commit -m 'docs: add maintainer and build/install guides'
```

The resulting history is intentionally simple:

```text
1. oneplus5: enable printer host peripheral support
2. build: add reproducible standalone kernel workflow
3. docs: add maintainer and build/install guides
```

Push the branch:

```bash
git push -u origin printer-host-support
```

---

## 13. Troubleshooting lessons from the initial bring-up

### `CONFIG_USB_VIDEO_CLASS did not resolve to =y`

Do not simply force `CONFIG_USB_VIDEO_CLASS=y` repeatedly. Check its media/V4L2 dependency chain. The fork enables the parent symbols explicitly:

```text
CONFIG_MEDIA_SUPPORT=y
CONFIG_MEDIA_CAMERA_SUPPORT=y
CONFIG_MEDIA_USB_SUPPORT=y
CONFIG_VIDEO_DEV=y
CONFIG_VIDEO_V4L2=y
CONFIG_USB_VIDEO_CLASS=y
```

Then regenerate the config from scratch:

```bash
rm -rf out
make O=out ARCH=arm64 SUBARCH=arm64 LLVM=1 lineage_oneplus5_defconfig
```

Inspect the resolved config:

```bash
grep -E '^CONFIG_(MEDIA_SUPPORT|MEDIA_CAMERA_SUPPORT|MEDIA_USB_SUPPORT|VIDEO_DEV|VIDEO_V4L2|USB_VIDEO_CLASS)=' out/.config
```

### `aarch64-linux-android-gcc: not found`

The kernel may be built with Clang while still requiring the Android GCC 4.9 cross-tool prefixes. Verify:

```bash
command -v clang
command -v aarch64-linux-android-gcc
command -v arm-linux-androideabi-gcc
```

All should resolve into `~/op5-kernel/toolchains/` after running:

```bash
./scripts/setup-toolchains.sh
```

### `openssl/bio.h: file not found`

Install the host OpenSSL development package:

```bash
sudo apt install -y libssl-dev
```

This is a host build dependency for kernel utilities such as `scripts/extract-cert`; it is not an Android target dependency.

### Stack-protector warning while the compiler is missing

A message such as:

```text
Cannot use CONFIG_CC_STACKPROTECTOR_STRONG: -fstack-protector-strong not supported by compiler
```

can be a secondary result of the expected compiler command not existing. Fix the toolchain/PATH error first before changing kernel security options.

---

## 14. Updating from LineageOS upstream later

Fetch upstream:

```bash
git fetch upstream
```

Rebase or merge deliberately onto the newer `lineage-22.2` state, resolve any defconfig changes, then perform another clean build and config validation.

Keep these categories separate whenever practical:

- upstream kernel-source update;
- functional defconfig changes;
- toolchain pin changes;
- documentation changes.

That separation makes regressions much easier to identify.
