#!/system/bin/sh
# Optional full-bundle assets. Engine-only packages simply do not contain them.

bundle_install_apk() {
  apk="$MODPATH/JDSP-O13.apk"
  [ -s "$apk" ] || return 0

  ui_print "- Full bundle: controller APK present"
  if command -v pm >/dev/null 2>&1; then
    if pm install -r "$apk" >/dev/null 2>&1; then
      ui_print "- Controller APK installed/updated"
    else
      ui_print "! Controller APK auto-install failed; APK remains at $apk"
    fi
  else
    ui_print "! Package manager unavailable; install $apk manually"
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

    ui_print "- Full bundle: seeded missing JamesDSP resources into $dst"
    return 0
  done

  ui_print "! Shared storage unavailable; bundled resources remain in module"
  return 0
}
