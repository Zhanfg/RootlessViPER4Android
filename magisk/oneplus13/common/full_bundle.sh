#!/system/bin/sh
# Optional full-bundle assets. Engine-only packages simply do not contain them.

bundle_log() {
  if command -v ui_print >/dev/null 2>&1; then
    ui_print "$*"
  else
    echo "$*"
  fi
}

bundle_install_apk() {
  apk="$MODPATH/JDSP-O13.apk"
  [ -s "$apk" ] || return 0

  marker="$MODPATH/.controller_apk.sha256"
  current_hash="$(sha256sum "$apk" 2>/dev/null | awk '{print $1}')"
  installed_hash="$(cat "$marker" 2>/dev/null)"

  bundle_log "- Full bundle: controller APK present"

  if [ -n "$current_hash" ] && [ "$current_hash" = "$installed_hash" ]; then
    bundle_log "- Controller APK bundle unchanged; skipping reinstall"
    return 0
  fi

  if command -v pm >/dev/null 2>&1; then
    if pm install -r "$apk" >/dev/null 2>&1; then
      [ -n "$current_hash" ] && printf '%s\n' "$current_hash" > "$marker"
      bundle_log "- Controller APK installed/updated"
    else
      bundle_log "! Controller APK auto-install failed; APK remains at $apk"
      for out in /sdcard/Download/JDSP-O13.apk /storage/emulated/0/Download/JDSP-O13.apk; do
        parent="$(dirname "$out")"
        [ -d "$parent" ] || continue
        cp -fp "$apk" "$out" 2>/dev/null && {
          bundle_log "- Controller APK copied to $out for manual install"
          break
        }
      done
    fi
  else
    bundle_log "! Package manager unavailable; install $apk manually"
  fi
}
bundle_sync_assets() {
  src="$MODPATH/resources/JamesDSP"
  [ -d "$src" ] || return 0

  # Never overwrite user-created IR/DDC/LiveProg files.
  for base in /sdcard/JamesDSP /storage/emulated/0/JamesDSP; do
    parent="$(dirname "$base")"
    [ -d "$parent" ] || continue
    dst="$base"
    mkdir -p "$dst"

    find "$src" -type f 2>/dev/null | while IFS= read -r file; do
      rel="${file#$src/}"
      out="$dst/$rel"
      [ -e "$out" ] && continue
      mkdir -p "$(dirname "$out")"
      cp -fp "$file" "$out" 2>/dev/null || true
    done

    bundle_log "- Full bundle: seeded missing JamesDSP resources into $dst"
    return 0
  done

  bundle_log "! Shared storage unavailable; bundled resources remain in module"
  return 0
}
