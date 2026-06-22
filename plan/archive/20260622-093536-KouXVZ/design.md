# design: flywheel の test を push+PR で走らせる GitHub Actions CI（FR-44）

adopt（結晶化）。grill 合意済み。dogfood: flywheel の eval ゲート思想（self-grade せず客観 exit
code で検証）を自分自身のテストに CI として適用する。

## 背景（なぜ）

flywheel は `test/*.sh`（11 本の自立テスト）を持つが CI が無く、push してもテストが回らない＝
リグレッションを push 後に人手で気付くしかない。実依存は `git` / `bash` / `jq` の 3 つだけ
（`jj` は `polish-rename-skip.sh:7` のコメント言及のみで実行依存なし）で、すべて
`ubuntu-latest` にプリインストール済み。よって最小コストで客観検証を常時化できる。

## 変更点

### 1. `test/run-all.sh`（新規・共有 runner）

- `test/` 配下の `*.sh` をループ実行する。
- **除外**: `chain-lib.sh` / `grep-lib.sh`（source 用ライブラリ。単体実行しない）。
- 各テストを `bash <file>` で実行し、**1 本でも非ゼロなら最終 exit を非ゼロに集約**する
  （落ちたファイル名を一覧表示）。全緑なら `exit 0`。
- ローカル実行と CI が**同じ入口**を通る（FR-42 の共有化方針と整合）。
- `#!/usr/bin/env bash` / `set -uo pipefail`。スクリプト位置から `test/` を解決し、cwd 非依存。

### 2. `.github/workflows/ci.yml`（新規）

- `name: ci`
- `on: [push, pull_request]`（push と PR の両方）
- 単一 job、`runs-on: ubuntu-latest`、**matrix なし**（tests に bash version 依存なし＝
  `declare -A` / `mapfile` 不使用を確認済み）。
- steps: `actions/checkout@v4` → `run: bash test/run-all.sh`。
- 依存（git/bash/jq）は ubuntu-latest プリインストールで**追加 install 不要**。

### 3. version bump → v0.8.24（ship 規約）

- `.claude-plugin/plugin.json` と `.claude-plugin/marketplace.json` の `version` を `0.8.24`（2 箇所）。
- `README.md` 冒頭の `vX.Y.Z` と Changelog に 1 行。
- `ROADMAP.md` の状態行に FR-44 を反映。

### 4. `test/run-all-aggregation.sh`（監視 council 指摘の反映）

監視 council（observer-behavior）が「`run-all.sh` の**失敗集約パス**（`fail=1` / `exit 1` / 失敗名
出力）は全緑 eval では一度も実走されず未検証＝happy-path のみ検証」を drift(impl) として検出。CI
runner の核契約（テストが落ちたら赤くなる）なので runtime 検証を追加して閉じる:

- `run-all.sh` に**第1引数で対象ディレクトリ**を渡せるようにする（省略時は `test/` 自身＝CI/従来の
  呼び方は不変）。
- `test/run-all-aggregation.sh` — temp に捨てテスト（pass / 故意 fail）を置き、
  `bash run-all.sh <tmpdir>` で「失敗あり→exit 非0 + 失敗名出力」「全緑→exit 0」を客観検証する。

## 非スコープ

- **GitHub での実 CI green の確認**: push 後に `/ci-watch` で人間/monitor が確認（done 条件外）。
- matrix（複数 OS / bash）・依存キャッシュ・lint 専用 job の追加。
- backlog に残る重複 FR-44 の削除（backlog の remove/reorder CLI 不在は別 gap・ROADMAP 候補）。

## 完了条件（eval）

```bash
bash test/run-all.sh
```
