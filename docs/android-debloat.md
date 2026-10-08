# OnePlus 5 — Android Debloat / RAM

## Commands

### Disable an app
```bash
adb shell pm disable-user --user 0 <package>
```

Or directly from the phone/root shell:

```bash
pm disable-user --user 0 <package>
```

### Re-enable an app
```bash
adb shell pm enable <package>
```

Or:

```bash
pm enable <package>
```

### Check which packages are disabled
```bash
pm list packages -d
```

### Check RAM after changes
```bash
dumpsys meminfo | head -50
```

For process-level RSS:

```bash
ps -A -o PID,USER,RSS,NAME --sort=-RSS | head -30
```

---

## Disabled Packages

These are the packages disabled to reduce unnecessary Android background activity.

- `org.mozilla.firefox` — Firefox
- `de.marmaro.krt.ffupdater` — FFUpdater
- `org.fdroid.fdroid` — F-Droid
- `com.stevesoltys.seedvault` — Seedvault backup
- `com.android.nfc` — NFC
- `com.android.deskclock` — Clock
- `org.lineageos.audiofx` — LineageOS AudioFX
- `com.android.dialer`
- `com.android.messaging`

> **Note:** Keep core Android processes such as `system_server`, `SystemUI`, `zygote`, NetworkStack, telephony, and the camera provider enabled. The phone is being used as a dedicated Klipper appliance, so avoid disabling anything needed for Wi-Fi, camera, display, or the Debian container.
