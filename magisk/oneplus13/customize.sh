#!/system/bin/sh
SKIPUNZIP=0

ui_print "- OnePlus 13 JamesDSP AIDL (Android 16)"
ui_print "- Additive QTI EffectFactory integration; no factory replacement"

MANUFACTURER="$(getprop ro.product.manufacturer)"
MODEL="$(getprop ro.product.model)"
DEVICE="$(getprop ro.product.device)"
BOARD="$(getprop ro.product.board)"
SDK="$(getprop ro.build.version.sdk)"

[ "$ARCH" = "arm64" ] || abort "! arm64 only"
[ "$MANUFACTURER" = "OnePlus" ] || abort "! Target manufacturer mismatch: $MANUFACTURER"
[ "$MODEL" = "PJZ110" ] || abort "! Target model mismatch: $MODEL"
[ "$DEVICE" = "OP5D0DL1" ] || abort "! Target device mismatch: $DEVICE"
[ "$BOARD" = "sun" ] || abort "! Target board mismatch: $BOARD"
[ "$SDK" = "36" ] || abort "! Android 16 / API 36 required; got API $SDK"

for old in ainur_jamesdsp jamesdsp JamesDSP; do
  d="/data/adb/modules/$old"
  if [ -d "$d" ] && [ ! -f "$d/disable" ] && [ ! -f "$d/remove" ]; then
    abort "! Active legacy JamesDSP module detected: $old. Disable it and reboot before installing this build."
  fi
done

LIB="$MODPATH/payload/libjamesdsp_aidl.so"
[ -s "$LIB" ] || abort "! Missing verified libjamesdsp_aidl.so; this package is not flash-ready"

SRC=""
DEST_REL=""
for candidate in \
  /odm/etc/audio_effects_config.xml \
  /vendor/etc/audio/sku_sun/audio_effects_config.xml; do
  if [ -f "$candidate" ]; then
    SRC="$candidate"
    case "$candidate" in
      /odm/*) DEST_REL="odm/etc/audio_effects_config.xml" ;;
      /vendor/*) DEST_REL="system/vendor/etc/audio/sku_sun/audio_effects_config.xml" ;;
    esac
    break
  fi
done
[ -n "$SRC" ] || abort "! No supported OnePlus 13 AIDL audio effect config found"

. "$MODPATH/common/patch_audio_config.sh" || abort "! Failed to load patcher"

DEST="$MODPATH/$DEST_REL"
mkdir -p "$(dirname "$DEST")"
patch_jdsp_audio_config "$SRC" "$DEST"
rc=$?
case "$rc" in
  0) ui_print "- Patched active config: $SRC" ;;
  10) ui_print "- Config was already patched for this AIDL engine" ;;
  *) abort "! Refusing unsafe audio config patch (code $rc)" ;;
esac

mkdir -p "$MODPATH/baseline"
cp -fp "$SRC" "$MODPATH/baseline/audio_effects_config.before.xml"
sha256sum "$SRC" > "$MODPATH/baseline/audio_effects_config.before.sha256" 2>/dev/null || true
printf '%s\n' "$SRC" > "$MODPATH/baseline/source_path"

mkdir -p "$MODPATH/odm/lib64/soundfx"
mv "$LIB" "$MODPATH/odm/lib64/soundfx/libjamesdsp_aidl.so"
rm -rf "$MODPATH/payload"

set_perm "$MODPATH/odm/lib64/soundfx/libjamesdsp_aidl.so" 0 0 0644
set_perm "$DEST" 0 2000 0644
chcon u:object_r:vendor_file:s0 "$MODPATH/odm/lib64/soundfx/libjamesdsp_aidl.so" 2>/dev/null || true
chcon u:object_r:vendor_configs_file:s0 "$DEST" 2>/dev/null || true

ui_print "- Stock IFactory/default is untouched"
ui_print "- No global <apply> entry was added; the root app attaches per session"
ui_print "- Reboot required"
