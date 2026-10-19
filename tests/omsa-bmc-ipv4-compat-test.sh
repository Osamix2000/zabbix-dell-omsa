#!/bin/bash
# OMSA 11.0 / 11.1のiDRAC IPv4情報の取得元切替を検証する（RFC 5737の文書用アドレスを使用）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source <(sed '/^function HandleArgs /,$d' "${SCRIPT_DIR}/omsa.sh")

FAILED=0
assert_eq() {
	local LABEL="$1" EXPECTED="$2" ACTUAL="$3"
	if [ "$EXPECTED" = "$ACTUAL" ]; then
		printf 'OK: %s => %s\n' "$LABEL" "$ACTUAL"
	else
		printf 'NG: %s expected=%s actual=%s\n' "$LABEL" "$EXPECTED" "$ACTUAL" >&2
		FAILED=1
	fi
}

SUMMARY='System Summary

--------------------------
Remote Access Controller
--------------------------
Remote Access Controller Information
Product                    : iDRAC8 Enterprise
IP Address                 : 192.0.2.37
IP Subnet                  : 255.255.252.0
IP Gateway                 : 192.0.2.1
IPv6 Address 1             : ::
IPv6 Address 2             : ::

--------------
Network Data
--------------
Network Interface 0
IP Address                 : 198.51.100.37'

# 同じ"IP Address"を含むOS NICが存在してもRemote Access Controllerの値を採用する
assert_eq "summary IPv4" "192.0.2.37" "$(printf '%s\n' "$SUMMARY" | ExtractSummaryBmcIPv4Field 'IP Address')"
assert_eq "summary subnet" "255.255.252.0" "$(printf '%s\n' "$SUMMARY" | ExtractSummaryBmcIPv4Field 'IP Subnet')"
assert_eq "summary gateway" "192.0.2.1" "$(printf '%s\n' "$SUMMARY" | ExtractSummaryBmcIPv4Field 'IP Gateway')"

NO_IDRAC='Network Data
IP Address                 : 198.51.100.37'
assert_eq "no iDRAC section" "" "$(printf '%s\n' "$NO_IDRAC" | ExtractSummaryBmcIPv4Field 'IP Address')"

INVALID='Remote Access Controller Information
IP Address : [No Value]
IP Subnet : 999.168.0.0
------------
Network Data
IP Address : 198.51.100.37'
assert_eq "invalid IPv4 ignored" "" "$(printf '%s\n' "$INVALID" | ExtractSummaryBmcIPv4Field 'IP Address')"
assert_eq "invalid subnet ignored" "" "$(printf '%s\n' "$INVALID" | ExtractSummaryBmcIPv4Field 'IP Subnet')"

# 本体のコマンド・キャッシュを置き換えて、監視スクリプト本体の選択順を確認する
FIXTURE_BMC='IPMI Version : 2.0
MAC Address : D0-94-66-12-B2-7D'
FIXTURE_SUMMARY="$SUMMARY"
OMSABmcOutput() { printf '%s\n' "$FIXTURE_BMC"; }
OMSABmcSummaryOutput() { printf '%s\n' "$FIXTURE_SUMMARY"; }

SOURCE_ONLY=0
assert_eq "BmcInfo fallback IPv4" "192.0.2.37" "$(BmcInfo ipv4)"
assert_eq "BmcInfo fallback subnet" "255.255.252.0" "$(BmcInfo ipv4_subnet)"
assert_eq "BmcInfo fallback gateway" "192.0.2.1" "$(BmcInfo ipv4_gateway)"
SOURCE_ONLY=1
assert_eq "fallback source" "OMSA" "$(BmcInfo ipv4)"
SOURCE_ONLY=0

# 旧バージョンで取得できるIPv4 Address節の値がある場合、従来の取得元を優先する
FIXTURE_BMC='Baseboard Management Controller Information
IPv4 Address
IP Address    : 10.1.2.3
IP Subnet     : 255.255.255.0
IP Gateway    : 10.1.2.1
IPv6 Address
IP Address    : ::'
assert_eq "prefer direct BMC IPv4" "10.1.2.3" "$(BmcInfo ipv4)"
assert_eq "prefer direct BMC subnet" "255.255.255.0" "$(BmcInfo ipv4_subnet)"
assert_eq "prefer direct BMC gateway" "10.1.2.1" "$(BmcInfo ipv4_gateway)"

# 管理コントローラー情報がなければ、誤ってOS NICのIPを取得しない
FIXTURE_BMC='IPMI Version : 2.0'
FIXTURE_SUMMARY="$NO_IDRAC"
assert_eq "unavailable IPv4 remains Unsupported" "Unsupported" "$(BmcInfo ipv4)"

if [ "$FAILED" -ne 0 ]; then
	echo "OMSA BMC IPv4 compatibility test: NG" >&2
	exit 1
fi
echo "OMSA BMC IPv4 compatibility test: OK"
