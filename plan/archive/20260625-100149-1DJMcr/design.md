# design — evolve 未実行リマインダ（改善A）

## 背景

skill-usage.csv 419 events に対し `flywheel:evolve` は **1 回**（最終 2026-06-15）。
evolve（自己改善 skill）に**起動トリガーが無い**ため、実行データが溜まっても skill の Gotchas に
還元されない。**greeter（SessionStart）に「evolve 未実行 N 日／未消化 N goal」のリマインダを表示**し、
人が `/flywheel:evolve` を回すよう促す（方式は grill で確定＝greeter リマインダ・nudge / 無人実行しない・
HOTL「決める＝人間」を保つ）。

## 何を作るか（ファイル/関数レベル）

### 1. `hooks/lib/common.sh` に `fw_evolve_staleness` を追加

evolve の停滞度を判定し、**停滞時のみリマインダ1行を echo**（非停滞・データ無しなら無音）。

- CSV パス解決は `fw_log_usage` と同一:
  `${CLAUDE_PLUGIN_DATA:-$(ls -d "$HOME"/.claude/plugins/data/flywheel-* 2>/dev/null | head -1)}/skill-usage.csv`
- CSV が無ければ無音で return（greeter を壊さない）。
- 最終 evolve 行 = `grep -nE ',(flywheel:)?evolve$'` の最後。無ければ「未実行（記録なし）」扱いで停滞。
- `days_since` = (now_epoch − evolve_epoch) / 86400（`date -u -d` / epoch 変換）。
- `goals_since` = 最終 evolve 行より後にある `,goal:`（start/adopt/plan）行数。
- **停滞条件**: `days_since >= ${EVOLVE_STALE_DAYS:-7}` または `goals_since >= ${EVOLVE_STALE_GOALS:-5}`、
  または evolve 記録なし。閾値は env で上書き可（テスト・調整用）。
- 停滞時の出力（1行）:
  `🧬 evolve 未実行: 最終 <YYYY-MM-DD>（<N>日前・直近 <M> goal 未消化）— /flywheel:evolve で skill に学びを還元`
  （記録なしは `🧬 evolve 未実行（記録なし）— /flywheel:evolve で skill に学びを還元`）

### 2. `hooks/session-greeter.sh` に1行差し込む

- 先頭付近で `evolve_line="$(fw_evolve_staleness)"` を1回計算。
- **dormant greeting**（末尾の emit）と **active=done greeting**（`done` ケースの next）に
  `${evolve_line:+\n  $evolve_line}` を足す。両方とも「次の作業を考える」間の瞬間なので適所。
- `set -euo pipefail` 下でも安全に（`fw_evolve_staleness` は失敗しても空を返す設計）。
- 既存の dormant/active 文面・gate 挙動は不変（追記のみ）。

### 3. `test/evolve-nudge.sh`（run-all が自動 glob）

`test/chain-lib.sh` の env 分離（`CLAUDE_PLUGIN_DATA` を /tmp に・dormant な使い捨て FW_ROOT）を流用。
`date -u -d` で相対タイムスタンプを生成し決定的に:

- **C1 stale（日数）**: 最終 evolve = 30 日前の CSV → greeter 出力に `evolve 未実行` を含む。
- **C2 fresh**: 最終 evolve = 今日（0 日前・goal 0 件）→ リマインダを**含まない**。
- **C3 goals 閾値**: evolve = 2 日前だが後続 `goal:*` を 5 件 → 停滞表示（日数でなく goal 数で発火）。
- **C4 CSV 欠落**: CSV 無し → 無音・exit 0・greeter 本体は通常 dormant 文面を出す（クラッシュしない）。

## 非スコープ

- 無人 auto-run（sdtab 週次）は不採用（grill で nudge を選択）。
- improvements.md の表示・evolve 自体の改修はしない（A は「起動させる」だけ）。

## 完了条件（eval）

```
bash test/run-all.sh
```

`test/evolve-nudge.sh`（C1–C4）が自動登録され、既存全スイートと共に緑であること。
