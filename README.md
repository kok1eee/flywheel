# flywheel v0.3.0

> **Sensors-first / harness-driven loop engine.** auto mode を前提に「設計が無ければ実装を物理ブロック」する門を hook で強制し、設計が validate を通って初めて実装ゲートが開き、goal 達成まで自動で回す。[o-m-cc](https://github.com/kok1eee/o-m-cc) を workflow ライブラリとして compose する driver。

## なぜ作ったか

o-m-cc は「設計しよう」と **prose（Guides）で誘導**する。だが Opus 4.7+ / auto mode は prose 誘導を抑制し、skill が発動しない。flywheel は逆向き——**「設計が無いなら実装ツールを物理的に通さない」を Sensor（hook）で強制**する。cc-sdd の「設計してから実装」を auto-mode ネイティブな門に変換する。

## コアフロー

```
① 適当プロンプト（flywheel start "<やりたいこと>"）
        ↓
② 設計フェーズ【絶対】門が閉じる
   plan/design.md を書く → grill/critic で叩く → validate-plan 合格まで実装に入れない
        ↓（合格 → 門が開く）
③ 自動 loop（人間不在）
   実装 → eval(test/build) → 未達なら回り続ける → done
```

**設計（spec）は2回使う**: 入口（無ければ実装を block）と出口（eval の合格基準の源）。だから「無限に回す」がトークン焚き火にならない——spec が done を定義するから終われる。

## state machine

```
no-spec → designing → spec-ready → implementing → polish → eval → done
```

state 遷移は**全て hook がモデルの自然なツール使用を観測して進める**。モデルは一度も state を進めない（これが「auto mode でモデルに依存しない」核心）。

| hook | イベント | 役割 |
|---|---|---|
| `design-gate` | PreToolUse(Edit/Write) | 設計未完了なら source 書き込みを block。spec-ready で最初の実装編集→implementing |
| `design-validator` | PostToolUse(Write/Edit) | design.md 書き込みを検知→`validate-plan` 自動実行→合格で spec-ready |
| `loop-driver` | Stop | implementing→**polish**(simplify を steer)→**eval**(ty/ruff/test の CLI 判定)。未達なら implementing に戻して veto。継続自体は native `/goal` に compose |

**品質スタックは2系統**: polish = `Skill: simplify`（LLM 整理 / steer）、eval = `ty`/`ruff`/`test`（CLI / 決定論）。`--no-polish` で polish 段を飛ばせる。

## 使い方

```bash
# 単発（goal ルート）
flywheel start "決済画面を作る" --eval "ty check && ruff check && pytest"
flywheel status                    # phase / goal / polish / 履歴
flywheel reset                     # 中止（門が開く）

# 複数 goal を順に消化（backlog ルート、cron 不要）
flywheel add "機能A" --eval "pytest"
flywheel add "機能B" --no-polish
flywheel list                      # backlog 一覧
flywheel next                      # done/dormant のとき先頭を pop して start
```

- 完了時、設計は `plan/archive/<ts>/` に退避される（記録 + plan/ クリーン化）
- 外側の定期/連続ループは native `/loop` / `/schedule` に委譲（flywheel は cron を持たない）
- bypass: `FLYWHEEL_OFF=1` / veto 上限: `FLYWHEEL_VETO_CAP`（既定 8。`CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` も参照）

## o-m-cc との境界

flywheel = **loop を強制し steer する harness**（hook・state・gate）。o-m-cc = **撃つべき仕事の中身**（skill・agent・判断知）。flywheel は o-m-cc を**呼ぶ**。置き換えない。o-m-cc は soft dependency（`validate-plan` を plugin cache から解決、無ければ degrade）。

## スコープ / 詳細

設計判断は [plan/design.md](plan/design.md) / [plan/requirements.md](plan/requirements.md) 参照。今後候補: intent-router(UserPromptSubmit 自動入口)、FR-3 headless 分岐（grill↔critic）、eval の挙動検証（o-m-cc verification）、Bash 実装意図 block、backlog auto-chain。

## Changelog

### 0.3.0
- **judgment library を同梱して自己完結化** — `validate-plan`(CLI) + designing フェーズの skill/agent（grill/design/discovery-council/deep-interview/verification + critic/scout/designer/researcher/analyst/debugger/code理解3/security-reviewer/prior-art3 + facets）を o-m-cc から移設。実行時の o-m-cc 依存ゼロ。`o-m-cc:`→`flywheel:` namespace 統一。
- **designing パイプライン統合** — design-gate が `plan/` の artifact を見て次の設計ステップを steer: 要件無し→`deep-interview`/`discovery-council`、要件のみ→`design`、設計あり→`grill`。3つの重複 skill が「designing の3段」に織られる。
- 仕分け: `sisyphus`/`quality-gate`/`task-decomposition`/`atom-suggest` 等は flywheel の機構が肩代わり or o-m-cc 固有のため移設せず凍結 o-m-cc に残置。

### 0.2.0
- **polish フェーズ（FR-11）**: implementing→polish(`Skill: simplify` を steer)→eval。品質を LLM 整理(polish) と CLI 判定(eval=ty/ruff/test) の2系統に分離。`--no-polish` で無効化。
- **完了スペックの archive（FR-12）**: done 到達時 `plan/{requirements,design}.md` + state スナップショットを `plan/archive/<ts>/` に退避。`start`/`next` も前回 plan を防御的に退避。
- **backlog ルート（FR-13）**: `flywheel add/list/next` で goal キューを順に消化。cron は持たず外側ループは native `/loop`/`/schedule` に委譲。
- fix: state 読取の空フィールドがタブ IFS で畳まれてズレる罠を Unit Separator(0x1F) で解消。

### 0.1.0
- walking skeleton: design-gate / design-validator / loop-driver / state machine / bin/flywheel。設計が validate を通るまで実装を物理ブロック → goal まで自動 loop。
