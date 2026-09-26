#!/system/bin/sh
MODDIR="$(dirname "$0")"

echo "=== OnePlus 13 JamesDSP AIDL status ==="
echo "manufacturer=$(getprop ro.product.manufacturer)"
echo "model=$(getprop ro.product.model)"
echo "device=$(getprop ro.product.device)"
echo "board=$(getprop ro.product.board)"
echo "sdk=$(getprop ro.build.version.sdk)"
echo
echo "--- services ---"
service list 2>/dev/null | grep -E 'android.hardware.audio.(effect.IFactory|core.IModule)' || true
echo "audioserver=$(pidof audioserver 2>/dev/null)"
echo "audiohalservice.qti=$(pidof audiohalservice.qti 2>/dev/null)"
echo
echo "--- registration ---"
grep -in 'jamesdsp\|f27317f4-c984-4de6-9a90-545759495bf2' \
  /odm/etc/audio_effects_config.xml \
  /vendor/etc/audio/sku_sun/audio_effects_config.xml 2>/dev/null || true
echo
echo "--- engine ---"
ls -lZ /odm/lib64/soundfx/libjamesdsp_aidl.so 2>/dev/null || true
echo
echo "--- AudioFlinger ---"
dumpsys media.audio_flinger 2>/dev/null |
  grep -Ei -C 3 'jamesdsp|f27317f4|effect chain|session' | head -200 || true
echo
echo "--- recent logs ---"
logcat -d -b all -v time -t 1500 2>/dev/null |
  grep -Ei 'jamesdsp|AHAL_EffectFactory|audioeffecthal|audiohalservice' | tail -200 || true
echo
echo "--- module health log ---"
cat "$MODDIR/health.log" 2>/dev/null || true

echo
echo "--- decoder source ---"
echo "selected=$(cat /data/adb/jdsp/decoder_source.conf 2>/dev/null || echo none)"
if [ -r "$MODDIR/decoder_state/active.source.prop" ]; then
  cat "$MODDIR/decoder_state/active.source.prop"
  echo "mounted:"
  cat "$MODDIR/decoder_state/mounted.map" 2>/dev/null || true
else
  echo "active=none"
fi
echo "Codec2 stores:"
service list 2>/dev/null | grep 'android.hardware.media.c2.IComponentStore' || true
echo "FFmpeg/custom components:"
dumpsys media.codec 2>/dev/null | grep -Ei 'c2\.ffmpeg|decoder' | head -120 || true
