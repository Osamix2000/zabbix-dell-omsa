#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source <(sed '/^function HandleArgs /,$d' "${SCRIPT_DIR}/omsa.sh")

FAILED=0

assert_eq() {
	local NAME="$1"
	local EXPECTED="$2"
	local ACTUAL="$3"

	if [ "${EXPECTED}" = "${ACTUAL}" ]; then
		echo "OK: ${NAME} => ${ACTUAL}"
	else
		echo "NG: ${NAME} expected=${EXPECTED} actual=${ACTUAL}" >&2
		FAILED=1
	fi
}

FAN_110='Fan Probes Information
Index                    : 0
Status                   : Ok
Probe Name               : System Board Fan 1 RPM
Reading                  : 2380 RPM
Minimum Warning Threshold: 600 RPM'

FAN_111='Fan Probes Information
Index                    : 0
Status                   : Ok
Probe Name               : System Board Fan 1 RPM
Reading                  : 2380RPM
Minimum Warning Threshold: 600RPM'

TEMP_110='Index : 1
Status : Ok
Probe Name : System Board Inlet Temp
Reading : 24.0 C'

TEMP_111='Index                    : 1
Status                   : Ok
Probe Name               : System Board Inlet Temp
Reading                  : 24.0C'

PWR_111='Power Consumption Information
Index : 1
Status : Ok
Probe Name : System Board Pwr Consumption
Reading : 539W
Warning Threshold : 994W
Index : 2
Status : Ok
Probe Name : Other
Reading : 100 W'

PSU='Individual Power Supply Elements
Index                    : 0
Status                   : Ok
Location                 : PS 1 Status
Type                     : AC
Index                    : 1
Status                   : Critical
Location                 : PS 2 Status'

VD='ID : 0
Status : Ok
Name : Virtual Disk 0
State : Ready
Layout : RAID-6
Size : 10.914 TB (12000138625024 bytes)'

FIXTURE="${FAN_110}"
OMSARun() { printf '%s\n' "${FIXTURE}"; }
assert_eq "fan 11.0 rpm spaced" "2380" "$(FanStatusOMSA 0 rpm)"
assert_eq "fan 11.0 status" "OK" "$(FanStatusOMSA 0 status)"

FIXTURE="${FAN_111}"
assert_eq "fan 11.1 rpm attached-unit" "2380" "$(FanStatusOMSA 0 rpm)"
assert_eq "fan discovery" "0" "$(printf '%s\n' "${FAN_111}" | ExtractOmreportFields Index)"

FIXTURE="${TEMP_110}"
assert_eq "temp 11.0" "24.0" "$(TempStatusOMSA 1)"

FIXTURE="${TEMP_111}"
assert_eq "temp 11.1" "24.0" "$(TempStatusOMSA 1)"

FIXTURE="${PWR_111}"
assert_eq "power reading" "539" "$(PowerStatusOMSA 1)"

FIXTURE="${PSU}"
assert_eq "psu index0" "OK" "$(PsuStatusOMSA 0)"
assert_eq "psu index1" "Critical" "$(PsuStatusOMSA 1)"

FIXTURE="${VD}"
assert_eq "vd status" "OK" "$(VirtualDiskStatusOMSA 0 0 status)"
assert_eq "vd raid" "RAID-6" "$(VirtualDiskStatusOMSA 0 0 raid)"
assert_eq "vd size bytes" "12000138625024" "$(VirtualDiskStatusOMSA 0 0 size)"

echo
if [ "${FAILED}" -eq 0 ]; then
	echo "OMSA parser compatibility test: OK"
	exit 0
fi

echo "OMSA parser compatibility test: NG" >&2
exit 1
