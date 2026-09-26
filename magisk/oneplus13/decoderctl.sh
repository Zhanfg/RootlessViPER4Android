#!/system/bin/sh
MODDIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
MODPATH="$MODDIR"
. "$MODDIR/common/decoder_source.sh" || exit 2

usage() {
  echo "Usage: decoderctl.sh list|status|select <id>|disable"
}

list_sources() {
  seen=""
  for root in "$MODDIR/decoder_sources" "$DECODER_DATA_ROOT"; do
    [ -d "$root" ] || continue
    for d in "$root"/*; do
      [ -d "$d" ] || continue
      [ -r "$d/source.prop" ] || continue
      id="$(decoder_read_prop id "$d/source.prop")"
      decoder_validate_id "$id" || continue
      case " $seen " in *" $id "*) continue ;; esac
      seen="$seen $id"
      name="$(decoder_read_prop name "$d/source.prop")"
      version="$(decoder_read_prop version "$d/source.prop")"
      ready="$(decoder_read_prop payload_ready "$d/source.prop")"
      backend="$(decoder_read_prop backend "$d/source.prop")"
      tier="$(decoder_read_prop tier "$d/source.prop")"
      activation="$(decoder_read_prop activation "$d/source.prop")"
      echo "$id|$name|$version|ready=${ready:-0}|backend=${backend:-unknown}|tier=${tier:-experimental}|activation=${activation:-unknown}|$d"
    done
  done
}

status_source() {
  echo "selected=$(decoder_source_selected_id)"
  if [ -r "$DECODER_STATE_DIR/active.source.prop" ]; then
    echo "active=$(cat "$DECODER_STATE_DIR/active.source.id" 2>/dev/null)"
    cat "$DECODER_STATE_DIR/active.source.prop"
    echo "mounts:"
    cat "$DECODER_STATE_DIR/mounted.map" 2>/dev/null || true
  else
    echo "active=none"
  fi
  echo "stores:"
  service list 2>/dev/null | grep 'android.hardware.media.c2.IComponentStore' || true
}

select_source() {
  id="$1"
  decoder_validate_id "$id" || {
    echo "Invalid source id: $id" >&2
    exit 3
  }
  mkdir -p "$(dirname "$DECODER_SELECT_FILE")"
  printf '%s\n' "$id" > "$DECODER_SELECT_FILE"
  decoder_install_selected_source
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "Decoder source staging failed: $rc" >&2
    exit "$rc"
  fi
  echo "Staged decoder source '$id'. Reboot required."
}

disable_source() {
  mkdir -p "$(dirname "$DECODER_SELECT_FILE")"
  printf '%s\n' "none" > "$DECODER_SELECT_FILE"
  decoder_unstage_active
  echo "Custom decoder source disabled for next boot. Reboot required."
}

case "$1" in
  list) list_sources ;;
  status) status_source ;;
  select) [ -n "$2" ] || { usage; exit 1; }; select_source "$2" ;;
  disable|none|off) disable_source ;;
  *) usage; exit 1 ;;
esac
