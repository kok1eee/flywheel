# flywheel v0.4.8

> **Sensors-first / harness-driven loop engine.** auto mode を前提に「設計が無ければ実装を物理ブロック」する門を hook で強制し、設計が validate を通って初めて実装ゲートが開き、goal 達成まで自動で回す。設計フェーズの judgment library（grill/critic/scout/design/discovery-council 等）+ validate-plan を同梱した**自己完結プラグイン**（o-m-cc 後継）。

## インストール

private repo（`kok1eee/flywheel`）。kok1eee アカウントの認証があるマシンで:

```bash
# GitHub から（別マシン）
claude plugin marketplace add git@github.com-kok1eee:kok1eee/flywheel.git
claude plugin install flywheel@kok1eee-flywheel
# → 再起動で hooks 有効化

# ローカル開発（編集を即反映）
claude plugin marketplace add /path/to/flywheel
claude plugin install flywheel@kok1eee-flywheel
#   編集後: claude plugin marketplace update kok1eee-flywheel && claude plugin update flywheel@kok1eee-flywheel
```

dormant 既定なので install しても `flywheel start` するまで通常作業を邪魔しない。

install すれば **全ディレクトリで動く**（hooks / `/flywheel:start` は user scope でグローバル、command は plugin 同梱の `bin/flywheel` を `${CLAUDE_PLUGIN_ROOT}` 経由で呼ぶので PATH 設定不要）。ターミナルから CLI を直接叩きたい場合だけ任意で PATH に通す:

```bash
ln -s ~/.claude/plugins/cache/kok1eee-flywheel/flywheel/*/bin/flywheel ~/.local/bin/flywheel  # 任意
```

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

「spec が done を定義する」は文字どおりの配線（FR-19・v0.4.5）: design.md の **`## 完了条件（eval）`**（必須セクション）に書いた fenced code block を、validate 合格時に design-validator が **eval_cmd へ昇格**させる。完了条件は AI が設計し（deep-interview の DONE 軸 / grill の完了条件枝で詰める）、人間は承認するだけ。判定は CLI の exit code（自己評価バイアスなし）。`--eval` 明示時は上書きされない。

## state machine

```
no-spec → designing → spec-ready → implementing → eval ⇄(修正loop) → polish → 再eval → done
```

state 遷移は**全て hook がモデルの自然なツール使用を観測して進める**。モデルは一度も state を進めない（これが「auto mode でモデルに依存しない」核心）。

| hook | イベント | 役割 |
|---|---|---|
| `design-gate` | PreToolUse(Edit/Write/NotebookEdit) | 設計未完了なら source 書き込みを block。spec-ready で最初の実装編集→implementing |
| `design-validator` | PostToolUse(Write/Edit) | design.md 書き込みを検知→`validate-plan` 自動実行→合格で spec-ready |
| `loop-driver` | Stop | implementing→**eval**(ty/ruff/test の CLI 判定)→初回合格で **polish**(simplify を steer・goal につき1回)→再 eval→done。未達なら implementing に戻して veto。継続自体は native `/goal` に compose |
| `skill-logger` | PreToolUse(Skill) | 全 skill 使用 + steer 発行を CSV 記録（観測のみ）。evolve の入力 / steer 従命率 / 人気・過少トリガーの把握 |

**品質スタックは2系統**: eval = `ty`/`ruff`/`test`（CLI / 決定論・done を定義）、polish = `Skill: simplify`（LLM 整理 / **初回 eval 合格後に1回だけ** = polish-on-green）。`--no-polish` で polish 段を飛ばせる。goal の累積 diff が小さい（既定 30 行未満・`FLYWHEEL_POLISH_MIN_DIFF`）ときは polish を自動省略（FR-20）。

**3つ目の品質手段 `/code-review` は意図的に配線しない**: バグ探索（simplify は cleanup-only でバグを見ない）は「意味のあるまとまり」（push / PR 前）に人間が手で撃つのが最も効く。推奨運用は **done 後・push 前に `/code-review`**（深掘りは effort 指定 or `ultra`）。

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

**低摩擦な入口（v0.4.0）:**
```bash
flywheel start "決済画面を作る"     # --eval 省略で test/lint を自動検出
/flywheel:start 決済画面を作る       # slash command（CLI を打たない）
export FLYWHEEL_AUTO=1              # invisible: 「決済画面を実装して」と言うだけで auto-engage（opt-in）
```

- セッション冒頭の SessionStart hook（`session-greeter`・FR-17）: dormant なら `flywheel start` の存在を1行リマインド（**gate は閉じない**。常時 gate ON にしない理由は [plan/design.md](plan/design.md) の「低摩擦入口」参照）。goal 進行中なら **phase/goal/次手を再アンカー**——compaction や resume でモデルの context から消えた「いまどこ」を再注入し、数時間〜数日の長時間運転を支える
- 完了時、設計は `plan/archive/<ts>/` に退避される（記録 + plan/ クリーン化）
- 外側の定期/連続ループは native `/loop` / `/schedule` に委譲（flywheel は cron を持たない）
- bypass: `FLYWHEEL_OFF=1` / veto 上限: `FLYWHEEL_VETO_CAP`（既定 8。`CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` も参照）/ eval 打ち切り: `FLYWHEEL_EVAL_TIMEOUT`（既定 540s）/ polish 省略閾値: `FLYWHEEL_POLISH_MIN_DIFF`（既定 30 行）

## o-m-cc との境界

flywheel = **loop を強制し steer する harness**（hook・state・gate）。o-m-cc = **撃つべき仕事の中身**（skill・agent・判断知）。flywheel は o-m-cc を**呼ぶ**。置き換えない。o-m-cc は soft dependency（`validate-plan` を plugin cache から解決、無ければ degrade）。

## スコープ / 詳細

設計判断は [plan/design.md](plan/design.md) / [plan/requirements.md](plan/requirements.md) 参照。今後候補: intent-router(UserPromptSubmit 自動入口)、FR-3 headless 分岐（grill↔critic）、eval の挙動検証（o-m-cc verification）、Bash 実装意図 block、backlog auto-chain。

## Changelog

### 0.4.8
- **fix: `!` 動的注入行の permission check 拒否** — skill/command の `!` 行に shell 変数展開があると「Contains simple_expansion」で弾かれ skill 自体が起動失敗する（`/flywheel:grill` で実地に踏んだ）。grill の Step 0 と `/flywheel:start` の起動行を展開フリーに書き直し（`$ARGUMENTS` / `${CLAUDE_PLUGIN_ROOT}` はローダー置換なので可）。
- **grill の plan-mode 適応（v0.5 先行）** — 対象優先 0 に「plan mode 中に会話で構成している計画」を追加。詰めた結果は ExitPlanMode の計画に反映し、ファイル化は承認時の hook が担う。
- v0.5 spec（plan-mode route への転回・FR-21/22/23）と spike 実証結果を plan/ に確定。`/goal` はモデルから起動できない旨を案内文に明記。

### 0.4.7
- **fix: slash command の PATH 依存（FR-16 改）** — `/flywheel:start` が裸の `flywheel` を呼んでいたため、CLI を PATH に通したマシンでしか動かなかった。`${CLAUDE_PLUGIN_ROOT}/bin/flywheel` 経由に変更し、**plugin を install すれば全ディレクトリ・全マシンで動く**ように。hook の案内メッセージも `FW_CLI`（PATH に無ければ同梱実体パス）に統一。
- **空引数の degrade** — サジェストから Enter 直押しで `/flywheel:start` が引数なし実行されると error で死んでいた。status 表示 + 「goal を聞いてから start せよ」のモデル誘導に変更。

### 0.4.6
- **polish の diff 適応（FR-20）** — start 時に baseline revision（jj `@-` / git HEAD）を記録し、初回 eval 合格時の**累積**変更行数が `FLYWHEEL_POLISH_MIN_DIFF`（既定 30）未満なら polish を省略して即 done。typo 修正級の goal に simplify 1ターンは過剰、かつ累積計測なので「細かく commit すると diff がゼロリセットされて常に skip」問題を回避。計測不能（VCS なし）は従来どおり polish（degrade）。FR-15 で将来とした weight-scaling の最初の実装。
- **`/code-review` の運用方針を明文化** — 意図的に配線しない（バグ探索は push/PR 前の意味のあるまとまりで人間が手で撃つのが最も効く。simplify は cleanup-only で補完関係）。推奨: done 後 push 前に `/code-review`。

### 0.4.5
- **spec-designed eval（FR-19）** — メタプロンプト手法（完了条件と指示文を AI 自身に設計させる）を designing フェーズに融合。design.md の `## 完了条件（eval）` を validate-plan の必須セクションにし、fenced block のコマンドを validate 合格時に design-validator が eval_cmd へ昇格（解決順: `--eval` 明示 > spec > 自動検出 > 空。出所は state の `eval_src`）。deep-interview に DONE 軸（AI が完了条件の案を設計→人間は承認/修正のみ）、grill に完了条件の枝（実行可能か・goal 固有か・緩すぎ/厳しすぎないか）を追加。eval が「プロジェクト全体の test が通る」から「**この goal の完了条件**」に変わり、FR-6 の『完了判定は設計の受け入れ基準に照合』がようやく実装になった。入口は増やさない（`/vibe` 等は作らず、雑 goal の受け止めは既存 designing パイプラインが担う）。

### 0.4.4
Anthropic skills blog（lessons-from-building-claude-code）の practice を反映。skills 監査の結果、Gotchas 全7スキル既存・トリガー description 済みなど大半は先取りできており、欠けていた2点を実装:
- **skill-logger hook（FR-18・practice「スキルの計測」）** — PreToolUse(Skill) で全 skill 使用を `skill-usage.csv` に記録。design-gate / loop-driver の steer 発行も `steer:*` 行で同 CSV に載るため、**steer 従命率**（design.md の dogfood 宿題）が初めて測れる。evolve の入力もこれで実配線（従来は書き手が無く常に空だった）。
- **evolve の自己完結化** — o-m-cc 残置の `bin/atoms` / `atoms.csv` への死に参照を除去し、改善案の置き場を `improvements.md`（計測データと同じ領域）に変更。memory パスの表記も環境非依存に。facets/agent-memory-guidance.md も同期。

### 0.4.3
Fable 5 webinar（autonomous agents の使いこなし）の推奨を harness に反映:
- **active 時の再アンカー（FR-17 拡張）** — goal 進行中のセッション開始・compaction 復帰時に session-greeter が phase/goal/次手を context へ再注入（「数時間〜数日の context 保持」を harness 側から補強）。phase 別: designing→設計ステップ steer、implementing/polish/eval→eval_cmd 込みの続行案内、done→next/reset 案内。
- **native `/goal` 併用の実配線** — design.md の「継続は /goal に compose」が出力に現れていなかった。`flywheel start` の出力と `/flywheel:start` に併用案内を追加（goal 駆動の徹底）。
- **done 時の verification 提案（非ブロック）** — eval は静的判定のみなので、done 時に `flywheel:verification`（挙動エビデンス収集）を提案（「自分の作業を検証する」）。

### 0.4.2
- **polish を eval 後に移動（FR-11 改 = polish-on-green）** — 旧 implementing→polish→eval は eval 失敗のたび polish が再発火し、修正ループの turn とトークンが倍掛かりだった（cap 8 で最大8回 simplify）。新: implementing→eval→初回 green で1回だけ polish→再 eval→done。修正ループは eval 最短で回り、磨く対象は修正込みの最終形、polish 後の再 eval 失敗は simplify が犯人と確定できる（make it work, then make it right）。1回保証は state の `polished` フラグ。
- **spec-ready 停止の空振り done 防止** — 門が開いた直後に source 未編集のまま停止すると eval が「未実装でも既存テストは green」で空振り合格し得た。spec-ready での停止は eval を回さず実装開始を steer（veto cap 保護）。
- **fix: intent-router が前回 plan を退避せず start していた** — auto-engage 経路に `fw_archive_plan` が無く、stale な design.md が残ったまま新 goal が始まると古い設計で門が開き得た。FR-12 の防御を両入口に統一。
- **fix: NotebookEdit が設計ゲートを素通り** — PreToolUse matcher に追加（.ipynb への実装書き込みも block）。
- 内部: dead code `fw_set` 削除、`fw_set_num`→`fw_set_json` 改名（boolean も渡すため）。
- 頑健性4点 — eval を `timeout` で自前打ち切り（既定 540s・`FLYWHEEL_EVAL_TIMEOUT`。hook timeout に殺されて判定なしで stop が通る silent degrade を veto に変換、Stop hook timeout も 600s に拡大）/ mise shims を PATH に前置（非対話 hook 環境の npm/node 欠落で eval が常に fail する事故防止）/ intent-router の goal 切り出しを文字単位に（バイト切断で UTF-8 が壊れて state.json が汚れるのを防止）/ リポ外（/tmp 等）への書き込みを gate 対象外に（設計フェーズの調査スクラッチを塞がない）。

### 0.4.1
- **SessionStart 入口案内（FR-17）** — dormant なセッション冒頭で `flywheel start` / `/flywheel:start` の存在を 1 行案内（`session-greeter` hook）。FR-15 と違い **gate を閉じない**（思い出させるだけ・誤爆リスク無し）。`FLYWHEEL_AUTO` の状態も併記し、常用なら auto-engage を勧める。`FLYWHEEL_OFF=1` / goal 進行中は沈黙。「常時 gate ON（最初から start モード）」は誤爆地獄になるため不採用——摩擦低減は FR-15 で解く、と spec に明記。

### 0.4.0
- **eval 自動検出（FR-14）** — `flywheel start "<goal>"` で `--eval` を省略するとプロジェクト（pyproject/package.json/Cargo/go.mod）から test/lint/型チェックを自動検出。日常は `flywheel start "<goal>"` だけで済む。
- **intent-router: invisible auto-engage（FR-15, opt-in）** — `FLYWHEEL_AUTO=1` のとき、build 意図の prompt（実装して/作って/機能追加）を UserPromptSubmit hook が検知し自動 `start`。質問・調査は engage しない、active 中は触らない、`flywheel reset` で即解除。「使っていることを感じさせない」理想形（既定 off、weight-scaling は将来）。
- **slash command（FR-16）** — `/flywheel:start <作りたいもの>` で CLI を打たず起動（明示派の入口）。

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
