#!/bin/bash
# OMSA実行パスの選択ロジックを、実機やDell OMSAの導入なしで回帰テストします。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source <(sed '/^function HandleArgs /,$d' "${SCRIPT_DIR}/omsa.sh")

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

assert_eq() {
    local LABEL="$1" EXPECTED="$2" ACTUAL="$3"
    if [ "$EXPECTED" != "$ACTUAL" ]; then
        printf 'NG: %s expected=%s actual=%s\n' "$LABEL" "$EXPECTED" "$ACTUAL" >&2
        exit 1
    fi
    printf 'OK: %s => %s\n' "$LABEL" "$ACTUAL"
}

WRAPPER="$TMP/wrapper"
NATIVE="$TMP/native"
EXPLICIT="$TMP/explicit"

printf '#!/bin/sh\necho "Chassis Information"\n' > "$WRAPPER"
printf '#!/bin/sh\necho "Chassis Information"\n' > "$NATIVE"
printf '#!/bin/sh\necho "Chassis Information"\n' > "$EXPLICIT"
chmod 700 "$WRAPPER" "$NATIVE" "$EXPLICIT"

unset OMSABIN
assert_eq "wrapper priority" "$WRAPPER" "$(SelectOMSABin "$WRAPPER" "$NATIVE")"

chmod 600 "$WRAPPER"
assert_eq "fallback to native if wrapper not executable" "$NATIVE" "$(SelectOMSABin "$WRAPPER" "$NATIVE")"

OMSABIN="$EXPLICIT"
assert_eq "explicit override" "$EXPLICIT" "$(SelectOMSABin "$WRAPPER" "$NATIVE")"

OMSABIN="$TMP/nonexistent-override"
assert_eq "explicit non-executable override is respected" "$TMP/nonexistent-override" "$(SelectOMSABin "$WRAPPER" "$NATIVE")"

unset OMSABIN
rm -f "$WRAPPER" "$NATIVE"
assert_eq "default fallback path" "$NATIVE" "$(SelectOMSABin "$WRAPPER" "$NATIVE")"

echo "OMSA binary selection compatibility test: OK"
