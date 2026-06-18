# CLAUDE.md — flywheel repo で作業するときの指針

flywheel は「設計してから作る」を hook で強制する Claude Code plugin。**全体像と機能史は
[README.md](README.md)、改善 backlog は [ROADMAP.md](ROADMAP.md) が正**。ここは重複させず、
このリポを触るセッションが踏みやすい落とし穴と規約だけを置く。

## 鉄則（壊すと設計が崩れる不変条件）

- **モデルは state を一度も進めない（C-2）**。phase 遷移は hook が「モデルの自然なツール使用」を
  観測して進める。`.flywheel/`（state.json / backlog.jsonl）への Edit/Write は全 phase で
  design-gate がブロックする。state を変えたいときは **CLI**（`flywheel set-eval` / `monitor-set` /
  `repos` / `go` / `reset`）を使う。`_advance` は `FLYWHEEL_HOOK=1` 必須。
- **done を閉めるのは eval（客観 exit code）+ monitor council（独立）の2つだけ**。自己申告 done /
  self-graded ゲートは入れない（FR-34 で撤去済み。auto-memory `flywheel-eval-is-sole-done-gate`）。
- **完了は eval ゲート一本**。層を足すなら stateless に留める（ROADMAP の epic は MD 見出しのみ・
  独自 state を持たせない）。

## state machine

```
no-spec → designing → spec-ready → implementing → eval ⇄(veto loop) → polish → 再eval → 監視council → done
```

done 後に backlog があれば自動連鎖（adopt=止めず続行 / start=go/no-go grill→discovery 自動。
FR-33/35。`FLYWHEEL_NO_CHAIN=1` で従来 hard-stop）。

## flywheel を flywheel で作る（dogfood）

このリポの改善は**できる限り flywheel の harness に載せて回す**（plan route or `/flywheel:add`→
`/flywheel:next`）。設計ゲート→eval→polish→監視 council→done を自分で踏むことが最良のテストになる。
ROADMAP 項目を `/flywheel:add`（軽量 grill で Done/Boundary/曖昧点を詰めてから積む）→ `next` で起動。

- **判断は self-answer しない**（grill の肝）。事実（コードに答えがある）は調べて埋め、判断
  （スコープ/トレードオフ/優先/命名/案の選択）は人間に聞く。HOTL=「調べる=loop / 決める=人間 /
  判定=monitor」（auto-memory `flywheel-hitl-to-hotl`）。

## 規約

- **テストは `test/*.sh`**。live state を壊さないよう `mktemp -d` の使い捨てリポで検証し、
  `CLAUDE_PLUGIN_DATA` を /tmp に向けて本番 CSV を汚さない。chain 系の共有ハーネス（環境分離・
  state ヘルパ・`setup_impl`/`setup_done_ready`/`run_hook`）は **`test/chain-lib.sh`** に集約済み。
  新テストはこれを source する。
- **シェルは bash で書く**（hook は `#!/usr/bin/env bash`）。共通ロジックは `hooks/lib/common.sh`。
- **version は `.claude-plugin/plugin.json` と `.claude-plugin/marketplace.json`（2 箇所）** を揃えて
  bump。README 冒頭の `vX.Y.Z` と Changelog、ROADMAP の状態列も同時に更新する。
- VCS は **jj**（global ルール準拠: describe は `-m` 必須・push 前に fetch→main@origin にリベース）。
  plugin は marketplace の `directory` ソースで repo を直読みするため、**hook の変更は再起動不要で
  即 live**。skill / command / agent の変更は**セッション再起動で反映**。

## 詳細

設計判断の全記録は `plan/archive/<ts>/`（done 時に退避）。機構メモは ROADMAP 末尾「機構メモ」節。
