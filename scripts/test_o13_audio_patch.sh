#!/usr/bin/env bash
set -euo pipefail

PATCHER="magisk/oneplus13/common/patch_audio_config.sh"
# shellcheck disable=SC1090
. "$PATCHER"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

make_stock() {
cat > "$1" <<'XML'
<audio_effects_conf version="2.0">
    <libraries>
        <library name="oplus" path="libOplusAudioxAidl.so"/>
    </libraries>
    <effects>
        <effect name="oplus" library="oplus" uuid="11111111-1111-1111-1111-111111111111"/>
    </effects>
</audio_effects_conf>
XML
}

make_legacy() {
cat > "$1" <<'XML'
<audio_effects_conf version="2.0">
    <libraries>
        <library name="oplus" path="libOplusAudioxAidl.so"/>
        <library name="jdsp" path="libjamesdsp.so"/>
    </libraries>
    <effects>
        <effect name="oplus" library="oplus" uuid="11111111-1111-1111-1111-111111111111"/>
        <effect name="jamesdsp" library="jdsp" uuid="f27317f4-c984-4de6-9a90-545759495bf2"/>
    </effects>
</audio_effects_conf>
XML
}

echo "[1/5] clean stock injection"
make_stock "$TMP/stock.xml"
JDSP_ALLOW_LEGACY_MIGRATION=0
patch_jdsp_audio_config "$TMP/stock.xml" "$TMP/stock.out.xml"
grep -q 'path="libjamesdsp_aidl.so"' "$TMP/stock.out.xml"
grep -q 'type="f98765f4-c321-5de6-9a45-123459495ab2"' "$TMP/stock.out.xml"

echo "[2/5] legacy UUID remains a conflict outside migration"
make_legacy "$TMP/legacy.xml"
set +e
JDSP_ALLOW_LEGACY_MIGRATION=0
patch_jdsp_audio_config "$TMP/legacy.xml" "$TMP/rejected.xml"
rc=$?
set -e
[ "$rc" -eq 20 ]

echo "[3/5] known Ainur registration converts during controlled migration"
JDSP_ALLOW_LEGACY_MIGRATION=1
set +e
patch_jdsp_audio_config "$TMP/legacy.xml" "$TMP/migrated.xml"
rc=$?
set -e
[ "$rc" -eq 11 ]
grep -q 'name="jamesdsp_aidl" path="libjamesdsp_aidl.so"' "$TMP/migrated.xml"
grep -q 'library="jamesdsp_aidl".*uuid="f27317f4-c984-4de6-9a90-545759495bf2"' "$TMP/migrated.xml"
grep -q 'type="f98765f4-c321-5de6-9a45-123459495ab2"' "$TMP/migrated.xml"
! grep -q 'path="libjamesdsp.so"' "$TMP/migrated.xml"
[ "$(grep -ci 'f27317f4-c984-4de6-9a90-545759495bf2' "$TMP/migrated.xml")" -eq 1 ]

echo "[4/5] unknown UUID owner stays blocked"
cat > "$TMP/unknown.xml" <<'XML'
<audio_effects_conf version="2.0">
    <libraries>
        <library name="mystery" path="libmystery.so"/>
    </libraries>
    <effects>
        <effect name="mystery" library="mystery" uuid="f27317f4-c984-4de6-9a90-545759495bf2"/>
    </effects>
</audio_effects_conf>
XML
set +e
JDSP_ALLOW_LEGACY_MIGRATION=1
patch_jdsp_audio_config "$TMP/unknown.xml" "$TMP/unknown.out.xml"
rc=$?
set -e
[ "$rc" -ne 0 ] && [ "$rc" -ne 10 ] && [ "$rc" -ne 11 ]

echo "[5/5] shared legacy library stays blocked"
cat > "$TMP/shared.xml" <<'XML'
<audio_effects_conf version="2.0">
    <libraries>
        <library name="jdsp" path="libjamesdsp.so"/>
    </libraries>
    <effects>
        <effect name="jamesdsp" library="jdsp" uuid="f27317f4-c984-4de6-9a90-545759495bf2"/>
        <effect name="other" library="jdsp" uuid="22222222-2222-2222-2222-222222222222"/>
    </effects>
</audio_effects_conf>
XML
set +e
JDSP_ALLOW_LEGACY_MIGRATION=1
patch_jdsp_audio_config "$TMP/shared.xml" "$TMP/shared.out.xml"
rc=$?
set -e
[ "$rc" -eq 27 ]

echo "O13 audio XML patch migration tests passed"
