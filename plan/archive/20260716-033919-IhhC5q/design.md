# monitor council mode 集計を flywheel status に出す

## 背景（合意済み・掘り直し不要）

Enterprise 契約後のトークン使用量調査（2026-07-14）で `flywheel:monitor` の呼出頻度の
高さが判明し、当初は「mode（lite/targeted/full）を計測するテレメトリを新設する」goal
として積んだ。しかし実装着手時に、**そのテレメトリは既に存在していた**ことが分かった:
`bin/flywheel monitor-set` は `fw_log_monitor_verdict`（`hooks/lib/common.sh`）経由で
毎呼出を `~/.claude/plugins/data/flywheel-*/monitor-verdicts.csv`
（`timestamp,verdict,level,lenses,diff_lines,mode`）に記録している（v0.8.42 で mode 列追加）。

実データ（54行）: mode 記録済み19件中 full=13(68%) / targeted=4 / lite=2。lite/標的の
コスト比例制御は動いているが、まだ過半数が full 3レンズ fan-out。

→ goal をリダイレクト。**記録は既にある。無いのは「見る場所」。** `flywheel status` に
mode 内訳を1行追加し、次回以降ユーザーが都度 CSV を手で集計しなくても比率が見えるようにする。

## 変更内容

### 1. `bin/flywheel` の `status)` ケース（L159-175）

- `history :` 出力の直前（または直後）に1行追加。`fw_data_dir`（既存関数、
  `hooks/lib/common.sh`）で解決した `monitor-verdicts.csv` を集計する:
  ```bash
  _mvcsv="$(fw_data_dir)/monitor-verdicts.csv"
  if [[ -f "$_mvcsv" ]]; then
    _mstats="$(awk -F',' 'NR>1{c[$6]++} END{printf "full=%d targeted=%d lite=%d 未記録=%d", c["full"]+0, c["targeted"]+0, c["lite"]+0, c[""]+0}' "$_mvcsv" 2>/dev/null)"
    echo "monitor mode: $_mstats（累積・全goal）"
  fi
  ```
  - `$6` は CSV の6列目 `mode`（`timestamp,verdict,level,lenses,diff_lines,mode`）。
    lenses は `|` join（v0.8.42・`_lens_norm`）済みでカンマを含まないため
    `awk -F','` の単純分割で安全。
  - CSV が無い（初回・過去バージョン）場合は行自体を出さない（`if [[ -f ]]` で握る）。
  - 集計は**全 goal 累積**（今の goal だけでなく歴史全体）。goal 単位の内訳は非スコープ
    （後述）。

### 2. テスト（`test/monitor-mode-status.sh` 新規）

- `test/chain-lib.sh` の環境分離ヘルパを source し、`CLAUDE_PLUGIN_DATA` を `mktemp -d`
  に向ける（既存規約: 本番 CSV を汚さない）。
- フィクスチャの `monitor-verdicts.csv`（header + full 2行 + targeted 1行 + lite 1行 +
  mode 空1行）を `$CLAUDE_PLUGIN_DATA/monitor-verdicts.csv` に置く。
- state を用意（`flywheel start` 相当）→ `flywheel status` の出力に
  `full=2 targeted=1 lite=1 未記録=1` を含むことをアサート。
- CSV が無いケース（`rm` してから status）でも `monitor mode:` 行が**出ない**こと
  （エラーにならず単に省略）もアサート。
- `test/run-all.sh` に自動で乗る。

## 非スコープ

- goal 単位（今の goal だけ）の mode 内訳 — 累積のみ。今回は「全体で lite/targeted が
  効いているか」を見たいので累積で十分
- lite/標的判定の閾値（`FLYWHEEL_MONITOR_LITE_DIFF`）調整 — 今回のデータ（full 68%）を
  見た上で閾値を上げるかは別の判断。本 phase は「見える化」のみで留め、閾値変更は
  データを見てから人間が判断する次の goal に分離
- CSV 自体のフォーマット変更・新規フィールド追加（monitor-set 側は変更しない）
- 旧 `.flywheel/monitor-log.jsonl` 案（当初の重複実装）は採用しない

## 完了条件（eval）

```
bash test/run-all.sh
```

新規 `test/monitor-mode-status.sh` が上記アサートで合格し、既存テスト
（design-gate / chain 系 / ultrawork-skill 等）に regression が無いこと。
