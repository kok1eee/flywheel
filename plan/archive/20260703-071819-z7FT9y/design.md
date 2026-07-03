# design: 2.1.198/199 対応（FR-53・council 同期化 + fork 空振り root cause + hooks 配線ガード）

## 背景・問題

Claude Code 2.1.198 で **subagent がデフォルトでバックグラウンド実行**に変わり、「fan-out →
集約 → 記録を同一ターンで行う」という monitor council の核前提が、明示的な sync 指定なしには
成立しなくなった。実踏（2026-07-03・FR-52 の council）: fork した monitor が観測者 3 体を spawn →
「完了通知を待ちます」とターン終了 → fork は非永続なので待つ主体が消え、完了通知は**親セッションに
漂着** → 集約も monitor-set も実行されない。Gotcha 113（fork 空振り）の**構造的な新 root cause**。

同日、遅延漂着した fork 側観測者レポートが clean 記録後に届き、そこでツリーを触ると FR-50 指紋が
無効化され再 council になる罠も実踏した（improvements.md へ退避して回避）。

また 2.1.191 のカンマ区切り matcher silent 失敗（修正済）が示した「**気づけない配線破れ**」class:
flywheel は全 matcher が pipe 区切りで未踏だが、design-gate（PreToolUse block）は配線が破れると
**fail-open**（設計ゲートごと無音で蒸発）なので、配線の機械観測に恒久的価値がある（FR-51 と同じ
「prompt-level/config-level の前提を CI で観測する」路線）。

## 方針

### 1. monitor SKILL.md Step 2 — 観測者 spawn の同期明記（1〜2 行）

Step 2 の fan-out 指示に「各観測者は **`run_in_background: false`（同期）** で spawn する」を明記。
理由も一言添える: 2.1.198+ は背景がデフォルトで、fork/同一ターン集約が構造的に空振りする。
同一メッセージ内の並列呼び出しで 3 体の並行性は保たれる（sync にしても失うものは無い＝done ゲート
では council 自体がクリティカルパス）。

### 2. Gotchas 更新（monitor SKILL.md・overseer 向けなので配置はここが正）

- **Gotcha 113（AUTO 項・[2026-06-15] forked 実行空振り）に root cause を追記**: 2.1.198+ では
  背景デフォルト × fork の非永続性で構造的に起きる（モデルの注意力の問題ではない）。回避は
  inline 実行 + 観測者の sync spawn。AUTO 項の手動更新は人間裁量（evolve の「追記のみ」は evolve
  自身の制約であってオーナー編集を禁じない）。
- **新 Gotcha（AUTO-GOTCHAS へ追記・[2026-07-03]）**: 遅延漂着した council レポート（背景 observer
  の通知が後続 phase に届く）は、clean 記録後のツリーに触らず低 severity は improvements.md へ
  退避する（FR-50 指紋の無効化＝意図しない再 council を防ぐ）。

### 3. test/hooks-wiring.sh — 配線ガード test（新規・grep-lib 系）

`hooks/hooks.json` の配線不変条件を assert する恒久ガード（前例: intent-router-removed / FR-51）:

1. hooks.json が **valid JSON**（`jq empty`）
2. `hooks[].hooks[].command` が参照する **script が hooks/ に実在**する（`${CLAUDE_PLUGIN_ROOT}` を
   `$ROOT` に置換して -f を assert。bash 起動なので exec bit は不変条件でない＝assert しない）
3. **matcher にカンマを含まない**（2.1.191 の silent 失敗 class。pipe 区切りが正）
4. zero-match false-pass ガード: hooks.json の存在 + command エントリが 1 件以上あること
5. 検査ロジックの positive control: fixture（カンマ matcher / 存在しない script）で検出→非ゼロを実走
   （FR-51 と同じ「lint が fire しない self-graded 化」防止）

### 4. ROADMAP — stacked slash-skill 干渉の watch note（実装なし）

2.1.199 の stacked slash-skill（最大 5 同時ロード）はプロンプト合成の話で、`/flywheel:add` →
`/flywheel:next` の 1 プロンプト運用が可能になる一方、skill 間干渉の管理が将来課題。ROADMAP の
改善候補に**未着手行として 1 行**残す（今は観測のみ・実装しない）。

## Boundary（触る範囲）

- `skills/monitor/SKILL.md`（Step 2 の sync 明記 + Gotcha 113 追記 + 新 Gotcha 1 件）
- `test/hooks-wiring.sh` 新規 1 本（run-all が自動で拾う・配線変更なし）
- `ROADMAP.md`（FR-53 行 + stacked-skill watch 行）/ README Changelog
- 出荷規約: version bump **v0.8.34**（plugin.json / marketplace.json / README 冒頭）
- 非スコープ: hooks.json / hook 実体の変更（配線は現状正しい）、背景 subagent を活用する継続監視
  等の新機構（ROADMAP 級の別テーマ）、stacked-skill 干渉への実装対応、loop-driver の変更
- polish（simplify/altitude レビュー）で採用した微修正: check_wiring を root 1 引数化 + jq path の
  抽出を 1 回に統合（0 件ガードと実在検査が同じデータを見る＝片更新乖離の構造防止）、規約 assert と
  不変条件 assert の線引きをコメント明記、monitor SKILL.md の sync spawn 指示の消失を grep で観測
  する assert を追加（prompt-level 前提のガード）、host 側 fail-open が residual である旨を
  ROADMAP FR-53 行に明記。loop-driver の指紋不一致 steer 文言改善は非スコープ維持で improvements.md
  へ退避。
- council 採択（drift implementing・observer-behavior）: sync ガードの grep が Gotcha 113 の言及にも
  マッチし Step 2 指示の消失を検知できない穴 → spawn 行に anchor（subagent_type 共起）。あわせて
  Note 級を消化: 消失 / 0 件の fixture 2 系を追加（完了条件 3 の失敗パス実走）、positive control は
  期待メッセージまで assert（expect_broken ヘルパ）。
- 再 council（clean）の Note 消化: sync anchor をマッチ行数 = 1 の assert に強化（完全引用の混入で
  消失検知が無効化される再発 class を loud 化）、matcher 検査 jq のエラーパスを loud 化、README
  Changelog に sync 消失検知の 1 語補完。

## 後方互換・degrade

- SKILL.md の変更は指示の明確化のみで、既存の council 手順・出力 schema は不変。
- hooks-wiring.sh は現配線で緑（カンマ無し・全 script 実在を確認済み）。hooks.json を持たない
  状態は guard 4 で fail（fail-open の無音化こそ検査対象なので、消失は loud に落とすのが正）。

## 完了条件（eval）

```
bash test/run-all.sh
```

exit 0。新テスト `test/hooks-wiring.sh` が満たすべき性質:

1. 現リポの hooks.json で全 assert green（valid JSON / 全 command script 実在 / カンマ matcher ゼロ）。
2. positive control: fixture のカンマ matcher と存在しない script 参照をそれぞれ検出して非ゼロ
   （検査の失敗パスを実走）。
3. hooks.json 消失 / command エントリ 0 件で fail（zero-match false-pass ガード）。
4. 既存 test 全緑（run-all 集約）。

## 検証の落とし穴（前例由来）

- jq の `// empty` と `-e` の exit code 規約に注意（空配列で false-pass しないよう件数を数えて assert）。
- `${CLAUDE_PLUGIN_ROOT}` は literal 文字列として hooks.json に入っている＝shell 展開せず文字列置換で
  `$ROOT` に読み替える。
- テストは bash（`#!/usr/bin/env bash`）・grep-lib.sh を source（副作用なし系）。fixture は mktemp。
- SKILL.md の Gotcha 追記は AUTO-GOTCHAS の cap 5 を超えないよう、Gotcha 113 は**既存項への追記**、
  新規は 1 件のみ（現在 monitor は AUTO 3 件 → 4 件になる）。
