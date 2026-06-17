# マルチレポ対応（最小スコープ）— design

## 方針

FW_ROOT は単一のまま維持し、**関連 sibling repo の集合を state に持たせて diff 計測だけを合算**する。
eval は eval_cmd（shell 文字列）が既に跨げるので触らない。cross-repo の gate/昇格（#5）は `flywheel go`
に委ね、本 goal では実装しない。「最小の追加で『半分しか検証されない』を消す」を狙う。

## データ設計

`state.repos`: 関連リポの配列。各要素は登録時点を固定するため baseline を同梱する。

```
"repos": [ { "path": "../shared-python-lib", "baseline": "<jj commit_id or git sha>" }, ... ]
```

- `path` は FW_ROOT 相対（表示・diff 実行時に `cd "$FW_ROOT/$path"`）。絶対パスも許容。
- `baseline` は登録時に対象リポで `jj log -r @- commit_id` → fallback `git rev-parse HEAD` で捕捉。
  FW_ROOT 自身の baseline（`state.baseline_rev`）とは独立（FR の非スコープ: FW_ROOT 構造は不変）。
- **注意（grill ②）**: baseline は `flywheel repos` 宣言**時点**を起点とするため、宣言前に sibling で
  行った変更は diff に乗らない。FW_ROOT と同様、goal 着手時に sibling でも `jj new` してから宣言する運用を推奨。
- **VCS 混在（grill ③）**: baseline 捕捉・diff 取得はどちらも `cd <repo>` 後に jj→git→degrade を試す
  cwd ベースなので、FW_ROOT=jj / sibling=git のような混在は各リポで自動検出され自然に解ける。
- **除外ルール（grill ④）**: per-file の実装判定（`fw_is_impl_write`: plan//docs//*.md 除外）は
  **各リポ root 相対**で適用する（diff --stat の出力パスは各 repo root 相対なのでそのまま通る）。

## コンポーネント変更

- **FR-A `bin/flywheel` `repos)` ケース追加**: `flywheel repos <path>...`。`set-eval`/`monitor-set` と
  同型（`fw_state_exists` ガード・phase 不問・`FLYWHEEL_HOOK` なし）。各 path の存在を確認し、
  `fw_repo_baseline <path>` で baseline 捕捉 → `state.repos` を `fw_set_json` で組み立て。
  引数なしは現在の repos を一覧表示（list 兼用）。usage 行も追従。
- **FR-A `hooks/lib/common.sh` `fw_repo_baseline <path>`**: 指定ディレクトリで jj `@-` commit_id →
  fallback git `HEAD`。`fw_baseline_rev` の per-path 版（既存ロジックを path 引数で一般化）。
- **FR-B `hooks/lib/common.sh` `fw_goal_diff_lines` 拡張**: 既存の FW_ROOT 集計に続けて、
  `state.repos` の各 `{path, baseline}` について「`cd "$FW_ROOT/$path"` で baseline からの実装 diff 行数」を
  同じ per-file ロジック（`fw_is_impl_write` を各リポ root 相対で適用）で加算する。jj/git 両対応は既存踏襲。
- **FR-C `should_polish`**: 変更不要。FR-B が効けば `fw_goal_diff_lines` の戻り値に sibling 分が乗り、
  polish 判定が自動で cross-repo を加味する（テストで確認）。
- **FR-D `bin/flywheel` `status`**: `repos` を `path (baseline短縮)` の形で表示する行を追加。

## 完了条件（eval）

静的チェック（構文・`repos)` ケース・新関数の存在）＋ 専用の機能テスト（mktemp で main + sibling の
2リポを作り、sibling を登録 → 両リポに実装変更 → `fw_goal_diff_lines` が**両方を合算**することを assert。
未登録なら FW_ROOT 分だけ、を対比）。実装前は red（`repos)`/関数/テスト未存在）、実装後に green。

```
bash -n bin/flywheel
bash -n hooks/lib/common.sh
grep -qE '^[[:space:]]*repos\)' bin/flywheel
grep -q 'fw_repo_baseline' hooks/lib/common.sh
bash test/multirepo-diff.sh
```

合格 = 構文 OK かつ `repos)` ケースと `fw_repo_baseline` が存在し、`test/multirepo-diff.sh` が
「sibling 登録時に diff が合算され、未登録時は FW_ROOT のみ」を緑で示す。
