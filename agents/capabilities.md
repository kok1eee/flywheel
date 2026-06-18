---
name: capabilities
description: エージェント能力サマリーのリファレンスドキュメント。各スキル／メインループからエージェント選択の材料として Read で参照される。自動起動せず、選択材料としてのみ使用する。
---

# Agent Capabilities

エージェント能力のサマリー。スキル／メインループでのエージェント選択、および小タスクでのキーワードマッチに使用。

> タスク分解は専用エージェント（旧 `planner`）ではなく、**designer が `design.md` の `## Tasks`(Boundary/Depends/Done) として書く**（v0.8.10〜）。ネイティブ `TaskCreate` は flywheel のコア loop では使わない（完了状態が eval ゲートと並走する二重管理を避けるため。完了判定は eval の exit code 一本。詳細は auto-memory `flywheel-eval-is-sole-done-gate`）。`TaskCreate/TaskUpdate` を使うのは discovery-council 等、自分の作業管理に閉じる範囲のみ。

## エージェントの原則

エージェントは**コンテキストファイアウォール**。大量の情報を処理し、要約だけをメインスレッドに返す。

### やるべきこと
- **単一目的** — 1つのエージェントに1つの仕事
- **コンテキスト削減** — 処理した情報の10-20%だけ返す
- **Input → Processing → Output** を明確に定義
- **peer-to-peer 連携** — 関連する teammate 同士でメッセージ交換

### やってはいけないこと
- ❌ 大量の生出力を返す（要約して返す）

---

## ディスパッチ戦略

タスク規模に応じて実行方式を自動選択する。**判断に迷ったら Agent Teams を選ぶ。**

### 判断フロー

```
タスクを受け取る
  │
  ├─ Glob/Grep 1回で答えが出る？ ──── YES ──→ 【S】直接実行
  │
  ├─ 判断・分析が必要？ ──────────── YES ──→ 【M】Agent Teams (2-3 teammates)
  │
  └─ 複数工程・並列作業？ ─────────── YES ──→ 【L】Agent Teams (5+ teammates)
```

### 規模別ガイド

| 規模 | 判断基準 | 方式 | 例 |
|------|---------|------|-----|
| **S** | ファイル特定、grep 1回、単純な事実確認 | 直接実行 | 「このクラスどこにある？」 |
| **M** | 調査+判断、レビュー、デバッグ、設計相談 | Agent Teams (2-3) | 「このバグの原因を調べて」「レビューして」 |
| **L** | 複数フェーズ、並列実装、計画全体 | Agent Teams (5+) | 「認証機能を実装して」「並列で作って」 |

### 方式の詳細

**【S】直接実行** — エージェントを使わない
```
Glob/Grep/Read で直接回答
```

**【M】Agent Teams** — 議論で質を上げる
```
TeamCreate → team_name で作成
  → Agent ツールで 2-3 teammates spawn（name + team_name 必須）
  → SendMessage で互いの発見を共有・議論（recipient = name）
  → 結果を統合
  → TeamDelete で解散
```

例: デバッグなら competing hypotheses パターン
```
debugger-1: 「認証トークンの期限切れが原因」
debugger-2: 「いや、CORS 設定の問題。トークンは正常」
→ 議論して真因を特定
```

**【L】Agent Teams + タスクリスト** — 大規模並列
```
TeamCreate → team_name で作成
  → Agent ツールで 5+ teammates spawn（name + team_name 必須）
  → TaskCreate で全タスク登録
  → teammates が自律的にクレーム・実行
  → SendMessage で peer-to-peer 調整（recipient = name）
  → TaskUpdate で完了（ネイティブタスクリスト）
  → TeamDelete で解散
```

### モデル選択（sub-agent を切るとき・FR-26）

既定は**指定省略 = 継承**（main loop / 親 agent のモデルがそのまま使われる）。降格は確信があるときだけ:

| タスク性質 | モデル | 例 |
|---|---|---|
| 列挙系（機械的 sweep） | `haiku` を明示 | ファイル探索、出現数カウント、命名規則の抽出（convention-scout） |
| 解釈系（気づけるかが勝負） | 省略（継承） | なぜこう設計されているか、隠れた制約、反証、要件発見 |
| 判断層（統合・確定） | agent 定義が `inherit` | analyst / scout / researcher / critic / designer |

- 安い子の失敗モードは「**重要なディテールを要約で潰す**」。要件発見の文脈では見落とした制約が design に伝播して一番高くつく——迷ったら継承
- **staged escalation**: 子の報告が期待と食い違う / 薄すぎる → 同じ調査を継承モデルで撃ち直す
- 子の prompt には**出力契約**（何を・どの形式で返したら完了か）を必ず書く（「spec が done を定義する」の子への適用）
- nested の深さは最大5階層・depth 5 の background 子には Agent ツールが渡らない（Claude Code 2.1.172+）。flywheel の想定は main → council メンバー → sweep の子の2階層
- 数ファイルで済む調査は委譲しない（spawn のオーバーヘッドの方が高い）

### 複数エージェントの相乗効果パターン

| パターン | 組み合わせ | 効果 |
|---------|-----------|------|
| **セキュリティ + 整合性** | security-reviewer + critic | セキュリティと計画整合性を同時にチェック |
| **仮説競合** | debugger × 2-3 | 異なる仮説を並列検証、偏りを排除 |
| **多角調査** | researcher + analyst + scout | コード・外部情報・要件を同時に調査 |
| **設計批評** | designer + critic | 設計しながらリアルタイムでレビュー |
| **コードレビュー (correctness bug)** | `Skill: code-review` (built-in) | bug を effort 別で検出・報告（`--comment` で GitHub PR コメント可）。無印は検出のみ → finding は main agent が修正。`--fix` で完全 bug-hunting + 自動適用（v2.1.152 で復活）。**v2.1.154 から `/simplify` は cleanup-only (reuse/simplification/efficiency/altitude) + fix に divergence** で別物 |

---

## 使用方法

### 小タスク（plan なし）
ユーザーリクエストのキーワードでマッチ → ディスパッチ戦略で規模判定 → 適切な方式で実行

### plan あり
得意分野・使用場面を参照 → タスクに適したエージェントを teammate として spawn

---

## エージェント一覧

| エージェント | 得意分野 | いつ使うか | 呼び出し方 | キーワード |
|-------------|---------|-----------|-----------|-----------|
| **analyst** | 現状分析・要件整理 | 新機能の計画前、要件定義作成 | `/discovery-council` | 要件, 分析, 調査, requirements |
| **designer** | アーキテクチャ設計＋タスク分解 | 要件定義完成後、実装の前 | `/design` | 設計, アーキテクチャ, design, タスク, 分解 |
| **scout** | ギャップ・スコープ分析 | 要件定義後、漏れや曖昧点の確認 | `/discovery-council` | 漏れ, 曖昧, スコープ, gaps |
| **critic** | 計画整合性チェック | 実装後、計画・設計との乖離確認 | `/quality-gate` / ユーザー直接 | 検証, 妥当性, リスク, validate, 整合性 |
| **debugger** | 体系的デバッグ | バグ・テスト失敗・予期しない動作、sisyphus の3エージェント方式 | ユーザー直接 / sisyphus | バグ, エラー, デバッグ, bug, error |
| **researcher** | コードベース探索・外部調査 | ファイル探索、構造把握、API仕様確認 | `/discovery-council` / ユーザー直接 | 探索, どこ, 構造, 調べて, 使い方, ベストプラクティス |
| **security-reviewer** | セキュリティチェック | 外部入力処理、認証実装の変更後 | `/quality-gate` | セキュリティ, 脆弱性, security |

> **コードレビュー (correctness bug 検出)** は Claude Code の built-in `Skill: code-review` に一任（effort level 指定可）。旧 `code-reviewer` agent は v0.58.0 で削除。cleanup-and-fix は v2.1.147 で一旦削除 → v2.1.152 で `--fix` 復活 → **v2.1.154 で `/simplify` と `/code-review --fix` が divergence**: `/code-review --fix` = 完全 bug-hunting + 自動 fix、`/simplify` = cleanup-only (reuse/simplification/efficiency/altitude) + fix。無印は検出のみで finding は main agent が反映、bug 系は `--fix` / 軽い整理は `/simplify`。format / style は lint で補完。

---

## カテゴリ別

### 分析・調査系（READ のみ）

| エージェント | Input | Processing | Output | Memory 蓄積 |
|-------------|-------|------------|--------|------------|
| analyst | コードベース、ユーザー要求 | 構造分析、要件抽出 | requirements.md | 制約・前提条件、要件パターン |
| researcher | ファイルパターン、技術キーワード | Glob/Grep + Web検索 | 探索結果、調査レポート | 構造マップ、技術選定の根拠、API の注意点 |
| scout | requirements.md | スコープ確認、ギャップ分析 | IN/OUT SCOPE + 質問リスト | 曖昧性パターン、エッジケース、critic クロスリード |

### 設計・計画系（READ のみ）

| エージェント | Input | Processing | Output | Memory 蓄積 |
|-------------|-------|------------|--------|------------|
| designer | requirements.md | アーキテクチャ設計＋タスク分解（依存関係整理） | design.md（`## Tasks` Boundary/Depends/Done を含む） | ADR の要約、設計パターン適用実績、タスク粒度基準 |
| critic | requirements + design + tasks | 妥当性検証 | レビューレポート | レビューの落とし穴、リスク評価精度、Calibration Loop |

### 実装・デバッグ系（WRITE 可）

| エージェント | Input | Processing | Output | Memory 蓄積 |
|-------------|-------|------------|--------|------------|
| debugger | バグの症状 / Verifier の報告 | 先入観なしの根本原因調査 → 修正 | デバッグレポート + 修正コード | バグパターン、修正の副作用 |

### 品質系

| エージェント | Input | Processing | Output | Memory 蓄積 |
|-------------|-------|------------|--------|------------|
| security-reviewer | diff、変更コード | OWASP Top 10 チェック | 脆弱性レポート | 脅威モデル、セキュリティ要件、Calibration Loop |

> **コードレビュー一般** (correctness bug 検出) は built-in `Skill: code-review` を使う（quality-gate skill が自動で呼び出し、findings は main agent が修正）。`security-reviewer` + `critic` は条件付き spawn（security 関連変更あり / requirements.md ありの時のみ）。

---

## フロー別のエージェント構成

### 計画フロー（/flywheel:sisyphus）

```
Phase 1: Discovery Council（同時 spawn + peer-to-peer）
  researcher ◄──► analyst ◄──► scout

Phase 2-3: 設計
  designer（design.md に `## Tasks`(Boundary/Depends/Done) で分解まで含む）
```

### レビューフロー（/flywheel:quality-gate）

```
1. Skill: code-review (built-in) — correctness bug 検出 → main agent が finding を修正（`--fix` で自動適用も可、v2.1.152 復活）
2. lint + ty (静的解析、Monitor で並列)
3. 条件付き Council:
     security 関連変更あり → security-reviewer
     plan/requirements.md あり → critic + 範囲整合性検証
     両方なし → スキップ
```

### ユーザー直接呼び出し

```
researcher — コードベース探索 + 外部ドキュメント調査
debugger   — バグの根本原因調査 → 修正
```

---

## 任意の外部 companion（コード探索のトークン効率化）

`code-explorer` / `architecture-mapper` / built-in `Explore` は grep / glob / Read でコードベースを探索するためトークンを消費する。外部 MCP **[codegraph](https://github.com/colbymchenry/codegraph)**（100% ローカル・自己完結・API キー不要）を併用すると、事前インデックス化したコード知識グラフを `codegraph_context` / `codegraph_trace` 等で直接クエリでき、観測ベンチで **トークン -57% / ツール呼び出し -71%** の削減。Progressive Disclosure / context 効率の方針と整合する。

- o-m-cc の**依存ではない**（任意導入。Lightweight 原則は維持）。インストールすると `~/.claude/settings.json` に自動登録される
- 補完関係: codegraph は「コード構造の事前インデックス探索」、o-m-cc の探索 agent は「探索結果を踏まえた分析・判断」。codegraph で位置特定 → agent が分析、という分業が効く

---

## 詳細ファイル

各エージェントの詳細な振る舞いは個別ファイルを参照:
- `agents/{agent-name}.md`
