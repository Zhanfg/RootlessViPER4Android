#!/system/bin/sh
SKIPUNZIP=0

ui_print "- OnePlus 13 JamesDSP AIDL (Android 16)"
ui_print "- Additive QTI EffectFactory integration; no factory replacement"

MANUFACTURER="$(getprop ro.product.manufacturer)"
MODEL="$(getprop ro.product.model)"
DEVICE="$(getprop ro.product.device)"
VDEVICE="$(getprop ro.product.vendor.device)"
BOARD="$(getprop ro.product.board)"
PLATFORM="$(getprop ro.board.platform)"
SOC="$(getprop ro.soc.model)"
SDK="$(getprop ro.build.version.sdk)"

[ "$ARCH" = "arm64" ] || abort "! arm64 only"
[ "$MANUFACTURER" = "OnePlus" ] || abort "! Target manufacturer mismatch: $MANUFACTURER"
[ "$MODEL" = "PJZ110" ] || abort "! Target model mismatch: $MODEL"
[ "$SDK" = "36" ] || abort "! Android 16 / API 36 required; got API $SDK"

case "$BOARD $PLATFORM $SOC" in
  *sun*|*SM8750*|*sm8750*) ;;
  *) abort "! SM8750/sun target not detected: board=$BOARD platform=$PLATFORM soc=$SOC" ;;
esac

ui_print "- Device identity: model=$MODEL device=$DEVICE vendor_device=$VDEVICE"
ui_print "- Platform: board=$BOARD platform=$PLATFORM soc=$SOC"

if ! service list 2>/dev/null | grep -q 'android.hardware.audio.effect.IFactory/default'; then
  abort "! Stock AIDL audio effect factory is not visible; refusing to install"
fi

for old in ainur_jamesdsp jamesdsp JamesDSP; do
  d="/data/adb/modules/$old"
  if [ -d "$d" ] && [ ! -f "$d/disable" ] && [ ! -f "$d/remove" ]; then
    abort "! Active legacy JamesDSP module detected: $old. Disable it and reboot before installing this build."
  fi
done

LIB="$MODPATH/payload/libjamesdsp_aidl.so"
[ -s "$LIB" ] || abort "! Missing verified libjamesdsp_aidl.so; this package is not flash-ready"

. "$MODPATH/common/patch_audio_config.sh" || abort "! Failed to load patcher"
. "$MODPATH/common/decoder_source.sh" || abort "! Failed to load decoder source layer"

mkdir -p "$MODPATH/baseline"
PATCHED=0

patch_one() {
  src="$1"
  rel="$2"
  tag="$3"
  [ -f "$src" ] || return 0

  dst="$MODPATH/$rel"
  mkdir -p "$(dirname "$dst")"

  patch_jdsp_audio_config "$src" "$dst"
  rc=$?
  case "$rc" in
    0|10)
      ui_print "- Patched $src"
      cp -fp "$src" "$MODPATH/baseline/$tag.before.xml"
      sha256sum "$src" > "$MODPATH/baseline/$tag.before.sha256" 2>/dev/null || true
      printf '%s\n' "$src" > "$MODPATH/baseline/$tag.source_path"
      PATCHED=$((PATCHED + 1))
      ;;
    *)
      abort "! Refusing unsafe patch for $src (code $rc)"
      ;;
  esac
}

# Patch every live O13 effect config that exists. Do not choose only the first:
# ColorOS/QTI can consume the ODM base together with the sku_sun vendor config.
patch_one /odm/etc/audio_effects_config.xml   odm/etc/audio_effects_config.xml odm

patch_one /vendor/etc/audio/sku_sun/audio_effects_config.xml   system/vendor/etc/audio/sku_sun/audio_effects_config.xml vendor_sku_sun

[ "$PATCHED" -gt 0 ] || abort "! No supported OnePlus 13 AIDL audio effect config found"

mkdir -p "$MODPATH/odm/lib64/soundfx"
mv "$LIB" "$MODPATH/odm/lib64/soundfx/libjamesdsp_aidl.so"
rm -rf "$MODPATH/payload"

set_perm "$MODPATH/odm/lib64/soundfx/libjamesdsp_aidl.so" 0 0 0644
chcon u:object_r:vendor_file:s0 "$MODPATH/odm/lib64/soundfx/libjamesdsp_aidl.so" 2>/dev/null || true

[ -f "$MODPATH/odm/etc/audio_effects_config.xml" ] &&
  set_perm "$MODPATH/odm/etc/audio_effects_config.xml" 0 2000 0644
[ -f "$MODPATH/system/vendor/etc/audio/sku_sun/audio_effects_config.xml" ] &&
  set_perm "$MODPATH/system/vendor/etc/audio/sku_sun/audio_effects_config.xml" 0 2000 0644

ui_print "- Patched $PATCHED live effect config(s)"
ui_print "- Stock IFactory/default is untouched"
ui_print "- No global <apply> entry was added; the root app attaches per session"

# Optional decoder source is a separate failure domain. Reject/quarantine only
# the decoder layer and keep the JamesDSP effect install intact.
decoder_install_selected_source
decoder_rc=$?
if [ "$decoder_rc" -ne 0 ]; then
  ui_print "! Decoder source rejected (code $decoder_rc); JamesDSP install continues"
  decoder_quarantine_active
fi

ui_print "- Reboot required"
