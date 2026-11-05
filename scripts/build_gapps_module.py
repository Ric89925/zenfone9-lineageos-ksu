#!/usr/bin/env python3
"""Build a systemless MindTheGapps "core" module for KernelSU (Next) from the OFFICIAL zip.

Usage:  py -3 scripts/build_gapps_module.py MindTheGapps-16.0.0-arm64-YYYYMMDD_HHMMSS.zip
Output: zf9/downloads/mtg_core_ksun.zip   (install it in KernelSU Next AFTER a metamodule)

Why a module: on a locked bootloader system/product are dm-verity protected, so a recovery
GApps zip would break boot. A module is mounted over /product and /system_ext from /data.
Google's APKs are not redistributed here; this only repacks the zip you downloaded.
"""
import sys, zipfile, re
from pathlib import Path

# Same optional apps MindTheGapps drops when space is short, plus the tablet build and the
# setup wizard (the phone is already set up). All of these can be installed from Play later.
DROP = ("system/product/priv-app/VelvetTitan/", "system/product/priv-app/Velvet/",
        "system/product/app/SpeechServicesByGoogle/", "system/product/app/talkback/",
        "system/product/priv-app/Wellbeing/", "system/product/priv-app/GoogleRestore/",
        "system/product/app/MarkupGoogle_v2/", "system/system_ext/priv-app/SetupWizard/",
        "system/product/overlay/GmsSetupWizardOverlay.apk", "system/product/etc/init/")

def main() -> None:
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    src = Path(sys.argv[1])
    m = re.search(r"MindTheGapps-(16\.0\.0)-arm64-(\d{8}_\d{6})", src.name)
    if not m:
        sys.exit(f"{src.name}: expected an official MindTheGapps-16.0.0-arm64-*.zip")
    out = Path(__file__).resolve().parent.parent / "zf9" / "downloads" / "mtg_core_ksun.zip"
    out.parent.mkdir(parents=True, exist_ok=True)
    files = {
        "module.prop": (f"id=mtg_core\nname=MindTheGapps core (systemless)\nversion={m[1]}-{m[2]}\n"
                        f"versionCode={m[2][:8]}\nauthor=MindTheGapps (repack for KernelSU Next)\n"
                        "description=Play Services, Play Store, GSF and sync adapters mounted over "
                        "/product and /system_ext. Verified partitions untouched.\n"),
        "system.prop": ("# from MindTheGapps gapps.rc (module .rc files load too late)\n"
                        "ro.com.google.gmsversion=16_202505\nro.opa.eligible_device=true\n"),
        "customize.sh": ('[ "$API" -ge 36 ] || abort "! Needs Android 16 (API 36); this is API $API"\n'
                         '[ "$ARCH" = "arm64" ] || abort "! arm64 only; this is $ARCH"\n'
                         'ui_print "- MindTheGapps core for /product + /system_ext"\n'
                         'set_perm_recursive "$MODPATH/system" 0 0 0755 0644 u:object_r:system_file:s0\n'),
    }
    n = 0
    with zipfile.ZipFile(src) as zin, zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=1) as zout:
        for name, text in files.items():
            zout.writestr(name, text)
        for info in zin.infolist():
            nm = info.filename
            if info.is_dir() or not nm.startswith(("system/product/", "system/system_ext/")):
                continue
            if nm.startswith(DROP):
                continue
            zout.writestr(nm, zin.read(nm))
            n += 1
    if n < 20:
        sys.exit(f"only {n} files copied; is this the right zip?")
    print(f"ok: {out} ({n} files, {out.stat().st_size:,} bytes)")

if __name__ == "__main__":
    main()
