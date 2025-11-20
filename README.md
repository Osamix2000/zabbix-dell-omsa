# Dell OMSA Zabbix 監視

このリポジトリには、Linux上でOMSAを実行しているDellサーバーのさまざまなコンポーネントや情報を監視するためのスクリプト・設定・Zabbixテンプレートが含まれています。

テスト済みバージョン:  
OMSA: 8.1.0  
Zabbix: 7.0.21

#### OMSA とは

Dell OpenManage Server Administrator (OMSA) は、サーバーの物理コンポーネントの状態取得や設定を行えるツールです。

https://www.dell.com/support/article/yu/en/yudhs1/sln312492/openmanage-server-administrator-omsa?lang=en

#### Zabbix とは

Zabbix はオープンソースの監視ソリューションです。

https://www.zabbix.com/

#### 本リポジトリについて

このリポジトリ内のスクリプトとテンプレートは、サーバーの最も重要なコンポーネントや情報を監視します。  
OMSAが提供する全ての細かい情報を網羅するものではありません。  
以下は取得可能な情報の一覧です。

### 自動検出される項目 (Discovery)

- 仮想ディスクとそのコントローラ
- 物理ディスクとそのコントローラ
- ファン (インデックス番号付き)
- 電源ユニット PSU (インデックス番号付き)
- 温度センサー
- RAMモジュール (インデックス番号付き)

### 監視される項目とトリガー

- 物理ディスクの状態  
  `Trigger: physical disk not online or predictive failure is true`
- 仮想ディスクのRAID種類/サイズ、ステータス  
  `Trigger: virtual disk status is not ok`
- ファンの状態・RPM  
  `Trigger: fan status not ok`
- PSUの状態  
  `Trigger: PSU status not ok`
- 温度センサーの値
- RAMモジュールの状態  
  `Trigger: RAM status not ok`
- サーバーモデル
- サーバーのサービスタグ
- BIOSバージョン
- iDRACバージョン
- サーバー全体のヘルスステータス  
  `Trigger: if any of the status indicators is not ok`

#### インストール方法

1. まずDell OMSAをインストールします  
   手順: http://linux.dell.com/repo/hardware/omsa.html

2. このリポジトリをZabbix Agentのパスにクローンします
```
git clone https://github.com/ronivay/zabbix-dell-omsa /etc/zabbix/dell-omsa
```

3. Zabbix Agent の設定を編集し以下を追加します
```
Include=/etc/zabbix/dell-omsa/omsa.conf
```

4. Zabbix Agent を再起動

5. zabbix ユーザーが omsa.sh をsudo無しで実行できるよう権限追加
```
visudo

以下を追加:
zabbix ALL=(ALL)  NOPASSWD: /etc/zabbix/dell-omsa/omsa.sh
```

6. テンプレートxmlをZabbix Serverにインポートしてテンプレートを割り当てる。

#### Tips

`omsa.sh` 内の `OMSABIN` 変数はデフォルトで `/opt/dell/srvadmin/bin/omreport` を指しています。  
環境によってOMSAが別ディレクトリにインストールされている場合は、この変数を変更してください。
