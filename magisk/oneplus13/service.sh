#!/system/bin/sh
MODDIR="$(dirname "$0")"
LOG="$MODDIR/health.log"
MARK="$MODDIR/.boot_pending"

i=0
while [ "$(getprop sys.boot_completed)" != "1" ] && [ "$i" -lt 180 ]; do
  sleep 1
  i=$((i + 1))
done
sleep 5

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

if logcat -d -b all -v brief -t 1200 2>/dev/null |
     grep -i 'libjamesdsp_aidl.so' |
     grep -Eqi 'dlopen.*fail|cannot.*load|not found|linker.*error'; then
  echo "JamesDSP AIDL library load failure; disabling module for next boot" >> "$LOG"
  touch "$MODDIR/disable"
  exit 0
fi

rm -f "$MARK"
echo "Audio services healthy; boot marker cleared" >> "$LOG"
