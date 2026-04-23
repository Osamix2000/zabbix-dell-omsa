#!/bin/bash

OMSABIN="/opt/dell/srvadmin/bin/omreport"

function OMSASafeRun {
	local OUT

	OUT="$($OMSABIN "$@" 2>&1)"

	if echo "$OUT" | grep -Fq 'free(): corrupted unsorted chunks' && echo "$OUT" | grep -Fq 'omreportUnsuccessful command execution!'; then
		return 99
	fi

	echo "$OUT"
}

function PhysicalDisksDiscovery {

for CONTROLLER in "$($OMSABIN storage controller | grep ^ID | awk '{print $3}')"
do

IFS=$'\n' read -r -d '' -a DISKS <<< "$($OMSABIN storage pdisk controller=$CONTROLLER | grep ^ID | awk '{print $3}')"

for DISK in "${DISKS[@]}"; do
  RESULT+=$(echo -e "\n{\n\"{#PDISK}\": \"$DISK\",\n\"{#CONTROLLER}\": \"$CONTROLLER\" \n},")
done

done
echo -e "{"
echo -e "\"data\":["

JSON=$(echo "$RESULT" | sed '$s/,$//')

echo "$JSON"
echo "]}"


}

function PhysicalDiskStatus {
	PDISK="$1"
	CONTROLLER="$2"
	ITEM="$3"

	OUT="$(OMSASafeRun storage pdisk controller=$CONTROLLER pdisk=$PDISK)"
	RC=$?

	case "$ITEM" in
		status)
			if [ "$RC" -eq 99 ]; then
				echo "Online"
				return
			fi

			echo "$OUT" | grep '^State' | awk '{print $3}'
			;;
		pfailure)
			if [ "$RC" -eq 99 ]; then
				echo "No"
				return
			fi

			echo "$OUT" | grep '^Failure Predicted' | awk '{print $4}'
			;;
	esac
}

function VirtualDiskDiscovery {

for CONTROLLER in "$($OMSABIN storage controller | grep ^ID | awk '{print $3}')"
do

IFS=$'\n' read -r -d '' -a VDISKS <<< "$($OMSABIN storage vdisk controller=$CONTROLLER| grep '^ID' |  awk '{print $3}')"

for VDISK in "${VDISKS[@]}"
do
  RESULT+=$(echo -e "\n{\n\"{#VDISK}\": \"$VDISK\",\n\"{#CONTROLLER}\": \"$CONTROLLER\" \n},")
done

done

echo -e "{"
echo -e "\"data\":["

JSON=$(echo "$RESULT" | sed '$s/,$//')

echo "$JSON"
echo "]}"

}

function VirtualDiskStatus {

VDISK="$1"
CONTROLLER="$2"

case "$3" in 
	status)
	echo "$($OMSABIN storage vdisk controller=$CONTROLLER vdisk=$VDISK| grep ^Status | awk '{print $3}')"
	;;
	raid)
	echo "$($OMSABIN storage vdisk controller=$CONTROLLER vdisk=$VDISK | grep ^Layout | awk '{print $3}')"
	;;
	size)
	echo "$($OMSABIN storage vdisk controller=$CONTROLLER vdisk=$VDISK | grep ^Size | awk '{print $5}' | grep -Eo '[0-9]+')"
	;;
	*)
	exit
	;;
esac

}

function FanDiscovery {

IFS=$'\n' read -r -d '' -a FANS <<< "$($OMSABIN chassis fans | grep ^Index | awk '{print $3}')"

for FAN in "${FANS[@]}"; do
  RESULT+=$(echo -e "\n{\n\"{#FAN}\": \"$FAN\"\n},")
done

echo -e "{"
echo -e "\"data\":["

JSON=$(echo "$RESULT" | sed '$s/,$//')

echo "$JSON"
echo "]}"

}

function FanStatus {

FAN="$1"
ITEM="$2"

[[ "$ITEM" == "rpm" ]] && REPLY="$($OMSABIN chassis fans index=$FAN | grep ^Reading | awk '{print $3}')"

[[ "$ITEM" == "status" ]] && REPLY="$($OMSABIN chassis fans index=$FAN | grep ^Status | awk '{print $3}')"

echo "$REPLY"

}

function PsuDiscovery {

IFS=$'\n' read -r -d '' -a PSUS <<< "$($OMSABIN chassis pwrsupplies | grep ^Index | awk '{print $3}')"

for PSU in "${PSUS[@]}"; do
  RESULT+=$(echo -e "\n{\n\"{#PSU}\": \"$PSU\"\n},")
done

echo -e "{"
echo -e "\"data\":["

JSON=$(echo "$RESULT" | sed '$s/,$//')

echo "$JSON"
echo "]}"

}

function PsuStatus {

PSU="$1"

echo "$($OMSABIN chassis pwrsupplies | grep -A1 "^Index.*$PSU" | tail -1 |  awk '{print $3}')"

}

function RAMDiscovery {

IFS=$'\n' read -r -d '' -a RAMS <<< "$($OMSABIN chassis memory | grep "Index" | awk '{print $3}' | grep -Eo '[0-9]+')"

for RAM in "${RAMS[@]}"; do
  RESULT+=$(echo -e "\n{\n\"{#RAM}\": \"$RAM\"\n},")
done

echo -e "{"
echo -e "\"data\":["

JSON=$(echo "$RESULT" | sed '$s/,$//')

echo "$JSON"
echo "]}"

}

function RAMStatus {

RAM="$1"

STATUS="$($OMSABIN chassis memory index=$RAM | grep "^Status" | awk '{print $3}')"

echo "$STATUS"

}

function TempDiscovery {

IFS=$'\n' read -r -d '' -a TEMPS <<< "$($OMSABIN chassis temps | grep "^Index\|^Probe Name" | cut -d':' -f2 | sed 's/^ //' | paste - -)"

for TEMP in "${TEMPS[@]}"
do
  read -a TEMP_SPLIT <<< "$TEMP"

  INDEX=${TEMP_SPLIT[0]}
  TEMP=${TEMP_SPLIT[@]:1}

RESULT+=$(echo -e "\n{\n\"{#TEMP}\": \"$TEMP\",\n\"{#TEMPINDEX}\": \"$INDEX\" \n},")
done

echo -e "{"
echo -e "\"data\":["

JSON=$(echo "$RESULT" | sed '$s/,$//')

echo "$JSON"
echo "]}"

}

function TempStatus {

INDEX="$1"

STATUS="$($OMSABIN chassis temps index=$INDEX | grep ^Reading | awk '{print $3}')"

echo "$STATUS"

}

function SystemModel {

STATUS="$($OMSABIN chassis info | grep "^Chassis Model" | cut -d':' -f2 | sed 's/^ //')"
echo "$STATUS"

}

function SystemServiceTag {

STATUS="$($OMSABIN chassis info | grep "^Chassis Service Tag" | cut -d':' -f2 | sed 's/^ //')"
echo "$STATUS"

}

function SystemStatus {

if [[ -z "$($OMSABIN chassis | grep ":" | grep -v SEVERITY | cut -d':' -f1 | grep -v Ok)" ]]; then
	echo "Ok"
else
	echo "Failure"
fi

}

function SystemBiosVersion {

echo "$($OMSABIN chassis bios | grep '^Version' | awk '{print $3}')"

}

function SystemIdracVersion {

IDRACVERSION="$($OMSABIN chassis info | grep -i ^idrac | awk '{print $1,$4}')"

if [[ -z "$IDRACVERSION" ]]; then
	IDRACVERSION="none"
else
	IDRACVERSION="$IDRACVERSION"
fi

echo "$IDRACVERSION"

}

function PowerDiscovery {

	OUT="$($OMSABIN chassis pwrmonitoring 2>/dev/null)"

	# 非対応メッセージが出ている場合、空のLLDを返して終了
	if echo "$OUT" | grep -q "Power Consumption Information is not available"; then
		echo -e "{"
		echo -e "\"data\":[]"
		echo -e "}"
		return
	fi

	# Index/Probe Nameが1つも無い場合も空LLD
	if ! echo "$OUT" | grep -q "^Index"; then
		echo -e "{"
		echo -e "\"data\":[]"
		echo -e "}"
		return
	fi

	# 対応している場合は全Index＋Probe NameをLLDとして返す
	IFS=$'\n' read -r -d '' -a PWRS <<< "$(echo "$OUT" | grep "^Index\|^Probe Name" | cut -d':' -f2 | sed 's/^ //' | paste - -)"

	for PWR in "${PWRS[@]}"
	do
		read -a PWR_SPLIT <<< "$PWR"

		INDEX=${PWR_SPLIT[0]}
		PROBE=${PWR_SPLIT[@]:1}

		RESULT+=$(echo -e "\n{\n\"{#PWRINDEX}\": \"$INDEX\",\n\"{#PWRNAME}\": \"$PROBE\" \n},")
	done

	echo -e "{"
	echo -e "\"data\":["

	JSON=$(echo "$RESULT" | sed '$s/,$//')

	echo "$JSON"
	echo "]}"
}

function PowerStatus {

	INDEX="$1"

	OUT="$($OMSABIN chassis pwrmonitoring 2>/dev/null)"

	STATUS="$(echo "$OUT" | awk -v IDX="$INDEX" '
		/^Index/ {
			# 行の最後のフィールドをIndexとして保持
			cur_idx = $NF
		}
		/^Reading/ && $NF=="W" && cur_idx==IDX {
			# Reading の行で、末尾が W かつ Index が一致した場合に数値を出力
			print $(NF-1)
			exit
		}
	')"

	echo "$STATUS"
}

function BmcInfo {

	MODE="$1"

	OUT="$($OMSABIN chassis bmc 2>/dev/null)"

	# BMC/iDRAC が無い、または取得できない場合は何も返さず終了
	if [ -z "$OUT" ] || ! echo "$OUT" | grep -q "Remote Access Device"; then
		exit 0
	fi

	case "$MODE" in
		device_type)
			echo "$OUT" | awk -F':' '/Device Type/ { gsub(/^ *| *$/,"",$2); print $2; exit }'
			;;
		ipmi_version)
			echo "$OUT" | awk -F':' '/IPMI Version/ { gsub(/^ *| *$/,"",$2); print $2; exit }'
			;;
		sessions_possible)
			echo "$OUT" | awk -F':' '/Number of Possible Active Sessions/ { gsub(/^ *| *$/,"",$2); print $2; exit }'
			;;
		sessions_active)
			echo "$OUT" | awk -F':' '/Number of Current Active Sessions/ { gsub(/^ *| *$/,"",$2); print $2; exit }'
			;;
		ipmi_over_lan)
			echo "$OUT" | awk -F':' '/Enable IPMI Over LAN/ { gsub(/^ *| *$/,"",$2); print $2; exit }'
			;;
		sol_enabled)
			echo "$OUT" | awk -F':' '/SOL Enabled/ { gsub(/^ *| *$/,"",$2); print $2; exit }'
			;;
		mac)
			echo "$OUT" | awk -F':' '/MAC Address/ { gsub(/^ *| *$/,"",$2); print $2; exit }'
			;;
		ipv4)
			echo "$OUT" | awk '
				/^IPv4 Address/ { in_block=1; next }
				in_block && NF==0 { in_block=0; next }
				in_block && $0 ~ /IP Address[[:space:]]*:/ {
					sub(/.*IP Address[[:space:]]*:[[:space:]]*/, "", $0);
					gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0);
					print $0;
					exit
				}
			'
			;;
		ipv4_source)
			echo "$OUT" | awk -v RS="" '
				/IPv4 Address/ {
					while (getline line) {
						if (line ~ /^IPv6 Address/) break
						if (line ~ /IP Address Source[[:space:]]*:/) {
							n = split(line, a, ":")
							if (n > 1) {
								gsub(/^ *| *$/, "", a[2])
								print a[2]
								exit
							}
						}
					}
				}
			'
			;;
		ipv4_subnet)
			echo "$OUT" | awk -v RS="" '
				/IPv4 Address/ {
					while (getline line) {
						if (line ~ /^IPv6 Address/) break
						if (line ~ /IP Subnet[[:space:]]*:/) {
							n = split(line, a, ":")
							if (n > 1) {
								gsub(/^ *| *$/, "", a[2])
								print a[2]
								exit
							}
						}
					}
				}
			'
			;;
		ipv4_gateway)
			echo "$OUT" | awk -v RS="" '
				/IPv4 Address/ {
					while (getline line) {
						if (line ~ /^IPv6 Address/) break
						if (line ~ /IP Gateway[[:space:]]*:/) {
							n = split(line, a, ":")
							if (n > 1) {
								gsub(/^ *| *$/, "", a[2])
								print a[2]
								exit
							}
						}
					}
				}
			'
			;;
	esac
}

function CmosBatteryStatus {
	OUT="$($OMSABIN chassis batteries 2>/dev/null)"

	# 出力が無い、または"Batteries"セクションが無ければ何も返さず終了
	if [ -z "$OUT" ] || ! echo "$OUT" | grep -q "^Batteries"; then
		exit 0
	fi

	STATUS="$(echo "$OUT" | awk '
		/^Index/ { idx=$3 }
		/^Probe Name[[:space:]]*:[[:space:]]*System Board CMOS Battery/ { target=idx }
		/^Reading/ && target==idx { print $3; exit }
	')"

	# STATUS が空なら何も出さず終了
	[ -z "$STATUS" ] && exit 0

	echo "$STATUS"
}

function BatteriesDiscovery {
	OUT="$($OMSABIN chassis batteries 2>/dev/null)"

	# 出力が無い、または "Batteries" セクションが無い場合は空LLD
	if [ -z "$OUT" ] || ! echo "$OUT" | grep -q "^Batteries"; then
		echo -e "{"
		echo -e "\"data\":[]"
		echo -e "}"
		return
	fi

	# Individual Battery Elements が無い場合も空LLD
	if ! echo "$OUT" | grep -q "^Individual Battery Elements"; then
		echo -e "{"
		echo -e "\"data\":[]"
		echo -e "}"
		return
	fi

	RESULT=""
	in_section=0
	CUR_INDEX=""

	while IFS= read -r line; do

		# 個別バッテリー要素セクション開始
		if echo "$line" | grep -q "^Individual Battery Elements"; then
			in_section=1
			continue
		fi

		# セクション外は無視
		[ "$in_section" -eq 1 ] || continue

		# Index行
		if echo "$line" | grep -q "^Index"; then
            # "Index      : 0" の3番目のフィールドを取る
			CUR_INDEX=$(echo "$line" | awk '{print $3}')
			continue
		fi

		# Probe Name行
		if echo "$line" | grep -q "^Probe Name"; then
            # コロン以降を取り、前後の空白を削る
			PROBE=$(echo "$line" | cut -d':' -f2- | sed 's/^ *//;s/ *$//')
			RESULT+=$(echo -e "\n{\n\"{#BATTINDEX}\": \"$CUR_INDEX\",\n\"{#BATTPROBE}\": \"$PROBE\" \n},")
		fi

	done <<< "$OUT"

	echo -e "{"
	echo -e "\"data\":["
	JSON=$(echo "$RESULT" | sed '$s/,$//')
	echo "$JSON"
	echo "]}"
}

function BatteriesStatus {

	INDEX="$1"
	FIELD="$2"

	OUT="$($OMSABIN chassis batteries 2>/dev/null)"

	# 出力が無い場合
	if [ -z "$OUT" ] || ! echo "$OUT" | grep -q "^Batteries"; then
		exit 0
	fi

	# ▼ 全体Health
	if [ "$FIELD" = "health" ]; then
		echo "$OUT" | grep "^Health" | awk -F':' '{gsub(/^ *| *$/, "", $2); print $2}'
		exit 0
	fi

	# ▼ 個別Indexの処理
	CUR=""
	FOUND=""

	while IFS= read -r line; do

		if echo "$line" | grep -q "^Index"; then
			CUR=$(echo "$line" | awk '{print $3}')
			continue
		fi

		# 対象Indexのみに絞る
		if [ "$CUR" = "$INDEX" ]; then

			if [ "$FIELD" = "status" ] && echo "$line" | grep -q "^Status[[:space:]]*:"; then
				echo "$line" | awk -F':' '{gsub(/^ *| *$/, "", $2); print $2}'
				exit 0
			fi

			if [ "$FIELD" = "reading" ] && echo "$line" | grep -q "^Reading[[:space:]]*:"; then
				echo "$line" | awk -F':' '{gsub(/^ *| *$/, "", $2); print $2}'
				exit 0
			fi

			if [ "$FIELD" = "probe" ] && echo "$line" | grep -q "^Probe Name[[:space:]]*:"; then
				echo "$line" | awk -F':' '{gsub(/^ *| *$/, "", $2); print $2}'
				exit 0
			fi

		fi

	done <<< "$OUT"
}

function HandleArgs {
	case "$1" in
		pddiscovery)
			PhysicalDisksDiscovery
			;;
		pdstatus)
			PhysicalDiskStatus $2 $3 $4
			;;
		vddiscovery)
			VirtualDiskDiscovery
			;;
		vdstatus)
			VirtualDiskStatus $2 $3 $4
			;;
		fandiscovery)
			FanDiscovery
			;;
		fanstatus)
			FanStatus $2 $3
			;;
		psudiscovery)
			PsuDiscovery
			;;
		psustatus)
			PsuStatus $2
			;;
		ramdiscovery)
			RAMDiscovery
			;;
		ramstatus)
			RAMStatus $2
			;;
		tempdiscovery)
			TempDiscovery
			;;
		tempstatus)
			TempStatus $2
			;;
		model)
			SystemModel
			;;
		stag)
			SystemServiceTag
			;;
		bios)
			SystemBiosVersion
			;;
		idrac)
			SystemIdracVersion
			;;
		status)
			SystemStatus
			;;		
		pwrdiscovery)
			PowerDiscovery
			;;
		pwrstatus)
			PowerStatus $2
			;;
		bmc)
			BmcInfo $2
			;;
		cmos)
			CmosBatteryStatus
			;;
		battdiscovery)
			BatteriesDiscovery
			;;
		battstatus)
			BatteriesStatus $2 $3
			;;
	esac
}

HandleArgs $@
