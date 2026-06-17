---
name: guide
description: "flywheel をどう駆動するか迷ったときの決定ガイド。ルート選択（plan route / start / adopt）・各 phase skill への振り分け・よくある詰まりを1枚で。「flywheel どう使う」「どの skill 使う」「次に何をすれば」「flywheel の使い方」「ゲートが開かない」「done にならない」で発動。実挙動は hook の live steer が正で、このガイドは地図。"
argument-hint: "<今やりたいこと（任意）>"
allowed-tools: [Read, Bash]
effort: low
---

# flywheel Guide — どう駆動するかの地図

> **これは地図。現在地は live が正。** 各 hook（design-gate / plan-steer / loop-driver）はその場で「次に何をすべきか」を steer する。迷ったらまず下の現在状態と `flywheel status` を見て、**hook の steer に従う**。このガイドと挙動がズレたら hook が正しい。

## 現在の状態（動的）

!`"${CLAUDE_PLUGIN_ROOT}/bin/flywheel" status 2>/dev/null || echo "dormant（state なし。門は開いている）"`

上の `phase` で今いる場所が分かる。`no-spec`/dormant=未起動 / `designing`=設計中（実装ブロック中）/ `spec-ready`/`implementing`/`polish`/`eval`=loop が回す作業中 / `done`=達成（`flywheel next` or `reset`）。

## やりたいことが `$ARGUMENTS` のとき — ルート選択

```
何を作る / 直す？
├ 計画を対話で固めてから実装したい（推奨・主経路）
│    → Shift+Tab で plan mode（grill が既定動作: 決定点を1問ずつ・推奨付き）
│      → 計画を承認すると plan-approved が design.md 化 + 完了条件を eval 昇格 + 自動 loop
│      （常用するなら FLYWHEEL_PLAN=1 を shell rc に）
├ 要件がまだ曖昧・ゼロから掘りたい
│    → /flywheel:start "<作りたいもの>"  → designing に入る
│      → /flywheel:deep-interview（1問ずつ掘る）→ /flywheel:discovery-council（3視点で requirements.md 確定）
├ 会話 or handoff(journal) で方針が既に固まっている
│    → /flywheel:adopt "<一言サマリ>"  → 掘るをスキップし design.md に結晶化
├ ROADMAP.md に着手したい改善候補がある（複数 phase を一気に回したい）
│    → /flywheel:add "<項目>" で軽量 grill→backlog に積む（繰り返し）→ /flywheel:next で逐次起動
│      （ROADMAP=源 → backlog → 実装。flywheel の中核ワークフロー）
├ 既存アプリへの機能追加（途中から）
│    → discovery-council で要件、/flywheel:design で設計、/flywheel:grill で叩く（既存コードは agent が調査委譲）
└ 些末 / Bash だけで完結する作業
     → 設計ゲートは過剰。FLYWHEEL_OFF=1 で門を bypass（または最初から起動しない）
```

## 設計フェーズの流れ（gate が閉じている間）

artifact の有無で next が決まる（design-gate が自動 steer する。手動なら下を辿る）:

| 今ある物 | 次 |
|---|---|
| 何もない | `/flywheel:deep-interview` → `/flywheel:discovery-council`（plan/requirements.md） |
| requirements.md | `/flywheel:design`（plan/design.md） |
| design.md | `/flywheel:grill` で詰問 → design.md 更新 → validate-plan 自動 → **合格で実装ゲート開放** |

**ゲートが開かない時の筆頭原因**: design.md に `## 完了条件（eval）` セクション（done を機械判定する fenced コマンド）が無い → validate-plan が差し戻す。完了条件は AI が設計し人間は承認するだけ。

## 実装 → done（gate が開いた後・loop-driver が回す）

```
実装 → 停止 → eval（自動検出 or --eval の test/lint）→ 緑 → polish(simplify) → 再 eval
      → 監視 council(/flywheel:monitor が done-gate で drift 検証) → clean なら done
未達 → veto で差し戻し（FLYWHEEL_VETO_CAP=8 で人間 hand-back）
drift → implementing 差し戻し / design・PRD レベルは人間 hand-back（FLYWHEEL_MONITOR_CAP）
```

長時間の連続自律で回すなら native の **`/goal` を併用**（flywheel=eval veto + steer、/goal=ターン継続の分業）。`/goal` は UI コマンドなので**ユーザーが打つ**（モデルは起動できない）。

## 補助スキル（いつでも）

- `/flywheel:critic` — 計画を**非対話で一括批判**（grill は対話、critic はレポート）
- `/flywheel:verification` — 完了宣言の前の自己検証（証拠なき成功宣言は不正）
- `/flywheel:handoff` — 別マシン/セッションへ引き継ぎ（journal.md に Recap + Next）
- `/flywheel:evolve` — 学び（実行履歴 + memory）を各 skill の Gotchas に還元

## よくある詰まり → 対処

| 症状 | 対処 |
|---|---|
| 実装が物理ブロックされる | 設計フェーズ。design.md を validate に通す（grill→更新）。緊急 bypass は `FLYWHEEL_OFF=1` |
| ゲートが validate で開かない | design.md に `## 完了条件（eval）` が無い／薄い |
| done にならない | eval 未達 or monitor が drift/pending。`flywheel status` で確認 |
| Bash だけの goal が spec-ready で止まる | `FLYWHEEL_OFF=1` で逃がす |
| 自律で続かない | `/goal <goal>` を併用（ユーザーが打つ） |
| 監視 council が空振り/詰まる | monitor cap で人間に返る。`flywheel monitor-set` の verdict 記録を確認 |

## CLI チートシート

```
flywheel start "<goal>" [--eval "<cmd>"] [--no-polish]   設計ゲート付きで起動
flywheel adopt "<summary>"                               合意済み方針を結晶化して起動
flywheel status / reset / next / list / add "<goal>"     状態 / 破棄 / 次 / backlog
flywheel watch-focus "<text>"                            監視 council の重点を指定（HITL）
```

## env

`FLYWHEEL_PLAN=1`(plan route 常用) / `FLYWHEEL_OFF=1`(bypass) / `FLYWHEEL_VETO_CAP`(既定8) / `FLYWHEEL_MONITOR_CAP`(既定=veto cap) / `FLYWHEEL_EVAL_TIMEOUT`(540) / `FLYWHEEL_POLISH_MIN_DIFF`(30)

---

**詳細は `README.md`。挙動の最終的な正は hook の live steer。** このガイドで迷子を減らし、判断は現在状態（上の status）に合わせる。

## Gotchas

- **このガイドの記述を hook より優先しない**: routes/phase 名や env は更新で変わりうる。`flywheel status` と hook の steer が現在地の正。食い違ったら hook に従い、必要なら evolve でこのガイドを直す。

<!-- AUTO-GOTCHAS -->
