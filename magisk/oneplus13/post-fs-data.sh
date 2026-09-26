#!/system/bin/sh
MODDIR="$(dirname "$0")"
MARK="$MODDIR/.boot_pending"
LOG="$MODDIR/health.log"

restore_legacy_migration() {
  [ -f "$MODDIR/.migration_pending" ] || return 0
  list="$MODDIR/migration/legacy_modules.list"
  [ -r "$list" ] || return 0

  while IFS= read -r legacy; do
    case "$legacy" in /data/adb/modules/*) ;; *) continue ;; esac
    [ -d "$legacy" ] || continue
    rm -f "$legacy/disable"
    echo "Restored legacy module for rollback: $legacy" >> "$LOG"
  done < "$list"

  rm -f "$MODDIR/.migration_pending"
}

quarantine() {
  mkdir -p "$MODDIR/.quarantine"
  [ -f "$MODDIR/odm/etc/audio_effects_config.xml" ] &&
    mv "$MODDIR/odm/etc/audio_effects_config.xml" "$MODDIR/.quarantine/audio_effects_config.xml"
  [ -f "$MODDIR/system/vendor/etc/audio/sku_sun/audio_effects_config.xml" ] &&
    mv "$MODDIR/system/vendor/etc/audio/sku_sun/audio_effects_config.xml" "$MODDIR/.quarantine/audio_effects_config_sku_sun.xml"
  [ -f "$MODDIR/odm/lib64/soundfx/libjamesdsp_aidl.so" ] &&
    mv "$MODDIR/odm/lib64/soundfx/libjamesdsp_aidl.so" "$MODDIR/.quarantine/libjamesdsp_aidl.so"
  restore_legacy_migration
  touch "$MODDIR/disable"
}

{
  echo "=== post-fs-data $(date 2>/dev/null) ==="
  if [ -f "$MARK" ]; then
    echo "Previous boot did not clear health marker; quarantining JamesDSP overlay"
    quarantine
    rm -f "$MARK"
    exit 0
  fi
  touch "$MARK"
  echo "Health marker armed"
} >> "$LOG" 2>&1
