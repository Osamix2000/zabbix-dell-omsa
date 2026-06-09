#!/bin/bash

# Dellハードウェア監視用スクリプト
# 既存のomsa.*キー互換を維持しつつ、OMSA未導入環境ではローカルコマンド等へフォールバックします。

PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

SCRIPT_VERSION="2.0.2"
SCRIPT_NAME="$(basename "$0")"
SCRIPT_UID="$(id -u 2>/dev/null || echo unknown)"

OMSABIN="${OMSABIN:-/opt/dell/srvadmin/bin/omreport}"
REDFISH_BASE_ENV="${REDFISH_BASE:-}"
REDFISH_BASE="${REDFISH_BASE:-https://169.254.0.1}"
REDFISH_CONFIG="${REDFISH_CONFIG:-/home/zabbix/.config/dell-redfish.conf}"
COMMAND_TIMEOUT="${COMMAND_TIMEOUT:-12}"
OMSA_TIMEOUT="${OMSA_TIMEOUT:-12}"
IPMI_TIMEOUT="${IPMI_TIMEOUT:-12}"
# Zabbixから同時に複数アイテムが実行されるとipmitoolが詰まりやすいため、既定では長めにキャッシュします。
IPMI_CACHE_TTL="${IPMI_CACHE_TTL:-240}"
IPMI_SENSOR_CACHE_LOCK="${IPMI_SENSOR_CACHE_LOCK:-/tmp/dell_hw_monitor_ipmi_sensor_${SCRIPT_UID}.lock}"
PERCCLI_TIMEOUT="${PERCCLI_TIMEOUT:-12}"
IPMI_SENSOR_CACHE="${IPMI_SENSOR_CACHE:-/tmp/dell_hw_monitor_ipmi_sensor_${SCRIPT_UID}.cache}"
# OMSAのBMC/iDRAC情報は初回取得が不安定な場合があるため、短時間キャッシュします。
OMSA_BMC_CACHE_TTL="${OMSA_BMC_CACHE_TTL:-240}"
OMSA_BMC_CACHE="${OMSA_BMC_CACHE:-/tmp/dell_hw_monitor_omsa_bmc_${SCRIPT_UID}.cache}"
OMSA_BMC_CACHE_LOCK="${OMSA_BMC_CACHE_LOCK:-/tmp/dell_hw_monitor_omsa_bmc_${SCRIPT_UID}.lock}"
# 温度センサーが取得不可の場合に返す値です。ZabbixのNumeric(float)向けに文字列ではなく数値を返します。
TEMP_UNSUPPORTED_VALUE="${TEMP_UNSUPPORTED_VALUE:--273}"
# ZabbixのunitsがBの場合、表示は1024換算になるため、既定では表示合わせで1024換算にします。
# 厳密な10進バイト値を返したい場合は SIZE_BASE=1000 を指定してください。
SIZE_BASE="${SIZE_BASE:-1024}"
PERCCLI_BIN="${PERCCLI_BIN:-}"
DEBUG="0"
SOURCE_ONLY="0"
LAST_SOURCE=""
INSTALL_PACKAGES_FORCE="0"

function PrintHelp {
	cat <<HELP
【Dellハードウェア監視用スクリプト v${SCRIPT_VERSION}】

フォーク元:
	https://github.com/ronivay/zabbix-dell-omsa
HELP
	cat <<HELP

使い方:
	${SCRIPT_NAME} <項目> [引数...]
	${SCRIPT_NAME} --help
	${SCRIPT_NAME} --backend-status
	${SCRIPT_NAME} --test-omsa
	${SCRIPT_NAME} --test-local
	${SCRIPT_NAME} --test-ipmi
	${SCRIPT_NAME} --test-perccli
	${SCRIPT_NAME} --test-redfish
	${SCRIPT_NAME} --install-packages
	${SCRIPT_NAME} --create-redfish-conf
	${SCRIPT_NAME} --debug <項目> [引数...]
	${SCRIPT_NAME} --source <項目> [引数...]

主な項目:
	model                         モデル名を取得
	stag                          サービスタグを取得
	bios                          BIOSバージョンを取得
	idrac                         iDRAC/BMC情報を取得
	status                        全体状態を取得
	fandiscovery                  ファン一覧を取得
	fanstatus <fan> <status|rpm>  ファン状態/RPMを取得
	tempdiscovery                 温度センサー一覧を取得
	tempstatus <temp>              温度を取得(空白入り名称も自動結合)
	psudiscovery                  電源ユニット系センサー一覧を取得
	psustatus <psu>               電源ユニット系状態を取得
	vddiscovery                   仮想ディスク一覧を取得
	vdstatus <vd> <ctrl> <status|raid|size>
	pddiscovery                   物理ディスク一覧を取得
	pdstatus <pd> <ctrl> <status|pfailure>
	battdiscovery                 バッテリー/BBU一覧を取得
	battstatus <battery> <health|status|reading|probe>
	bmc <項目>                    BMC/iDRAC関連情報を取得

手動作業用オプション:
	--install-packages             現在のOSに合わせて必要パッケージをインストールし、IPMI関連サービスを有効化
	--create-redfish-conf          Redfish用curl設定ファイルを対話形式で作成

取得優先順位:
	1. OMSA
	2. ローカルコマンド(dmidecode, ipmitool -I open, perccli)
	3. Redfish
	4. racadm(現時点では補助扱い)

補足:
	OMSAで正常に取得できる場合はOMSAの値を優先します。
	OMSAが未導入、失敗、非対応、対象項目が空の場合のみ他の方法で取得します。
	OMSAがCritical/Failed/Degraded等の異常値を返した場合は、その値を採用します。
	状態値は可能な範囲でOK/Warning/Critical/Unknown/Unsupportedへ正規化します。
	取得できない項目はUnknownまたはUnsupportedを返します。
	温度の数値アイテムは、取得不可時に既定で-273を返します。
	Redfish認証情報は/home/zabbix/.config/dell-redfish.confを使用します。
	ipmitoolのsensor結果はキャッシュし、Zabbix実行時のタイムアウトと多重実行を抑制します。
	perccliはDell配布ファイルから別途導入する想定です。
	仮想ディスクサイズはZabbixのB単位表示に合わせ、既定で1024換算します。厳密な10進換算にしたい場合はSIZE_BASE=1000を指定してください。

現在のOS向けのインストールコマンド例:
HELP
	PrintInstallCommands 2>/dev/null || cat <<'HELP_FALLBACK'
	OSを判定できませんでした。Ubuntu/Debian系、CentOS7、AlmaLinux/RHEL/Rocky 8以降等で実行してください。
HELP_FALLBACK
	echo
}
function DebugLog {
	[ "$DEBUG" = "1" ] && echo "DEBUG: $*" >&2
}

function SetSource {
	LAST_SOURCE="$1"
}

function PrintValue {
	local SRC="$1"
	shift
	SetSource "$SRC"
	if [ "$SOURCE_ONLY" = "1" ]; then
		echo "$LAST_SOURCE"
	else
		echo "$*"
	fi
}

function PrintNoData {
	local SRC="$1"
	SetSource "$SRC"
	if [ "$SOURCE_ONLY" = "1" ]; then
		echo "$LAST_SOURCE"
	fi
	return 1
}

function IsCommand {
	command -v "$1" >/dev/null 2>&1
}

function RunWithTimeoutValue {
	local TIMEOUT_VALUE="$1"
	shift
	if IsCommand timeout; then
		timeout "$TIMEOUT_VALUE" "$@"
	else
		"$@"
	fi
}

function RunWithTimeout {
	RunWithTimeoutValue "$COMMAND_TIMEOUT" "$@"
}

function Trim {
	sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

function JsonEscape {
	sed 's/\\/\\\\/g;s/"/\\"/g'
}

function EmptyLLD {
	echo '{"data":[]}'
}

function NormalizeHealth {
	case "$1" in
		Ok|OK|ok|Optimal|Opt|Optl|Online|Onln|Ready|Enabled)
			echo "OK"
			;;
		Non-Critical|NonCritical|Warning|Warn|Dgrd|Pdgd|Degraded|Partially*)
			echo "Warning"
			;;
		Critical|Failed|Failure|Offln|Offline|Msng|Missing|UBad|Bad)
			echo "Critical"
			;;
		"")
			echo "Unknown"
			;;
		*)
			echo "$1"
			;;
	esac
}

function NormalizePdState {
	case "$1" in
		Onln|Online)
			echo "Online"
			;;
		UGood)
			echo "Ready"
			;;
		Offln|Offline|Msng|Missing|UBad)
			echo "Failed"
			;;
		rbld|Rbld|Rebuild)
			echo "Rebuild"
			;;
		*)
			echo "${1:-Unknown}"
			;;
	esac
}

function SizeToBytes {
	local VALUE="$1"
	local UNIT="$2"
	local BASE="${SIZE_BASE:-1024}"

	case "$BASE" in
		1000|1024)
			;;
		*)
			BASE="1024"
			;;
	esac

	awk -v V="$VALUE" -v U="$UNIT" -v B="$BASE" 'BEGIN {
		U=toupper(U)
		M=1
		if (U=="KB" || U=="KIB") M=B
		else if (U=="MB" || U=="MIB") M=B*B
		else if (U=="GB" || U=="GIB") M=B*B*B
		else if (U=="TB" || U=="TIB") M=B*B*B*B
		else if (U=="PB" || U=="PIB") M=B*B*B*B*B
		printf "%.0f\n", V*M
	}'
}

function OMSARun {
	[ -x "$OMSABIN" ] || return 127
	RunWithTimeoutValue "$OMSA_TIMEOUT" "$OMSABIN" "$@" 2>&1
}

function OMSAUsable {
	[ -x "$OMSABIN" ] || return 1
	local OUT
	OUT="$(OMSARun chassis info)" || return 1
	[ -n "$OUT" ] || return 1
	echo "$OUT" | grep -q "^Chassis" || return 1
	return 0
}

function OMSAValueOrEmpty {
	local OUT
	OUT="$(OMSARun "$@")" || return 1
	[ -n "$OUT" ] || return 1
	echo "$OUT"
	return 0
}

function FindPerccli {
	if [ -n "$PERCCLI_BIN" ] && [ -x "$PERCCLI_BIN" ]; then
		echo "$PERCCLI_BIN"
		return 0
	fi

	for BIN in \
		/opt/MegaRAID/perccli/perccli64 \
		/opt/MegaRAID/perccli/perccli \
		/opt/MegaRAID/storcli/storcli64 \
		/opt/MegaRAID/storcli/storcli \
		/usr/sbin/perccli64 \
		/usr/sbin/perccli \
		/usr/sbin/storcli64 \
		/usr/sbin/storcli \
		/usr/bin/perccli64 \
		/usr/bin/perccli \
		/usr/bin/storcli64 \
		/usr/bin/storcli
	do
		[ -x "$BIN" ] && echo "$BIN" && return 0
	done

	return 1
}

function PerccliRun {
	local BIN
	BIN="$(FindPerccli)" || return 127
	RunWithTimeoutValue "$PERCCLI_TIMEOUT" "$BIN" "$@" 2>&1
}

function PerccliControllers {
	local OUT
	OUT="$(PerccliRun show)" || return 1
	echo "$OUT" | awk '$1 ~ /^[0-9]+$/ {print $1}'
}

function IPMIRun {
	IsCommand ipmitool || return 127
	RunWithTimeoutValue "$IPMI_TIMEOUT" ipmitool -I open "$@" 2>&1
}

function CacheIsFresh {
	local FILE="$1"
	local TTL="$2"
	local NOW MTIME AGE
	[ -s "$FILE" ] || return 1
	NOW="$(date +%s)"
	MTIME="$(stat -c %Y "$FILE" 2>/dev/null)" || return 1
	AGE=$((NOW - MTIME))
	[ "$AGE" -le "$TTL" ]
}


function RemoveStaleIPMILock {
	local LOCK="$1"
	local LIMIT="${2:-30}"
	local NOW MTIME AGE
	[ -d "$LOCK" ] || return 0
	NOW="$(date +%s)"
	MTIME="$(stat -c %Y "$LOCK" 2>/dev/null)" || return 0
	AGE=$((NOW - MTIME))
	if [ "$AGE" -gt "$LIMIT" ]; then
		rmdir "$LOCK" 2>/dev/null || true
	fi
}

function IPMISensorOutput {
	local OUT WAIT_COUNT TMPFILE

	# 新しいキャッシュがあれば即返す
	if CacheIsFresh "$IPMI_SENSOR_CACHE" "$IPMI_CACHE_TTL"; then
		cat "$IPMI_SENSOR_CACHE"
		return 0
	fi

	RemoveStaleIPMILock "$IPMI_SENSOR_CACHE_LOCK" 30

	# 複数アイテム同時実行時にipmitoolを多重起動しないように簡易ロックする
	if mkdir "$IPMI_SENSOR_CACHE_LOCK" 2>/dev/null; then
		OUT="$(IPMIRun sensor)"
		if [ $? -ne 0 ] || [ -z "$OUT" ]; then
			rmdir "$IPMI_SENSOR_CACHE_LOCK" 2>/dev/null || true
			if [ -s "$IPMI_SENSOR_CACHE" ]; then
				cat "$IPMI_SENSOR_CACHE"
				return 0
			fi
			return 1
		fi
		TMPFILE="${IPMI_SENSOR_CACHE}.$$"
		printf '%s
' "$OUT" > "$TMPFILE" 2>/dev/null && mv -f "$TMPFILE" "$IPMI_SENSOR_CACHE" 2>/dev/null || rm -f "$TMPFILE" 2>/dev/null || true
		chmod 644 "$IPMI_SENSOR_CACHE" 2>/dev/null || true
		rmdir "$IPMI_SENSOR_CACHE_LOCK" 2>/dev/null || true
		printf '%s
' "$OUT"
		return 0
	fi

	# 他プロセスが更新中の場合、少し待ってから新しいキャッシュを使う
	WAIT_COUNT=0
	while [ "$WAIT_COUNT" -lt 10 ]; do
		if CacheIsFresh "$IPMI_SENSOR_CACHE" "$IPMI_CACHE_TTL"; then
			cat "$IPMI_SENSOR_CACHE"
			return 0
		fi
		sleep 0.1
		WAIT_COUNT=$((WAIT_COUNT + 1))
	done

	# キャッシュが無い場合だけ最後に直接取得を試す
	OUT="$(IPMIRun sensor)" || return 1
	[ -n "$OUT" ] || return 1
	TMPFILE="${IPMI_SENSOR_CACHE}.$$"
	printf '%s
' "$OUT" > "$TMPFILE" 2>/dev/null && mv -f "$TMPFILE" "$IPMI_SENSOR_CACHE" 2>/dev/null || rm -f "$TMPFILE" 2>/dev/null || true
	chmod 644 "$IPMI_SENSOR_CACHE" 2>/dev/null || true
	printf '%s
' "$OUT"
}
function OMSABmcOutput {
	local OUT WAIT_COUNT TMPFILE

	# BMC/iDRAC情報はZabbixの複数アイテムから同時に呼ばれやすく、初回に空やタイムアウトになる場合があるためキャッシュする
	if CacheIsFresh "$OMSA_BMC_CACHE" "$OMSA_BMC_CACHE_TTL"; then
		cat "$OMSA_BMC_CACHE"
		return 0
	fi

	RemoveStaleIPMILock "$OMSA_BMC_CACHE_LOCK" 30

	if mkdir "$OMSA_BMC_CACHE_LOCK" 2>/dev/null; then
		OUT="$(OMSARun chassis bmc 2>/dev/null)" || true
		if [ -z "$OUT" ]; then
			sleep 1
			OUT="$(OMSARun chassis bmc 2>/dev/null)" || true
		fi

		if [ -n "$OUT" ]; then
			TMPFILE="${OMSA_BMC_CACHE}.$$"
			printf '%s
' "$OUT" > "$TMPFILE" 2>/dev/null && mv -f "$TMPFILE" "$OMSA_BMC_CACHE" 2>/dev/null || rm -f "$TMPFILE" 2>/dev/null || true
			chmod 644 "$OMSA_BMC_CACHE" 2>/dev/null || true
			rmdir "$OMSA_BMC_CACHE_LOCK" 2>/dev/null || true
			printf '%s
' "$OUT"
			return 0
		fi

		rmdir "$OMSA_BMC_CACHE_LOCK" 2>/dev/null || true
		# 取得に失敗しても古いキャッシュがあれば、初回Unsupported化を避けるため利用する
		if [ -s "$OMSA_BMC_CACHE" ]; then
			cat "$OMSA_BMC_CACHE"
			return 0
		fi
		return 1
	fi

	WAIT_COUNT=0
	while [ "$WAIT_COUNT" -lt 20 ]; do
		if CacheIsFresh "$OMSA_BMC_CACHE" "$OMSA_BMC_CACHE_TTL"; then
			cat "$OMSA_BMC_CACHE"
			return 0
		fi
		sleep 0.1
		WAIT_COUNT=$((WAIT_COUNT + 1))
	done

	if [ -s "$OMSA_BMC_CACHE" ]; then
		cat "$OMSA_BMC_CACHE"
		return 0
	fi
	return 1
}

function ExtractOmreportField {
	local FIELD="$1"
	awk -F':' -v FIELD="$FIELD" '
		$0 ~ "^[[:space:]]*" FIELD "[[:space:]]*:" {
			$1=""
			sub(/^:/, "", $0)
			gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
			print $0
			exit
		}
	'
}

function ExtractBmcIPv4Field {
	local FIELD="$1"
	awk -F':' -v FIELD="$FIELD" '
		/^[[:space:]]*IPv4 Address[[:space:]]*:/ {
			v=$2
			gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
			if (FIELD == "IP Address" && v ~ /^[0-9.]+$/) { print v; exit }
		}
		/^[[:space:]]*IPv4 Address[[:space:]]*$/ { in_ipv4=1; next }
		in_ipv4 && /^[[:space:]]*IPv6 Address/ { in_ipv4=0 }
		in_ipv4 && $0 ~ "^[[:space:]]*" FIELD "[[:space:]]*:" {
			$1=""
			sub(/^:/, "", $0)
			gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
			print $0
			exit
		}
	'
}

function NormalizeLicenseValue {
	local VALUE="$*"
	VALUE="$(printf '%s
' "$VALUE" | Trim)"
	case "$VALUE" in
		""|BMC|bmc|Unknown|UNKNOWN|None|none|Unsupported|Baseboard*)
			return 1
			;;
	esac
	if printf '%s
' "$VALUE" | grep -Eiq 'Enterprise|Express|Basic|Datacenter|Data[ -]?Center|iDRAC[0-9].*(Enterprise|Express|Basic)'; then
		printf '%s
' "$VALUE"
		return 0
	fi
	# Device Typeが単なるBMCではなく、ライセンスらしい文字列の場合のみ返す
	return 1
}

function ExtractBmcLicenseOMSA {
	local OUT="$1"
	local VALUE
	VALUE="$(printf '%s
' "$OUT" | ExtractOmreportField "License Description")"
	VALUE="$(NormalizeLicenseValue "$VALUE")" && { printf '%s
' "$VALUE"; return 0; }
	VALUE="$(printf '%s
' "$OUT" | ExtractOmreportField "License Type")"
	VALUE="$(NormalizeLicenseValue "$VALUE")" && { printf '%s
' "$VALUE"; return 0; }
	VALUE="$(printf '%s
' "$OUT" | ExtractOmreportField "License")"
	VALUE="$(NormalizeLicenseValue "$VALUE")" && { printf '%s
' "$VALUE"; return 0; }

	# OMSAで取得できたDevice Typeは既存テンプレート互換のため、そのまま返します。
	# Redfish/racadm等の非OMSA取得でBMC/Baseboard系しか取れない場合は、ライセンス種別ではないためUnsupported扱いにします。
	VALUE="$(printf '%s
' "$OUT" | ExtractOmreportField "Device Type" | Trim)"
	[ -n "$VALUE" ] && { printf '%s
' "$VALUE"; return 0; }
	return 1
}

function FindRacadm {
	local BIN
	for BIN in \
		racadm \
		/opt/dell/srvadmin/sbin/racadm \
		/opt/dell/srvadmin/bin/racadm \
		/opt/dell/srvadmin/bin/idracadm7 \
		/opt/dell/srvadmin/sbin/idracadm7
	do
		if command -v "$BIN" >/dev/null 2>&1; then
			command -v "$BIN"
			return 0
		fi
		[ -x "$BIN" ] && echo "$BIN" && return 0
	done
	return 1
}

function RacadmLicense {
	local BIN OUT VALUE
	BIN="$(FindRacadm)" || return 1
	OUT="$(RunWithTimeoutValue "$COMMAND_TIMEOUT" "$BIN" license view 2>/dev/null)" || return 1
	VALUE="$(printf '%s
' "$OUT" | awk -F'=' '/License Description|License Type|License/ {v=$2; gsub(/^[[:space:]]+|[[:space:]]+$/, "", v); print v; exit}')"
	[ -n "$VALUE" ] || VALUE="$(printf '%s
' "$OUT" | awk -F':' '/License Description|License Type|License/ {v=$2; gsub(/^[[:space:]]+|[[:space:]]+$/, "", v); print v; exit}')"
	VALUE="$(NormalizeLicenseValue "$VALUE")" || return 1
	printf '%s
' "$VALUE"
}

function RedfishLicense {
	local OUT MEMBER VALUE
	OUT="$(RedfishGet /redfish/v1/Dell/Managers/iDRAC.Embedded.1/DellLicenseCollection 2>/dev/null)" || return 1
	[ -n "$OUT" ] || return 1
	VALUE="$(printf '%s
' "$OUT" | tr -d '\n' | JsonStringValue "LicenseDescription")"
	VALUE="$(NormalizeLicenseValue "$VALUE")" && { printf '%s
' "$VALUE"; return 0; }
	MEMBER="$(printf '%s
' "$OUT" | tr -d '\n' | sed -n 's/.*"@odata.id"[[:space:]]*:[[:space:]]*"\([^"]*DellLicenseCollection[^"]*\)".*/\1/p' | head -1)"
	[ -n "$MEMBER" ] || return 1
	OUT="$(RedfishGet "$MEMBER" 2>/dev/null)" || return 1
	VALUE="$(printf '%s
' "$OUT" | tr -d '\n' | JsonStringValue "LicenseDescription")"
	VALUE="$(NormalizeLicenseValue "$VALUE")" && { printf '%s
' "$VALUE"; return 0; }
	VALUE="$(printf '%s
' "$OUT" | tr -d '\n' | JsonStringValue "LicenseType")"
	VALUE="$(NormalizeLicenseValue "$VALUE")" && { printf '%s
' "$VALUE"; return 0; }
	VALUE="$(printf '%s
' "$OUT" | tr -d '\n' | JsonStringValue "Name")"
	VALUE="$(NormalizeLicenseValue "$VALUE")" && { printf '%s
' "$VALUE"; return 0; }
	return 1
}

function DmiGet {
	local KEY="$1"
	IsCommand dmidecode || return 127
	RunWithTimeout dmidecode -s "$KEY" 2>/dev/null | head -1 | Trim
}

function LoadRedfishBaseFromConfig {
	local CONF_BASE
	[ -f "$REDFISH_CONFIG" ] || return 0
	[ -n "$REDFISH_BASE_ENV" ] && return 0
	CONF_BASE="$(sed -n 's/^#[[:space:]]*REDFISH_BASE=["'"'"']\{0,1\}\([^"'"'"'[:space:]]*\).*/\1/p' "$REDFISH_CONFIG" | head -1)"
	[ -n "$CONF_BASE" ] && REDFISH_BASE="$CONF_BASE"
}

function RedfishAvailable {
	[ -f "$REDFISH_CONFIG" ] || return 1
	IsCommand curl || return 1
	return 0
}

function RedfishGet {
	local URI="$1"
	RedfishAvailable || return 127
	LoadRedfishBaseFromConfig
	curl --config "$REDFISH_CONFIG" "${REDFISH_BASE}${URI}" 2>/dev/null
}

function JsonStringValue {
	local KEY="$1"
	sed -n "s/.*\"${KEY}\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1
}

function JsonNumberValue {
	local KEY="$1"
	sed -n "s/.*\"${KEY}\"[[:space:]]*:[[:space:]]*\([0-9.]*\).*/\1/p" | head -1
}

function RedfishServiceRootValue {
	local KEY="$1"
	local OUT
	OUT="$(RedfishGet /redfish/v1/)" || return 1
	[ -n "$OUT" ] || return 1
	echo "$OUT" | tr -d '\n' | JsonStringValue "$KEY"
}

function RedfishSystemValue {
	local KEY="$1"
	local OUT
	OUT="$(RedfishGet /redfish/v1/Systems/System.Embedded.1)" || return 1
	[ -n "$OUT" ] || return 1
	echo "$OUT" | tr -d '\n' | JsonStringValue "$KEY"
}

function RedfishManagerValue {
	local KEY="$1"
	local OUT
	OUT="$(RedfishGet /redfish/v1/Managers/iDRAC.Embedded.1)" || return 1
	[ -n "$OUT" ] || return 1
	echo "$OUT" | tr -d '\n' | JsonStringValue "$KEY"
}

function RedfishSystemHealth {
	local OUT HEALTH
	OUT="$(RedfishGet /redfish/v1/Systems/System.Embedded.1)" || return 1
	[ -n "$OUT" ] || return 1
	HEALTH="$(echo "$OUT" | tr -d '\n' | sed -n 's/.*"Status"[[:space:]]*:{[^}]*"HealthRollup"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
	[ -n "$HEALTH" ] || HEALTH="$(echo "$OUT" | tr -d '\n' | sed -n 's/.*"Status"[[:space:]]*:{[^}]*"Health"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
	[ -n "$HEALTH" ] || return 1
	NormalizeHealth "$HEALTH"
}

function JsonObjectLines {
	# 簡易JSONパーサーです。
	# Dell Redfishやperccliのような監視用途のJSONから、配列内の各オブジェクトを1行化します。
	tr '\n' ' ' | sed 's/}[[:space:]]*,[[:space:]]*{/}\
{/g'
}

function JsonStringValueFromLine {
	local LINE="$1"
	local KEY="$2"
	printf '%s\n' "$LINE" | JsonStringValue "$KEY"
}

function JsonNumberValueFromLine {
	local LINE="$1"
	local KEY="$2"
	printf '%s\n' "$LINE" | JsonNumberValue "$KEY"
}

function RedfishThermalOutput {
	local OUT
	OUT="$(RedfishGet /redfish/v1/Chassis/System.Embedded.1/Thermal)" || return 1
	[ -n "$OUT" ] || return 1
	printf '%s\n' "$OUT"
}

function RedfishPowerOutput {
	local OUT
	OUT="$(RedfishGet /redfish/v1/Chassis/System.Embedded.1/Power)" || return 1
	[ -n "$OUT" ] || return 1
	printf '%s\n' "$OUT"
}

function SystemModel {
	local OUT VALUE
	OUT="$(OMSAValueOrEmpty chassis info)"
	VALUE="$(echo "$OUT" | awk -F':' '/^Chassis Model/ {print $2; exit}' | Trim)"
	[ -n "$VALUE" ] && PrintValue "OMSA" "$VALUE" && return

	VALUE="$(DmiGet system-product-name)"
	[ -n "$VALUE" ] && PrintValue "dmidecode" "$VALUE" && return

	VALUE="$(RedfishSystemValue Model)"
	[ -n "$VALUE" ] && PrintValue "Redfish" "$VALUE" && return

	PrintValue "none" "Unknown"
}

function SystemServiceTag {
	local OUT VALUE
	OUT="$(OMSAValueOrEmpty chassis info)"
	VALUE="$(echo "$OUT" | awk -F':' '/^Chassis Service Tag/ {print $2; exit}' | Trim)"
	[ -n "$VALUE" ] && PrintValue "OMSA" "$VALUE" && return

	VALUE="$(DmiGet system-serial-number)"
	[ -n "$VALUE" ] && PrintValue "dmidecode" "$VALUE" && return

	VALUE="$(RedfishServiceRootValue ServiceTag)"
	[ -n "$VALUE" ] && PrintValue "Redfish" "$VALUE" && return

	VALUE="$(RedfishSystemValue SKU)"
	[ -n "$VALUE" ] && PrintValue "Redfish" "$VALUE" && return

	PrintValue "none" "Unknown"
}

function SystemBiosVersion {
	local OUT VALUE
	OUT="$(OMSAValueOrEmpty chassis bios)"
	VALUE="$(echo "$OUT" | awk '/^Version/ {print $3; exit}' | Trim)"
	[ -n "$VALUE" ] && PrintValue "OMSA" "$VALUE" && return

	VALUE="$(DmiGet bios-version)"
	[ -n "$VALUE" ] && PrintValue "dmidecode" "$VALUE" && return

	VALUE="$(RedfishSystemValue BiosVersion)"
	[ -n "$VALUE" ] && PrintValue "Redfish" "$VALUE" && return

	PrintValue "none" "Unknown"
}

function SystemIdracVersion {
	local OUT VALUE
	OUT="$(OMSAValueOrEmpty chassis info)"
	VALUE="$(echo "$OUT" | awk 'BEGIN{IGNORECASE=1} /^idrac/ {print $1,$4; exit}' | Trim)"
	[ -n "$VALUE" ] && PrintValue "OMSA" "$VALUE" && return

	VALUE="$(RedfishManagerValue FirmwareVersion)"
	[ -n "$VALUE" ] && PrintValue "Redfish" "$VALUE" && return

	OUT="$(IPMIRun mc info)"
	VALUE="$(echo "$OUT" | awk -F':' '/Firmware Revision/ {print $2; exit}' | Trim)"
	[ -n "$VALUE" ] && PrintValue "ipmitool" "$VALUE" && return

	PrintValue "none" "none"
}

function SystemStatus {
	local OUT VALUE
	OUT="$(OMSAValueOrEmpty chassis)"
	if [ -n "$OUT" ]; then
		if echo "$OUT" | awk -F':' '
			/SEVERITY/ {next}
			/:/ {
				status=$1
				gsub(/^[[:space:]]+|[[:space:]]+$/, "", status)
				if (tolower(status) != "ok") bad=1
			}
			END {exit bad ? 0 : 1}
		'; then
			PrintValue "OMSA" "Failure"
		else
			PrintValue "OMSA" "OK"
		fi
		return
	fi

	VALUE="$(RedfishSystemHealth)"
	[ -n "$VALUE" ] && PrintValue "Redfish" "$VALUE" && return

	if PerccliRun show | awk '$NF ~ /Opt/ {ok=1} END{exit ok?0:1}'; then
		PrintValue "perccli" "OK"
		return
	fi

	PrintValue "none" "Unknown"
}

function PhysicalDisksDiscoveryOMSA {
	local CONTROLLERS CONTROLLER DISKS DISK RESULT JSON
	CONTROLLERS="$(OMSARun storage controller | grep ^ID | awk '{print $3}')" || return 1
	[ -n "$CONTROLLERS" ] || return 1
	for CONTROLLER in $CONTROLLERS; do
		DISKS="$(OMSARun storage pdisk controller="$CONTROLLER" | grep ^ID | awk '{print $3}')"
		for DISK in $DISKS; do
			RESULT+="$(printf '\n{\n\"{#PDISK}\": \"%s\",\n\"{#CONTROLLER}\": \"%s\"\n},' "$(echo "$DISK" | JsonEscape)" "$(echo "$CONTROLLER" | JsonEscape)")"
		done
	done
	[ -n "$RESULT" ] || return 1
	JSON="$(echo "$RESULT" | sed '$s/,$//')"
	printf '{\n"data":[%s\n]}\n' "$JSON"
}

function PhysicalDisksDiscoveryPerccli {
	local CONTROLLER OUT RESULT JSON LINE DISK
	for CONTROLLER in $(PerccliControllers); do
		OUT="$(PerccliRun /c"$CONTROLLER"/eall/sall show)" || continue
		while IFS= read -r LINE; do
			DISK="$(echo "$LINE" | awk '$1 ~ /^[0-9]+:[0-9]+$/ {print $1}')"
			[ -n "$DISK" ] || continue
			RESULT+="$(printf '\n{\n\"{#PDISK}\": \"%s\",\n\"{#CONTROLLER}\": \"%s\"\n},' "$(echo "$DISK" | JsonEscape)" "$(echo "$CONTROLLER" | JsonEscape)")"
		done <<< "$OUT"
	done
	[ -n "$RESULT" ] || return 1
	JSON="$(echo "$RESULT" | sed '$s/,$//')"
	printf '{\n"data":[%s\n]}\n' "$JSON"
}

function PhysicalDisksDiscovery {
	local OUT
	OUT="$(PhysicalDisksDiscoveryOMSA)" && { [ "$SOURCE_ONLY" = "1" ] && echo "OMSA" || echo "$OUT"; SetSource "OMSA"; return; }
	OUT="$(PhysicalDisksDiscoveryPerccli)" && { [ "$SOURCE_ONLY" = "1" ] && echo "perccli" || echo "$OUT"; SetSource "perccli"; return; }
	[ "$SOURCE_ONLY" = "1" ] && echo "none" || EmptyLLD
}

function PhysicalDiskStatusOMSA {
	local PDISK="$1"
	local CONTROLLER="$2"
	local ITEM="$3"
	local OUT VALUE
	OUT="$(OMSARun storage pdisk controller="$CONTROLLER" pdisk="$PDISK")" || return 1
	[ -n "$OUT" ] || return 1
	case "$ITEM" in
		status)
			VALUE="$(echo "$OUT" | awk '/^State/ {print $3; exit}')"
			;;
		pfailure)
			VALUE="$(echo "$OUT" | awk '/^Failure Predicted/ {print $4; exit}')"
			;;
	esac
	[ -n "$VALUE" ] || return 1
	echo "$VALUE"
}

function PhysicalDiskStatusPerccli {
	local PDISK="$1"
	local CONTROLLER="$2"
	local ITEM="$3"
	local EID SLOT OUT LINE VALUE SMART PRED
	EID="${PDISK%%:*}"
	SLOT="${PDISK##*:}"
	case "$ITEM" in
		status)
			OUT="$(PerccliRun /c"$CONTROLLER"/eall/sall show)" || return 1
			LINE="$(echo "$OUT" | awk -v D="$PDISK" '$1==D {print; exit}')"
			VALUE="$(echo "$LINE" | awk '{print $3}')"
			[ -n "$VALUE" ] || return 1
			NormalizePdState "$VALUE"
			;;
		pfailure)
			OUT="$(PerccliRun /c"$CONTROLLER"/e"$EID"/s"$SLOT" show all)" || return 1
			PRED="$(echo "$OUT" | awk -F'=' '/Predictive Failure Count/ {gsub(/^ *| *$/, "", $2); print $2; exit}')"
			SMART="$(echo "$OUT" | awk -F'=' '/S.M.A.R.T alert flagged by drive/ {gsub(/^ *| *$/, "", $2); print $2; exit}')"
			if [ "$SMART" = "Yes" ]; then
				echo "Yes"
			elif echo "$PRED" | grep -Eq '^[0-9]+$' && [ "$PRED" -gt 0 ]; then
				echo "Yes"
			else
				echo "No"
			fi
			;;
		*)
			return 1
			;;
	esac
}

function PhysicalDiskStatus {
	local VALUE
	VALUE="$(PhysicalDiskStatusOMSA "$1" "$2" "$3")" && [ -n "$VALUE" ] && PrintValue "OMSA" "$VALUE" && return
	VALUE="$(PhysicalDiskStatusPerccli "$1" "$2" "$3")" && [ -n "$VALUE" ] && PrintValue "perccli" "$VALUE" && return
	PrintValue "none" "Unknown"
}

function VirtualDiskDiscoveryOMSA {
	local CONTROLLERS CONTROLLER VDISKS VDISK RESULT JSON
	CONTROLLERS="$(OMSARun storage controller | grep ^ID | awk '{print $3}')" || return 1
	[ -n "$CONTROLLERS" ] || return 1
	for CONTROLLER in $CONTROLLERS; do
		VDISKS="$(OMSARun storage vdisk controller="$CONTROLLER" | grep '^ID' | awk '{print $3}')"
		for VDISK in $VDISKS; do
			RESULT+="$(printf '\n{\n\"{#VDISK}\": \"%s\",\n\"{#CONTROLLER}\": \"%s\"\n},' "$(echo "$VDISK" | JsonEscape)" "$(echo "$CONTROLLER" | JsonEscape)")"
		done
	done
	[ -n "$RESULT" ] || return 1
	JSON="$(echo "$RESULT" | sed '$s/,$//')"
	printf '{\n"data":[%s\n]}\n' "$JSON"
}

function VirtualDiskDiscoveryPerccli {
	local CONTROLLER OUT RESULT JSON VDISK
	for CONTROLLER in $(PerccliControllers); do
		OUT="$(PerccliRun /c"$CONTROLLER"/vall show)" || continue
		while IFS= read -r VDISK; do
			[ -n "$VDISK" ] || continue
			RESULT+="$(printf '\n{\n\"{#VDISK}\": \"%s\",\n\"{#CONTROLLER}\": \"%s\"\n},' "$(echo "$VDISK" | JsonEscape)" "$(echo "$CONTROLLER" | JsonEscape)")"
		done <<< "$(echo "$OUT" | awk '$1 ~ /^[0-9]+\/[0-9]+$/ {print $1}')"
	done
	[ -n "$RESULT" ] || return 1
	JSON="$(echo "$RESULT" | sed '$s/,$//')"
	printf '{\n"data":[%s\n]}\n' "$JSON"
}

function VirtualDiskDiscovery {
	local OUT
	OUT="$(VirtualDiskDiscoveryOMSA)" && { [ "$SOURCE_ONLY" = "1" ] && echo "OMSA" || echo "$OUT"; SetSource "OMSA"; return; }
	OUT="$(VirtualDiskDiscoveryPerccli)" && { [ "$SOURCE_ONLY" = "1" ] && echo "perccli" || echo "$OUT"; SetSource "perccli"; return; }
	[ "$SOURCE_ONLY" = "1" ] && echo "none" || EmptyLLD
}

function VirtualDiskStatusOMSA {
	local VDISK="$1"
	local CONTROLLER="$2"
	local ITEM="$3"
	local OUT VALUE
	OUT="$(OMSARun storage vdisk controller="$CONTROLLER" vdisk="$VDISK")" || return 1
	[ -n "$OUT" ] || return 1
	case "$ITEM" in
		status)
			VALUE="$(echo "$OUT" | awk '/^Status/ {print $3; exit}')"
			VALUE="$(NormalizeHealth "$VALUE")"
			;;
		raid)
			VALUE="$(echo "$OUT" | awk '/^Layout/ {print $3; exit}')"
			;;
		size)
			VALUE="$(echo "$OUT" | awk -F'[()]' '/^Size/ && $2 ~ /bytes/ {gsub(/[^0-9]/, "", $2); print $2; exit}')"
			if [ -z "$VALUE" ]; then
				VALUE="$(echo "$OUT" | awk '/^Size/ {for(i=1;i<=NF;i++){if($i ~ /^[0-9,.]+$/){v=$i; u=$(i+1); gsub(/,/, "", v); print v " " u; exit}}}')"
				if [ -n "$VALUE" ]; then
					VALUE="$(SizeToBytes "$(echo "$VALUE" | awk '{print $1}')" "$(echo "$VALUE" | awk '{print $2}')")"
				fi
			fi
			;;
	esac
	[ -n "$VALUE" ] || return 1
	echo "$VALUE"
}

function VirtualDiskStatusPerccli {
	local VDISK="$1"
	local CONTROLLER="$2"
	local ITEM="$3"
	local OUT LINE VALUE UNIT
	OUT="$(PerccliRun /c"$CONTROLLER"/vall show)" || return 1
	LINE="$(echo "$OUT" | awk -v D="$VDISK" '$1==D {print; exit}')"
	[ -n "$LINE" ] || return 1
	case "$ITEM" in
		status)
			NormalizeHealth "$(echo "$LINE" | awk '{print $3}')"
			;;
		raid)
			echo "$LINE" | awk '{print $2}'
			;;
		size)
			VALUE="$(echo "$LINE" | awk '{print $9}')"
			UNIT="$(echo "$LINE" | awk '{print $10}')"
			[ -n "$VALUE" ] && [ -n "$UNIT" ] || return 1
			SizeToBytes "$VALUE" "$UNIT"
			;;
		*)
			return 1
			;;
	esac
}

function VirtualDiskStatus {
	local VALUE
	VALUE="$(VirtualDiskStatusOMSA "$1" "$2" "$3")" && [ -n "$VALUE" ] && PrintValue "OMSA" "$VALUE" && return
	VALUE="$(VirtualDiskStatusPerccli "$1" "$2" "$3")" && [ -n "$VALUE" ] && PrintValue "perccli" "$VALUE" && return
	if [ "$3" = "size" ]; then
		PrintNoData "none"
		return 1
	fi
	PrintValue "none" "Unknown"
}

function FanDiscoveryOMSA {
	local OUT FANS FAN RESULT JSON
	OUT="$(OMSARun chassis fans)" || return 1
	FANS="$(echo "$OUT" | grep ^Index | awk '{print $3}')"
	[ -n "$FANS" ] || return 1
	for FAN in $FANS; do
		RESULT+="$(printf '\n{\n\"{#FAN}\": \"%s\"\n},' "$(echo "$FAN" | JsonEscape)")"
	done
	JSON="$(echo "$RESULT" | sed '$s/,$//')"
	printf '{\n"data":[%s\n]}\n' "$JSON"
}

function FanDiscoveryIPMI {
	local OUT RESULT JSON NAME
	OUT="$(IPMISensorOutput)" || return 1
	while IFS= read -r NAME; do
		[ -n "$NAME" ] || continue
		RESULT+="$(printf '\n{\n\"{#FAN}\": \"%s\"\n},' "$(echo "$NAME" | JsonEscape)")"
	done <<< "$(echo "$OUT" | awk -F'|' 'tolower($1) ~ /fan/ && tolower($3) ~ /rpm/ {gsub(/^ *| *$/, "", $1); print $1}')"
	[ -n "$RESULT" ] || return 1
	JSON="$(echo "$RESULT" | sed '$s/,$//')"
	printf '{\n"data":[%s\n]}\n' "$JSON"
}

function FanDiscovery {
	local OUT
	OUT="$(FanDiscoveryOMSA)" && { [ "$SOURCE_ONLY" = "1" ] && echo "OMSA" || echo "$OUT"; SetSource "OMSA"; return; }
	OUT="$(FanDiscoveryIPMI)" && { [ "$SOURCE_ONLY" = "1" ] && echo "ipmitool" || echo "$OUT"; SetSource "ipmitool"; return; }
	[ "$SOURCE_ONLY" = "1" ] && echo "none" || EmptyLLD
}

function FanStatusOMSA {
	local FAN="$1"
	local ITEM="$2"
	local OUT VALUE
	OUT="$(OMSARun chassis fans index="$FAN")" || return 1
	[ -n "$OUT" ] || return 1
	case "$ITEM" in
		rpm)
			VALUE="$(echo "$OUT" | awk '/^Reading/ {print $3; exit}')"
			;;
		status)
			VALUE="$(echo "$OUT" | awk '/^Status/ {print $3; exit}')"
			VALUE="$(NormalizeHealth "$VALUE")"
			;;
	esac
	[ -n "$VALUE" ] || return 1
	echo "$VALUE"
}

function FanStatusIPMI {
	local FAN="$1"
	local ITEM="$2"
	local LINE VALUE
	LINE="$(IPMISensorOutput | awk -F'|' -v F="$FAN" '{name=$1; gsub(/^ *| *$/, "", name); if(name==F){print; exit}}')" || return 1
	[ -n "$LINE" ] || return 1
	case "$ITEM" in
		rpm)
			VALUE="$(echo "$LINE" | awk -F'|' '{gsub(/^ *| *$/, "", $2); print $2}' | grep -Eo '^[0-9.]+')"
			;;
		status)
			VALUE="$(echo "$LINE" | awk -F'|' '{gsub(/^ *| *$/, "", $4); print $4}')"
			VALUE="$(NormalizeHealth "$VALUE")"
			;;
	esac
	[ -n "$VALUE" ] || return 1
	echo "$VALUE"
}

function FanStatus {
	local VALUE
	VALUE="$(FanStatusOMSA "$1" "$2")" && [ -n "$VALUE" ] && PrintValue "OMSA" "$VALUE" && return
	VALUE="$(FanStatusIPMI "$1" "$2")" && [ -n "$VALUE" ] && PrintValue "ipmitool" "$VALUE" && return
	case "$2" in
		rpm)
			PrintValue "none" "0"
			;;
		*)
			PrintValue "none" "Unknown"
			;;
	esac
}

function TempDiscoveryOMSA {
	local OUT LINE INDEX PROBE RESULT JSON
	OUT="$(OMSARun chassis temps)" || return 1
	while IFS= read -r LINE; do
		case "$LINE" in
			Index*)
				INDEX="$(printf '%s\n' "$LINE" | cut -d':' -f2- | Trim)"
				;;
			"Probe Name"*)
				PROBE="$(printf '%s\n' "$LINE" | cut -d':' -f2- | Trim)"
				if [ -n "$INDEX" ] && [ -n "$PROBE" ]; then
					RESULT+="$(printf '\n{\n\"{#TEMP}\": \"%s\",\n\"{#TEMPINDEX}\": \"%s\"\n},' "$(echo "$PROBE" | JsonEscape)" "$(echo "$INDEX" | JsonEscape)")"
					INDEX=""
					PROBE=""
				fi
				;;
		esac
	done <<< "$OUT"
	[ -n "$RESULT" ] || return 1
	JSON="$(echo "$RESULT" | sed '$s/,$//')"
	printf '{\n"data":[%s\n]}\n' "$JSON"
}

function TempDiscoveryIPMI {
	local OUT RESULT JSON NAME INDEX DISP
	OUT="$(IPMISensorOutput)" || return 1
	while IFS=$'\t' read -r NAME INDEX DISP; do
		[ -n "$NAME" ] || continue
		[ -n "$DISP" ] || DISP="$NAME"
		RESULT+="$(printf '\n{\n\"{#TEMP}\": \"%s\",\n\"{#TEMPINDEX}\": \"%s\"\n},' "$(echo "$DISP" | JsonEscape)" "$(echo "$INDEX" | JsonEscape)")"
	done <<< "$(echo "$OUT" | awk -F'|' '
		function trim(s) {
			gsub(/^ *| *$/, "", s)
			return s
		}
		function ipmi_temp_display_name(raw) {
			if (raw == "Inlet Temp") return "System Board Inlet Temp"
			if (raw == "Exhaust Temp") return "System Board Exhaust Temp"
			if (raw == "Temp") {
				cpu_temp_count++
				return "CPU" cpu_temp_count " Temp"
			}
			return raw
		}
		BEGIN {n=0}
		tolower($3) ~ /degrees c/ {
			name=trim($1)
			disp=ipmi_temp_display_name(name)
			printf "%s\tipmi:%d\t%s\n", name, n, disp
			n++
		}
	')"
	[ -n "$RESULT" ] || return 1
	JSON="$(echo "$RESULT" | sed '$s/,$//')"
	printf '{\n"data":[%s\n]}\n' "$JSON"
}

function TempDiscoveryRedfish {
	local OUT RESULT JSON LINE NAME INDEX DISP N
	OUT="$(RedfishThermalOutput)" || return 1
	N=0
	while IFS= read -r LINE; do
		printf '%s\n' "$LINE" | grep -q '"ReadingCelsius"' || continue
		NAME="$(JsonStringValueFromLine "$LINE" "Name" | Trim)"
		[ -n "$NAME" ] || NAME="Redfish Temp $N"
		INDEX="redfish-temp:$N"
		DISP="$NAME"
		RESULT+="$(printf '\n{\n\"{#TEMP}\": \"%s\",\n\"{#TEMPINDEX}\": \"%s\"\n},' "$(echo "$DISP" | JsonEscape)" "$(echo "$INDEX" | JsonEscape)")"
		N=$((N + 1))
	done <<< "$(printf '%s\n' "$OUT" | JsonObjectLines)"
	[ -n "$RESULT" ] || return 1
	JSON="$(echo "$RESULT" | sed '$s/,$//')"
	printf '{\n"data":[%s\n]}\n' "$JSON"
}

function TempDiscovery {
	local OUT
	OUT="$(TempDiscoveryOMSA)" && { [ "$SOURCE_ONLY" = "1" ] && echo "OMSA" || echo "$OUT"; SetSource "OMSA"; return; }
	OUT="$(TempDiscoveryRedfish)" && { [ "$SOURCE_ONLY" = "1" ] && echo "Redfish" || echo "$OUT"; SetSource "Redfish"; return; }
	OUT="$(TempDiscoveryIPMI)" && { [ "$SOURCE_ONLY" = "1" ] && echo "ipmitool" || echo "$OUT"; SetSource "ipmitool"; return; }
	[ "$SOURCE_ONLY" = "1" ] && echo "none" || EmptyLLD
}

function TempStatusOMSA {
	local INDEX="$1"
	local OUT VALUE
	OUT="$(OMSARun chassis temps index="$INDEX")" || return 1
	VALUE="$(echo "$OUT" | awk '/^Reading/ {print $3; exit}')"
	[ -n "$VALUE" ] || return 1
	echo "$VALUE"
}

function TempStatusIPMI {
	local TEMP="$1"
	local VALUE LINE TARGET_INDEX
	if echo "$TEMP" | grep -Eq '^ipmi:[0-9]+$'; then
		TARGET_INDEX="${TEMP#ipmi:}"
		LINE="$(IPMISensorOutput | awk -F'|' -v IDX="$TARGET_INDEX" '
			BEGIN {n=0}
			tolower($3) ~ /degrees c/ {
				val=$2
				gsub(/^ *| *$/, "", val)
				if (n==IDX) {print val; exit}
				n++
			}
		')" || return 1
		VALUE="$(echo "$LINE" | grep -Eo '^-?[0-9.]+')"
	elif echo "$TEMP" | grep -Eq '^[0-9]+$'; then
		TARGET_INDEX="$TEMP"
		LINE="$(IPMISensorOutput | awk -F'|' -v IDX="$TARGET_INDEX" '
			BEGIN {n=0}
			tolower($3) ~ /degrees c/ {
				val=$2
				gsub(/^ *| *$/, "", val)
				if (n==IDX || n+1==IDX) {print val; exit}
				n++
			}
		')" || return 1
		VALUE="$(echo "$LINE" | grep -Eo '^-?[0-9.]+')"
	else
		VALUE="$(IPMISensorOutput | awk -F'|' -v T="$TEMP" '
			function trim(s) {
				gsub(/^ *| *$/, "", s)
				return s
			}
			function ipmi_temp_display_name(raw) {
				if (raw == "Inlet Temp") return "System Board Inlet Temp"
				if (raw == "Exhaust Temp") return "System Board Exhaust Temp"
				if (raw == "Temp") {
					cpu_temp_count++
					return "CPU" cpu_temp_count " Temp"
				}
				return raw
			}
			tolower($3) ~ /degrees c/ {
				raw=trim($1)
				disp=ipmi_temp_display_name(raw)
				legacy=raw
				if (raw == "Temp" && cpu_temp_count > 1) legacy="Temp " cpu_temp_count
				if (raw==T || disp==T || legacy==T) {
					val=trim($2)
					print val
					exit
				}
			}
		' | grep -Eo '^-?[0-9.]+')"
	fi
	[ -n "$VALUE" ] || return 1
	echo "$VALUE"
}

function TempStatusRedfish {
	local TEMP="$1"
	local OUT LINE VALUE TARGET_INDEX
	OUT="$(RedfishThermalOutput)" || return 1
	if echo "$TEMP" | grep -Eq '^redfish-temp:[0-9]+$'; then
		TARGET_INDEX="${TEMP#redfish-temp:}"
		LINE="$(printf '%s\n' "$OUT" | JsonObjectLines | awk -v IDX="$TARGET_INDEX" '
			/"ReadingCelsius"/ {
				if (n==IDX) {print; exit}
				n++
			}
		')"
	else
		LINE="$(printf '%s\n' "$OUT" | JsonObjectLines | awk -v T="$TEMP" '
			/"ReadingCelsius"/ {
				line=$0
				name=line
				gsub(/^.*"Name"[[:space:]]*:[[:space:]]*"/, "", name)
				gsub(/".*$/, "", name)
				if (name==T) {print line; exit}
			}
		')"
	fi
	[ -n "$LINE" ] || return 1
	VALUE="$(JsonNumberValueFromLine "$LINE" "ReadingCelsius")"
	[ -n "$VALUE" ] || return 1
	printf '%s\n' "$VALUE"
}

function TempStatus {
	local VALUE
	VALUE="$(TempStatusOMSA "$1")" && [ -n "$VALUE" ] && PrintValue "OMSA" "$VALUE" && return
	VALUE="$(TempStatusRedfish "$1")" && [ -n "$VALUE" ] && PrintValue "Redfish" "$VALUE" && return
	VALUE="$(TempStatusIPMI "$1")" && [ -n "$VALUE" ] && PrintValue "ipmitool" "$VALUE" && return
	# ZabbixのNumeric(float)アイテムをunsupportedにしないため、取得不可時は数値を返す
	# 既定は -273 です。未対応/取得不可が一目で分かるようにしています。
	PrintValue "none" "$TEMP_UNSUPPORTED_VALUE"
}

function PsuDiscoveryOMSA {
	local OUT PSUS PSU RESULT JSON
	OUT="$(OMSARun chassis pwrsupplies)" || return 1
	PSUS="$(echo "$OUT" | grep ^Index | awk '{print $3}')"
	[ -n "$PSUS" ] || return 1
	for PSU in $PSUS; do
		RESULT+="$(printf '\n{\n\"{#PSU}\": \"%s\"\n},' "$(echo "$PSU" | JsonEscape)")"
	done
	JSON="$(echo "$RESULT" | sed '$s/,$//')"
	printf '{\n"data":[%s\n]}\n' "$JSON"
}

function PsuDiscoveryIPMI {
	local OUT RESULT JSON NAME
	OUT="$(IPMISensorOutput)" || return 1
	while IFS= read -r NAME; do
		[ -n "$NAME" ] || continue
		RESULT+="$(printf '\n{\n\"{#PSU}\": \"%s\"\n},' "$(echo "$NAME" | JsonEscape)")"
	done <<< "$(echo "$OUT" | awk -F'|' 'tolower($1) ~ /(ps|power)/ {gsub(/^ *| *$/, "", $1); print $1}')"
	[ -n "$RESULT" ] || return 1
	JSON="$(echo "$RESULT" | sed '$s/,$//')"
	printf '{\n"data":[%s\n]}\n' "$JSON"
}

function PsuDiscovery {
	local OUT
	OUT="$(PsuDiscoveryOMSA)" && { [ "$SOURCE_ONLY" = "1" ] && echo "OMSA" || echo "$OUT"; SetSource "OMSA"; return; }
	OUT="$(PsuDiscoveryIPMI)" && { [ "$SOURCE_ONLY" = "1" ] && echo "ipmitool" || echo "$OUT"; SetSource "ipmitool"; return; }
	[ "$SOURCE_ONLY" = "1" ] && echo "none" || EmptyLLD
}

function PsuStatusOMSA {
	local PSU="$1"
	local VALUE
	VALUE="$(OMSARun chassis pwrsupplies | grep -A1 "^Index.*$PSU" | tail -1 | awk '{print $3}')"
	[ -n "$VALUE" ] || return 1
	NormalizeHealth "$VALUE"
}

function PsuStatusIPMI {
	local PSU="$1"
	local VALUE
	VALUE="$(IPMISensorOutput | awk -F'|' -v P="$PSU" '{name=$1; gsub(/^ *| *$/, "", name); if(name==P){gsub(/^ *| *$/, "", $4); print $4; exit}}')"
	[ -n "$VALUE" ] || return 1
	NormalizeHealth "$VALUE"
}

function PsuStatus {
	local VALUE
	VALUE="$(PsuStatusOMSA "$1")" && [ -n "$VALUE" ] && PrintValue "OMSA" "$VALUE" && return
	VALUE="$(PsuStatusIPMI "$1")" && [ -n "$VALUE" ] && PrintValue "ipmitool" "$VALUE" && return
	PrintValue "none" "Unknown"
}

function RAMDiscovery {
	local OUT RAMS RAM RESULT JSON
	OUT="$(OMSARun chassis memory)"
	RAMS="$(echo "$OUT" | grep "Index" | awk '{print $3}' | grep -Eo '[0-9]+')"
	if [ -n "$RAMS" ]; then
		for RAM in $RAMS; do
			RESULT+="$(printf '\n{\n\"{#RAM}\": \"%s\"\n},' "$(echo "$RAM" | JsonEscape)")"
		done
		JSON="$(echo "$RESULT" | sed '$s/,$//')"
		printf '{\n"data":[%s\n]}\n' "$JSON"
		return
	fi
	EmptyLLD
}

function RAMStatus {
	local RAM="$1"
	local OUT VALUE
	OUT="$(OMSARun chassis memory index="$RAM")" || true
	VALUE="$(echo "$OUT" | awk '/^Status/ {print $3; exit}')"
	[ -n "$VALUE" ] && PrintValue "OMSA" "$(NormalizeHealth "$VALUE")" && return
	PrintValue "none" "Unsupported"
}

function PowerDiscoveryOMSA {
	local OUT LINE INDEX PROBE RESULT JSON
	OUT="$(OMSARun chassis pwrmonitoring 2>/dev/null)" || return 1
	if echo "$OUT" | grep -q "Power Consumption Information is not available"; then
		return 1
	fi
	while IFS= read -r LINE; do
		case "$LINE" in
			Index*)
				INDEX="$(printf '%s\n' "$LINE" | cut -d':' -f2- | Trim)"
				;;
			"Probe Name"*)
				PROBE="$(printf '%s\n' "$LINE" | cut -d':' -f2- | Trim)"
				if [ -n "$INDEX" ] && [ -n "$PROBE" ]; then
					RESULT+="$(printf '\n{\n\"{#PWRINDEX}\": \"%s\",\n\"{#PWRNAME}\": \"%s\"\n},' "$(echo "$INDEX" | JsonEscape)" "$(echo "$PROBE" | JsonEscape)")"
					INDEX=""
					PROBE=""
				fi
				;;
		esac
	done <<< "$OUT"
	[ -n "$RESULT" ] || return 1
	JSON="$(echo "$RESULT" | sed '$s/,$//')"
	printf '{\n"data":[%s\n]}\n' "$JSON"
}

function PowerDiscoveryRedfish {
	local OUT RESULT JSON LINE NAME INDEX N
	OUT="$(RedfishPowerOutput)" || return 1
	N=0
	while IFS= read -r LINE; do
		printf '%s\n' "$LINE" | grep -q '"PowerConsumedWatts"' || continue
		NAME="$(JsonStringValueFromLine "$LINE" "Name" | Trim)"
		[ -n "$NAME" ] || NAME="Power Consumption $N"
		INDEX="redfish-pwr:$N"
		RESULT+="$(printf '\n{\n\"{#PWRINDEX}\": \"%s\",\n\"{#PWRNAME}\": \"%s\"\n},' "$(echo "$INDEX" | JsonEscape)" "$(echo "$NAME" | JsonEscape)")"
		N=$((N + 1))
	done <<< "$(printf '%s\n' "$OUT" | JsonObjectLines)"
	[ -n "$RESULT" ] || return 1
	JSON="$(echo "$RESULT" | sed '$s/,$//')"
	printf '{\n"data":[%s\n]}\n' "$JSON"
}

function PowerDiscovery {
	local OUT
	OUT="$(PowerDiscoveryOMSA)" && { [ "$SOURCE_ONLY" = "1" ] && echo "OMSA" || echo "$OUT"; SetSource "OMSA"; return; }
	OUT="$(PowerDiscoveryRedfish)" && { [ "$SOURCE_ONLY" = "1" ] && echo "Redfish" || echo "$OUT"; SetSource "Redfish"; return; }
	[ "$SOURCE_ONLY" = "1" ] && echo "none" || EmptyLLD
}

function PowerStatusOMSA {
	local INDEX="$1"
	local OUT VALUE
	OUT="$(OMSARun chassis pwrmonitoring 2>/dev/null)" || return 1
	VALUE="$(echo "$OUT" | awk -v IDX="$INDEX" '
		/^Index/ {cur_idx=$NF}
		/^Reading/ && $NF=="W" && cur_idx==IDX {print $(NF-1); exit}
	')"
	[ -n "$VALUE" ] || return 1
	printf '%s\n' "$VALUE"
}

function PowerStatusRedfish {
	local INDEX="$1"
	local OUT LINE VALUE TARGET_INDEX
	OUT="$(RedfishPowerOutput)" || return 1
	if echo "$INDEX" | grep -Eq '^redfish-pwr:[0-9]+$'; then
		TARGET_INDEX="${INDEX#redfish-pwr:}"
		LINE="$(printf '%s\n' "$OUT" | JsonObjectLines | awk -v IDX="$TARGET_INDEX" '
			/"PowerConsumedWatts"/ {
				if (n==IDX) {print; exit}
				n++
			}
		')"
	else
		LINE="$(printf '%s\n' "$OUT" | JsonObjectLines | awk -v T="$INDEX" '
			/"PowerConsumedWatts"/ {
				line=$0
				name=line
				gsub(/^.*"Name"[[:space:]]*:[[:space:]]*"/, "", name)
				gsub(/".*$/, "", name)
				if (name==T) {print line; exit}
			}
		')"
	fi
	[ -n "$LINE" ] || return 1
	VALUE="$(JsonNumberValueFromLine "$LINE" "PowerConsumedWatts")"
	[ -n "$VALUE" ] || return 1
	printf '%s\n' "$VALUE"
}

function PowerStatus {
	local INDEX="$1"
	local VALUE
	VALUE="$(PowerStatusOMSA "$INDEX")" && [ -n "$VALUE" ] && PrintValue "OMSA" "$VALUE" && return
	VALUE="$(PowerStatusRedfish "$INDEX")" && [ -n "$VALUE" ] && PrintValue "Redfish" "$VALUE" && return
	# 消費電力はNumeric型想定のため、取得不可時に文字列を返さないよう0を返します。
	PrintValue "none" "0"
}

function BmcInfo {
	local MODE="$1"
	local OUT VALUE
	OUT="$(OMSABmcOutput 2>/dev/null)" || true
	if [ -n "$OUT" ]; then
		case "$MODE" in
			device_type)
				VALUE="$(ExtractBmcLicenseOMSA "$OUT")"
				;;
			ipmi_version)
				VALUE="$(printf '%s
' "$OUT" | ExtractOmreportField "IPMI Version")"
				;;
			sessions_possible)
				VALUE="$(printf '%s
' "$OUT" | ExtractOmreportField "Number of Possible Active Sessions")"
				;;
			sessions_active)
				VALUE="$(printf '%s
' "$OUT" | ExtractOmreportField "Number of Current Active Sessions")"
				;;
			ipmi_over_lan)
				VALUE="$(printf '%s
' "$OUT" | ExtractOmreportField "Enable IPMI Over LAN")"
				;;
			sol_enabled)
				VALUE="$(printf '%s
' "$OUT" | ExtractOmreportField "SOL Enabled")"
				;;
			mac)
				VALUE="$(printf '%s
' "$OUT" | ExtractOmreportField "MAC Address")"
				;;
			ipv4)
				VALUE="$(printf '%s
' "$OUT" | ExtractBmcIPv4Field "IP Address")"
				;;
			ipv4_source)
				VALUE="$(printf '%s
' "$OUT" | ExtractBmcIPv4Field "IP Address Source")"
				;;
			ipv4_subnet)
				VALUE="$(printf '%s
' "$OUT" | ExtractBmcIPv4Field "IP Subnet")"
				;;
			ipv4_gateway)
				VALUE="$(printf '%s
' "$OUT" | ExtractBmcIPv4Field "IP Gateway")"
				;;
		esac
		[ -n "$VALUE" ] && PrintValue "OMSA" "$VALUE" && return
	fi

	case "$MODE" in
		device_type)
			VALUE="$(RedfishLicense)"
			[ -n "$VALUE" ] && PrintValue "Redfish" "$VALUE" && return
			VALUE="$(RacadmLicense)"
			[ -n "$VALUE" ] && PrintValue "racadm" "$VALUE" && return
			PrintValue "none" "Unsupported"
			;;
		ipmi_version)
			VALUE="$(IPMIRun mc info | awk -F':' '/IPMI Version/ {print $2; exit}' | Trim)"
			[ -n "$VALUE" ] && PrintValue "ipmitool" "$VALUE" || PrintValue "none" "Unknown"
			;;
		mac)
			VALUE="$(RedfishServiceRootValue ManagerMACAddress)"
			[ -n "$VALUE" ] && PrintValue "Redfish" "$VALUE" || PrintValue "none" "Unknown"
			;;
		*)
			PrintValue "none" "Unsupported"
			;;
	esac
}

function BatteriesDiscoveryOMSA {
	local OUT RESULT JSON CUR_INDEX PROBE IN_SECTION LINE
	OUT="$(OMSARun chassis batteries 2>/dev/null)" || return 1
	[ -n "$OUT" ] && echo "$OUT" | grep -q "^Batteries" || return 1
	echo "$OUT" | grep -q "^Individual Battery Elements" || return 1
	IN_SECTION=0
	while IFS= read -r LINE; do
		if echo "$LINE" | grep -q "^Individual Battery Elements"; then
			IN_SECTION=1
			continue
		fi
		[ "$IN_SECTION" -eq 1 ] || continue
		if echo "$LINE" | grep -q "^Index"; then
			CUR_INDEX="$(echo "$LINE" | awk '{print $3}')"
			continue
		fi
		if echo "$LINE" | grep -q "^Probe Name"; then
			PROBE="$(echo "$LINE" | cut -d':' -f2- | Trim)"
			RESULT+="$(printf '\n{\n\"{#BATTINDEX}\": \"%s\",\n\"{#BATTPROBE}\": \"%s\"\n},' "$(echo "$CUR_INDEX" | JsonEscape)" "$(echo "$PROBE" | JsonEscape)")"
		fi
	done <<< "$OUT"
	[ -n "$RESULT" ] || return 1
	JSON="$(echo "$RESULT" | sed '$s/,$//')"
	printf '{\n"data":[%s\n]}\n' "$JSON"
}

function BatteriesDiscoveryPerccli {
	local CONTROLLER OUT RESULT JSON
	for CONTROLLER in $(PerccliControllers); do
		OUT="$(PerccliRun /c"$CONTROLLER"/bbu show all)" || true
		if echo "$OUT" | grep -q "Status = Success"; then
			RESULT+="$(printf '\n{\n\"{#BATTINDEX}\": \"c%s-bbu\",\n\"{#BATTPROBE}\": \"PERC BBU c%s\"\n},' "$CONTROLLER" "$CONTROLLER")"
			continue
		fi
		OUT="$(PerccliRun /c"$CONTROLLER"/cv show all)" || true
		if echo "$OUT" | grep -q "Status = Success"; then
			RESULT+="$(printf '\n{\n\"{#BATTINDEX}\": \"c%s-cv\",\n\"{#BATTPROBE}\": \"PERC CacheVault c%s\"\n},' "$CONTROLLER" "$CONTROLLER")"
		fi
	done
	[ -n "$RESULT" ] || return 1
	JSON="$(echo "$RESULT" | sed '$s/,$//')"
	printf '{\n"data":[%s\n]}\n' "$JSON"
}

function BatteriesDiscovery {
	local OUT
	OUT="$(BatteriesDiscoveryOMSA)" && { [ "$SOURCE_ONLY" = "1" ] && echo "OMSA" || echo "$OUT"; SetSource "OMSA"; return; }
	OUT="$(BatteriesDiscoveryPerccli)" && { [ "$SOURCE_ONLY" = "1" ] && echo "perccli" || echo "$OUT"; SetSource "perccli"; return; }
	[ "$SOURCE_ONLY" = "1" ] && echo "none" || EmptyLLD
}

function BatteriesStatusOMSA {
	local INDEX="$1"
	local FIELD="$2"
	local OUT VALUE CUR LINE
	OUT="$(OMSARun chassis batteries 2>/dev/null)" || return 1
	[ -n "$OUT" ] && echo "$OUT" | grep -q "^Batteries" || return 1
	if [ "$FIELD" = "health" ]; then
		VALUE="$(echo "$OUT" | awk -F':' '/^Health/ {gsub(/^ *| *$/, "", $2); print $2; exit}')"
		[ -n "$VALUE" ] && echo "$VALUE" && return 0
	fi
	while IFS= read -r LINE; do
		if echo "$LINE" | grep -q "^Index"; then
			CUR="$(echo "$LINE" | awk '{print $3}')"
			continue
		fi
		[ "$CUR" = "$INDEX" ] || continue
		case "$FIELD" in
			status)
				echo "$LINE" | grep -q "^Status[[:space:]]*:" && echo "$LINE" | awk -F':' '{gsub(/^ *| *$/, "", $2); print $2; exit}' && return 0
				;;
			reading)
				echo "$LINE" | grep -q "^Reading[[:space:]]*:" && echo "$LINE" | awk -F':' '{gsub(/^ *| *$/, "", $2); print $2; exit}' && return 0
				;;
			probe)
				echo "$LINE" | grep -q "^Probe Name[[:space:]]*:" && echo "$LINE" | awk -F':' '{gsub(/^ *| *$/, "", $2); print $2; exit}' && return 0
				;;
		esac
	done <<< "$OUT"
	return 1
}

function BatteriesStatusPerccli {
	local INDEX="$1"
	local FIELD="$2"
	local CONTROLLER TYPE OUT VALUE
	if echo "$INDEX" | grep -q '^c[0-9][0-9]*-bbu$'; then
		CONTROLLER="${INDEX#c}"
		CONTROLLER="${CONTROLLER%-bbu}"
		TYPE="bbu"
	elif echo "$INDEX" | grep -q '^c[0-9][0-9]*-cv$'; then
		CONTROLLER="${INDEX#c}"
		CONTROLLER="${CONTROLLER%-cv}"
		TYPE="cv"
	elif [ "$INDEX" = "0" ]; then
		CONTROLLER="0"
		TYPE="bbu"
	else
		return 1
	fi
	OUT="$(PerccliRun /c"$CONTROLLER"/"$TYPE" show all)" || return 1
	echo "$OUT" | grep -q "Status = Success" || return 1
	case "$FIELD" in
		health|status)
			VALUE="$(echo "$OUT" | awk -F' ' '/Battery State/ {print $3; exit}')"
			[ -n "$VALUE" ] || VALUE="$(echo "$OUT" | awk -F':' '/Status/ {print $2; exit}' | Trim)"
			NormalizeHealth "$VALUE"
			;;
		reading)
			VALUE="$(echo "$OUT" | awk -F' ' '/Battery State/ {print $3; exit}')"
			[ -n "$VALUE" ] && echo "$VALUE" || echo "Unknown"
			;;
		probe)
			echo "PERC ${TYPE^^} c${CONTROLLER}"
			;;
		*)
			return 1
			;;
	esac
}

function BatteriesStatus {
	local VALUE
	VALUE="$(BatteriesStatusOMSA "$1" "$2")" && [ -n "$VALUE" ] && { case "$2" in health|status) VALUE="$(NormalizeHealth "$VALUE")" ;; esac; PrintValue "OMSA" "$VALUE"; return; }
	VALUE="$(BatteriesStatusPerccli "$1" "$2")" && [ -n "$VALUE" ] && PrintValue "perccli" "$VALUE" && return
	PrintValue "none" "Unsupported"
}

function CmosBatteryStatus {
	local OUT VALUE
	OUT="$(OMSARun chassis batteries 2>/dev/null)" || true
	VALUE="$(echo "$OUT" | awk '
		/^Index/ {idx=$3}
		/^Probe Name[[:space:]]*:[[:space:]]*System Board CMOS Battery/ {target=idx}
		/^Reading/ && target==idx {print $3; exit}
	')"
	[ -n "$VALUE" ] && PrintValue "OMSA" "$VALUE" && return
	PrintValue "none" "Unsupported"
}


function DetectOSFamily {
	local ID_LIKE_SAFE="" ID_SAFE=""
	if [ -r /etc/os-release ]; then
		. /etc/os-release
		ID_SAFE="${ID:-}"
		ID_LIKE_SAFE="${ID_LIKE:-}"
	fi
	case "$ID_SAFE" in
		ubuntu|debian)
			echo "debian"
			return 0
			;;
		centos|rhel|almalinux|rocky|fedora|ol)
			echo "rhel"
			return 0
			;;
	esac
	case "$ID_LIKE_SAFE" in
		*debian*)
			echo "debian"
			return 0
			;;
		*rhel*|*fedora*)
			echo "rhel"
			return 0
			;;
	esac
	if IsCommand apt; then
		echo "debian"
		return 0
	fi
	if IsCommand dnf || IsCommand yum; then
		echo "rhel"
		return 0
	fi
	return 1
}

function DetectPackageTool {
	local FAMILY ID_SAFE="" VERSION_ID_SAFE="" MAJOR=""
	FAMILY="${1:-$(DetectOSFamily 2>/dev/null)}"
	if [ -r /etc/os-release ]; then
		. /etc/os-release
		ID_SAFE="${ID:-}"
		VERSION_ID_SAFE="${VERSION_ID:-}"
	fi
	case "$FAMILY" in
		debian)
			echo "apt"
			return 0
			;;
		rhel)
			MAJOR="${VERSION_ID_SAFE%%.*}"
			if [ "$ID_SAFE" = "centos" ] && [ "$MAJOR" = "7" ] && IsCommand yum; then
				echo "yum"
				return 0
			fi
			if IsCommand dnf; then
				echo "dnf"
				return 0
			fi
			if IsCommand yum; then
				echo "yum"
				return 0
			fi
			;;
	esac
	return 1
}

function PrintInstallCommands {
	local FAMILY TOOL
	FAMILY="$(DetectOSFamily)" || { echo "	OSを判定できませんでした。Ubuntu/Debian系、CentOS7、AlmaLinux/RHEL/Rocky 8以降等で実行してください。"; return 1; }
	TOOL="$(DetectPackageTool "$FAMILY")" || { echo "	パッケージ管理コマンドを判定できませんでした。"; return 1; }
	case "$TOOL" in
		apt)
			cat <<'EOF'
	apt update
	apt -y install dmidecode ipmitool openipmi curl
	systemctl enable --now openipmi
	modprobe ipmi_msghandler
	modprobe ipmi_devintf
	modprobe ipmi_si
EOF
			;;
		yum)
			cat <<'EOF'
	yum -y install dmidecode ipmitool OpenIPMI curl
	systemctl enable --now ipmi
	modprobe ipmi_msghandler
	modprobe ipmi_devintf
	modprobe ipmi_si
EOF
			;;
		dnf)
			cat <<'EOF'
	dnf -y install dmidecode ipmitool OpenIPMI curl
	systemctl enable --now ipmi
	modprobe ipmi_msghandler
	modprobe ipmi_devintf
	modprobe ipmi_si
EOF
			;;
	esac
}

function InstallPackages {
	local FAMILY TOOL
	if [ "${EUID:-$(id -u)}" -ne 0 ]; then
		echo "パッケージをインストールするため、rootユーザーで実行してください。" >&2
		return 1
	fi
	FAMILY="$(DetectOSFamily)" || { echo "OSを判定できませんでした。Ubuntu/Debian系、CentOS7、AlmaLinux/RHEL/Rocky 8以降等で実行してください。" >&2; return 1; }
	TOOL="$(DetectPackageTool "$FAMILY")" || { echo "パッケージ管理コマンドを判定できませんでした。" >&2; return 1; }
	case "$TOOL" in
		apt)
			apt update
			apt -y install dmidecode ipmitool openipmi curl
			systemctl enable --now openipmi || true
			;;
		yum)
			yum -y install dmidecode ipmitool OpenIPMI curl
			systemctl enable --now ipmi || systemctl enable --now openipmi || true
			;;
		dnf)
			dnf -y install dmidecode ipmitool OpenIPMI curl
			systemctl enable --now ipmi || systemctl enable --now openipmi || true
			;;
	esac
	modprobe ipmi_msghandler || true
	modprobe ipmi_devintf || true
	modprobe ipmi_si || true
	echo "必要パッケージのインストール処理が完了しました。perccliはDell配布ファイルから別途導入してください。"
}

function CurlConfigEscape {
	sed 's/\\/\\\\/g;s/"/\\"/g'
}

function CreateRedfishConfig {
	local CONF DIR DEFAULT_BASE INPUT_BASE USERNAME PASSWORD ESC_USER ESC_PASS ANSWER OWNER_ARGS
	CONF="$REDFISH_CONFIG"
	DIR="$(dirname "$CONF")"
	LoadRedfishBaseFromConfig
	DEFAULT_BASE="$REDFISH_BASE"

	if [ -f "$CONF" ]; then
		printf '既に%sが存在します。\n上書きしますか？ [y/N]: ' "$CONF" >&2
		read -r ANSWER
		case "$ANSWER" in
			y|Y|yes|YES)
				;;
			*)
				echo "作成を中止しました。"
				return 1
				;;
		esac
	fi

	printf 'Redfish接続先 [%s]: ' "$DEFAULT_BASE" >&2
	read -r INPUT_BASE
	[ -n "$INPUT_BASE" ] && REDFISH_BASE="$INPUT_BASE"

	printf 'Redfishユーザー名: ' >&2
	read -r USERNAME
	printf 'Redfishパスワード: ' >&2
	read -rs PASSWORD
	printf '
' >&2

	if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
		echo "ユーザー名またはパスワードが空のため作成を中止しました。" >&2
		return 1
	fi

	ESC_USER="$(printf '%s' "$USERNAME" | CurlConfigEscape)"
	ESC_PASS="$(printf '%s' "$PASSWORD" | CurlConfigEscape)"

	if [ "${EUID:-$(id -u)}" -eq 0 ] && id zabbix >/dev/null 2>&1; then
		install -o zabbix -g zabbix -m 700 -d "$DIR"
		OWNER_ARGS="zabbix:zabbix"
	else
		mkdir -p "$DIR"
		chmod 700 "$DIR"
		OWNER_ARGS=""
	fi

	cat > "$CONF" <<EOF
# REDFISH_BASE="${REDFISH_BASE}"
# 上記の接続先はこのスクリプトが読み込みます。
# curl自体はURLをコマンド引数から受け取ります。
insecure
silent
show-error
connect-timeout = 12
max-time = 12
user = "${ESC_USER}:${ESC_PASS}"
EOF
	chmod 600 "$CONF"
	[ -n "$OWNER_ARGS" ] && chown "$OWNER_ARGS" "$CONF"
	echo "Redfish設定ファイルを作成しました: $CONF"
	echo "接続先は環境変数REDFISH_BASEで変更できます。"
	echo "現在の想定接続先: $REDFISH_BASE"
}

function TestOMSA {
	if OMSAUsable; then
		echo "OMSA: OK"
	else
		echo "OMSA: Unsupported"
	fi
}

function TestDmidecode {
	IsCommand dmidecode && echo "dmidecode: OK" || echo "dmidecode: Unsupported"
}

function TestLocal {
	TestDmidecode
	if IPMIRun mc info >/dev/null 2>&1; then
		echo "ipmitool -I open: OK"
	else
		echo "ipmitool -I open: Unsupported"
	fi
	TestPerccli
}

function TestIPMI {
	if IPMIRun mc info >/dev/null 2>&1; then
		echo "ipmitool -I open: OK"
	else
		echo "ipmitool -I open: Unsupported"
	fi
}

function TestPerccli {
	local BIN
	BIN="$(FindPerccli)" || { echo "perccli: Unsupported"; return; }
	if PerccliRun show >/dev/null 2>&1; then
		echo "perccli: OK ($BIN)"
	else
		echo "perccli: Failed ($BIN)"
	fi
}

function TestRedfish {
	if ! RedfishAvailable; then
		echo "Redfish: Unsupported"
		return
	fi
	if RedfishGet /redfish/v1/ >/dev/null 2>&1; then
		echo "Redfish: OK"
	else
		echo "Redfish: Failed"
	fi
}

function BackendStatus {
	TestOMSA
	TestDmidecode
	TestIPMI
	TestPerccli
	TestRedfish
}

function JoinArgs {
	local OUT=""
	while [ "$#" -gt 0 ]; do
		if [ -z "$OUT" ]; then
			OUT="$1"
		else
			OUT="$OUT $1"
		fi
		shift
	done
	printf '%s' "$OUT"
}

function DispatchFanStatus {
	local COUNT ITEM FAN_PARTS FAN
	COUNT="$#"
	[ "$COUNT" -ge 2 ] || { PrintValue "none" "Unknown"; return; }
	ITEM="${!COUNT}"
	FAN_PARTS=$((COUNT - 1))
	FAN="$(JoinArgs "${@:1:$FAN_PARTS}")"
	FanStatus "$FAN" "$ITEM"
}

function DispatchTempStatus {
	local TEMP
	TEMP="$(JoinArgs "$@")"
	TempStatus "$TEMP"
}

function DispatchPsuStatus {
	local PSU
	PSU="$(JoinArgs "$@")"
	PsuStatus "$PSU"
}

function HandleArgs {
	case "$1" in
		--help|-h)
			PrintHelp
			;;
		--backend-status)
			BackendStatus
			;;
		--test-omsa)
			TestOMSA
			;;
		--test-local)
			TestLocal
			;;
		--test-ipmi)
			TestIPMI
			;;
		--test-perccli)
			TestPerccli
			;;
		--test-redfish)
			TestRedfish
			;;
		--install-packages)
			InstallPackages
			;;
		--create-redfish-conf)
			CreateRedfishConfig
			;;
		--debug)
			DEBUG="1"
			shift
			HandleArgs "$@"
			;;
		--source)
			SOURCE_ONLY="1"
			shift
			HandleArgs "$@"
			;;
		pddiscovery)
			PhysicalDisksDiscovery
			;;
		pdstatus)
			PhysicalDiskStatus "$2" "$3" "$4"
			;;
		vddiscovery)
			VirtualDiskDiscovery
			;;
		vdstatus)
			VirtualDiskStatus "$2" "$3" "$4"
			;;
		fandiscovery)
			FanDiscovery
			;;
		fanstatus)
			shift
			DispatchFanStatus "$@"
			;;
		psudiscovery)
			PsuDiscovery
			;;
		psustatus)
			shift
			DispatchPsuStatus "$@"
			;;
		ramdiscovery)
			RAMDiscovery
			;;
		ramstatus)
			RAMStatus "$2"
			;;
		tempdiscovery)
			TempDiscovery
			;;
		tempstatus)
			shift
			DispatchTempStatus "$@"
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
			PowerStatus "$2"
			;;
		bmc)
			BmcInfo "$2"
			;;
		cmos)
			CmosBatteryStatus
			;;
		battdiscovery)
			BatteriesDiscovery
			;;
		battstatus)
			BatteriesStatus "$2" "$3"
			;;
		*)
			PrintHelp
			exit 1
			;;
	esac
}

HandleArgs "$@"
