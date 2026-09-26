#!/system/bin/sh
MODDIR="$(dirname "$0")"
LOG="$MODDIR/health.log"
MARK="$MODDIR/.boot_pending"
CTRL_PKG="com.alienware377.viper4android.rootful"
CTRL_APK="$MODDIR/JamesDSPManager.apk"

i=0
while [ "$(getprop sys.boot_completed)" != "1" ] && [ "$i" -lt 180 ]; do
  sleep 1
  i=$((i + 1))
done
sleep 5

# Install/update the bundled rootful controller after Android has finished booting.
# Keep the APK in the module so the controller version always matches the engine.
if [ -s "$CTRL_APK" ]; then
  INSTALLED_APK="$(pm path "$CTRL_PKG" 2>/dev/null | sed -n 's/^package://p' | head -1)"
  NEED_INSTALL=1
  if [ -n "$INSTALLED_APK" ] && [ -r "$INSTALLED_APK" ]; then
    BUNDLED_SHA="$(sha256sum "$CTRL_APK" 2>/dev/null | awk '{print $1}')"
    INSTALLED_SHA="$(sha256sum "$INSTALLED_APK" 2>/dev/null | awk '{print $1}')"
    [ -n "$BUNDLED_SHA" ] && [ "$BUNDLED_SHA" = "$INSTALLED_SHA" ] && NEED_INSTALL=0
  fi

  if [ "$NEED_INSTALL" -eq 1 ]; then
    TMP_APK="/data/local/tmp/oneplus13-jdsp-controller.apk"
    cp -f "$CTRL_APK" "$TMP_APK"
    chmod 0644 "$TMP_APK"
    OUT="$(cmd package install -r -g "$TMP_APK" 2>&1)"
    RC=$?
    rm -f "$TMP_APK"
    {
      echo "controller_install_rc=$RC"
      echo "$OUT"
    } >> "$LOG"
  fi
fi

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
