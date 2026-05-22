# 🖥️ Dell OMSA互換 Zabbix監視

フォーク元: https://github.com/ronivay/zabbix-dell-omsa

このリポジトリには、Dellサーバーのハードウェア情報をZabbixで監視する為のスクリプト、Zabbix Agent設定、Zabbixテンプレートが含まれています。<br>
既存の`omsa.*`キーとの互換性を維持しつつ、OMSAが使える環境ではOMSAを最優先で使用します。<br>
OMSAが無い環境やOMSAで取得できない項目は、`dmidecode`、`ipmitool -I open`、`perccli`、Redfish、`racadm`等で取得を試みます。

更新日: 2026年5月22日(金)

---

## 📚 目次

- [🧭 現在の方針](#policy)
- [✅ テスト済みバージョン](#tested-version)
- [🧩 OMSAとは](#what-is-omsa)
- [📊 Zabbixとは](#what-is-zabbix)
- [📦 本リポジトリについて](#about-repository)
- [🔁 取得優先順位](#backend-priority)
- [🧱 取得元ごとの役割](#backend-role)
- [🔎 自動検出される項目](#discovery)
- [🚨 監視される主な項目とトリガー](#items-and-triggers)
- [🔐 iDRACライセンスについて](#idrac-license)
- [🏷️ 状態値の扱い](#status-values)
- [🔢 数値アイテムの取得不可時の値](#numeric-fallback)
- [🛠️ インストール方法](#install)
- [📥 必要パッケージ](#packages)
- [💽 perccliについて](#perccli)
- [🌐 Redfishについて](#redfish)
- [🧪 手動確認](#manual-check)
- [🧾 主な手動取得例](#manual-examples)
- [⚙️ 主な環境変数](#environment-variables)
- [🗄️ IPMIキャッシュについて](#ipmi-cache)
- [⚠️ 注意点](#notes)
- [💡 Tips](#tips)

---

<a id="policy"></a>

## 🧭 現在の方針

既存のOMSA監視環境は、これまで通りOMSAを使って監視します。<br>
新規構築サーバーやUbuntu 26.04以降等、OMSAの導入や動作が難しい環境では、OMSAに依存しない監視もできるようにしています。<br>
基本方針は以下です。

1. OMSAで取得できる場合は、OMSAの値を最優先します。
2. OMSAが未導入、失敗、非対応、対象項目が空の場合のみ別手段へフォールバックします。
3. OMSAが`Critical`、`Failed`、`Degraded`等の異常値を返した場合は、その値を採用します。
4. 取得できない項目は`Unknown`または`Unsupported`として扱います。
5. Zabbix側の既存テンプレートや`omsa.*`キーはできるだけ維持します。

<a id="tested-version"></a>

## ✅ テスト済みバージョン

現時点で確認している主なバージョンです。

| 種別 | バージョン |
|---|---|
| スクリプト | 2.0.0 |
| OMSA | 11.0.0.0 |
| Zabbix | 7.0.26 |
| perccli | 007.1020.0000.0000 |

<a id="what-is-omsa"></a>

## 🧩 OMSAとは

Dell OpenManage Server Administrator (OMSA) は、Dellサーバーの物理コンポーネントの状態取得や設定を行えるツールです。

https://www.dell.com/support/article/yu/en/yudhs1/sln312492/openmanage-server-administrator-omsa?lang=en

<a id="what-is-zabbix"></a>

## 📊 Zabbixとは

Zabbixはオープンソースの監視ソリューションです。

https://www.zabbix.com/

<a id="about-repository"></a>

## 📦 本リポジトリについて

このリポジトリ内のスクリプトとテンプレートは、Dellサーバーの主要なハードウェア情報を監視することを目的としています。<br>
OMSA、iDRAC、Redfish、perccli等が提供する全ての細かい情報を網羅するものではありません。

<a id="backend-priority"></a>

## 🔁 取得優先順位

スクリプトは、原則として以下の順番で情報取得を試みます。

1. OMSA `omreport`
2. ローカルコマンド
	- `dmidecode`
	- `ipmitool -I open`
	- `perccli`
3. Redfish
4. `racadm`

ただし、項目によって最適な取得元が異なる為、実際の処理では項目ごとに取得元を切り替えます。<br>
OMSAで取得できた値は、基本的にそのまま採用します。<br>
OMSAで取得できなかった項目だけ、OMSA以外の方法で取得を試みます。

<a id="backend-role"></a>

## 🧱 取得元ごとの役割

| 取得元 | 主な用途 |
|---|---|
| OMSA | 既存OMSA監視環境での最優先取得元 |
| dmidecode | モデル、サービスタグ、BIOSバージョン |
| ipmitool -I open | BMC/iDRAC基本情報、温度、ファン、PSU系センサー |
| perccli | PERC、RAID、物理ディスク、仮想ディスク、BBU/CV |
| Redfish | 全体ヘルス、iDRAC FW、温度、ファン、ログ、iDRAC9/10ライセンス補助 |
| racadm | iDRACライセンス等の補助取得 |

<a id="discovery"></a>

## 🔎 自動検出される項目 (Discovery)

- 仮想ディスクとそのコントローラー
- 物理ディスクとそのコントローラー
- ファン
- 電源ユニット PSU
- 温度センサー
- RAMモジュール
- CMOSバッテリー
- BBU/CV

<a id="items-and-triggers"></a>

## 🚨 監視される主な項目とトリガー

- 物理ディスクの状態
	- `Trigger: physical disk not online or predictive failure is true`
- 仮想ディスクのRAID種類、サイズ、ステータス
	- `Trigger: virtual disk status is not ok`
- ファンの状態、RPM
	- `Trigger: fan status not ok`
- PSUの状態
	- `Trigger: PSU status not ok`
- 温度センサーの値
- RAMモジュールの状態
	- `Trigger: RAM status not ok`
- サーバーモデル
- サーバーのサービスタグ
- BIOSバージョン
- iDRACバージョン
- iDRAC IPv4アドレス
- iDRACライセンス
- サーバー全体のヘルスステータス
	- `Trigger: if any of the status indicators is not ok`

<a id="idrac-license"></a>

## 🔐 iDRACライセンスについて

iDRACライセンスは、取得できる環境と取得できない環境があります。
取得優先順位は以下です。

1. OMSA
2. iDRAC9/10 Redfish `DellLicenseCollection`
3. `racadm license view`
4. `Unsupported`

OMSAで`Baseboard Management Controller`等の値が取得できた場合は、OMSAの値としてそのまま出力します。<br>
OMSAで取得できなかった後に、Redfishや`racadm`等の非OMSA取得元で`BMC`や`Baseboard`系の値しか判断できない場合は、ライセンス種別ではない為`Unsupported`を返します。<br>
iDRAC8以下では、Redfishでライセンス種別を取得できない前提です。

<a id="status-values"></a>

## 🏷️ 状態値の扱い

状態値は、可能な範囲で以下のように正規化します。

- `OK`
- `Warning`
- `Critical`
- `Unknown`
- `Unsupported`
- `Timeout`
- `AuthFailed`

`Unsupported`は、非対応や未導入を示す値です。<br>
原則として、障害扱いにしない想定です。<br>
`Unknown`、`Timeout`、`AuthFailed`は、環境や項目によって監視上の注意対象にするか検討してください。

<a id="numeric-fallback"></a>

## 🔢 数値アイテムの取得不可時の値

Zabbixの数値型アイテムに文字列を返すと型エラーになります。<br>
その為、取得不可時は以下のように返します。

| 項目 | 返却値 |
|---|---:|
| 温度 | `-273` |
| ファンRPM | `0` |

温度の取得不可時の値は、環境変数`TEMP_UNSUPPORTED_VALUE`で変更できます。

```shell
TEMP_UNSUPPORTED_VALUE=-999 /home/zabbix/.sh/omsa.sh tempstatus Inlet Temp
```

<a id="install"></a>

## 🛠️ インストール方法

### 1. リポジトリをクローン

```shell
mkdir -p /home/zabbix/github
cd /home/zabbix/github
git clone https://github.com/Osamix2000/zabbix-dell-omsa.git
```

XMLファイルをZabbix Serverへインポートする為、作業しているPCにもクローンしておくと便利です。

### 2. クローンしたフォルダへ移動

```shell
cd zabbix-dell-omsa
```

### 3. スクリプトとZabbix Agent設定を配置

既存の`/home/zabbix/.sh/omsa.sh`がある場合は、先にバックアップしてください。

```shell
mkdir -p /home/zabbix/.sh
cp -a /home/zabbix/.sh/omsa.sh /home/zabbix/.sh/omsa.sh.bak.$(date +%Y%m%d%H%M%S)
```

新規配置または置き換えます。

```shell
ln -s /home/zabbix/github/zabbix-dell-omsa/omsa.sh /home/zabbix/.sh/omsa.sh
ln -s /home/zabbix/github/zabbix-dell-omsa/omsa.conf /etc/zabbix/zabbix_agentd.d/omsa.conf
```

既にファイルが存在している場合は、必要に応じて`ln -sfn`で貼り直してください。

### 4. 権限を設定

```shell
chown -R zabbix:zabbix /home/zabbix
chmod 700 /home/zabbix/github/zabbix-dell-omsa/omsa.sh
```

### 5. Zabbixユーザーの実行権限を追加

`visudo`で以下を追加します。

```text
zabbix ALL=(ALL)  NOPASSWD: /home/zabbix/.sh/omsa.sh
zabbix ALL=(ALL)  NOPASSWD: /home/zabbix/github/zabbix-dell-omsa/omsa.sh
```

### 6. Zabbix AgentのTimeoutを確認

OMSA以外の取得では、`ipmitool`や`perccli`が少し時間を使う可能性があります。<br>
Zabbix Agent側の`Timeout`は`12`秒程度を推奨します。

Zabbix Agentの場合です。

```shell
vim /etc/zabbix/zabbix_agentd.conf
```

```text
Timeout=12
```

Zabbix Agent2の場合です。

```shell
vim /etc/zabbix/zabbix_agent2.conf
```

```text
Timeout=12
```

### 7. Zabbix Agentを再起動

Zabbix Agentの場合です。

```shell
systemctl restart zabbix-agent
```

Zabbix Agent2の場合です。

```shell
systemctl restart zabbix-agent2
```

### 8. テンプレートをインポート

`dell-omsa-template-ja.xml`をZabbix Serverにインポートして、対象ホストにテンプレートを割り当てます。

<a id="packages"></a>

## 📥 必要パッケージ

OMSAのみで監視する場合は、OMSAが正常に動いていれば最低限の監視は可能です。<br>
OMSAなし環境、またはOMSAで取得できない項目を補助取得する場合は、以下を導入します。

### スクリプトからインストールする場合

```shell
/home/zabbix/.sh/omsa.sh --install-packages
```

このオプションはOSを判定し、必要パッケージのインストールとIPMI関連サービスの有効化を行います。<br>
`perccli`はDell配布ファイルから導入する必要がある為、自動インストール対象には含めていません。

### CentOS7系

```shell
yum -y install dmidecode ipmitool OpenIPMI curl
systemctl enable --now ipmi
modprobe ipmi_msghandler
modprobe ipmi_devintf
modprobe ipmi_si
```

### AlmaLinux/RHEL/Rocky 8以降等dnf系Red Hat系

```shell
dnf -y install dmidecode ipmitool OpenIPMI curl
systemctl enable --now ipmi
modprobe ipmi_msghandler
modprobe ipmi_devintf
modprobe ipmi_si
```

### Ubuntu/Debian系

```shell
apt update
apt -y install dmidecode ipmitool openipmi curl
systemctl enable --now openipmi
modprobe ipmi_msghandler
modprobe ipmi_devintf
modprobe ipmi_si
```

<a id="perccli"></a>

## 💽 perccliについて

`perccli`は標準リポジトリではなく、Dell配布のdeb/RPM/tar.gzから導入します。<br>
Dell PERC環境では、RAID、物理ディスク、仮想ディスク、BBU/CV監視の主な取得元になります。<br>
代表的な確認コマンドです。

```shell
/opt/MegaRAID/perccli/perccli64 show
```

```shell
/opt/MegaRAID/perccli/perccli64 /c0/vall show
```

```shell
/opt/MegaRAID/perccli/perccli64 /c0/eall/sall show
```

スクリプトは主に以下のパスを自動検出します。

```text
/opt/MegaRAID/perccli/perccli64
/opt/MegaRAID/perccli/perccli
/opt/MegaRAID/storcli/storcli64
/opt/MegaRAID/storcli/storcli
```

<a id="redfish"></a>

## 🌐 Redfishについて

Redfishは必須ではありません。<br>
使える環境だけ補助的に利用します。<br>
Redfishを使う場合は、以下の設定ファイルを作成します。

```text
/home/zabbix/.config/dell-redfish.conf
```

### Redfish設定ファイルをスクリプトから作成

```shell
/home/zabbix/.sh/omsa.sh --create-redfish-conf
```

作成される内容の例です。

```text
# REDFISH_BASE="https://169.254.0.1"
# 上記の接続先はこのスクリプトが読み込みます。
# curl自体はURLをコマンド引数から受け取ります。
insecure
silent
show-error
connect-timeout = 12
max-time = 12
user = "zabbix-redfish:example-password"
```

Redfish接続先は、設定ファイル内の`# REDFISH_BASE="..."`に保存されます。<br>
環境変数`REDFISH_BASE`を指定した場合は、環境変数側が優先されます。

### Redfish設定ファイルを手動作成する場合

```shell
install -o zabbix -g zabbix -m 700 -d /home/zabbix/.config
```

```shell
vim /home/zabbix/.config/dell-redfish.conf
```

```text
# REDFISH_BASE="https://169.254.0.1"
insecure
silent
show-error
connect-timeout = 12
max-time = 12
user = "zabbix-redfish:example-password"
```

```shell
chown zabbix:zabbix /home/zabbix/.config/dell-redfish.conf
chmod 600 /home/zabbix/.config/dell-redfish.conf
```

<a id="manual-check"></a>

## 🧪 手動確認

導入後は、まず手動で状態確認してください。

```shell
/home/zabbix/.sh/omsa.sh --help
```

```shell
/home/zabbix/.sh/omsa.sh --backend-status
```

```shell
/home/zabbix/.sh/omsa.sh --test-omsa
```

```shell
/home/zabbix/.sh/omsa.sh --test-local
```

```shell
/home/zabbix/.sh/omsa.sh --test-ipmi
```

```shell
/home/zabbix/.sh/omsa.sh --test-perccli
```

```shell
/home/zabbix/.sh/omsa.sh --test-redfish
```

取得元を確認したい場合です。

```shell
/home/zabbix/.sh/omsa.sh --source model
```

デバッグ出力を出したい場合です。

```shell
/home/zabbix/.sh/omsa.sh --debug model
```

<a id="manual-examples"></a>

## 🧾 主な手動取得例

```shell
/home/zabbix/.sh/omsa.sh model
```

```shell
/home/zabbix/.sh/omsa.sh stag
```

```shell
/home/zabbix/.sh/omsa.sh bios
```

```shell
/home/zabbix/.sh/omsa.sh idrac
```

```shell
/home/zabbix/.sh/omsa.sh status
```

```shell
/home/zabbix/.sh/omsa.sh bmc ipv4
```

```shell
/home/zabbix/.sh/omsa.sh bmc device_type
```

```shell
/home/zabbix/.sh/omsa.sh tempdiscovery
```

```shell
/home/zabbix/.sh/omsa.sh fandiscovery
```

```shell
/home/zabbix/.sh/omsa.sh vddiscovery
```

```shell
/home/zabbix/.sh/omsa.sh pddiscovery
```

<a id="environment-variables"></a>

## ⚙️ 主な環境変数

| 変数 | 既定値 | 用途 |
|---|---:|---|
| `COMMAND_TIMEOUT` | `12` | 共通の内部タイムアウト秒数 |
| `OMSA_TIMEOUT` | `12` | OMSAコマンドの内部タイムアウト秒数 |
| `IPMI_TIMEOUT` | `12` | ipmitoolの内部タイムアウト秒数 |
| `PERCCLI_TIMEOUT` | `12` | perccliの内部タイムアウト秒数 |
| `IPMI_CACHE_TTL` | `240` | IPMI sensor結果キャッシュの有効秒数 |
| `TEMP_UNSUPPORTED_VALUE` | `-273` | 温度取得不可時の返却値 |
| `SIZE_BASE` | `1024` | 仮想ディスクサイズ換算基準 |
| `REDFISH_BASE` | `https://169.254.0.1` | Redfish接続先 |
| `REDFISH_CONFIG` | `/home/zabbix/.config/dell-redfish.conf` | Redfish用curl設定ファイル |

<a id="ipmi-cache"></a>

## 🗄️ IPMIキャッシュについて

`ipmitool -I open sensor`はZabbixから同時実行されると重くなりやすい為、スクリプト側でキャッシュします。<br>
既定では`240`秒です。<br>
IPMIセンサーキャッシュは、実行ユーザーごとに分離されます。<br>
rootで手動確認したキャッシュが、Zabbix実行時に干渉しにくいようにしています。

<a id="notes"></a>

## ⚠️ 注意点

- まず検証サーバーで手動実行してください。
- 既存OMSAサーバーではOMSAが第1優先です。
- OMSAが異常値を返した場合は、その値を採用します。
- Redfishは取れる環境だけ補助的に使います。
- iDRAC8以下ではRedfishでライセンス取得できない前提です。
- iDRAC9/10では`DellLicenseCollection`を試します。
- iDRAC10はBasic認証だけを前提にしない方針ですが、現時点では実機未検証です。
- `Unsupported`は非対応や未導入を表す為、原則として障害扱いしない想定です。
- `Unknown`や`Timeout`は監視上の注意対象にするか検討してください。
- `perccli`の物理ディスクIDは`32:0`のような`EID:Slt`形式になる場合があります。
- OMSAの物理ディスクID`0:1:0`とは表記が異なる為、取得元を切り替える場合はZabbix上で別アイテムとして再検出される可能性があります。

<a id="tips"></a>

## 💡 Tips

OMSAの`omreport`パスは、既定で以下を想定しています。

```text
/opt/dell/srvadmin/bin/omreport
```

環境によってOMSAが別ディレクトリにインストールされている場合は、スクリプト内のOMSAパス設定を変更してください。
