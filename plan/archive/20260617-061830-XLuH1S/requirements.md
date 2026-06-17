# マルチレポ対応（最小スコープ）— requirements

## 背景 / 概要

flywheel は `FW_ROOT`（jj root → git root → pwd）の**単一リポ**を前提に設計されている。
だが実務では「favorite-pop と shared-python-lib を同時に直す」ように、1つの goal が
**複数の関連リポに跨る**ことがある。現状その goal を flywheel で回すと:

- **eval**: `loop-driver.sh:111` は `cd "$FW_ROOT" && bash -c "$eval_cmd"`。eval_cmd は
  shell 文字列なので `&& uv run --directory ../shared-python-lib pytest` と書けば sibling に
  既に届く（＝eval は実質マルチレポ対応済み・コード変更不要）。
- **diff / polish**: `common.sh:96 fw_goal_diff_lines` は `cd "$FW_ROOT" && jj diff` で
  **FW_ROOT しか測らない**。sibling 側の変更が diff 行数に乗らず、polish 判定
  （`should_polish` の閾値）が**過少カウント**して「半分しか見ていない」状態になる。

本 goal は **最小スコープ**で「diff/polish が宣言した sibling repo を合算する」を解消する。

## 機能要件

- **FR-A 関連リポ宣言**: `flywheel repos <path>...` で goal に関連する sibling repo 集合を
  `state.repos` に登録する。登録時に各 path の baseline（jj `@-` / git `HEAD`）を捕捉して保存する。
  `set-eval` と同型（`fw_state_exists` ガード・phase 不問・飛行中に追加可・`FLYWHEEL_HOOK` 不要）。
- **FR-B diff 合算**: `fw_goal_diff_lines` が FW_ROOT の実装 diff 行数に加え、`state.repos` 各リポの
  「保存 baseline からの実装 diff 行数」を合算して返す。per-file の実装判定（`fw_is_impl_write`）は
  各リポ root 相対で従来どおり適用する。
- **FR-C polish 反映**: `should_polish` は `fw_goal_diff_lines` 経由で cross-repo 変更を自動的に
  加味する（FR-B が効けば追加コードは不要なことの確認を含む）。
- **FR-D status 表示**: `flywheel status` に登録済み `repos`（path と baseline）を表示する。

## 非スコープ

- eval_cmd の sibling 自動注入（eval は人間が eval_cmd に書いて跨ぐ。`fw_detect_eval` は FW_ROOT のまま）。
- cross-repo の source 編集を「実装」と見なした gate / 自動昇格（touch point #5）。sibling への編集は
  従来どおり design-gate の対象外で、spec-ready→implementing は `flywheel go` で昇格する（H-1 と地続き）。
- per-repo の独立した done 判定・per-repo veto。done は単一 state の eval exit code で従来どおり判定。
- FW_ROOT 自体の baseline 構造変更（FW_ROOT は従来の `fw_baseline_rev` を維持。repos だけ map で持つ）。
