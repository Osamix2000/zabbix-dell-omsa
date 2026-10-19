# ChangeLog

## 2.0.3 - 2026年10月19日(月)

2026年7月30日頃に実装したOMSA 11.0/11.1対応の改修と、その後の互換性修正・不具合修正を本バージョンにまとめています。

### OMSA 11.0 / 11.1の互換性向上

- OMSA 11.0.0.0と11.1.0.0の出力差に対応するため、ファン、温度、電力、PSU、RAM、物理ディスク、仮想ディスクの解析を、固定列ではなく可能な限り`項目名 : 値`に基づく方式へ変更しました。
- ファンRPMは`2380 RPM` / `2380RPM`、温度は`24.0 C` / `24.0C`、消費電力は`539 W` / `539W`の両形式から数値を抽出できるようにしました。
- 物理ディスクと仮想ディスクの状態、RAIDレイアウト、サイズ等の解析を改善しました。仮想ディスクサイズは`(xxxxx bytes)`がある場合はその数値を優先し、なければ単位付きサイズから換算します。
- BMC/iDRAC情報の取得では、`omreport chassis remoteaccess`と従来の`omreport chassis bmc`を利用可能な範囲で併用します。
- `--test-omsa`でOMSAバージョンを取得できる場合、結果に表示するようにしました。

### iDRACとOMSA実行パスの改善

- 環境変数`OMSABIN`による明示指定を最優先し、実行可能な`/usr/local/sbin/omreport`互換ラッパーがあれば使用します。存在しない場合は従来の`/opt/dell/srvadmin/bin/omreport`へフォールバックします。
- OMSA 11.1.0.0などで`chassis remoteaccess`と`chassis bmc`からiDRACのIPv4情報を取得できない場合、`omreport system summary`の`Remote Access Controller Information`節からIPv4アドレス、サブネット、ゲートウェイを補完します。
- 管理コントローラー以外のNICのIPアドレスを誤って取得しないよう解析対象を限定し、情報取得時の負荷を抑えるため短時間キャッシュを追加しました。

### 物理ディスク監視の不具合修正

- OMSAの物理ディスクID（例: `0:1:0`）に含まれるコロンが解析処理で失われ、Discoveryが重複したり、物理ディスク状態が`Unknown`になったりする不具合を修正しました。
- `ExtractOmreportField` / `ExtractOmreportFields`が項目名の区切り文字だけを除去し、値の内部にあるコロンを保持するようにしました。
- 従来のperccli形式の物理ディスクID（例: `32:0`）と、既存のZabbix監視キー・テンプレートは維持しています。

### テスト・検証

- OMSA 11.0.0.0および11.1.0.0の実機環境で、OMSA認識、物理ディスクDiscovery、代表的な物理ディスク状態・予測故障取得を確認しました。
- OMSA 11.0.0.0の環境では仮想ディスク・ファンのDiscovery、11.1.0.0の環境ではiDRAC管理IPv4の取得を確認しました。
- ファン・温度・電力・仮想ディスク解析、OMSA実行パス選択、iDRAC IPv4取得、物理ディスクID解析について回帰テストを追加・実施しました。
- ディスクがOMSAの認識対象から外れた場合でも、既存の仮想ディスク冗長性低下の監視とトリガーによる障害通知が動作することを確認しました。
- GitHub管理用の`.gitignore`を追加し、秘密鍵、認証情報、ログ、一時ファイル、配布成果物等をGit管理対象から除外しました。

## 2.0.2 - 2026年6月9日(火)

参照: [GitHub Release v2.0.2](https://github.com/Osamix2000/zabbix-dell-omsa/releases/tag/v2.0.2)

- `sudoers.d/zabbix-omsa`を追加し、`/etc/sudoers`本体を直接変更せずにZabbix用のsudo実行権限を管理できるようにしました。
- 従来sudo環境では、対象スクリプトのsudo成功ログとPAMセッションログを抑制できる設定を追加しました。
- Ubuntu 26.04などのsudo-rs環境向けに`sudoers.d/zabbix-omsa.sudo-rs`を追加しました。sudo-rs向けは実行許可のみを扱い、ログ抑制は行いません。
- sudoers.dの設定方法とsudo-rsの注意事項をREADMEに追加しました。
- `SCRIPT_VERSION`を`2.0.2`に更新しました。監視ロジックは変更していません。

## 2.0.1 - 2026年5月25日(月)

参照: [GitHub Release v2.0.1](https://github.com/Osamix2000/zabbix-dell-omsa/releases/tag/v2.0.1)

- CPU温度と消費電力が適切に取得できなくなっていた不具合を修正しました。

## 2.0.0 - 2026年5月22日(金)

参照: [GitHub Release v2.0.0](https://github.com/Osamix2000/zabbix-dell-omsa/releases/tag/v2.0.0)

- OMSA専用の監視スクリプトから、OMSAを最優先としつつ`dmidecode`、`ipmitool -I open`、`perccli`、Redfish、`racadm`で取得情報を補える構成へ変更しました。
- 既存の`omsa.*`キーおよびZabbixテンプレートとの互換性を維持しました。
- 手動確認オプション、日本語ヘルプ、パッケージ導入支援、Redfish認証設定ファイル作成、IPMI/BMCキャッシュとコマンド実行タイムアウトを追加しました。
- Zabbix数値アイテムの取得不可時の値を整理し、物理ディスク状態の表記・仮想ディスクサイズ換算の扱いを改善しました。

## 1.0.2 - 2026年5月22日(金)

参照: [GitHub Release v1.0.2](https://github.com/Osamix2000/zabbix-dell-omsa/releases/tag/v1.0.2)

- 変更内容の詳細は公開リリースノートに記載されていません。
