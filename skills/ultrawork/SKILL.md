---
name: ultrawork
description: "戦略・分析系の難問に judge panel（全 Opus 4.8）でトップレベルの回答を出す。切り口を動的設計→候補案を並列生成→審査→勝者に接木して統合。計7〜9体の Opus が走る高コストコマンドのため「ultrawork」と明示されたときだけ発動（自発起動禁止）。コード実装の依頼は対象外＝flywheel:start / 通常の依頼へ。"
argument-hint: "<戦略・分析系の問い>"
allowed-tools: [Workflow, Read, Bash, Artifact, TaskOutput, AskUserQuestion]
effort: high
---

# ultrawork — 全 Opus 4.8 judge panel（トップレベル回答の合成）

**「既存の常識にとらわれず、全てのリソースを総動員し、トップレベルの回答を出す」を機構化する。**
一本道の回答ではなく、互いに異なる切り口の候補案を並列に立て、審査で殴り合わせ、勝者に他候補の
良い所を接木して統合する（judge panel）。中身は**全部 Opus 4.8 固定**——メインセッションのモデルが
何であれ（Sonnet 運用のままでも）、このコマンドの思考品質は常に可用な最強モデル（Opus 4.8）。

- **対象**: 戦略・分析・意思決定系の問い（例: 事業方針、アーキテクチャ選定の考え方、優先順位づけ）。
- **対象外**: コード実装（flywheel:start へ）・単純な事実調べ（通常の依頼で足りる）。
- **flywheel の状態機械（goal/eval/monitor/backlog）には一切触らない**。dormant でも goal 進行中
  でも呼べる一発回答用（`.flywheel/` の読み書きゼロ）。
- **起動条件**: ユーザーが「ultrawork」と明示したとき（`/flywheel:ultrawork` またはその旨の発話）
  だけ。7〜9体の Opus が走る高コスト動作なので、問いが難しそうという自己判断で勝手に回さない。
  このスキル/コマンドの起動自体が Workflow ツールの明示 opt-in に該当する。

## Step 1: 問いの受領

`$ARGUMENTS` を問いとする（無ければ直近の会話から問いを特定する）。目的・制約・前提が読めない
ほど曖昧な場合だけ、AskUserQuestion で 1〜2 問に絞って確認してから回す（質問攻めにしない。
判断材料が揃っているなら聞かずに進む）。

## Step 2: Workflow を1回呼ぶ

以下の canonical スクリプトを `Workflow` ツールに `script` として**一字一句そのまま**渡し、
`args` に `{ "question": "<問い全文>" }` を渡す。コピー時の要約・省略・言い換え・整形は禁止
——特に opus 指定を1つでも落とすと「常に Opus 品質」の保証が silent に消える（テストは
ファイルしか見ないため、呼び出し時の改変は検出できない）。

```js
export const meta = {
  name: 'ultrawork',
  description: 'Opus judge panel: 動的lens → 並列候補 → 審査2体 → 統合',
  phases: [
    { title: 'Plan', detail: 'Opusが切り口3〜5個を動的設計' },
    { title: 'Generate', detail: '切り口ごとにOpusが候補案を並列生成' },
    { title: 'Judge', detail: '審査2体（実行可能性/独創性）が全候補を採点' },
    { title: 'Synthesize', detail: '勝者に他候補の良所を接木して最終回答' },
  ],
}

const q = args.question
const LENSES_SCHEMA = {
  type: 'object', required: ['lenses'],
  properties: { lenses: { type: 'array', minItems: 3, maxItems: 5, items: {
    type: 'object', required: ['name', 'core', 'wins_if'],
    properties: { name: { type: 'string' }, core: { type: 'string' }, wins_if: { type: 'string' } } } } },
}
const SCORES_SCHEMA = {
  type: 'object', required: ['scores'],
  properties: { scores: { type: 'array', items: {
    type: 'object', required: ['index', 'score', 'keep'],
    properties: { index: { type: 'integer' }, score: { type: 'integer' }, keep: { type: 'string' }, critique: { type: 'string' } } } } },
}

phase('Plan')
const plan = await agent(`問い: ${q}

この問いに対し、互いに本質的に異なるアプローチとなる切り口（lens）を3〜5個設計してください。
問いが狭ければ3個・広ければ5個。表面的な言い換えや粒度違いは不可——前提・価値観・戦い方が
異なるものを選ぶこと。既存の常識にとらわれない切り口を最低1つ含めること。
各切り口: name（短い名前）/ core（発想の核・1〜2文）/ wins_if（この切り口が勝つ条件）。`,
  { model: 'opus', label: 'plan:lenses', schema: LENSES_SCHEMA })

phase('Generate')
const gens = await parallel(plan.lenses.map(l => () =>
  agent(`問い: ${q}

あなたの切り口: ${l.name} — ${l.core}

この切り口に全振りした最良の回答案を書いてください。他の切り口とのバランス配慮は不要
（多様性は panel 側で担保する）。構成: 結論 → 根拠 → 実行手順 → リスクと対処。
自分の切り口の弱点も最後に1段落で自己申告すること。`,
    { model: 'opus', label: 'gen:' + l.name, phase: 'Generate' })
    .then(text => ({ lens: l.name, text }))
))
const candidates = gens.filter(Boolean)
if (candidates.length === 0) {
  return { error: '候補生成が全滅（agent エラー）。通常回答へフォールバックせよ。' }
}

const listing = candidates.map((c, i) => `【候補${i}: ${c.lens}】\n${c.text}`).join('\n\n----\n\n')

let winner = 0
let grafts = []
let judgedOk = false
let scoreSummary = 'judge skip（候補1件のみ）'
if (candidates.length >= 2) {
  phase('Judge')  // barrier が正当: 審査は全候補の見比べ（cross-item 比較）が本質
  const JUDGE_LENSES = [
    { name: 'feasibility', charter: 'あなたは「実行可能性・リスク・コスト」の審査員。絵に描いた餅・隠れた前提・実行時の破綻点を暴き、現実に完遂できる案を高く評価する。' },
    { name: 'upside', charter: 'あなたは「独創性・期待値・見落とし」の審査員。無難なだけの案を低く評価し、非自明な洞察・高い期待値・他候補が見落とした機会を高く評価する。' },
  ]
  const judges = (await parallel(JUDGE_LENSES.map(j => () =>
    agent(`${j.charter}

問い: ${q}

${listing}

全候補を1〜10で採点し、各候補について「最終回答に接木すべき最良の要素」を keep として
1つずつ挙げてください（勝者以外の候補からも必ず拾う）。index は候補番号。`,
      { model: 'opus', label: 'judge:' + j.name, phase: 'Judge', schema: SCORES_SCHEMA })
  ))).filter(Boolean)

  if (judges.length > 0) {
    judgedOk = true
    const totals = candidates.map((c, i) => judges.reduce((s, j) => {
      const row = (j.scores || []).find(r => r.index === i)
      return s + (row ? row.score : 0)
    }, 0))
    winner = totals.indexOf(Math.max(...totals))
    grafts = judges.flatMap(j => (j.scores || [])
      .filter(r => r.index !== winner && r.keep)
      .map(r => `候補${r.index}より: ${r.keep}`))
    scoreSummary = candidates.map((c, i) => `${c.lens}=${totals[i]}`).join(' / ')
  } else {
    scoreSummary = 'judge 全滅 → Synthesize が自力で選定'
  }
}

phase('Synthesize')
// 審査が機能したときは勝者全文+接木要素だけ渡す（負け候補全文の再送を避けて入力を圧縮。
// 接木材料は Judge が keep として抽出済み）。審査欠落時のみ全候補を渡して自力選定させる。
const material = judgedOk
  ? `勝者候補（全文）:\n【${candidates[winner].lens}】\n${candidates[winner].text}`
  : listing
const final = await agent(`問い: ${q}

${material}

審査結果: ${scoreSummary}
勝者候補: 候補${winner}（${candidates[winner].lens}）
接木する要素:
${grafts.length ? grafts.join('\n') : '（審査の指名なし。提示された候補から自分で最良要素を拾うこと）'}

勝者候補を骨格に、接木要素を統合した最終回答を書いてください。審査が同点・欠落の場合は
自分で全候補を読み比べて骨格を選び、選定理由を明記。最後に「どの切り口を骨格にし、
何を接木したか」を1段落で透明化すること。`,
  { model: 'opus', label: 'synthesize' })

return {
  final,
  lenses: candidates.map(c => c.lens),
  winner: candidates[winner].lens,
  score_summary: scoreSummary,
}
```

Workflow は background で走り task ID が返る。完了通知（task-notification）を受けてから
Step 3 へ（必要なら TaskOutput で結果を取得）。

## Step 3: 結果の提示

- 統合回答（`final`）を**会話に直接**返す。冒頭に結論、続けて本文。
- **判断過程を隠さない**: どの切り口が候補に立ち（`lenses`）、どれが勝ち（`winner` /
  `score_summary`）、何を接木したかを1段落で透明化する。
- 候補比較表や長大な分析になった場合**のみ** Artifact（私的 web ページ）を併記する
  （軽い問いには作らない。判断は回答規模次第）。

## Step 4: 失敗時 degrade

Workflow がエラー / `error` フィールド / 空を返したら、**その旨を明示して**通常の単発回答に
フォールバックする（無言で普通の回答にすり替えない——panel が回らなかった事実はユーザーの
コスト判断に関わる情報）。

## Gotchas

- **自発起動しない**: 明示トリガー（「ultrawork」）限定（冒頭の起動条件参照）。高コストの
  opt-in はユーザーの権利。
- **コード実装に使わない**: 実装は eval/monitor ゲートで品質担保するのが flywheel の設計。
  ultrawork は検証ループの無い一発回答であり、コードには不適。実装依頼が来たら
  flywheel:start / adopt 経路へ誘導する。
- **opus 指定を1つでも欠かさない**: スクリプト編集時に agent 呼び出しを足すなら必ず model を
  opus に明示。`test/ultrawork-skill.sh` が agent 呼び出し数と opus 指定数の**集計一致**を CI で
  assert している（ペア照合ではない＝コメント内の紛れ込みで相殺され得るので、編集時は数だけ
  信じず diff を目視すること）。fable は退役済みモデルとして**混入検査の対象**（残骸・巻き戻りを
  CI が fail する）。

<!-- AUTO-GOTCHAS -->
<!-- 以下は実行経験から自動追記。不要なら削除してよい -->
