# design: sibling .gitignore 警告（FR-57・multi-repo 指紋churn の入口ガード / FR-50 follow-up 解消）

## 背景・問題

FR-50/v0.8.31 の既知限界（ROADMAP マルチレポ epic の follow-up・low）: 本番の jj は untracked を
snapshot するため、`flywheel repos` で宣言した sibling 側の `.gitignore` が `.flywheel` を除外して
いないと、sibling の `.flywheel/` state 書き込みのたびに累積 diff（= 指紋）が揺れ、
**monitor=clean の指紋不一致 → 無限 re-council** になり得る。FW_ROOT 側は test C5 で assert 済みだが
sibling 側は「登録時に警告/要求する設計判断が未了」のまま残っていた。

## 方針

`flywheel repos` の登録ループ内（baseline 捕捉の直後）で sibling の `.gitignore` を検査し、
`.flywheel` の除外エントリが無ければ **stderr 警告 1 行**（**exit 0 のまま・登録は成功**）:

- **警告のみで要求（登録拒否）にしない**: 拒否は既存運用を壊す過剰対応。pure git リポや
  一時的な検証 repo では問題が顕在化しないケースもある。
- 判定: `grep -qE '^/?\.flywheel/?$' "$_dir/.gitignore" 2>/dev/null`。`.gitignore` 不在も警告対象
  （grep が非ゼロ）。パターンは行全体一致（`.flywheel` / `.flywheel/` / root-anchor の
  `/.flywheel` / `/.flywheel/` を許容＝council 指摘で拡大。`**/.flywheel` や CRLF・行末空白等の
  変種は稀なので v1 非対応＝警告が出たら人間が確認すればよい・過剰検知側に倒す）。
- 警告文に**理由**（jj は untracked を snapshot → state churn で指紋が揺れ無限 re-council）と
  **対処**（`echo '.flywheel/' >> <sibling>/.gitignore`）を含める。
- 検査は observation-only（grep がどう失敗しても登録は成功。既存の baseline 空警告と同じ流儀）。

## Boundary（触る範囲）

- `bin/flywheel`（repos の登録ループに警告 3〜4 行）
- `test/repos-gitignore-warn.sh` 新規 1 本（chain-lib。multirepo-diff.sh は既存 assertion を触らない）
- 出荷規約: README Changelog / ROADMAP（FR-57 行 + マルチレポ epic の follow-up 記述を解消済みに更新）/
  version **v0.8.38**（plugin.json / marketplace.json / README 冒頭）
- 非スコープ: 登録拒否（要求化）、`flywheel start` 時の FW_ROOT 側検査（C5 で担保済み・greeter 常駐
  検査は過剰）、gitignore の自動追記（他人のリポを勝手に書き換えない）、**症状発生地点（loop-driver
  の指紋不一致 steer）での原因ヒント再掲**（polish altitude 指摘で認識。登録時警告はスクロールバックに
  埋もれ得るが、loop-driver 変更は本 goal のスコープ外＝improvements.md へ退避し次に loop-driver を
  触る goal に同乗）

## polish（simplify レビュー採択）

- mk_sibling の git リポ生成ボイラープレート（4 箇所目）を chain-lib の `mk_git_repo` に抽出。
  diff 外の既存 3 箇所（chain-lib 初期化・monitor-fingerprint・multirepo-diff）は improvements.md へ。
- C1-C3 の「登録 → stderr grep」コピペを `expect_warn` ヘルパに縮約（警告文言変更時の 3 箇所同時
  修正を 1 箇所に）。
- ROADMAP の FR-57 二重記載を解消（epic 親行は次行参照のみ）。

## 後方互換・degrade

- 警告は stderr のみ・exit code / state 書き込み / 出力（stdout）不変 → 既存テスト
  （multirepo-diff.sh / monitor-fingerprint.sh の repos 呼び出し）は無変更で緑のはず。
  ※ 既存テストの sibling fixture が .gitignore 無しなら警告が stderr に増えるが、
  既存 assert は stderr の無警告を要求していない（実装時に grep で確認）。

## 完了条件（eval）

```
bash test/run-all.sh
```

exit 0。新テスト `test/repos-gitignore-warn.sh`（chain-lib）が満たすべき性質:

1. C1: `.gitignore` の無い sibling を登録 → exit 0・登録成功（repos に載る）・stderr に警告
   （「.flywheel」を含む）。
2. C2: `.flywheel/` を `.gitignore` に持つ sibling を登録 → exit 0・警告なし。
3. C3: `.flywheel`（スラッシュ無し）エントリでも警告なし（`/?` 許容の演習）。
4. 既存 test 全緑（run-all 集約）。

## 検証の落とし穴（前例由来）

- 警告文はテストで「どのチェックが fire したか」を判別できる固有語（「.flywheel」「gitignore」）を
  含める（expect_broken の学び＝非ゼロ/有無だけの assert は誤爆を隠す）。
- stderr のみ検査: `2>&1 >/dev/null` のリダイレクト順（monitor-lens-csv C5 の既存イディオム）。
- sibling fixture は chain-lib の $TMP 配下に git init で作る（multirepo 系テストの precedent）。
