# design: lens 効果計測（FR-52・monitor verdict の CSV 計測でレンズ運用をデータ駆動に）

## 背景・問題

監視 council のレンズ（observer-requirement / behavior / progress）と AUTO-GOTCHAS のレンズ項は
育つ一方で、**どのレンズが採用 drift を出したかがどこにも記録されない**。そのため
AUTO-GOTCHAS の cap 5 追い出しと「レンズ別の着眼点」への昇格（人間の判断）が勘になる。
skill 使用は `skill-usage.csv`（FR-18）で計測しているのに、監視 council の効果だけ無計測という
非対称を埋める。学習 loop の観測側（「効いたか」）を閉じる FR-51 の続き。

## 方針

`flywheel monitor-set` に optional `--lens <カンマ列>` を追加し、**verdict 記録と同時に**
`fw_data_dir` の CSV へ 1 行追記する（書き手は CLI ＝ C-2 整合。モデルはファイルを直接書かない）。

### CLI インターフェース

```
flywheel monitor-set clean
flywheel monitor-set drift implementing "<reason>" --lens observer-behavior,observer-requirement
```

- `--lens` は**任意・任意位置**。arg-scan（`add` の `--eval`/`--notes` パース precedent と同型）で
  flag を抜き、残る positional は従来どおり `<status> [level] [reason]`（**後方互換**: 既存呼び出しは
  無変更で動く）。
- 値は「採用 drift を出した reviewer のカンマ列」。**drift のときだけ渡す**（clean は採用 drift ゼロ
  なので lens なし）。overseer への指示は `skills/monitor/SKILL.md` Step 4 に追記。
- reviewer 名は SKILL.md の観測者リスト（データ）が正であり enum 検証しない（レンズ追加で CLI が
  壊れない）。sanitize のみ: `"` と改行を除去し、`,` を `|` に変換して 1 フィールドに収める。

### CSV 仕様

- ファイル: `$(fw_data_dir)/monitor-verdicts.csv`（skill-usage.csv と同居・同じ解決規約 FR-31）
- ヘッダ: `timestamp,verdict,level,lenses`
- 1 council verdict = 1 行。**clean も記録する**（レンズ効果の分母＝council 実行回数になる）。
  例: `2026-07-03T06:30:00Z,drift,implementing,observer-behavior|observer-requirement` /
  `2026-07-03T06:40:00Z,clean,,`
- **pending は記録しない**（fuse の priming（enter_polish）や手動リセットで、council の verdict では
  ないため。分母を汚さない）。
- 書き込みは `fw_log_monitor_verdict()`（`hooks/lib/common.sh`・`fw_log_usage` の直後に同型で追加）:
  mkdir/append 失敗でも `|| true` で**verdict 記録（fw_set_json）を絶対に妨げない**（observation-only）。
  呼び出しは bin/flywheel の monitor-set case 末尾（fw_set_json 成功後）。

### FR-51 council Note の同乗（clean 指紋の都合で持ち越した微修正）

1. README Changelog 0.8.32 / ROADMAP FR-51 行の「初期値『観測者は』」を実装どおり
   「観測者は / reviewer は」に修正（1 語の doc lag）。
2. `test/gotcha-actor-routing.sh` の positive control fixture に `reviewer は` title を 1 行足し、
   SUBJECTS の 2 語目を実演習させる。

## Boundary（触る範囲）

- `bin/flywheel`（monitor-set case: --lens パース + fw_log_monitor_verdict 呼び出し）
- `hooks/lib/common.sh`（`fw_log_monitor_verdict()` 新規・fw_log_usage 隣）
- `skills/monitor/SKILL.md`（Step 4 に --lens の渡し方を追記）
- `test/monitor-lens-csv.sh` 新規 1 本（run-all が自動で拾う）
- 同乗: `test/gotcha-actor-routing.sh` fixture 1 行・README/ROADMAP の FR-51 文言 1 語
- 出荷規約: version bump **v0.8.33**（plugin.json / marketplace.json / README 冒頭）+ Changelog +
  ROADMAP に FR-52 行（dev infra epic・FR-48 隣）
- 非スコープ: Gotcha 単位の attribution（観測者に引用 id を出させる機構が必要）、CSV の集計/可視化
  コマンド（データが溜まってから）、loop-driver の読み取り（記録のみ・執行に使わない）
- polish（simplify/altitude レビュー）で採用した微修正: CSV 追記の共通部を `_fw_log_csv` に抽出し
  fw_log_usage / fw_log_monitor_verdict を thin wrapper 化（挙動同一・既存 test が回帰網）、テストの
  goal 起動を chain-lib の `setup_impl` に統一、drift + lens 空のとき stderr 警告 1 行（exit 0 のまま・
  「--lens を渡す」prompt-level 契約の機械観測。テスト C5 で実証）。

## 後方互換・degrade

- `--lens` 省略時は従来と完全同一の挙動 + lenses 空の行が増えるだけ。既存 test（monitor-fingerprint
  等の monitor-set 呼び出し）は無変更で緑のまま＝回帰網。
- CSV 書き込み失敗（データ領域 read-only 等）でも verdict 記録は成功する（exit 0・state 反映）。
- pending 呼び出しは CSV 無記録で従来どおり。

## 完了条件（eval）

```
bash test/run-all.sh
```

exit 0。新テスト `test/monitor-lens-csv.sh`（chain-lib.sh の隔離ハーネス: mktemp リポ +
`CLAUDE_PLUGIN_DATA` を /tmp に向け本番 CSV を汚さない）が満たすべき性質:

1. C1: `monitor-set drift implementing "r" --lens a,b` → CSV に `,drift,implementing,a|b` 行 +
   ヘッダが存在し、state の monitor.status=drift も従来どおり記録される。
2. C2: `monitor-set clean`（--lens なし）→ `,clean,,` 行が追記される（分母記録）。
3. C3: `monitor-set pending` → CSV に行が**増えない**。
4. C4: データ領域を書き込み不能にしても monitor-set は exit 0 で verdict が state に入る
   （observation-only の実証）。
5. C5/C6（polish・council 採択）: 「drift には --lens・clean には無し」契約の違反を両方向とも
   stderr 警告で機械観測する（exit 0 のまま）。
6. 同乗分: `test/gotcha-actor-routing.sh` の positive control が `reviewer は` fixture も検出する。
7. 既存 test 全緑（run-all 集約）。

## 検証の落とし穴（前例由来）

- CSV の lenses フィールドに `,` をそのまま入れると列が割れる → 入力カンマ列は `|` 連結に変換して
  1 フィールド化（ヘッダ 4 列を固定）。
- `while [[ $# -gt 0 ]]` の arg-scan で空配列を `set --` に戻すとき bash の set -u と干渉しない形
  （bash 5.x 前提だが `${args[@]+"${args[@]}"}` 等の防御は既存 precedent に合わせる）。
- monitor-set は `set -euo pipefail` 下 → 計測系は必ず `|| true` を付け、fingerprint 計算
  （`|| true` 済み）と同じ流儀で verdict 記録を中断させない。
- テストは chain-lib.sh を source（monitor-set は fw_state_exists 必須・live state を壊さない）。
