---
name: grill
description: "完成した plan/design を対話で容赦なく詰問し、実装前に穴を潰す。決定木を1枝ずつ降り、各質問に推奨回答を添える。コードで答えが出る点は聞かず自分で調べて埋める。「grill して」「叩いて」「この設計で大丈夫?」「plan を詰めて」「設計を対話レビュー」で発動。※ ゼロから要件を掘り下げるなら deep-interview、非対話で一括批判レポートなら critic。"
argument-hint: "<plan/design path or description to grill>"
allowed-tools: [Read, Glob, Grep, AskUserQuestion, Skill]
effort: medium
---

# Grill - plan/design の対話詰問 (stress-test)

完成した plan/design を容赦なく詰問し、実装前に穴を潰す。`critic`（非対話で一括批判レポートを返す agent）と違い、**1問ずつ対話で決定木を降りる**のが本質。`deep-interview`（ゼロから要件を引き出す）の対極で、こちらは「既にある設計を叩く」。

> **対話前提スキル**: 1 問ずつ詰めるのが本質。AskUserQuestion が使えない環境では「対話モードで /flywheel:grill を実行してください」と案内して終了する。

## Step 0: 前提確認 — 詰める plan/design があること（動的注入）

!`ls plan/design.md plan/requirements.md 2>/dev/null; true`

**grill は「完成度の高い plan/design を叩く」後段スキル。** 対象が無いまま詰問しても空回りする。対象の優先順位:

0. **plan mode 中なら、いま会話で構成している計画そのもの**（plan mode はファイルが書けないので、詰めた結果は ExitPlanMode で提示する計画テキストに反映する。`plan/*.md` への artifact 化は承認時に flywheel の hook がやる。`~/.claude/plans/` の native 計画ファイルも対象になり得る）
1. 上の注入に出た `plan/*.md` → 最優先で Read
2. `$ARGUMENTS` が指すファイル / 設計記述
3. 会話中で直前に固めた設計

**対象が無い / 曖昧なアイデアしか無い場合は grill せず、まず計画を作る側へ誘導する**:

| 状態 | 誘導先 |
|---|---|
| 要件がまだ曖昧 | `/flywheel:deep-interview`（掘り下げ）→ `discovery-council` → `design` |
| 要件はあるが design が無い | `/flywheel:design` |

設計ができてから grill に戻る。**flywheel designing パイプライン上の位置**: deep-interview → discovery-council → design で plan ができた後、実装ゲートが開く前の最終 vetting（grill 合格 → validate-plan → 門が開く）。

## 原則

- **1回に1つの質問**。バッチで聞かない
- **決定木を branch ごとに降りる**: 決定を1つずつ解決し、決定間の依存を順番に潰していく
- **各質問に推奨回答を添える**（「私の推奨は X、理由は〜」）。ユーザーが即断できる形にする
- **self-answer は *事実* に限る**: コードに答えがある（現状の実装・既存パターン・命名規約）ものだけ Glob/Grep/Read で埋める（無駄な往復を減らす）。**判断**（スコープ / トレードオフ / 優先順位 / 命名 / どの案を採るか / 曖昧点の解釈）は**コードに答えが無い → 必ず聞く**。迷ったら聞く側に倒す — これが grill の肝（聞かなすぎ ＞ 聞きすぎ。質問しない grill は本末転倒）
- 共有理解に達するまで relentless に続ける。ただし「もういい / 十分」で打ち切る

## 観点（決定木の枝）

`facets/references/plan-review-checklist.md` を Read し、4 観点（完全性 / 実現可能性 / リスク管理 / 明確性）を決定木の枝として使う。

**5つ目の枝（必須・flywheel 配下では最重要）: 完了条件（eval）**。design.md の「## 完了条件（eval）」を必ず1問は詰める:
- fenced block のコマンドは**実行可能か**（存在しないテストファイルを指していないか）
- **goal 固有か**（プロジェクト全体の test/lint だけなら自動検出と同じ。この機能の done を判定できる形に詰める）
- **合格 = goal 達成と言い切れるか**（緩すぎる条件は空振り done、厳しすぎる条件は永遠に done しない）

## Step 1: 対象の取り込み

動的注入で見つかった `plan/*.md`、または `$ARGUMENTS` の対象を Read。明示・暗黙の**決定点を列挙**する。先に Glob/Grep でコード文脈を埋めておく。

## Step 2: 詰問ループ

最も未解決・最もリスクの高い決定から1問ずつ:
```yaml
AskUserQuestion:
  question: "<決定点への鋭い問い>（推奨: <推奨案> / 理由: <根拠>）"
  options:
    - "<推奨案（Recommended）>"
    - "<代替案>"
    - "自由に記述"
```
- **コードで判明する事項は質問にしない**。調べて「`<file:line>` を見たら X なのでこの枝は解決」と報告して次へ
- 1つ解決したら、それに依存する下流の決定へ降りる

## Step 3: 解決サマリー

詰めた決定を構造化して確認。残った**未解決点・リスク**を明記する。

## Step 4: 反映

- `design.md` があれば、解決した決定の反映（更新）を提案
- 詰め終えたら design.md を更新 → validate-plan が自動で通り実装ゲートが開く（flywheel の implementing へ）。要件レベルの欠落が出たら **`/flywheel:deep-interview`（掘り下げ）or discovery-council に戻す**

## Gotchas

- **対象なしで空回り**: plan/design.md も $ARGUMENTS も無ければ詰問対象が無い。1問だけ「何を grill するか」を確認してから始める。曖昧な要件しか無いなら `/flywheel:deep-interview` に誘導
- **聞きすぎ/聞かなすぎ**: *事実*（コードに答えがある）は先に Glob/Grep/Read で self-answer してから AskUserQuestion。だが *判断*（スコープ / 優先順位 / 命名 / 案の選択 / 曖昧点の解釈）まで self-answer で済ませると「**質問してこない grill**」になり本末転倒。判断は必ず聞く・迷ったら聞く側（実際 plan route で判断まで self-answer して質問が激減した事例あり）
- **critic との混同**: 非対話で一括の批判レポートが欲しいなら `critic` を spawn する。grill は「1問ずつ対話で決定木を降りる」用途。両者は補完（同じことを二重にやらない）
- **詰問が批判で終わる**: grill のゴールは「実装可能な状態に詰める」こと。穴の指摘で止めず、各決定に推奨回答を出して**解決**まで持っていく

<!-- AUTO-GOTCHAS -->
