# ChangeLog

## 2.1.0 - 2026年7月30日(木)

- OMSA 11.0.0.0 / 11.1.0.0の両方を同一コードで扱えるように`omreport`解析を見直し
- ファンRPMで`2380 RPM`と`2380RPM`の両形式を数値`2380`へ正規化
- 温度と消費電力も単位の空白有無に依存せず数値だけ取得
- ファン、温度、PSU、RAM、消費電力のIndex/項目解析を固定列依存から項目名ベースへ変更
- 物理ディスク、仮想ディスクの状態、RAID、サイズ解析を固定列依存から項目名ベースへ変更
- 仮想ディスクサイズは`(xxxxx bytes)`があればそれを最優先し、無ければ単位付きサイズから換算
- BMC/iDRAC情報は`omreport chassis remoteaccess`と`chassis bmc`を利用可能な範囲で併用
- `--test-omsa`で取得可能な場合にOMSAバージョンを表示
- OMSA 11.0/11.1相当の出力差を確認する`tests/omsa-parser-compat-test.sh`を追加
- GitHub管理向け`.gitignore`を追加し、SSH情報、秘密鍵、`.env`、一時ファイル、ログ、配布成果物等を除外
