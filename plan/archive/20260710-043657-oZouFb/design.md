# design: ultrawork — 全部 Fable 固定の judge panel スキル/コマンド

## 背景・問題

flywheel の原点となったメタプロンプト「私の目的は〇〇です。これを達成するために最も適した
指示文をあなた自身が設計してください。必要な情報があれば質問してもらっても構いません。
これは難題です。既存の常識にとらわれず、全てのリソースを総動員し、トップレベルの回答を
出してください」のうち、①目的宣言=goal ②指示文の自己設計=design phase ③質問=grill、は
flywheel が実現済みだが、**④「常識にとらわれず全リソース総動員でトップレベルの回答」だけが
未実装**だった（2026-07-09 議論）。eval/monitor ループは「検証済みで正しい」を担保する機構で
あって「複数案から最良を選ぶ」機構ではない。

④の実体は judge panel パターン: 互いに異なる切り口で候補案を並列生成 → 全候補を見比べて
審査 → 勝者に他候補の良い所を接木して統合。これを **戦略・分析系の一発回答**（コード実装で
ない問い）向けの独立コマンドとして実装する。

## 方針（2026-07-09〜10 の会話 + grill で確定）

- **全部 Fable 固定**: Plan（切り口決定）/ Generate（候補生成）/ Judge（審査）/ Synthesize
  （統合）の全 agent 呼び出しに `model: 'fable'` を明示。メインセッションのモデルが何であれ
  （Sonnet 運用のままでも）ultrawork の中身は常に Fable 品質、という保証。subagent 層別
  （v0.8.40: 観測=sonnet / 思考=inherit）に第3の層「判断最大化=fable 固定」を追加する位置づけ。
- **切り口（lens）は動的**: 固定リストにせず、Plan 段の Fable が問いごとに最適な分解を決める
  （「常識にとらわれず」の一部。問いが狭ければ3・広ければ5）。
- **flywheel の状態機械に乗せない**: goal/eval/monitor/backlog を一切触らない一発回答用。
  `.flywheel/` への読み書きゼロ。dormant でも goal 進行中でも呼べる（進行中 goal に影響しない）。
- **規模感（grill 確定）**: 動的3〜5候補 + 審査2体（別視点・全候補を見比べる）+ 統合1体
  = Plan 込みで計7〜9体の Fable。コストが張るため **ユーザーの明示起動限定**
  （`/flywheel:ultrawork` またはユーザーが「ultrawork」と明示したときだけ。Workflow ツールの
  opt-in ポリシーとも整合: skill/command 経由の起動が明示 opt-in に該当する。自発起動は禁止）。
- **回答形式（grill 確定）**: 統合回答は常に会話に直接返す。候補比較表や長大な分析になった
  場合のみ Artifact（私的 web ページ）を併用（実行時の回答規模で判断）。

## 成果物1: skills/ultrawork/SKILL.md（新規・本体）

frontmatter:

```yaml
---
name: ultrawork
description: "戦略・分析系の難問に judge panel（全 Fable）でトップレベルの回答を出す。切り口を動的設計→候補案を並列生成→審査→勝者に接木して統合。計7〜9体の Fable が走る高コストコマンドのため「ultrawork」と明示されたときだけ発動（自発起動禁止）。コード実装は flywheel:start / 通常の依頼へ。"
argument-hint: "<戦略・分析系の問い>"
allowed-tools: [Workflow, Read, Bash, Artifact, TaskOutput]
effort: high
---
```

本文の骨子（overseer=メインセッションへの手順書）:

1. **問いの受領**: `$ARGUMENTS`（無ければ会話から問いを特定）。曖昧すぎる場合（目的・制約・
   前提が読めない）は AskUserQuestion で 1〜2 問だけ絞ってから回す（deep-research の
   「underspecified なら先に聞く」と同じ規律）。
2. **Workflow を1回呼ぶ**: SKILL.md に canonical スクリプトを記載（下記）。問いは `args` で渡す。
3. **結果の提示**: workflow の返り値（final / candidates 要約 / 審査サマリ）を受けて、統合回答を
   会話に直接返す。候補比較や分析が長大なら Artifact を併記。**どの候補が勝ちなぜか・
   接木した要素は何か**を1段落で透明化する（判断過程を隠さない）。
4. **失敗時 degrade**: workflow がエラー/空を返したら、その旨を明示して通常の単発回答に
   フォールバック（無言で普通の回答にすり替えない）。

canonical Workflow スクリプト（SKILL.md 内に記載する設計。要点のみ抜粋）:

```js
export const meta = {
  name: 'ultrawork',
  description: 'Fable judge panel: 動的lens → 並列候補 → 審査2体 → 統合',
  phases: [
    { title: 'Plan', detail: 'Fableが切り口3〜5個を動的設計' },
    { title: 'Generate', detail: '切り口ごとにFableが候補案を並列生成' },
    { title: 'Judge', detail: '審査2体（実行可能性/独創性）が全候補を採点' },
    { title: 'Synthesize', detail: '勝者に他候補の良所を接木して最終回答' },
  ],
}
phase('Plan')
const plan = await agent(`問い: ${args.question}
この問いに対し、互いに本質的に異なるアプローチとなる切り口を3〜5個設計せよ（問いが狭ければ3・広ければ5。表面的な言い換えは不可）。各切り口に name / 発想の核 / この切り口が勝つ条件 を付けること。`,
  { model: 'fable', label: 'plan:lenses', schema: LENSES_SCHEMA })

phase('Generate')
const candidates = (await parallel(plan.lenses.map(l => () =>
  agent(`問い: ${args.question}
あなたの切り口: ${l.name} — ${l.core}
この切り口に全振りした最良の回答案を書け。他の切り口へのバランス配慮は不要（多様性は panel 側で担保する）。結論→根拠→実行手順→リスクの順。`,
    { model: 'fable', label: `gen:${l.name}`, phase: 'Generate' })
))).filter(Boolean)

phase('Judge')  // barrier が正当: 審査は全候補の見比べが本質（cross-item 比較）
const judges = (await parallel(JUDGE_LENSES.map(j => () =>
  agent(`${j.charter}\n問い: ${args.question}\n候補:\n${fmt(candidates)}\n全候補を採点(1-10)し、各候補の「統合時に残すべき要素」を1つずつ挙げよ。`,
    { model: 'fable', label: `judge:${j.name}`, phase: 'Judge', schema: SCORES_SCHEMA })
))).filter(Boolean)

phase('Synthesize')
const final = await agent(`問い: ${args.question}
勝者候補（審査合算1位）: ...\n他候補から接木する要素（審査員の指名分）: ...\n勝者を骨格に、接木要素を統合した最終回答を書け。同点や審査欠落時は自分で全候補を読み比べて骨格を選び、選定理由を明記せよ。`,
  { model: 'fable', label: 'synthesize', phase: 'Synthesize' })
return { final, lens_names, score_summary }
```

- `JUDGE_LENSES` は2体固定: 「実行可能性・リスク・コスト」レンズと「独創性・期待値・
  見落とし」レンズ（審査の多様性は体数でなく視点差で確保）。
- エラー処理（設計判断）: candidates が 0 → workflow は `{error}` を返し skill 側が
  フォールバック。1 のみ → Judge を skip して Synthesize に直行（degrade 明記）。judges が
  全滅 → Synthesize が自分で読み比べて選ぶ（prompt に組み込み済み＝別経路不要）。同点 →
  Synthesize が選定理由付きで裁定。
- スクリプト内で `Date.now()` 等は使わない（Workflow 制約）。

## 成果物2: commands/ultrawork.md（新規・薄いラッパー）

`add.md` 等と同型の frontmatter（description / argument-hint）。本文は「`$ARGUMENTS` を問いとして
`Skill: flywheel:ultrawork` を起動する」薄い導線のみ（手順の実体は SKILL.md に一元化・重複させない）。
`$ARGUMENTS` は FR-40 に倣い single-quote 包みで記載。

## 成果物3: test/ultrawork-skill.sh（新規・構造アサート）

grep-lib ベース（`fail`/`ok`/`$ROOT`・mktemp 副作用なし。FR-51 gotcha-actor-routing と同型）:

1. `skills/ultrawork/SKILL.md` が存在し、frontmatter に `name:` / `description:` /
   `allowed-tools:`（`Workflow` を含む）がある。
2. **全 Fable 不変条件（本 goal の核）**: SKILL.md 内の `agent(` 出現数と `model: 'fable'`
   出現数が一致し、かつ `model: 'sonnet'` / `'haiku'` / `'opus'` が 0 件（判断部分の
   全 Fable 固定が silent に崩れたら CI が落ちる）。
3. description に高コスト明示（「ultrawork」トリガー限定）の文言が含まれる（自発起動禁止の
   契約が消えたら fail）。
4. `commands/ultrawork.md` が存在し frontmatter に description がある。
5. **positive control**（FR-51 前例・self-graded 化防止）: mktemp fixture に
   `agent(` はあるが `model: 'fable'` が無い偽 SKILL.md を作り、検査関数が非ゼロで fail する
   ことを実走 assert。

## Boundary（触る範囲）

- `skills/ultrawork/SKILL.md` 新規 / `commands/ultrawork.md` 新規 / `test/ultrawork-skill.sh` 新規。
- 出荷規約: README Changelog + 機能節（コマンド一覧があれば追記）/ ROADMAP に行を追加
  （「計画・分解の質」epic 配下・状態 ✅）/ version bump **v0.8.43**（plugin.json /
  marketplace.json 2箇所 / README 冒頭）。
- 非スコープ: flywheel 状態機械との統合（design phase を judge panel 化する案は別 goal・
  今回は独立コマンドのみ）、agents/*.md の新規追加（Workflow の agent() は既定 subagent を
  使う＝agent-model-tiering の層別リスト対象外）、実行系の automated テスト（Workflow 実走は
  高コスト・非決定論のため構造アサートに限定）、コード実装系の問いへの適用（skill description
  で明示的に flywheel:start へ誘導）。

## 後方互換・degrade

- 完全な追加のみ（既存ファイルの変更は README/ROADMAP/version の docs 3点だけ）。hook /
  CLI / 状態機械は一切触らない＝既存挙動への回帰リスクはゼロに近い。
- skill/command の反映は次セッション再起動から（CLAUDE.md 規約どおり）。
- Workflow ツールが使えない環境（headless 等で不可の場合）は、skill 手順4の degrade と同じく
  「その旨を明示して通常回答へフォールバック」。

## residual（polish altitude レビューで明示化）

- **Workflow API の実走 smoke は未実施**。canonical スクリプトの API 形状（`agent(prompt,
  {model/label/phase/schema})` / `parallel` / `phase` / `args` / model enum に `fable` / 早期
  `return` / `Date.now` 不使用）は実装セッションが保有する Workflow ツール仕様書と**静的照合
  済み**だが、実走は Fable 7〜9体のコストがかかるため出荷時点では回していない＝**初回の実利用
  が実測を兼ねる**（API 不一致なら Step 4 の明示フォールバックで顕在化する設計。silent には
  壊れない）。smoke を先に回すかはユーザーのコスト判断に委ねる。
- **コピー忠実性はテストで守れない**: テストはファイルを検査するのみで、モデルが Workflow
  呼び出し時にスクリプトを改変する経路は検出不能。Step 2 の「一字一句そのまま」指示と Gotchas
  で prompt-level 対処（機械化するなら将来 hook で Workflow 入力を検査する案があるが、現時点
  では過剰と判断）。

## 完了条件（eval）

```
bash test/run-all.sh
```

exit 0。満たすべき性質:

1. `test/ultrawork-skill.sh` が上記 1〜4 の構造 assert で緑（SKILL.md/command の存在・
   frontmatter・全 Fable 不変条件・高コスト明示）。
2. positive control: `model: 'fable'` 欠落 fixture に対し検査関数が非ゼロを返すことを実走 assert。
3. 既存 test 全緑（run-all 集約。既存ファイルへの変更が docs のみであることの傍証）。

## 検証の落とし穴（前例由来）

- SKILL.md 内のスクリプトはコードブロック内の JS なので、`agent(` の grep は fenced code block
  内も本文も区別せず数える（それで良い＝不変条件は「このファイルに書かれた全 agent 呼び出しが
  fable 指定」）。コメント中の `agent(` 混入で数がズレる場合はコメント側の表記を変える。
- `model: 'fable'` のクォート表記は SKILL.md 内で単一引用符に統一する（テストの grep パターンと
  一致させる。二重引用符との混在で数え漏らさない）。
- description のトリガーは「ultrawork」に絞る（「難問」「戦略」等の一般語で誤発動すると
  7〜9体の Fable が意図せず走る＝コスト事故。skill-eval の観点で最小トリガー）。
