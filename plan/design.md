# FR-34: verification → monitor 統合（self-graded ゲートの撤去）

## 背景・問題

`verification`（FR-32）は eval が薄い（`eval_src=auto`）goal で done 前に挙動エビデンス確認を要求する **self-graded ゲート**。loop-driver が `Skill: flywheel:verification` 実行 + `verify-set clean` を steer するが、`verify-set clean` は evidence 省略可・非記録のため、モデルは skill を回さず**自己申告で素通り**できる。

実測（2026-06-18）: `steer:verification` 9 回に対し `flywheel:verification` skill 起動は **0 回**（skill-logger が全 skill を記録するのに CSV に皆無）。空通過は本物。

HOTL（human on the loop）方向では「人間が見ていなくても信用できる検証」が要る。self-graded ゲートはその弱点 → **独立検証に一本化**する。

## 方針（ユーザー合意済み）

done を閉める判定 gate を **eval（客観 exit code）と monitor（独立 council）の2つだけ**にする。verification の関心事は次のように振り分ける:

- **「テスト/実装が意味あるか」（静的判定）** → monitor の `observer-behavior` レンズ（既に独立で存在）。
- **「実際に動くか」（実行）** → monitor の **overseer が smoke を実行**し、出力を Read-only 観測者に判定させる（動かすのは Bash を持つ overseer・判定は独立観測者＝自己申告でない／観測者に Bash は持たせない＝過去の state 汚染事故を回避）。
- **薄い eval の runnable goal** → 「runtime smoke を eval（`set-eval` / design 完了条件）に足せ」を monitor の drift memo 経由で促す（可能なら客観 eval に昇格）。

結果: self-graded な `verify-set` ゲートは撤去。loop-driver は単純化（gate が1つ減る）。

## 変更詳細

### 1. `hooks/loop-driver.sh`（FR-32 ゲート撤去・loop が縮む）
- `vcap` / `verification_bump()`（L55-61）を削除。
- `mstatus == "clean"` ブロック内の verification `if`（L185-198）を削除し、monitor clean → そのまま done へ進む。
- done 経路の `fw_set_json verification null; fw_set_json verification_attempts 0`（L202）と、eval-fail クリーンアップの同2行（L256-257）を削除。
- `fw_log_usage "steer:verification"` も消える（steer 自体が無くなる）。

### 2. `skills/monitor/SKILL.md`（独立検証の受け皿に拡張）
- `observer-behavior` レンズの charter を拡張: 「緑テストが要件パスを検証してるか（静的）」に加え、**「runnable な変更なら runtime エビデンスがあるか。静的テストしか無い runnable 変更は impl-drift として『eval に runtime smoke を足せ』を memo」**。
- 新ステップ（Step 2 の前）: **overseer の smoke 実行（条件付き）**。変更が runnable surface（web/server/CLI/UI）に触れ、かつ eval が薄い（`eval_src=auto` で挙動を起動していない）ときだけ、overseer が `Skill: verification` の「挙動検証」手順で smoke を実行し、エビデンス（出力/スクショ/レスポンス）をスクラッチに退避 → path で `observer-behavior` に渡す。docs/純ロジック / thick-eval（eval が既に挙動を走らせている）なら skip。観測者は従来どおり Read-only。

### 3. `skills/verification/SKILL.md`（gate から外し、汎用規律として残す）
- 「証拠なき成功宣言は不正」「挙動検証（Skill: run / webwright）」の中身は価値があるので**残す**（任意起動の汎用規律）。
- 「flywheel の eval ゲートとの関係」節から **FR-32 ゲート役（verify-set・done 前ブロック）の記述を削除**し、「monitor の overseer がこの手順で挙動エビデンスを取る」旨に置換。standalone gate ではなくなった、と明記。

### 4. `bin/flywheel`（verify-set 撤去）
- usage L34-35 と `verify-set)` case（L194-205）を削除。
- L225 のコメント「set-eval/monitor-set/verify-set も非記録」から verify-set を除く。
- `go)` の thick-eval 判定（L231-233）と `fw_eval_is_thin` は**温存**（verification とは無関係）。

### 5. `hooks/lib/common.sh`
- `fw_eval_is_thin()`（L361）は `go` が使うので**温存**。L360 のコメントから「verification ゲート」言及を除き「go の thick-eval 判定」に直す。

### 6. 小修正
- `agents/drift-observer.md` の description「完了前の自己検証は verification」を実態（verification は gate でなく汎用規律）に微修正。
- `skills/guide/SKILL.md` L67 の `/flywheel:verification` 記述を「汎用の自己検証（gate ではない）」に微修正。

### 7. ドキュメント
- README: changelog に 0.8.15 追加、ヘッダ version、`FLYWHEEL_VERIFY_CAP` 環境変数（撤去なら表から削除）。
- ROADMAP: HOTL epic の verification 行を ✅ に。
- version 0.8.14 → 0.8.15（plugin.json / marketplace.json×2）。

## 完了条件（eval）

```
bash -n hooks/loop-driver.sh && bash -n bin/flywheel \
  && ! grep -q 'verify-set\|verification_bump\|steer:verification' hooks/loop-driver.sh bin/flywheel \
  && grep -q 'fw_eval_is_thin' bin/flywheel \
  && bash test/adopt-chain.sh \
  && bash test/verification-merge.sh
```

新規 `test/verification-merge.sh`（mktemp・live state 非汚染）:
- **薄 eval + monitor clean → done**: `eval_src=auto` で monitor=clean をセット → loop-driver 実行 → verification steer が出ず（exit 0・phase=done）、backlog 空なら done で止まる。
- **回帰**: 既存 `test/adopt-chain.sh` が引き続き全 PASS（monitor clean → done → chain の経路が壊れていない）。

## 非スコープ
- start 経路 auto-chain の「調査自動 + grill-me」化（HOTL epic の次フェーズ・別 goal）。
- monitor overseer の smoke 自動化を超えた runtime 検証フレームワーク（Skill: run/webwright への委譲のまま）。
- `fw_eval_is_thin` のロジック変更（go 用に温存）。
