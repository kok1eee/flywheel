---
description: goal を軽量 grill で練ってから backlog に正式 phase として積む（雑な add を防ぐ）。複数 phase を積んで /flywheel:next で逐次実行。
argument-hint: "\"<phase の概要>\""
---

`$ARGUMENTS` を **正式な phase として backlog に積みます**。`adopt` は掘らない（結晶化）ので、雑なまま積むと next→design→実装に直行します。それを防ぐため、**積む前に軽量 grill で3点だけ詰めてください**。

引数なしで呼ばれたときは現在の backlog を表示して終了:

<!-- $ARGUMENTS は single-quote 包みでシェル解釈から保護（FR-40）。literal ' を含むと壊れる＝稀・bulletproof は非スコープ -->
!`[ -z '$ARGUMENTS' ] && "${CLAUDE_PLUGIN_ROOT}/bin/flywheel" list || true`

## 手順（引数があるとき）

1. **軽量 grill — AskUserQuestion で1問ずつ・3点だけ**。self-answer してよいのは *事実*（コードに答えがある）だけ。*判断*（この phase の Done/Boundary の決定・優先順位・曖昧点の解釈）はコードに答えが無いので**必ず聞く**（迷ったら聞く側）。`$ARGUMENTS` について、調べれば分かる事実は Glob/Grep/Read で埋め、判断は1問ずつ（推奨案を添えて）確認する:
   - **Done（eval）**: この phase が緑になる合否コマンドは何か（done を機械判定する形。曖昧なら「何が満たされたら完了か」を詰める）
   - **Boundary**: 触るファイル群（task 境界。既存 phase / 他の積んだ phase と Boundary が重ならないか＝重なるなら統合）
   - **依存・曖昧点**: 前提となる phase はあるか / まだ未確定の点はないか

   フル grill（decision tree を枝の先まで）はしない。全体設計レベルの掘りは `/flywheel:start` か plan mode 側の役割。ここは「雑さを消す3点」に留める。

2. 3点が固まったら backlog に積む（goal は練れた1行に。Done は `--eval`、Boundary/曖昧点は `--notes` へ）:

   ```
   "${CLAUDE_PLUGIN_ROOT}/bin/flywheel" add --adopt --eval "<Done コマンド>" --notes "<Boundary / 残った曖昧点>" "<練れた phase goal>"
   ```

   これを Bash で実行する（`--notes` は `next` 起動時に `state.notes` へ引き継がれ、design.md を書く種になる＝別セッションでも揮発しない）。

3. 複数 phase を続けて積むなら 1〜2 を繰り返し、最後に **`/flywheel:next`** で先頭から逐次起動する。

積んだ一覧（引数なしの `/flywheel:add` = `flywheel list`）には各行に `[adopt]/[start]` と `[notes ✓]` が出ます。
