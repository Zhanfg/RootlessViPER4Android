#!/system/bin/sh

JDSP_UUID="f27317f4-c984-4de6-9a90-545759495bf2"
JDSP_TYPE="f98765f4-c321-5de6-9a45-123459495ab2"
JDSP_LIB_NAME="jamesdsp_aidl"
JDSP_LIB_FILE="libjamesdsp_aidl.so"

patch_jdsp_audio_config() {
  src="$1"
  dst="$2"

  [ -f "$src" ] || { echo "source config missing: $src" >&2; return 2; }
  grep -q '<audio_effects_conf' "$src" || {
    echo "not an audio_effects_conf document: $src" >&2
    return 3
  }
  grep -q '</libraries>' "$src" || { echo "missing </libraries>" >&2; return 4; }
  grep -q '</effects>' "$src" || { echo "missing </effects>" >&2; return 5; }

  if grep -qi "$JDSP_UUID" "$src"; then
    if grep -q "path=\"$JDSP_LIB_FILE\"" "$src"; then
      cp -fp "$src" "$dst" || return 6
      echo "JamesDSP AIDL registration already present"
      return 10
    fi
    echo "conflict: JamesDSP UUID already registered by another library" >&2
    return 20
  fi

  if grep -q "name=\"$JDSP_LIB_NAME\"" "$src"; then
    echo "conflict: library name $JDSP_LIB_NAME already exists" >&2
    return 21
  fi

  tmp="$dst.tmp.$$"
  awk -v libname="$JDSP_LIB_NAME" -v libfile="$JDSP_LIB_FILE" \
      -v uuid="$JDSP_UUID" -v typeuuid="$JDSP_TYPE" '
    BEGIN { added_lib=0; added_effect=0 }
    /<\/libraries>/ && !added_lib {
      printf "        <library name=\"%s\" path=\"%s\"/>\n", libname, libfile
      added_lib=1
    }
    /<\/effects>/ && !added_effect {
      printf "        <effect name=\"jamesdsp\" library=\"%s\" uuid=\"%s\" type=\"%s\"/>\n", libname, uuid, typeuuid
      added_effect=1
    }
    { print }
    END {
      if (!added_lib || !added_effect) exit 42
    }
  ' "$src" > "$tmp" || {
    rc=$?
    rm -f "$tmp"
    echo "failed to patch XML (awk=$rc)" >&2
    return 22
  }

  [ "$(grep -ci "$JDSP_UUID" "$tmp")" -eq 1 ] || {
    rm -f "$tmp"; echo "UUID validation failed" >&2; return 23;
  }
  [ "$(grep -c "path=\"$JDSP_LIB_FILE\"" "$tmp")" -eq 1 ] || {
    rm -f "$tmp"; echo "library validation failed" >&2; return 24;
  }
  [ "$(grep -c '<libraries>' "$tmp")" -eq "$(grep -c '</libraries>' "$tmp")" ] || {
    rm -f "$tmp"; echo "libraries tag balance failed" >&2; return 25;
  }
  [ "$(grep -c '<effects>' "$tmp")" -eq "$(grep -c '</effects>' "$tmp")" ] || {
    rm -f "$tmp"; echo "effects tag balance failed" >&2; return 26;
  }

  mv -f "$tmp" "$dst" || return 27
  return 0
}
