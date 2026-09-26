#!/system/bin/sh
# Decoder Source Mount Layer
# Generic systemless staging for add-on Codec2 decoder stores.

DECODER_DATA_ROOT="/data/adb/jdsp/decoder_sources"
DECODER_SELECT_FILE="/data/adb/jdsp/decoder_source.conf"
DECODER_STATE_DIR="$MODPATH/decoder_state"

decoder_log() {
  if command -v ui_print >/dev/null 2>&1; then
    ui_print "- Decoder: $*"
  else
    echo "Decoder: $*"
  fi
}

decoder_read_prop() {
  key="$1"
  file="$2"
  [ -r "$file" ] || return 1
  sed -n "s/^$key=//p" "$file" | head -1
}

decoder_validate_id() {
  case "$1" in
    ""|*[!A-Za-z0-9._-]*) return 1 ;;
    *) return 0 ;;
  esac
}

decoder_target_allowed() {
  case "$1" in
    /vendor/bin/hw/*|\
    /vendor/lib64/*|\
    /vendor/etc/init/*|\
    /vendor/etc/vintf/*|\
    /vendor/etc/seccomp_policy/*|\
    /vendor/etc/media_codecs*.xml|\
    /vendor/etc/media_codecs*.conf|\
    /odm/bin/hw/*|\
    /odm/lib64/*|\
    /odm/etc/init/*|\
    /odm/etc/vintf/*|\
    /odm/etc/seccomp_policy/*|\
    /odm/etc/media_codecs*.xml|\
    /odm/etc/media_codecs*.conf)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

decoder_module_path_for_target() {
  target="$1"
  case "$target" in
    /vendor/*) printf '%s/system/vendor/%s\n' "$MODPATH" "${target#/vendor/}" ;;
    /odm/*)    printf '%s/odm/%s\n' "$MODPATH" "${target#/odm/}" ;;
    *) return 1 ;;
  esac
}

decoder_source_selected_id() {
  [ -r "$DECODER_SELECT_FILE" ] || { echo "none"; return 0; }
  sed -n '1{s/[[:space:]]//g;p;}' "$DECODER_SELECT_FILE"
}

decoder_find_source() {
  id="$1"
  for root in "$MODPATH/decoder_sources" "$DECODER_DATA_ROOT"; do
    [ -d "$root/$id" ] && { printf '%s\n' "$root/$id"; return 0; }
  done
  return 1
}

decoder_validate_source() {
  srcdir="$1"
  prop="$srcdir/source.prop"
  map="$srcdir/mount.map"

  [ -r "$prop" ] || { decoder_log "missing source.prop"; return 20; }
  [ -r "$map" ] || { decoder_log "missing mount.map"; return 21; }

  id="$(decoder_read_prop id "$prop")"
  backend="$(decoder_read_prop backend "$prop")"
  abi="$(decoder_read_prop abi "$prop")"
  amin="$(decoder_read_prop android_min "$prop")"
  amax="$(decoder_read_prop android_max "$prop")"

  decoder_validate_id "$id" || { decoder_log "invalid id: $id"; return 22; }
  [ "$abi" = "arm64-v8a" ] || { decoder_log "unsupported ABI: $abi"; return 23; }

  sdk="$(getprop ro.build.version.sdk)"
  [ -n "$amin" ] && [ "$sdk" -lt "$amin" ] 2>/dev/null && {
    decoder_log "API $sdk below source minimum $amin"; return 24;
  }
  [ -n "$amax" ] && [ "$sdk" -gt "$amax" ] 2>/dev/null && {
    decoder_log "API $sdk above source maximum $amax"; return 25;
  }

  case "$backend" in
    codec2-service|codec2-apex|codec2-library) ;;
    *) decoder_log "unsupported backend: $backend"; return 26 ;;
  esac

  while IFS='|' read -r rel target mode; do
    case "$rel" in ""|\#*) continue ;; esac
    [ -n "$target" ] || { decoder_log "empty mount target"; return 27; }
    decoder_target_allowed "$target" || {
      decoder_log "target outside decoder allowlist: $target"; return 28;
    }
    case "$rel" in
      /*|*..*) decoder_log "unsafe payload path: $rel"; return 29 ;;
    esac
    [ -f "$srcdir/payload/$rel" ] || {
      decoder_log "missing payload: $rel"; return 30;
    }
  done < "$map"

  if [ -x "$srcdir/verify.sh" ]; then
    DECODER_SOURCE_DIR="$srcdir" DECODER_SOURCE_PROP="$prop" \
      sh "$srcdir/verify.sh" || return 31
  fi

  return 0
}

decoder_stage_source() {
  srcdir="$1"
  prop="$srcdir/source.prop"
  id="$(decoder_read_prop id "$prop")"
  replace="$(decoder_read_prop allow_replace "$prop")"
  [ "$replace" = "1" ] || replace=0

  mkdir -p "$DECODER_STATE_DIR"
  : > "$DECODER_STATE_DIR/mounted.map"

  while IFS='|' read -r rel target mode; do
    case "$rel" in ""|\#*) continue ;; esac

    decoder_target_allowed "$target" || return 40
    dst="$(decoder_module_path_for_target "$target")" || return 41

    if [ -e "$target" ] && [ "$replace" != "1" ]; then
      decoder_log "refusing stock collision: $target"
      return 42
    fi

    mkdir -p "$(dirname "$dst")"
    cp -fp "$srcdir/payload/$rel" "$dst" || return 43

    perm="${mode:-0644}"
    chmod "$perm" "$dst" 2>/dev/null || true

    case "$target" in
      */bin/*|*/bin/hw/*) chcon u:object_r:vendor_file:s0 "$dst" 2>/dev/null || true ;;
      */etc/*)            chcon u:object_r:vendor_configs_file:s0 "$dst" 2>/dev/null || true ;;
      */lib64/*)          chcon u:object_r:vendor_file:s0 "$dst" 2>/dev/null || true ;;
    esac

    printf '%s|%s\n' "$target" "$dst" >> "$DECODER_STATE_DIR/mounted.map"
  done < "$srcdir/mount.map"

  cp -fp "$prop" "$DECODER_STATE_DIR/active.source.prop"
  printf '%s\n' "$srcdir" > "$DECODER_STATE_DIR/active.source.path"
  printf '%s\n' "$id" > "$DECODER_STATE_DIR/active.source.id"
  decoder_log "staged source: $id"
  return 0
}

decoder_install_selected_source() {
  id="$(decoder_source_selected_id)"
  case "$id" in
    ""|none|off|disabled)
      decoder_log "no custom decoder source selected"
      rm -rf "$DECODER_STATE_DIR"
      return 0
      ;;
  esac

  decoder_validate_id "$id" || {
    decoder_log "invalid selected source id: $id"
    return 50
  }

  srcdir="$(decoder_find_source "$id")" || {
    decoder_log "selected source not found: $id"
    return 51
  }

  decoder_log "validating source $id"
  decoder_validate_source "$srcdir" || return $?
  decoder_stage_source "$srcdir" || return $?
  return 0
}

decoder_health_check_active() {
  [ -r "$DECODER_STATE_DIR/active.source.prop" ] || return 0

  prop="$DECODER_STATE_DIR/active.source.prop"
  srcpath="$(cat "$DECODER_STATE_DIR/active.source.path" 2>/dev/null)"
  instance="$(decoder_read_prop service_instance "$prop")"
  expect="$(decoder_read_prop expected_components "$prop")"

  ok=1
  if [ -n "$instance" ]; then
    service list 2>/dev/null |
      grep -q "android.hardware.media.c2.IComponentStore/$instance" || ok=0
  fi

  OLDIFS="$IFS"; IFS=','
  for c in $expect; do
    [ -n "$c" ] || continue
    dumpsys media.codec 2>/dev/null | grep -q "$c" || {
      logcat -d -b all -t 1500 2>/dev/null | grep -q "$c" || ok=0
    }
  done
  IFS="$OLDIFS"

  if [ -n "$srcpath" ] && [ -x "$srcpath/health.sh" ]; then
    DECODER_SOURCE_DIR="$srcpath" DECODER_SOURCE_PROP="$prop" \
      sh "$srcpath/health.sh" || ok=0
  fi

  [ "$ok" = "1" ]
}

decoder_quarantine_active() {
  [ -d "$DECODER_STATE_DIR" ] || return 0
  q="$MODPATH/.decoder_quarantine"
  rm -rf "$q"
  mkdir -p "$q"

  if [ -r "$DECODER_STATE_DIR/mounted.map" ]; then
    while IFS='|' read -r target staged; do
      [ -n "$staged" ] || continue
      [ -e "$staged" ] || continue
      rel="${staged#$MODPATH/}"
      mkdir -p "$q/$(dirname "$rel")"
      mv "$staged" "$q/$rel" 2>/dev/null || rm -f "$staged"
    done < "$DECODER_STATE_DIR/mounted.map"
  fi

  cp -af "$DECODER_STATE_DIR" "$q/state" 2>/dev/null || true
  rm -rf "$DECODER_STATE_DIR"
  return 0
}
