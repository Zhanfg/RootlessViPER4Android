#!/system/bin/sh

JDSP_UUID="f27317f4-c984-4de6-9a90-545759495bf2"
JDSP_TYPE="f98765f4-c321-5de6-9a45-123459495ab2"
JDSP_LIB_NAME="jamesdsp_aidl"
JDSP_LIB_FILE="libjamesdsp_aidl.so"
JDSP_LEGACY_LIB_FILE="libjamesdsp.so"

validate_jdsp_audio_config() {
  file="$1"

  [ "$(grep -ci "$JDSP_UUID" "$file" 2>/dev/null)" -eq 1 ] || {
    echo "UUID validation failed" >&2
    return 31
  }
  [ "$(grep -c "path=\"$JDSP_LIB_FILE\"" "$file" 2>/dev/null)" -eq 1 ] || {
    echo "library validation failed" >&2
    return 32
  }
  [ "$(grep -c '<libraries' "$file" 2>/dev/null)" -eq "$(grep -c '</libraries>' "$file" 2>/dev/null)" ] || {
    echo "libraries tag balance failed" >&2
    return 33
  }
  [ "$(grep -c '<effects' "$file" 2>/dev/null)" -eq "$(grep -c '</effects>' "$file" 2>/dev/null)" ] || {
    echo "effects tag balance failed" >&2
    return 34
  }
  return 0
}

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

  mkdir -p "$(dirname "$dst")"

  if grep -qi "$JDSP_UUID" "$src"; then
    if grep -q "path=\"$JDSP_LIB_FILE\"" "$src"; then
      cp -fp "$src" "$dst" || return 6
      validate_jdsp_audio_config "$dst" || return $?
      echo "JamesDSP AIDL registration already present"
      return 10
    fi

    if [ "${JDSP_ALLOW_LEGACY_MIGRATION:-0}" = "1" ]; then
      uuid_count="$(grep -ci "$JDSP_UUID" "$src" 2>/dev/null)"
      [ "$uuid_count" -eq 1 ] || {
        echo "legacy migration rejected: UUID appears $uuid_count times" >&2
        return 23
      }

      effect_line="$(grep -i "$JDSP_UUID" "$src" | head -1)"
      printf '%s\n' "$effect_line" | grep -Eqi 'name="jamesdsp"' || {
        echo "legacy migration rejected: UUID owner is not JamesDSP" >&2
        return 24
      }

      legacy_lib="$(printf '%s\n' "$effect_line" |
        sed -n 's/.*library="\([^"]*\)".*/\1/p' | head -1)"
      [ -n "$legacy_lib" ] || {
        echo "legacy migration rejected: cannot resolve legacy library" >&2
        return 25
      }

      legacy_lib_defs="$(grep -E "name=\"$legacy_lib\"" "$src" 2>/dev/null |
        grep -c "path=\"$JDSP_LEGACY_LIB_FILE\"")"
      [ "$legacy_lib_defs" -eq 1 ] || {
        echo "legacy migration rejected: expected one $JDSP_LEGACY_LIB_FILE definition for $legacy_lib" >&2
        return 26
      }

      legacy_refs="$(grep -c "library=\"$legacy_lib\"" "$src" 2>/dev/null)"
      [ "$legacy_refs" -eq 1 ] || {
        echo "legacy migration rejected: legacy library is shared by $legacy_refs effects" >&2
        return 27
      }

      if [ "$legacy_lib" != "$JDSP_LIB_NAME" ] &&
         grep -q "name=\"$JDSP_LIB_NAME\"" "$src"; then
        echo "conflict: library name $JDSP_LIB_NAME already exists" >&2
        return 21
      fi

      tmp="$dst.tmp.$$"
      awk -v leglib="$legacy_lib"           -v legfile="$JDSP_LEGACY_LIB_FILE"           -v libname="$JDSP_LIB_NAME"           -v libfile="$JDSP_LIB_FILE"           -v uuid="$JDSP_UUID"           -v typeuuid="$JDSP_TYPE" '
        {
          if (index($0, "name=\"" leglib "\"") &&
              index($0, "path=\"" legfile "\"")) {
            printf "        <library name=\"%s\" path=\"%s\"/>\n", libname, libfile
            next
          }
          if (tolower($0) ~ tolower(uuid)) {
            printf "        <effect name=\"jamesdsp\" library=\"%s\" uuid=\"%s\" type=\"%s\"/>\n", libname, uuid, typeuuid
            next
          }
          print
        }
      ' "$src" > "$tmp" || {
        rc=$?
        rm -f "$tmp"
        echo "failed to migrate legacy XML (awk=$rc)" >&2
        return 30
      }

      validate_jdsp_audio_config "$tmp" || {
        rc=$?
        rm -f "$tmp"
        return "$rc"
      }

      if grep -q "path=\"$JDSP_LEGACY_LIB_FILE\"" "$tmp"; then
        rm -f "$tmp"
        echo "legacy library still referenced after migration" >&2
        return 28
      fi

      mv -f "$tmp" "$dst" || return 35
      echo "Converted known legacy JamesDSP registration to AIDL"
      return 11
    fi

    echo "conflict: JamesDSP UUID already registered by another library" >&2
    return 20
  fi

  if grep -q "name=\"$JDSP_LIB_NAME\"" "$src"; then
    echo "conflict: library name $JDSP_LIB_NAME already exists" >&2
    return 21
  fi
  if grep -q '<effect[^>]*name="jamesdsp"' "$src"; then
    echo "conflict: effect name jamesdsp already exists" >&2
    return 22
  fi

  tmp="$dst.tmp.$$"
  awk -v libname="$JDSP_LIB_NAME" -v libfile="$JDSP_LIB_FILE"       -v uuid="$JDSP_UUID" -v typeuuid="$JDSP_TYPE" '
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
    return 30
  }

  validate_jdsp_audio_config "$tmp" || {
    rc=$?
    rm -f "$tmp"
    return "$rc"
  }

  mv -f "$tmp" "$dst" || return 35
  return 0
}
