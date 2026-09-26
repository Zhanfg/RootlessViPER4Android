#!/system/bin/sh
MODDIR="$(dirname "$0")"
LOG="$MODDIR/health.log"
MARK="$MODDIR/.boot_pending"
MODPATH="$MODDIR"
. "$MODDIR/common/decoder_source.sh" 2>/dev/null || true
[ -r "$MODDIR/common/full_bundle.sh" ] && . "$MODDIR/common/full_bundle.sh"

i=0
while [ "$(getprop sys.boot_completed)" != "1" ] && [ "$i" -lt 180 ]; do
  sleep 1
  i=$((i + 1))
done
sleep 5

# Retry full-bundle setup after boot in case shared storage/package manager
# was unavailable during module installation.
type bundle_install_apk >/dev/null 2>&1 && bundle_install_apk >/dev/null 2>&1 || true
type bundle_sync_assets >/dev/null 2>&1 && bundle_sync_assets >/dev/null 2>&1 || true

FACTORY="$(service list 2>/dev/null | grep 'android.hardware.audio.effect.IFactory/default' | head -1)"
AUDIOSERVER="$(pidof audioserver 2>/dev/null)"
AUDIOHAL="$(pidof audiohalservice.qti 2>/dev/null)"
FOUT="$FACTORY"; [ -n "$FOUT" ] || FOUT=missing
AOUT="$AUDIOSERVER"; [ -n "$AOUT" ] || AOUT=missing
HOUT="$AUDIOHAL"; [ -n "$HOUT" ] || HOUT=missing

{
  echo "=== late health $(date 2>/dev/null) ==="
  echo "factory=$FOUT"
  echo "audioserver=$AOUT"
  echo "audiohalservice.qti=$HOUT"
  if [ -s "$MODDIR/JDSP-O13.apk" ]; then
    echo "bundle=full"
    echo "controller_apk_bytes=$(stat -c %s "$MODDIR/JDSP-O13.apk" 2>/dev/null || echo unknown)"
    echo "convolver_files=$(find "$MODDIR/resources/JamesDSP/Convolver" -type f 2>/dev/null | wc -l)"
    echo "ddc_files=$(find "$MODDIR/resources/JamesDSP/DDC" -type f 2>/dev/null | wc -l)"
    echo "liveprog_files=$(find "$MODDIR/resources/JamesDSP/Liveprog" -type f 2>/dev/null | wc -l)"
  else
    echo "bundle=engine-only"
  fi
  echo "registration:"
  grep -i 'f27317f4-c984-4de6-9a90-545759495bf2\|libjamesdsp_aidl.so' \
    /odm/etc/audio_effects_config.xml \
    /vendor/etc/audio/sku_sun/audio_effects_config.xml 2>/dev/null || true
  echo "library:"
  ls -lZ /odm/lib64/soundfx/libjamesdsp_aidl.so 2>/dev/null || true
  echo "recent JamesDSP/QTI effect logs:"
  logcat -d -b all -v brief -t 1200 2>/dev/null |
    grep -Ei 'jamesdsp|AHAL_EffectFactory|audioeffecthal' | tail -120 || true
} >> "$LOG" 2>&1

if [ -z "$FACTORY" ] || [ -z "$AUDIOSERVER" ] || [ -z "$AUDIOHAL" ]; then
  echo "Critical stock audio service missing; disabling module for next boot" >> "$LOG"
  touch "$MODDIR/disable"
  exit 0
fi

if [ -r "$MODDIR/decoder_state/active.source.prop" ]; then
  {
    echo "decoder source:"
    cat "$MODDIR/decoder_state/active.source.prop" 2>/dev/null
    echo "codec2 stores:"
    service list 2>/dev/null | grep 'android.hardware.media.c2.IComponentStore' || true
  } >> "$LOG" 2>&1

  if ! decoder_health_check_active; then
    echo "Decoder source health failed; quarantining decoder layer only" >> "$LOG"
    decoder_quarantine_active
    echo "Decoder source removed from next boot; JamesDSP remains enabled" >> "$LOG"
  else
    echo "Decoder source healthy" >> "$LOG"
  fi
fi

if logcat -d -b all -v brief -t 1200 2>/dev/null |
     grep -i 'libjamesdsp_aidl.so' |
     grep -Eqi 'dlopen.*fail|cannot.*load|not found|linker.*error'; then
  echo "JamesDSP AIDL library load failure; disabling module for next boot" >> "$LOG"
  touch "$MODDIR/disable"
  exit 0
fi

rm -f "$MARK"
echo "Audio services healthy; boot marker cleared" >> "$LOG"
