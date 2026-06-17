---
name: design
description: "designer エージェントによるアーキテクチャ設計。requirements.md を基に design.md を作成。「設計して」「アーキテクチャ設計して」「アーキテクチャを考えて」「設計書を作って」で発動。"
argument-hint: ""
allowed-tools: [Agent, Read, Write, Glob, Grep, WebSearch, WebFetch, AskUserQuestion]
effort: high
---

# Design - アーキテクチャ設計

requirements.md を基に designer エージェントがアーキテクチャ設計書を作成する。

## 前提

plan/requirements.md が存在すること。なければ「先に /discovery-council で要件定義を行ってください」と案内する。

## Step 1: designer spawn

```
Agent:
  subagent_type: "flywheel:designer"
  name: "designer"
  description: "アーキテクチャ設計"
  prompt: |
    ## エージェント定義
    agents/designer.md の指示に従ってください。

    ## コンテキスト
    - タスク: plan/requirements.md を基にアーキテクチャ設計書を作成

    ## 入力
    - plan/requirements.md
    - requirements.md に `## 既知の不足` セクションがある場合、設計でカバーできる不足は補完し、カバーできないものは design.md の `## 既知の不足` に引き継ぐ

    ## 完了
    - 設計書の出力が完了したらその旨を報告

    ## 出力
    - plan/design.md に設計書を出力
    - 設計書に **## Tasks** セクションを含める（実装を独立検証可能な単位に分解）。各 task に
      `Boundary:`（触るファイル群＝task 境界）/ `Depends:`（前提 task）/ `Done:`（その task の eval）を明記。
      task は恣意的な数でなく design の File Structure Plan（どのファイルを作る/触るか）から導く。
      異なる task の Boundary が重なるなら統合する（Boundary の重複は分割ミスのサイン）。
```

> **foreground spawn**: designer の完了を待ってから制御を返す。background spawn しないこと。

## 出力

plan/design.md（**## Tasks** セクション付き — 下記の型）

### Tasks セクションの型（task 分解の型）

実装を「独立に検証できる単位」に構造的に割る。恣意的な phase 数でなく、design の File Structure Plan
（どのファイルを作る/触るか）から境界を導く（cc-sdd の Boundary/Depends 由来・参考程度）。

- **Boundary**: その task が触るファイル群（= task の境界）。**異なる task の Boundary が重なるなら統合する**
  （同じファイルを2 task が触るのは分割ミス）。
- **Depends**: 前提 task（DAG。独立なら並列・adopt chain で逐次起動できる）。
- **Done**: その task が緑になる eval（独立に検証できる単位であることの担保）。

書式の例:

    ## Tasks
    - T1 <何を作る>  | Boundary: foo.py, bar.py | Depends: -  | Done: <その task の eval>
    - T2 <何を作る>  | Boundary: api/baz.py      | Depends: T1 | Done: <その task の eval>

割った task は `flywheel add --adopt "<task>"` で backlog に積み、`flywheel next` で逐次 adopt 起動すると
掘り直さず結晶化で回せる（adopt chain）。

## Gotchas

- **requirements.md 無しで spawn しない**: 前提が無いと designer が空想で設計し、下流のタスク分解・実装がずれる。無ければ `discovery-council` へ誘導して終了する
- **background spawn 禁止**: designer は foreground で完了を待つ。background にすると design.md 未完成のまま grill / validate-plan に進んでしまう
- **`## 既知の不足` の引き継ぎ漏れ**: requirements.md の既知の不足を design.md に反映/引き継がないと、grill / eval まで漏れが顕在化しない
- **軽微な設計変更で毎回 spawn しない**: designer は opus/high でトークンが重い。1 コンポーネントの微修正なら design.md を直接 Edit する方が速い
- **Tasks は Boundary から割る・数で割らない**: 「phase1-5」と数で分けず File Structure Plan のファイル境界で割る。異なる task の Boundary が重なるなら統合（同一ファイルを2 task が触るのは分割ミス）。各 task が独立した Done(eval) を持てないなら割り方が粗いサイン（cc-sdd 由来の型）

<!-- AUTO-GOTCHAS -->
