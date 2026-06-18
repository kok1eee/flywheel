# design: grep-test の共有 lib 化（FR-42）

adopt（合意の結晶化）。simplify が rule-of-three で指摘した重複の解消。

## 背景（なぜ）

`test/grill-termination.sh` / `test/adopt-args-sanitize.sh` / `test/checkpoint-button.sh` の3 grep-test が
`fail()` / `ok()` と `DIR`/`ROOT` 解決（約6行）を**3回重複**（rule-of-three）。`test/chain-lib.sh` は
source 時に **mktemp / git init / 使い捨てリポへ cd** の副作用を持つ（chain 系 state テスト専用足場）ので、
ファイルを grep するだけの test が source すると cwd が飛ぶ＝不適。**副作用なしの軽量 lib** に抽出する。

## 変更点

- 新規 `test/grep-lib.sh`（**副作用なし**・source しても環境を変えない）: `fail()` / `ok()` /
  `ROOT`（lib 自身の位置 `${BASH_SOURCE[0]}` からリポルートを解決）を提供。
- 3 grep-test が冒頭で `source "$(dirname "${BASH_SOURCE[0]}")/grep-lib.sh"` し、各自の
  `fail`/`ok`/`DIR`/`ROOT` 定義を削除して `$ROOT` を共有のものに依存。
- `set -uo pipefail` は各 test 側に残す。

## 非スコープ

- `chain-lib.sh` を source する state 系テスト（adopt-chain / start-chain / eval-veto-hint / verification-merge /
  add-notes / multirepo-diff）は**不変**（chain-lib の副作用足場が必要なので grep-lib に移さない）。
- `grep-lib.sh` に余計な機能を足さない（`fail`/`ok`/`ROOT` のみ）。source/hook/本体コードは触らない。

## 完了条件（eval）

3 grep-test が共有 lib を source した状態で全部緑（= lib 抽出で壊れていない）:

```bash
bash test/grill-termination.sh && bash test/adopt-args-sanitize.sh && bash test/checkpoint-button.sh
```
