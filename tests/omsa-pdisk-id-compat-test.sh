#!/bin/bash
# OMSA物理ディスクのコロン区切りID (例: 0:1:0) を保ったままLLD・状態取得できるか検証
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

OMSA_LIST='List of Physical Disks on Controller PERC H730 Mini (Embedded)
ID                              : 0:1:0
Status                          : Non-Critical
State                           : Online
Failure Predicted               : No
ID                              : 0:1:1
Status                          : Non-Critical
State                           : Online
Failure Predicted               : No'

assert_eq "single colon-separated ID" "0:1:0" "$(printf '%s\n' "$OMSA_LIST" | ExtractOmreportField "ID")"
assert_eq "multiple colon-separated IDs" "$(printf '0:1:0\n0:1:1')" "$(printf '%s\n' "$OMSA_LIST" | ExtractOmreportFields "ID")"
assert_eq "simple field unchanged" "Online" "$(printf '%s\n' "$OMSA_LIST" | ExtractOmreportField "State")"
assert_eq "spaces and units unchanged" "2380 RPM" "$(printf 'Reading : 2380 RPM\n' | ExtractOmreportField "Reading")"

# 実機と同じ8台のOMSA物理ディスク一覧と、pdisk=0:1:0を要求する詳細取得を模擬する
OMSARun() {
	case "$*" in
		"storage controller")
			printf 'Controller PERC H730 Mini\nID : 0\n'
			;;
		"storage pdisk controller=0")
			local DISK
			for DISK in 0 1 2 3 4 5 6 7; do
				printf 'ID : 0:1:%s\nStatus : Non-Critical\nState : Online\nFailure Predicted : No\n' "$DISK"
			done
			;;
		"storage pdisk controller=0 pdisk=0:1:0")
			printf 'ID : 0:1:0\nStatus : Non-Critical\nState : Online\nFailure Predicted : No\n'
			;;
		*)
			return 1
			;;
	esac
}
PerccliRun() { return 1; }

DISCOVERY="$(PhysicalDisksDiscoveryOMSA)"
assert_eq "8 physical disks => 8 LLD entries" "8" "$(printf '%s\n' "$DISCOVERY" | grep -c '"{#PDISK}"')"
for DISK in 0 1 2 3 4 5 6 7; do
	assert_eq "PDISK 0:1:${DISK}" "1" "$(printf '%s\n' "$DISCOVERY" | grep -Fc "\"{#PDISK}\": \"0:1:${DISK}\"")"
done
assert_eq "controller 0 preserved" "8" "$(printf '%s\n' "$DISCOVERY" | grep -c '"{#CONTROLLER}": "0"')"

assert_eq "OMSA status" "Online" "$(PhysicalDiskStatusOMSA '0:1:0' 0 status)"
assert_eq "OMSA predictive failure" "No" "$(PhysicalDiskStatusOMSA '0:1:0' 0 pfailure)"
SOURCE_ONLY=1
assert_eq "status backend is OMSA" "OMSA" "$(PhysicalDiskStatus '0:1:0' 0 status)"
SOURCE_ONLY=0

# legacyのperccli ID (EID:Slt) もLLDで変わらないことを確認
PerccliRun() {
	case "$*" in
		"show") printf '0 PERCH730Mini Opt\n' ;;
		"/c0/eall/sall show") printf '32:0 0 Onln 0 10.913 TB SATA HDD\n32:1 1 Onln 0 10.913 TB SATA HDD\n' ;;
		*) return 1 ;;
	esac
}
PERCCLI_DISCOVERY="$(PhysicalDisksDiscoveryPerccli)"
assert_eq "perccli 2 LLD entries" "2" "$(printf '%s\n' "$PERCCLI_DISCOVERY" | grep -c '"{#PDISK}"')"
assert_eq "perccli EID:Slt 32:0" "1" "$(printf '%s\n' "$PERCCLI_DISCOVERY" | grep -Fc '"{#PDISK}": "32:0"')"
assert_eq "perccli EID:Slt 32:1" "1" "$(printf '%s\n' "$PERCCLI_DISCOVERY" | grep -Fc '"{#PDISK}": "32:1"')"

if [ "$FAILED" -ne 0 ]; then
	echo "OMSA physical disk ID compatibility test: NG" >&2
	exit 1
fi
echo "OMSA physical disk ID compatibility test: OK"
