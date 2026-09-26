#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-magisk/oneplus13/decoder_sources}"
fail=0

for dir in "$ROOT"/*; do
  [[ -d "$dir" ]] || continue
  prop="$dir/source.prop"
  map="$dir/mount.map"
  [[ -f "$prop" ]] || { echo "missing source.prop: $dir"; fail=1; continue; }
  [[ -f "$map" ]] || { echo "missing mount.map: $dir"; fail=1; continue; }

  getp() { sed -n "s/^$1=//p" "$prop" | head -1; }
  id="$(getp id)"
  abi="$(getp abi)"
  backend="$(getp backend)"
  ready="$(getp payload_ready)"

  [[ "$id" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "bad id: $id"; fail=1; }
  [[ "$abi" == "arm64-v8a" ]] || { echo "$id: unsupported abi $abi"; fail=1; }
  [[ "$backend" =~ ^codec2-(service|apex|library)$ ]] || { echo "$id: bad backend $backend"; fail=1; }
  [[ "$ready" =~ ^[01]$ ]] || { echo "$id: payload_ready must be 0/1"; fail=1; }

  while IFS='|' read -r rel target mode; do
    [[ -z "$rel" || "$rel" == #* ]] && continue
    case "$target" in
      /vendor/bin/hw/*|/vendor/lib64/*|/vendor/etc/init/*|/vendor/etc/vintf/*|/vendor/etc/seccomp_policy/*|/vendor/etc/media_codecs*.xml|/vendor/etc/media_codecs*.conf|/odm/bin/hw/*|/odm/lib64/*|/odm/etc/init/*|/odm/etc/vintf/*|/odm/etc/seccomp_policy/*|/odm/etc/media_codecs*.xml|/odm/etc/media_codecs*.conf) ;;
      *) echo "$id: forbidden target $target"; fail=1 ;;
    esac
    [[ "$mode" =~ ^0?[0-7]{3,4}$ ]] || { echo "$id: bad mode $mode"; fail=1; }
    if [[ "$ready" == "1" && ! -f "$dir/payload/$rel" ]]; then
      echo "$id: ready source missing payload/$rel"
      fail=1
    fi
  done < "$map"

  if [[ -f "$dir/build.recipe" ]]; then
    grep -q '^source_repo=' "$dir/build.recipe" || { echo "$id: recipe missing source_repo"; fail=1; }
    grep -q '^source_ref=' "$dir/build.recipe" || { echo "$id: recipe missing source_ref"; fail=1; }
    grep -q '^build_target=' "$dir/build.recipe" || { echo "$id: recipe missing build_target"; fail=1; }
  fi

  echo "validated decoder source: $id (ready=$ready)"
done

exit "$fail"
