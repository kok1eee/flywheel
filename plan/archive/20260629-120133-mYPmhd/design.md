# design: fw_impl_fingerprint に宣言 sibling repo を含める（multi-repo stale clean 穴塞ぎ）

## 背景・問題

FR-50（改善C）で monitor=clean を「baseline 累積実装 diff の指紋（sha256）」に紐付け、loop-driver の
clean ゲートが**指紋一致時のみ done**にした。だが `fw_impl_fingerprint`（`hooks/lib/common.sh`）は
**FW_ROOT の `jj diff --from $base` だけ**を hash しており、`flywheel repos` で宣言した sibling repo
（`state.repos`）を見ていない。

結果（FR-50/C の既知限界）: multi-repo goal で **FW_ROOT は無変更だが sibling repo を変更**して停止すると、
FW_ROOT 指紋は不変 → monitor-set clean の後に sibling を直しても指紋一致と判定され **stale clean が
done をすり抜ける**。`fw_goal_diff_lines`（diff 行数の集約）は既に FW_ROOT + sibling を合算しているのに、
指紋だけが FW_ROOT 単独という非対称が穴の本体。

## 方針

指紋を `fw_goal_diff_lines` と**同一の集約規約**に揃える。FW_ROOT の diff に続けて `state.repos` を
jq 配列順でループし、各 repo の `jj diff --from <その repo の baseline>` を連結してから hash する。

### 連結規約（fw_goal_diff_lines と一致）

- 順序: **FW_ROOT diff 先頭** → `state.repos` の jq 配列順（`(.repos // [])[]`）
- 各 sibling は**自身の baseline**（`state.repos[].baseline`）で `jj diff --from`（jj 不能なら `git diff` に degrade）
- path 解決は `fw_repo_dir`（FW_ROOT 相対 or 絶対の両対応・規約を1箇所に）
- diff 取得は `--git`（FW_ROOT と同形式で一貫）

### 空判定の位置（grill で確定した core 決定）

`[[ -n "$d" ]]` の**空判定を FW_ROOT + sibling を連結した後**に移す。これにより
**FW_ROOT 無変更でも sibling に変更があれば指紋が立つ** → stale clean が正しく再 council される
（穴の本体を塞ぐ）。連結後の全 diff が空のときだけ空指紋を返す（＝後方互換の done に degrade）。

### 変更後の擬似コード

```bash
fw_impl_fingerprint() {
  local base d p b
  base="$(fw_baseline_rev)"
  [[ -n "$base" ]] || return 0
  d="$( cd "$FW_ROOT" 2>/dev/null && { jj diff --from "$base" --git 2>/dev/null || git diff "$base" 2>/dev/null; } )" || true
  # 宣言 sibling repo（state.repos）を同規約で連結（各 repo は自身の baseline）
  while IFS=$'\t' read -r p b; do
    [[ -z "$p" || -z "$b" ]] && continue
    d+="$( cd "$(fw_repo_dir "$p")" 2>/dev/null && { jj diff --from "$b" --git 2>/dev/null || git diff "$b" 2>/dev/null; } )"
  done < <(jq -r '(.repos // [])[] | [.path, .baseline] | @tsv' "$FW_STATE" 2>/dev/null)
  [[ -n "$d" ]] && command -v sha256sum >/dev/null 2>&1 || return 0
  printf '%s' "$d" | sha256sum | awk '{print $1}'
}
```

## Boundary（触る範囲）

- `hooks/lib/common.sh` の `fw_impl_fingerprint()` を拡張 + per-repo の raw diff プリミティブ
  `fw_repo_git_diff()` を新規追加（FW_ROOT と sibling の diff 取得を1箇所に統一＝規約の対称性を構造的に担保）。コメントも FR-A/B 合算に言及するよう更新
- `test/monitor-fingerprint.sh` に **sibling 回帰を1本追加**（既存 assertion は触らない）
- それ以外（loop-driver の clean ゲート・monitor-set・他 test）のロジックは無変更
- 出荷規約（CLAUDE.md）: 振る舞い変更なので version bump を同 change に含める＝plugin.json /
  marketplace.json を v0.8.31・README 冒頭 + Changelog・ROADMAP の FR-50 既知限界行を更新

## 後方互換・degrade

- `state.repos` 未宣言（single-repo goal）→ ループが0回 → **従来と完全に同一の指紋**
- sibling の baseline 空（VCS 不能 repo）→ `[[ -z "$b" ]] && continue` で skip ＝ diff 空扱い・無害
- `sha256sum` 不在 / 連結後 diff 空 → 従来どおり空指紋（後方互換 done に degrade）

## 完了条件（eval）

```
bash test/monitor-fingerprint.sh && bash test/multirepo-diff.sh
```

両方 exit 0。`test/monitor-fingerprint.sh` に追加する sibling 回帰が満たすべき性質:

1. **sibling だけ変更 → 指紋が変わる**: FW_ROOT 無変更のまま、宣言した sibling repo の追跡ファイルを
   変更すると `fw_impl_fingerprint` の出力が baseline 時と変わる（穴塞ぎの核）。
2. **repos 未宣言の後方互換**: sibling を宣言しない状態では従来と同じ指紋（FW_ROOT 単独 hash）であること。
3. 既存の monitor-fingerprint / multirepo-diff assertion は全て緑のまま。

## 検証の落とし穴（council 由来・FR-50 の学び）

- test は mktemp の **git + untracked** リポ、本番は **jj + .gitignore** で「同結果を別機構で達成」する。
  指紋の安定性（`.flywheel/` が diff に出ない等）は gitignore 依存なので、test 側でも sibling repo の
  `.flywheel` 除外を assert に1つ含める（FR-50 C5 と同じ轍を踏まない）。
- diff は必ず **baseline 累積**（`jj diff --from $base`）。plain `jj diff` は commit でゼロリセットする。
