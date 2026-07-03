# design: evolve actor-routing の機械検査化（FR-51・誤配送 Gotcha の恒久ガード test）

## 背景・問題

evolve の Gotcha 書き込みには actor-routing 規則（Step 2.7、2026-07-02 追加）があるが、これは
**prompt-level の注意書き**に留まる。実際に 2026-06-29 / 07-01 の観測者向けレンズ 2 件が
`skills/monitor/SKILL.md` の AUTO-GOTCHAS に誤配送され、観測者（`agents/drift-observer.md` を
system prompt として読む）に**一度も届かないまま 2〜4 日生存**した。検出したのは flywheel 自身では
なく外部の /code-review であり、「eval も smoke も掛からない非 runnable 変更（.md 編集）」という
検証の死角がメタ層に残っている。

C-2 の思想（モデルを信用せず機械が観測する）を evolve の出力にも適用し、この誤配送 class を
CI（`test/run-all.sh`）で機械的に殺す恒久ガード test を足す。前例は `test/intent-router-removed.sh`
（grep ベースの再混入ガード）。

## 方針

新テスト **`test/gotcha-actor-routing.sh`**（`grep-lib.sh` を source: 副作用なし・fail/ok/$ROOT）。

### 検出仕様（実例 class に絞る＝false positive ゼロ設計）

- 対象領域: 各 `skills/*/SKILL.md` の `<!-- AUTO-GOTCHAS -->` **マーカーより下**のみ
  （マーカーより上の手動 Gotchas は不問。マーカーが無い SKILL.md は検査対象 0 行で pass）。
- 検出パターン: auto 追記の定型 `- **[YYYY-MM-DD] <title>**:` の **title が actor 主語で始まる**行。
  actor 主語はキーワード配列（初期値 `観測者は` のみ。fan-out agent が増えたらここに足す運用）。
- **本文中の言及は不問**: 「観測者 fan-out も…」等、title 主語でない「観測者」言及（monitor の
  既存 AUTO 項や手動 Gotchas）は検出しない。誤配送の実例は title 主語形のみで、広く取ると
  overseer 向け正当記述を誤検知して除外リスト運用になるため。
- 検出時は `file:line: 内容` を表示して fail し、「`agents/<name>.md` の AUTO-GOTCHAS へ移設せよ」
  と修正先を明示する。

### 検査ロジックの自己検証（positive control）

lint が一度も fire しないままだと self-graded 同然（`test/run-all-aggregation.sh` の前例と同じ論点）
なので、検査本体は**対象ディレクトリを引数に取る関数**にし、同一テスト内で:

1. `$ROOT/skills` に対して実行 → 現リポは検出 0 で pass すること
2. mktemp fixture に誤配送 Gotcha（AUTO-GOTCHAS 配下・「観測者は」title）を仕込んで実行 →
   **検出して非ゼロを返す**こと（失敗パスの実走）
3. fixture のマーカー**より上**に同文を置いた場合・本文中言及のみの場合 → 検出しないこと
   （false positive ガードの実走）

### zero-match false-pass ガード

`skills/` ディレクトリの存在を先に assert（`intent-router-removed.sh` が監視 council 指摘で
入れたのと同じ轍: 対象消失時に grep exit 2 が `!` で false-pass する穴）。

## Boundary（触る範囲）

- **`test/gotcha-actor-routing.sh` 新規 1 本のみ**（コード変更）。`run-all.sh` は `test/*.sh` を
  自動で拾う（除外は chain-lib/grep-lib のみ）ため配線変更なし。
- polish（simplify/altitude レビュー）で採用した微修正: 実リポに AUTO-GOTCHAS マーカーが 1 つも
  無ければ fail する形式 drift ガードを追加（検査の vacuous pass 防止）、SUBJECTS に Step 2.7 が
  例示する「reviewer は」を追加、evolve SKILL.md Step 2.7 の fan-out 行に SUBJECTS への相互参照
  1 行を追記（規則自体は不変・二重保守の導線を閉じるのみ）。
- 出荷規約（CLAUDE.md）: README 機能史 + Changelog、ROADMAP に FR-51 行、version bump
  **v0.8.32**（plugin.json / marketplace.json の 2 箇所 + README 冒頭）。
- 非スコープ: 逆方向検査（agents/*.md への overseer 向け混入＝実例なし）、キーワードの網羅化、
  evolve SKILL.md の変更（Step 2.7 は出荷済み）、hook 化（まず CI ガードで十分。踏み直したら昇格検討）。

## 後方互換・degrade

- 現リポは誤配送ゼロ（2026-07-02 に移設済み）なので追加直後から緑。
- AUTO-GOTCHAS マーカーを持たない skill / 新規 skill は検査対象 0 行で無害に pass。
- 将来 fan-out agent（reviewer 等）向けの誤配送が新 class で出たら、キーワード配列に 1 語足すだけ。

## 完了条件（eval）

```
bash test/run-all.sh
```

exit 0。新テスト `test/gotcha-actor-routing.sh` が満たすべき性質:

1. 現リポの `skills/` に対して検出 0 件で pass（移設済みの現状が緑）。
2. positive control: fixture の誤配送 Gotcha（マーカー配下・「観測者は」title）を検出して
   非ゼロ + 該当 `file:line` を出力する（失敗パスの実走を assert）。
3. false positive ガード: マーカーより上の同文・本文中の「観測者」言及のみの fixture は検出しない。
4. `skills/` 不在なら fail（zero-match false-pass ガード）。
5. 既存 test は全て緑のまま（run-all 集約）。

## 検証の落とし穴（council / 前例由来）

- 対象ディレクトリ消失で grep が exit 2 → `!` 反転で false-pass（intent-router-removed の学び）。
  存在 assert を先行させる。
- マーカー以下の切り出しは awk（`/<!-- AUTO-GOTCHAS -->/{f=1;next} f`）で行い、行番号は FNR で
  実ファイル行を報告する（grep 直では領域限定ができない）。
- テストは bash で書く（`#!/usr/bin/env bash`・リポ規約）。zsh 直書き禁止。
