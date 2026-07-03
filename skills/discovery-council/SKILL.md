---
name: discovery-council
description: "3エージェント（researcher, analyst, scout）による並列要件分析 Council。peer-to-peer で相互検証し requirements.md を確定。「要件を整理して」「要件定義して」「現状分析して」「要件をまとめて」で発動。"
argument-hint: "<feature description>"
allowed-tools: [Agent, TeamCreate, TeamDelete, SendMessage, TaskCreate, TaskUpdate, Read, Write, Edit, AskUserQuestion, Glob, Grep, WebSearch, WebFetch]
effort: high
context: fork
---

# Discovery Council - 並列要件分析

3エージェント（researcher, analyst, scout）が peer-to-peer で相互検証し、requirements.md を確定する。

## 機能

$ARGUMENTS

## プロジェクト状態（動的注入）

### ディレクトリ構造
!`ls -d */ 2>/dev/null || echo "(サブディレクトリなし)"`

### 技術スタック
!`ls package.json pyproject.toml Cargo.toml go.mod Gemfile setup.py requirements.txt 2>/dev/null || echo "(技術スタック検出なし — md+shell 等)"`

## Step 1: チーム作成

```
TeamDelete:
  team_name: "<既存チーム名>"  # エラーが出なければスキップ

TeamCreate:
  team_name: "discovery"
  description: "Discovery Council: 要件分析"
```

## Step 2: 3エージェント同時 spawn

3つのエージェントを同時 spawn:

| エージェント | 役割 | 出力先 |
|-------------|------|--------|
| researcher | 技術調査（既存実装、外部知見） | SendMessage で共有 |
| analyst | 要件分析 → requirements.md 作成 | plan/requirements.md |
| scout | ギャップ分析（漏れ・曖昧点の検出） | SendMessage で共有 |

→ **Agent prompt テンプレートは reference.md を Read して使用**

Council プロトコル: 独立に分析 → SendMessage で相互共有 → 相互検証 → analyst が最終統合

メンバー 3 体は **`run_in_background: false`（同期）で spawn** する（binding fan-out＝同一フローで
集約して requirements.md を確定するため。同一メッセージ内の並列呼び出しで並行性は不変。
binding/advisory の判定基準は ROADMAP「機構メモ」が正）。

メンバーは広い調査 sweep を nested sub-agent（code-explorer / architecture-mapper / convention-scout 等）に委譲できる（FR-26。各 agent 定義の「調査の委譲」参照）。nested の子も binding（メンバーが同一ターンで結論を集約する）なので `run_in_background: false` で spawn する。列挙系の子は `model: haiku`、解釈系は指定省略（継承）。メンバー自身は `model: inherit` で main loop のモデルを継承する。

## Step 3: 曖昧点の確認（スキップ禁止）

Council の報告を集約した後、**曖昧点が残っていれば AskUserQuestion で確認する**。このステップはスキップしてはならない。

```
1. scout の報告から未解決の曖昧点を抽出
2. analyst の requirements.md ドラフトで「仮定」として記録された箇所を抽出
3. 曖昧点があれば → AskUserQuestion で具体的に質問（1回にまとめる）
4. 回答を requirements.md に反映
5. 曖昧点がなければ → そのまま次へ
```

**AskUserQuestion が使えない環境 or critical でない曖昧点の場合**: 曖昧点を `## 仮定` セクションに記録して先に進む。

## Step 4: チーム終了

全エージェントの報告完了後、チームを削除する。

```
TeamDelete
```

## Gotchas

- **researcher の外部検索待ちで council が停滞**: 3 体は同一メッセージ内で並列に sync spawn される（FR-55）ので analyst/scout が researcher を「待つ」ことはないが、researcher 自身が外部検索を掘りすぎると集約が遅れる。researcher の調査は要点に絞らせる（旧記述の `background: true` 非同期運用は 2.1.198 の背景デフォルト化で廃止＝binding fan-out は sync が正）
- **scout が曖昧点を発見しても analyst に伝わらない**: SendMessage の recipient 名を正確に。name が間違っていると silent loss する
- **要件が広すぎてスコープ爆発**: scout が IN/OUT SCOPE を明確にしないまま analyst が全部盛りの requirements.md を書く。scout の分析を待ってから最終化する
- **既存プロジェクトの文脈を無視**: 動的注入でプロジェクト構造は把握済みだが、CLAUDE.md の開発ガイドラインも必ず確認する

<!-- AUTO-GOTCHAS -->

## 出力

plan/requirements.md
