# ZenFone 9: LineageOS + KernelSU Next + GApps on a LOCKED bootloader (simplified guide)

Device: ASUS ZenFone 9 (AI2202, WW/US, platform `taro`), bootloader **locked**.
Result: LineageOS 23.2 (Android 16), root with KernelSU Next (LKM), Google apps, Pixel-style app set.
Bootloader stays locked, dm-verity stays enforcing. Tested on one phone, 5 Nov 2026.

This is a simplified, fixed-up walk-through of josharrington's method
([josharrington/zenfone9-lineageos](https://github.com/josharrington/zenfone9-lineageos)).
Read his [safety warnings](https://github.com/josharrington/zenfone9-lineageos/blob/main/docs/15-install-guide.md) and [how it works](https://github.com/josharrington/zenfone9-lineageos/blob/main/docs/14-lineage-booted.md) first (copies are also in `docs/`).

> **Risks.** This erases all data. There is no verified EDL unbrick path. You keep a private
> signing key (`zf9\key.pem`): lose it and you can only restore stock. Do this on a phone you can lose.

---

## 0. What you need (Windows; Linux works the same with `python3`)

| Item | Where |
|---|---|
| Python 3, Android platform-tools, OpenSSL, `payload-dumper-go`, ASUS USB driver | [docs/setup-windows.md](docs/setup-windows.md) |
| Phone on ASUS firmware **WW-34.0304.2004.145** (tested) | [README downloads](README.md#downloads) |
| This folder (everything below is run from it, e.g. `C:\zf9`) | your copy of this repo |

The installer downloads and SHA-256-verifies the ASUS firmware and the LineageOS ROM itself.
Nothing proprietary is shipped in this folder.

## 1. Install LineageOS (one command)

USB debugging on, phone connected, then from the folder:

```
py -3 scripts\install_lineage_locked.py doctor
py -3 scripts\install_lineage_locked.py install
```

It generates your key, signs the boot chain, wipes data, writes the logical partitions and boots
LineageOS. First boot can stay black for several minutes.
**Back up `zf9\key.pem` now** (off this PC).

If it stopped while the phone was in **fastbootd** (e.g. a cable drop), resume with:
```
py -3 scripts\install_lineage_locked.py finish
```

## 2. Root: KernelSU Next (LKM)

1. Install the KernelSU Next manager APK ([releases](https://github.com/KernelSU-Next/KernelSU-Next/releases/latest)).
2. `adb push zf9\images\lineage\boot.img /sdcard/Download/boot.img`
3. In the app: **Install → Select a file** → that `boot.img` → KMI **`android12-5.10`**
   (this kernel's version string has no `androidXX` tag, so it asks).
   **Never** use *Direct install* or *Install to inactive slot*: they write boot without re-signing.
4. Pull the patched file and sign + flash it:
   ```
   adb pull /sdcard/Download/<kernelsu_next_patched_file>.img zf9\boot_ksun.img
   py -3 scripts\install_lineage_locked.py root --patched-boot .\zf9\boot_ksun.img
   ```
   Ignore its Magisk wording at the end. The app should show **Working · LKM**.
   If it does not, repeat step 3 with `android13-5.10`.
5. Run `zf9-sync.cmd` once. It should say *phone is in sync*, and it saves a last-known-good copy
   to `zf9\current\` (used by the recovery command in section 6).

## 3. Metamodule (required before any module can mount files)

KernelSU Next hands file mounting to one *metamodule*. Install **mountify**
([backslashxx/mountify](https://github.com/backslashxx/mountify)) in the app, reboot.
Only one metamodule at a time; switching uninstalls all modules.

## 4. Google apps (systemless, verity stays on)

A normal GApps zip in recovery would modify verified partitions and break boot. Use a module instead:

1. Download the official **MindTheGapps 16.0.0 arm64** zip ([releases](https://github.com/MindTheGapps/16.0.0-arm64/releases)).
2. Build the module (repacks your download; no Google files are shipped here):
   ```
   py -3 scripts\build_gapps_module.py C:\path\to\MindTheGapps-16.0.0-arm64-XXXXXXXX_XXXXXX.zip
   adb push zf9\downloads\mtg_core_ksun.zip /sdcard/Download/
   ```
3. Install `mtg_core_ksun.zip` in KernelSU Next → reboot → check:
   ```
   adb shell ls /product/priv-app/GmsCore
   adb shell pm path com.google.android.gms
   ```
4. Sign in: Settings → Passwords & accounts → Google.
   Restoring app data after setup (no setup wizard): `adb shell bmgr list sets`, then
   `adb shell bmgr restore <token> <package> [<package>...]` for apps you reinstalled.

## 5. Pixelify (Google apps as defaults, Lineage duplicates disabled)

```
powershell -ExecutionPolicy Bypass -File .\zf9-pixelify.ps1
```
Opens each missing Google app in the Play Store (tap Install, press Enter), makes Phone,
Messages, Chrome and Gboard the defaults, then **disables** (never uninstalls) the Lineage twins.
Undo: `-Undo`. AudioFX stays enabled. Re-apply after installing more apps: `-Apply`.

Optional sideloads (from APKMirror, signature-verified): Pixel Weather, Google Recorder.

## 6. Living with it

| Situation | Do this |
|---|---|
| After a KonaBess GPU edit or a KernelSU Next update | **Don't reboot.** Run `zf9-sync.cmd`, answer `y`. It re-signs only vbmeta for what changed. |
| Phone shows *avb check failed* | Hold Vol Down + Power (bootloader), then `py -3 scripts\install_lineage_locked.py resign --boot-img zf9\current\boot.img --vendor-boot-img zf9\current\vendor_boot.img --dtbo-img zf9\current\dtbo.img` |
| Back to clean Lineage (no root) | `py -3 scripts\install_lineage_locked.py resign` |
| Back to stock ASUS | `py -3 scripts\install_lineage_locked.py restore` |
| A module bootloops | Press Volume Down repeatedly during boot (KernelSU safe mode), remove it |

Never: OTA updates, recovery sideloads, GApps/mod zips in recovery, KernelSU *Direct install*.

## Known limitations

- Boot state is yellow (custom key): boot warning screen, Play Integrity device/strong usually fail.
- Slot b is emptied during install; there is no A/B fallback.
- Updates = re-run the installer with a new build (no OTA).
- Some GPU driver modules crash the Qualcomm media codec HAL on this ROM
  (check: `adb shell "su -c 'dmesg | grep -c c2-hal'"` should stay ~0).

## What this fork changes vs upstream

- **Install no longer fails with `Not enough space for partition`.** The installer now cancels
  any pending Virtual A/B snapshot and deletes *every* logical partition in super (other slot,
  orphaned `*-cow`), verifies super is empty, then creates partitions largest-first.
- **AVB hash descriptor bug fixed.** `num_bytes_following` was not padded to a multiple of 8.
  It happened to work for `boot` (4-letter name) but made any re-signed `vendor_boot` fail with
  *avb check failed*. Descriptors are now byte-identical to `avbtool`, and every vbmeta is checked
  against libavb's descriptor rules before flashing.
- `vendor_boot`/`dtbo` are hashed over their header length (what the bootloader verifies).
- New commands: `finish` (resume from fastbootd), `resign` (flash any boot/dtbo/vendor_boot with a
  matching signed vbmeta), `sync` (re-sign vbmeta for whatever is live after KonaBess/KernelSU updates).
- Systemless GApps module builder and the Pixelify script.

## Credits

- **josharrington**: the locked-bootloader method, installer and docs this is built on.
- **Lynnrin (rinko)**: the unofficial LineageOS 23.2 build for the ZenFone 9.
- **LineageOS project**; **ASUS** for the firmware.
- **KernelSU Next** team (rifsxd and contributors) and **KernelSU** (tiann) for LKM root and docs.
- **MindTheGapps** for the GApps package; **backslashxx & KOWX712** for mountify.
- **ssut** for payload-dumper-go; **Google/AOSP** for AVB/libavb; **topjohnwu** for Magisk.
- **libxzr** for KonaBess (optional GPU tuning).
- Fixes, testing and this guide: **Ric89925**, with **Claude (Anthropic)** as AI assistant.
