# flywheel

> **Claude Code を「設計してから作る」マシンにする plugin。** 設計が無ければ実装ツールを hook が物理的にブロックし、設計が validate を通って初めて実装ゲートが開き、goal の完了条件（eval）を満たすまで自動で回り続ける。設計フェーズの judgment library（grill / critic / scout / discovery-council 等の skill・agent）と `validate-plan` を同梱した自己完結プラグイン。

v0.8.18 / MIT License

## インストール

```bash
claude plugin marketplace add kok1eee/flywheel
claude plugin install flywheel@kok1eee-flywheel
# → Claude Code を再起動（hooks が有効化される）
```

要件: Claude Code + `jq`。VCS（jj / git）はあれば polish 省略の diff 計測に使われる（無くても degrade して動く）。

- **dormant 既定**: install しても起動するまで通常作業を一切邪魔しない。セッション冒頭に入口の1行案内が出るだけ
- **全ディレクトリで動く**: hooks / `/flywheel:start` は user scope でグローバル。command は plugin 同梱の `bin/flywheel` を `${CLAUDE_PLUGIN_ROOT}` 経由で呼ぶので PATH 設定不要
- ターミナルから CLI を直接叩きたい場合だけ任意で PATH に通す:

```bash
ln -s ~/.claude/plugins/cache/kok1eee-flywheel/flywheel/*/bin/flywheel ~/.local/bin/flywheel  # 任意
```

### ローカル開発（clone して編集する人向け）

```bash
claude plugin marketplace add /path/to/flywheel
claude plugin install flywheel@kok1eee-flywheel
# 編集後の反映:
claude plugin marketplace update kok1eee-flywheel && claude plugin update flywheel@kok1eee-flywheel
```

## なぜ作ったか

「設計してから実装する」を prose（CLAUDE.md / スキルの文章）で誘導しても、auto mode のモデルは従うとは限らない。flywheel は逆向き——**「設計が無いなら実装ツールを物理的に通さない」を hook（Sensor）で強制**する。モデルの善意に頼らず、harness が門を閉める。

もう1つの核心は**設計（spec）を2回使う**こと: 入口（無ければ実装を block）と出口（design.md に書いた完了条件が eval コマンドへ昇格し、done を定義する）。だから「goal まで無限に回す」がトークン焚き火にならない——spec が done を定義するから終われる。

## 使い方

### 主経路: plan mode（対話）

```bash
export FLYWHEEL_PLAN=1   # opt-in（常用するなら shell rc へ）
```

```
Shift+Tab で plan mode → 計画づくり（grill の操作系が既定動作: 決定点を1問ずつ・推奨付き）
  → ExitPlanMode = plan-gate が形式検証（非スコープ・完了条件の無い計画は差し戻し）
  → ユーザー承認 = hook が計画を plan/design.md に保存・完了条件を eval 化・implementing へ
  → 以後 done まで自動 loop（eval が落ちる限り停止を veto / green で polish → 再 eval → done）
```

「**しっかり = plan mode、ワンショット = auto のまま**」。モード選択（Shift+Tab）が意図シグナルなので誤爆ゼロ——designing 中の read-only 強制も native plan mode が担う。flywheel は「計画の品質」と「承認後の自動 loop」に集中する。

### 会話 / handoff の合意を載せる: adopt（v0.7.0・FR-29）

会話の中で「何を作るか」が既に固まっているとき、要件をゼロから掘り直すのは摩擦。**合意を design.md に結晶化するだけ**で loop に載せる第3の入口:

```
/flywheel:adopt <一言サマリ>
  → source 解決: このセッションの会話の合意 > .claude/journal.md 先頭の Next Actions（handoff 経由）
  → モデルが design.md を結晶化（完了条件も）→ validate → spec-ready → implementing → 自動 loop
```

別マシン / 新セッションで会話コンテキストが空でも、**handoff → adopt** が成立する（議論したセッションで `/flywheel:handoff` → journal.md を VCS 共有 → 別マシンで `/flywheel:adopt` が Next Actions を結晶化）。designing への入り方は3通り: **start=掘る / plan mode=作って承認 / adopt=結晶化**。

### CLI ルート（headless / backlog 用）

```bash
# 単発
flywheel start "決済画面を作る"                  # --eval 省略で test/lint を自動検出
flywheel start "決済画面を作る" --eval "pytest"  # 明示指定（spec 昇格より優先）
/flywheel:start 決済画面を作る                   # slash command（CLI を打たない）
flywheel status                                 # phase / goal / polish / 履歴
flywheel reset                                  # 中止（門が開く）

# 複数 goal を順に消化（backlog ルート、cron 不要）
flywheel add "機能A" --eval "pytest"
flywheel add "機能B" --no-polish
flywheel list                                   # backlog 一覧
flywheel next                                   # done/dormant のとき先頭を pop して start
```

### コアフロー

```
① goal を渡す（plan mode 承認 or flywheel start）
        ↓
② 設計フェーズ【絶対】── 門が閉じる
   plan/design.md を書く → grill/critic で叩く → validate-plan 合格まで実装に入れない
        ↓（合格 → 門が開く）
③ 自動 loop（人間不在）
   実装 → eval(test/lint/型) → 未達なら veto して回り続ける → green で polish → 再 eval → done
```

- 完了時、設計は `plan/archive/<ts>/` に退避される（記録 + plan/ クリーン化）
- 外側の定期/連続ループは native `/loop` / `/schedule` に委譲（flywheel は cron を持たない）
- done 後・push 前に `/code-review` を手で撃つのが推奨運用（後述）

## 仕組み: state machine と hooks

```
no-spec → designing → spec-ready → implementing → eval ⇄(修正loop) → polish → 再eval → done
```

state 遷移は**全て hook がモデルの自然なツール使用を観測して進める**。モデルは一度も state を進めない（これが「auto mode でモデルに依存しない」核心。state を直接進める迂回路も塞いである: `_advance` は hook 専用、`.flywheel/` への Edit/Write は全 phase でブロック）。

| hook | イベント | 役割 |
|---|---|---|
| `session-greeter` | SessionStart | dormant なら入口を1行案内（gate は閉じない）。goal 進行中なら phase/goal/次手を再アンカー（compaction / resume で消えた「いまどこ」を再注入） |
| `plan-steer` | UserPromptSubmit | `FLYWHEEL_PLAN=1` + plan mode 中、grill の操作系を毎プロンプト注入（skill 発動に依存しない既定動作） |
| `plan-gate` | PreToolUse(ExitPlanMode) | 計画テキストを検証——非スコープ / 完了条件（fenced command）の無い計画は差し戻し |
| `plan-approved` | PostToolUse(ExitPlanMode) | 承認の瞬間に計画を plan/design.md へ保存 + 完了条件を eval_cmd 昇格 + implementing へ |
| `design-gate` | PreToolUse(Edit/Write/NotebookEdit) | 設計未完了なら source 書き込みを block。spec-ready で最初の実装編集 → implementing |
| `design-validator` | PostToolUse(Write/Edit) | design.md 書き込みを検知 → `validate-plan` 自動実行 → 合格で spec-ready |
| `loop-driver` | Stop | implementing → eval（CLI 判定）→ 初回合格で polish（simplify を goal につき1回 steer）→ 再 eval → 監視 council → done。done 後 backlog があれば自動連鎖（adopt=続行 / start=go/no-go grill→discovery・FR-33/35）。未達なら veto（command-not-found 系なら「eval_cmd を `set-eval` で直せ」を示唆・FR-36）。fail 数の前回比で 📉改善=続行 / ➡️横ばい=別仮説 / 📈悪化=revert を steer |
| `skill-logger` | PreToolUse(Skill) | 全 skill 使用 + steer 発行を CSV 記録（観測のみ。evolve の入力 / steer 従命率の計測） |
| `intent-router` | UserPromptSubmit | legacy（`FLYWHEEL_AUTO=1` の auto-engage）。plan route が上位互換 |

**品質スタックは2系統**: eval = test/lint/型チェック（CLI / 決定論・done を定義）、polish = `Skill: simplify`（LLM 整理 / **初回 eval 合格後に1回だけ** = polish-on-green）。`--no-polish` で飛ばせる。goal の累積 diff が小さい（既定 30 行未満）ときは polish を自動省略。

**3つ目の品質手段 `/code-review` は意図的に配線しない**: バグ探索（simplify は cleanup-only でバグを見ない）は「意味のあるまとまり」（push / PR 前）に人間が手で撃つのが最も効く。推奨は **done 後・push 前に `/code-review`**（深掘りは effort 指定 or `ultra`）。

### 完了条件は spec が定義する

design.md の **`## 完了条件（eval）`**（validate の必須セクション）に書いた fenced code block を、validate 合格時に design-validator が **eval コマンドへ昇格**させる。完了条件は AI が設計し（deep-interview の DONE 軸 / grill の完了条件枝で詰める）、人間は承認するだけ。判定は CLI の exit code（自己評価バイアスなし）。`--eval` 明示時は上書きされない。

## 設定（環境変数）

| 変数 | 既定 | 意味 |
|---|---|---|
| `FLYWHEEL_PLAN` | off | `1` で plan mode = flywheel（主経路の opt-in） |
| `FLYWHEEL_OFF` | off | `1` で全 hook を bypass |
| `FLYWHEEL_VETO_CAP` | 8 | eval 失敗時の停止 veto 上限（`CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` も参照） |
| `FLYWHEEL_MONITOR_CAP` | =veto cap (8) | 監視ループ（done-gate council）が人間に hand-back するまでの試行上限（FR-30） |
| `FLYWHEEL_EVAL_TIMEOUT` | 540 | eval コマンドの打ち切り秒数 |
| `FLYWHEEL_POLISH_MIN_DIFF` | 30 | 累積変更行数がこれ未満なら polish を省略 |
| `FLYWHEEL_NO_CHAIN` | off | `1` で done 時の chain（backlog 自動消化）を無効化し、従来の hard-stop（手動 `next` を促すだけ）に戻す。adopt 経路は止めず連鎖（FR-33）、start 経路は連鎖前に go/no-go を grill→discovery 自動（FR-35） |
| `FLYWHEEL_NO_FUSE` | off | `1` で polish+monitor 融合（FR-38）を無効化し、従来の分離2ステップ（simplify → 別停止で monitor）に戻す |
| `FLYWHEEL_VALIDATE_PLAN` | — | validate-plan 実体の明示パス（通常は同梱版が自動解決） |
| `FLYWHEEL_AUTO` | off | legacy: build 意図の prompt で自動 engage（plan route が上位互換） |

## 同梱物

designing フェーズの judgment library を同梱し、**実行時の外部 plugin 依存ゼロ**で完結する:

- **skills**: `guide`（駆動の決定ガイド・どのセッションでも）/ `grill`（plan を対話で詰問）/ `design` / `discovery-council` / `deep-interview` / `verification` / `monitor`（done-gate 検証 council・FR-30）/ `evolve` / `handoff`
- **agents**: critic / scout / designer / researcher / analyst / debugger / security-reviewer / `drift-observer`（監視 council の観測者・FR-30）/ コード理解系（code-explorer, architecture-mapper, convention-scout）/ prior-art 系（market-researcher, oss-scout, pattern-observer）
- **bin**: `flywheel`（CLI）/ `validate-plan`（設計の形式検証）

判断層の agent（analyst / scout / researcher / critic）は **nested subagents（2.1.172+）で調査・反証を子に委譲**する二層構造: 判断層は `model: inherit` で main loop のモデルを継承し、列挙系の sweep の子だけ `haiku` に降格（heuristics は `agents/capabilities.md`）。

（作者の旧 plugin「o-m-cc」の後継。flywheel = loop を強制し steer する harness、o-m-cc = 判断知ライブラリという分業だったが、designing に必要な分は移設済み）

## 詳細

設計判断の全記録は [plan/design.md](plan/design.md) / [plan/requirements.md](plan/requirements.md) 参照。今後候補: FR-3 headless 分岐（grill↔critic）、eval の挙動検証（verification 統合）、`FLYWHEEL_PLAN` の default 化判断。

## Changelog

### 0.8.18
- **polish+monitor steer の融合 — done 前ゲートの往復を 3→2 に（FR-38）** — done 前は polish(simplify) と monitor council の2段だが、`enter_polish` が `exit 2` で monitor ゲート手前で抜けるため `simplify(stop)→monitor(stop)→done` と毎段で停止→Stop hook→再開のハンドシェイクを挟んでいた。polish が要るとき **1 本の steer で「simplify→monitor を同じターンで」** 実行させ、monitor を pending に prime する（次停止で eval緑 + monitor verdict を一括判定 → done）。**逐次パイプラインであって並列ではない**: monitor は simplify 後の最終コードを検証するので順序固定、削るのは段間の停止1回分だけで挙動の中身は不変。**安全性**: eval は毎停止で独立に回るので simplify が eval を壊しても次停止の eval-fail が拾い done をすり抜けない / model が monitor を飛ばしても prime した pending を次停止の monitor ゲートが拾って再 steer（従来挙動へ安全に degrade）。`enter_polish` に `$2="monitor"` モードを足して統合（新関数を増やさない）。**デフォルト ON・`FLYWHEEL_NO_FUSE=1`** で従来の分離2ステップに戻すエスケープハッチ。eval_cmd 未設定経路の polish（1 引数呼び出し）は `${2:-}` で従来の simplify-only 枝に入り不変。monitor ゲート本体も不変。`test/polish-monitor-fuse.sh`(C1 融合 / C2 エスケープ / C3 融合 entry→clean→done / C4 degrade 安全)。**FR-38 自身の loop で自己 dogfood**（融合 steer が自分に発火 → テストが set -u バグを捕捉 → 監視 council が test カバレッジ drift を検出 → 修正 → clean）。

### 0.8.17
- **初回 eval veto で原因示唆（FR-36）** — eval が `command not found` 系で落ちるのは「コードが悪い」のでなく「eval_cmd 自体が解決できていない」ことが多い（コマンド名ミス・未インストール・パス誤り）。loop が「修正して続けろ」と steer し続ける長い迂回を初手で短絡するため、eval-fail steer に `$cmd_hint` を追加: シェル（`bash -c` 経由）が解決失敗した signal だけを **shell プレフィクス付き**（`(^|/)(bash|zsh|sh|dash|ash): .*(command not found|No such file or directory|: not found)`）で検出し「eval_cmd 自体が怪しい。`flywheel set-eval` で直せ」と促す。裸の `No such file or directory` 等は通常のテスト失敗出力（`config.yml: No such file...`）にも現れるので **shell プレフィクスで弾く**（誤検知ガードを `test/eval-veto-hint.sh` C3 でロック）。監視 council が広すぎる初版 grep の誤検知を drift 検出 → 修正の dogfood 込み。
- **polish 比例制御: 純粋 rename を simplify skip（FR-37・最小スコープ）** — 純粋な move/rename は中身が変わらないのに行数を稼ぎ、無意味な simplify ターンを生む懸念があった。調査で **jj も git も pure rename を `{a => b} | 0`（0 行）に collapse**（rename 検出は既定 ON）＝既存の `FLYWHEEL_POLISH_MIN_DIFF`（30）閾値で**既に skip 済み**と判明。残る穴は `fw_repo_diff_lines` の **git fallback が `-M` 無し**で `diff.renames=false` 環境では rename が delete+add=2×N 行に膨らむこと。git fallback に明示 `-M`(--find-renames) を足し config 非依存で collapse させた。**copy(`-C`) は足さない**（コピー＝重複＝simplify が拾うべき対象）。`test/polish-rename-skip.sh` で検証。**ファイル間コード移動（add≈del）と reset 再 baseline は defer**（ROADMAP follow-up）。
- いずれも **chain dogfood で完走**（`/flywheel:add` で adopt+start を積む → `next` → FR-36 done → **done→start 連鎖で FR-35 の go/no-go grill が実発火** → FR-37 done）。FR-33/35/監視 drift-catch をライブで検証。

### 0.8.16
- **start 経路 auto-chain を HOTL 化（FR-35・HOTL phase2）** — FR-33 では done→次が **start 経路**（要件を一から掘る）goal のとき hard-stop（`exit 0` で人間に丸ごと hand-back）していた。これを「**調べる=loop 自動 / 決める=人間 / 判定=monitor**」の HOTL に寄せる。loop-driver は Stop hook で AskUserQuestion を呼べないので、start 分岐を **`exit 2` + steer** に変更: (1) まず人間に **go/no-go を1問 grill**（vague な start goal の drift を一段目で止める）→ (2) go なら discovery を自動で回し requirements/design を draft（過程の**判断だけ grill**・事実は self-answer）→ (3) design ゲート→実装→done→連鎖。`FLYWHEEL_NO_CHAIN=1` で従来 hard-stop に戻せる。順序原則どおり verification 独立化（FR-34）を前提に start 経路を緩めた。`test/start-chain.sh`(3) + `test/adopt-chain.sh` ケース2 更新。共有ハーネスを `test/chain-lib.sh` に抽出。

### 0.8.15
- **verification を monitor council に統合 / self-graded ゲート撤去（FR-34・HITL→HOTL）** — 旧 `verification`（FR-32）は eval が薄い goal で done 前に挙動エビデンス確認を要求する self-graded ゲートだったが、`verify-set clean`（evidence 省略可・非記録）でモデルが skill を回さず**自己申告で素通り**できた。実測で `steer:verification` 9 回に対し `flywheel:verification` skill 起動は **0 回**（空通過）。**human on the loop** では「人間が見ていなくても信用できる検証」が要るため、self-graded ゲートを撤去し独立検証に一本化した: done を閉めるのは **eval（客観 exit code）+ monitor council（独立）の2つだけ**。挙動検証は monitor に統合 — `observer-behavior` レンズが「runnable なら runtime エビデンスがあるか」を判定し、必要なら **overseer（Bash 保持）が smoke を実行 → Read-only 観測者が判定**（動かすのは overseer・判定は独立／観測者に Bash は持たせない）。薄い eval の runnable goal は drift(impl) memo で「eval に runtime smoke を足せ」と促す。`loop-driver.sh` の FR-32 ブロック・`verify-set` CLI を削除（loop が単純化）。`fw_eval_is_thin` は `flywheel go` の thick-eval 判定で温存。verification skill は **gate から外し汎用の自己検証規律として存続**（monitor overseer がこの手順を参照）。`test/verification-merge.sh` で「薄 eval + monitor clean → verification steer なしで done / verification state 不生成 / steer 不記録」を mktemp 検証。

### 0.8.14
- **adopt chain — done で backlog を自動消化（FR-33）** — これまで goal done 後は「`flywheel next` で次を」と人間に促すだけで、複数 phase を逐次回すには毎回手動 `/next` が必要だった。loop-driver の done 確定後に backlog があれば**自動で次の goal を起動**する（`loop-driver.sh`）。**経路別に挙動を分ける**: 次が **adopt 経路**（合意済み・`/add` 既定）なら止めず `exit 2` で設計→実装へ**連鎖続行**（backlog 全部一気）。次が **start 経路**（要件を一から掘る）なら pop はするが `exit 0` で**人間に hand-back**（design/PRD への遡上は自動化しない HITL 原則）。**無限ループ不可**: `next` が backlog 先頭を pop する＝backlog は単調減少（空で自然停止）。stuck な goal は各 goal の veto/monitor cap が人間へ返すので暴走せず、専用 chain cap は不要。`FLYWHEEL_NO_CHAIN=1` で従来挙動に戻せる。完了は引き続き eval ゲート一本（chain は done 後の起動だけを自動化し、各 goal の eval/monitor/done 判定は不変）。`test/adopt-chain.sh` で adopt 連鎖 / start 停止 / NO_CHAIN / backlog 空 の4ケースを mktemp 検証。

### 0.8.13
- **drift steer の文言明確化** — monitor の drift verdict は loop-driver が読んだ瞬間に `monitor=null` にクリアされる（`loop-driver.sh:150`）が、monitor 記録後にモデルが**先回りで修正**すると次の停止で「修正前に記録された drift」が初回執行され、「🔁 drift 検知、修正して」が空振りに見え「**古い verdict を読み続けるバグ？**」と誤解された（実運用）。drift implementing steer（L177-178）に「この verdict は処理済み・クリア済み、修正したら次の停止で自動的に再 monitor が走る（古い verdict を読み続けない）」を明示。**挙動は不変**（steer 文言の追加のみ）。これは v0.8.12 の **ROADMAP メイン機能化（源→`/flywheel:add`→backlog→`/next`）の初 dogfood** で実装した（ROADMAP に積む→/add で軽量 grill→/next で起動→実装→done を実機で完走）。

### 0.8.12
- **grill が判断を必ず聞く + ROADMAP をメイン機能に** — **(1)** grill が「コードで答えが出るなら聞くな（肝）」を *判断* にまで広げて self-answer し、ユーザーに質問しなくなる問題（実会話で発生）を矯正。`skills/grill/SKILL.md`（原則 + Gotcha）・`hooks/plan-steer.sh`（FR-24・plan mode steer）・`commands/add.md`（軽量 grill）の3箇所に「**self-answer は *事実*（コードに答えがある）のみ。*判断*（スコープ/トレードオフ/優先順位/命名/案の選択）は必ず聞く・迷ったら聞く側**」を明文化。**(2)** `ROADMAP.md` を flywheel の**中核ワークフローの源**に: ヘッダに「源 → `/flywheel:add`（軽量 grill で phase 化）→ backlog → `/flywheel:next` → 実装」の回し方 + 状態列に「backlog 中」、`skills/guide/SKILL.md` のルート選択に ROADMAP 取り込み枝を追加。新コマンド・テーブル parse は作らず既存の `/add`→`/next` で繋ぐ（「使われない入口を増やさない」原則）。

### 0.8.11
- **adopt chain をスラッシュから駆動 + `/add` に軽量 grill-me（雑な add を防ぐ）** — v0.8.10 の adopt chain は CLI のみで入口が無かったため `/flywheel:next`・`/flywheel:add`（`commands/next.md`・`add.md`）を追加。さらに `/flywheel:add` は単に積むのでなく**軽量 grill（Done / Boundary / 依存・曖昧点の3点）で phase を練ってから積む**オーケストレーションにした。`adopt` は掘らない（結晶化）ので、雑な add がそのまま next→design→実装に直行するのを入口で防ぐ。grill 成果は backlog entry の `notes`（Boundary/曖昧点）+ `eval_cmd`（Done）に保存し、`next` 起動時に `state.notes` へ引き継ぐ（別セッション跨ぎでも揮発しない）。`flywheel list` が `[notes ✓]`、`status` が notes 行を表示。`.notes // ""` で後方互換。フル grill は start / plan mode 側に任せ、add は3点に留める。**非スコープ**: `/adopt` の「backlog 全部一気」（auto-chain・loop-driver 変更）は次 phase に切り出し。

### 0.8.10
- **task 分解の型 + adopt chain（cc-sdd 参考）** — 「plan を phase ごとに作る」運用を flywheel ネイティブに。**(A 型)** `skills/design/SKILL.md` に「## Tasks（`Boundary:`/`Depends:`/`Done:`）」セクションを促す型を追加。task を恣意的な数でなく **design の File Structure Plan（ファイル境界）から構造的に割る**（cc-sdd の Boundary/Depends 由来）。異なる task の Boundary が重なれば統合＝分割ミスを検出できる。**(B adopt chain)** `flywheel add --adopt "<task>"` で backlog に **adopt 経路で**積み、`flywheel next` が `entry` を尊重して**掘らず結晶化起動**する（従来 `next` は start 固定で毎回 designing の掘り直しが挟まった）。`flywheel list` が `[entry]` を表示、`.entry // "start"` で**後方互換**。これで「task を綺麗に割る型 × 各 task を逐次 adopt で回す」が繋がる。flywheel 自身を adopt で起動して dogfood（型を実戦投入 → Boundary 重複で T3→T1 統合を検出 → 監視 council clean → done）。follow-up: 完了条件 eval を grep から mktemp 実行時テストに厚く（監視 council の non-blocking 指摘）。

### 0.8.9
- **マルチレポ対応（最小スコープ）— diff/polish が宣言した sibling repo を合算** — flywheel は FW_ROOT 単一リポ前提で、関連リポに跨る goal（例: app + shared-python-lib を同時に直す）では `fw_goal_diff_lines` が FW_ROOT しか測らず polish 判定が**過少カウント**＝「半分しか検証されない」状態だった。`flywheel repos <path>...` で sibling repo を登録（登録時に各リポの baseline=jj `@-`/git `HEAD` を捕捉）し、`fw_goal_diff_lines` が FW_ROOT + 宣言リポの diff を合算する。`fw_repo_baseline`/`fw_repo_dir`/`fw_repo_diff_lines` に per-repo 化（VCS 種別は cwd ベースで自動検出＝jj/git 混在可）。eval は eval_cmd が shell 文字列で既に跨げるため**不変**（`... && uv run --directory ../lib pytest`）。`set-eval`/`monitor-set` と同型の CLI（`fw_state_exists` ガード・phase 不問）。**非スコープ**: cross-repo 編集の gate/自動昇格（#5 は `flywheel go` で代替）/ per-repo の独立 done。flywheel 自身の実 goal で dogfood し、done 前の監視 council が FR-D（`status` の baseline 表示欠落）を drift 検出 → 差し戻し → 修正 → done まで完走。

### 0.8.8
- **`flywheel go` の usage 記録を削除（計測の一貫性）** — v0.8.7 で go だけ `fw_log_usage "go"` を記録していたが、同型のはずの `set-eval`/`monitor-set`/`verify-set` はどれも記録しておらず**片肺**だった。さらに evolve は `skill-usage.csv` を「スキル名」として読む（`grep -v ',steer:'` で steer 行だけ除外）ため、裸の `go` 行は無効スキル名の**ノイズ**になる。記録を外して介入系 CLI サブコマンドと挙動を揃えた（起動計測の正は `fw_init` の `goal:*`。go は spec-ready→implementing の昇格であって新規起動ではないので `goal:*` の対象でもない）。挙動（昇格ロジック・ゲート）は v0.8.7 と不変。

### 0.8.7
- **`flywheel go` — 非コード goal を spec-ready から手動昇格（H-1 解消）** — Bash 運用 / docs のみの非コード goal は source 編集が発生せず、`design-gate.sh` の「spec-ready で最初の source 編集 → implementing 昇格」が永久に発火せず **spec-ready で詰まっていた**（逃げは `FLYWHEEL_OFF=1`＝flywheel を切るしかなかった）。偽の source 編集を捏造させず、CLI 入口 `flywheel go` で spec-ready→implementing を昇格する正規ルートを追加（`design-gate` の「最初の source 編集」の非コード版）。eval / veto / polish / monitor / done は既存 loop-driver に委譲（polish は diff≒0 で自動 skip され無害）。**thick eval 必須**（`eval_cmd` 非空 かつ `eval_src ∈ {explicit, spec}`、薄い `auto` eval / eval 無しは拒否し `set-eval` か design.md 完了条件を促す）＝薄い eval での空振り done を入口で防ぐ。**spec-ready 限定**（`designing`/`no-spec` は設計スキップの裏口防止のため拒否、`implementing` 以降は no-op）。`set-eval`/`monitor-set`/`verify-set` と同型（`fw_state_exists` ガード・`FLYWHEEL_HOOK` ガードなし＝CLI の state 書き込みは C-2 対象外）。

### 0.8.6
- **handoff に「CLAUDE.md ↔ README drift チェック」を追加（非ブロック nudge）** — CLAUDE.md は更新する道具（`/claude-md-management:revise-claude-md`）はあるのに起動の「きっかけ」が無く、README/実態だけ進んで取り残されがちだった（実運用で README と CLAUDE.md の内容が食い違う事故が発生）。handoff の区切りの瞬間に Step 4 として鮮度チェックを差し込み、CLAUDE.md と README が**両方ある時だけ**・drift シグナル（`jj diff -s`/`git status` で README だけ変更／Recap が規約・手順変更を含む／二重記述の矛盾）がある時だけ、何がズレているか名指しで revise-claude-md を促す。**自動書き換えはしない**（drift の自動修正は新たな drift を生むため判断はユーザー/skill に委ねる）。handoff 本体は絶対にブロックしない。

### 0.8.5
- **`flywheel set-eval "<cmd>"` — 飛行中に eval_cmd を直す（gap B 解消）** — `eval_cmd` は spec-ready 以降 immutable で、design.md の完了条件から昇格した eval が誤っていた / 構成が変わった場合、`flywheel reset` で designing からやり直すしかなかった（dogfood で「reset 地獄」を踏んだ）。`monitor-set`/`verify-set` と同型の CLI 入口を追加（`fw_state_exists` ガード・**phase 不問**・`FLYWHEEL_HOOK` ガードなし＝CLI の state 書き込みは C-2 対象外、禁止はモデルによる state.json 直編集のみ）。`eval_cmd` と `eval_src=explicit` を書くので、FR-32 の `fw_eval_is_thin`（`eval_src=auto`）ゲートも自然に外れる。

### 0.8.4
- **fix: eval 自動検出を uv/bun/pnpm/yarn 対応** — `fw_detect_eval` が `pytest`/`npm` を直叩きしていたため、uv プロジェクト（`uv.lock`/`[tool.uv]`）では `.venv` の pytest が PATH に無く `command not found`、bun プロジェクトでは npm script が解決できなかった（loop-driver は mise shims しか PATH 前置しない）。lockfile から実ランナーを判定し `uv run` / `bun run` / `pnpm run` / `yarn run` を前置。
- **FR-32: verification を eval 薄プロジェクト限定の done 前 blocking ゲートに** — `steer:verification` が発行されても実行 0 件だったのは、verification が done 後の optional nudge（`exit 0`）で強制力ゼロだったため。`eval_src=auto`（プロジェクト全体検出＝goal 固有の振る舞いを見ていない薄い eval）のときだけ、`verify-set`（`monitor-set` ミラー）で挙動エビデンス確認を done の条件にする blocking ゲートを追加（`vcap` で空振り防止）。`explicit`（`--eval`）/ `spec`（design.md 完了条件）の厚い eval は対象外。
- **ROADMAP.md 追加** — dogfooding retrospective の改善 backlog（gap B = eval immutable / H-1 = 非コード goal 詰まり / マルチレポ未対応 等をレバレッジ順に）。

### 0.8.3
- **`flywheel:guide` スキル（駆動の決定ガイド）** — flywheel をどう回すか迷ったときの「地図」を1枚で。現在 phase の動的表示（`!flywheel status`）+ ルート選択の決定木（plan route / start / adopt / 既存追加 / bypass）+ 設計フェーズの artifact 別 next + 実装→done loop + よくある詰まり + CLI/env チート。**実挙動は再実装せず hook の live steer に委ねる**方針（ズレたら hook が正、と明記）。user スコープのプラグインなので `/flywheel:guide` でどのセッションからでも呼べる

### 0.8.2
- **計測の置き場を evolve と統一（FR-31 の完成）** — FR-31 で全 start 経路が `goal:*` を記録するようにしたが、`fw_log_usage` の fallback 先（`~/.claude/flywheel-data`）が evolve のデータ解決（`~/.claude/plugins/data/flywheel-*`）と食い違っており、**hook 経路（plan route）は本番 CSV / CLI 経路（command の `!` 行・素の CLI）は fallback CSV** へと記録先が割れていた（evolve は本番のみ読むので CLI 経路の `goal:start` を取りこぼす）。`fw_log_usage` のデータ解決を evolve と同順（`CLAUDE_PLUGIN_DATA` → plugin データ領域 → 最後の保険）に揃え、全経路が evolve の読む1ファイルに集約されるようにした。観測漏れが経路・置き場の両面で塞がった

### 0.8.1
- **goal-start を全 start 経路で計測（FR-31）** — `flywheel:start`（skill 経路）しか skill-usage.csv に乗らず、**plan route（Shift+Tab→承認）と `flywheel start` CLI と auto-engage の起動が観測漏れ**していた（推奨経路の plan route ほど記録が消えるという逆転）。全 start 経路の共通 chokepoint である `fw_init` に計測を1箇所追加し、経路を手元 signal から導出して `goal:plan`（plan route）/ `goal:adopt`（adopt）/ `goal:start`（CLI start/next・auto）として記録。総 start 数 = `goal:*` の件数で経路に依らず取れるようになり、evolve の実績データが起動回数を取りこぼさなくなった

### 0.8.0
- **監視 council（done-gate 検証）— 別 verifier で drift を潰す（FR-30）** — eval 緑（polish 後）→ done の直前に監視 council を1回走らせ、eval（静的）が捉えられない drift を実装文脈を持たない第三者の目で検証する。記事 Loop Engineering の「Verifier を別に」「検証の死角」への解毒剤
  - `Skill: flywheel:monitor`（overseer）が観測者 3 レンズ（**要件逸脱 / 挙動 / 進捗**）を `flywheel:drift-observer`（Read-only）で fan-out → confidence-scoring + 降格マトリクスで単独集約（observer 間 peer cross-check はしない）→ `flywheel monitor-set <status> [level] [reason]` で verdict を記録
  - drift の執行は loop-driver に集約。drift フラグは CLI 経由で state に書く（hook から Agent は spawn 不可・design-gate が `.flywheel/` への model 書込をブロックするため）
  - **巻き戻し天井**: 自動で戻れるのは implementing まで（差し戻して継続）。design / requirements レベルの drift は phase=designing に戻して**人間に hand-back**（自動ループしない）
  - **監視ループの hand-back cap**: `monitor_attempts`（eval veto と別系統・green 領域専用カウンタ）が `FLYWHEEL_MONITOR_CAP`（既定 8）到達で必ず人間に返す。skill 不調で verdict が出ない / drift が解消しない場合でも無限ループしない（eval veto は green ごとにリセットされ監視ループに効かないため別カウンタが必要だった）
  - **HITL**: `flywheel watch-focus "<text>"` で人間が監視の重点を指定でき、overseer が観測者に渡す。verdict は `flywheel status` で確認可
  - state に `watch_focus` / `monitor` / `monitor_attempts` を追加。eval 失敗（緑が崩れた）時は monitor と試行回数をクリアして次の緑で再検証。monitor は LLM 判断であり決定論ゲートは eval が担う前提を維持
  - **continuous mid-run watchdog は非スコープ（v2）**。drift→loop-driver の執行経路は共通なので無改修で後付けできる設計

### 0.7.0
- **会話 / handoff 合意からの adopt 入口（FR-29）** — designing への第3の入り方。会話 or `.claude/journal.md`（handoff 経由）で既に合意した実装方針を、要件をゼロから掘り直さず **design.md に結晶化**して loop に載せる。plan-approved（FR-22）と同型だが plan mode を経由しない
  - `/flywheel:adopt <一言サマリ>`（主入口）/ `flywheel adopt "..."`（CLI ヘルパー）。source 解決は会話の合意 > journal の最新 Next Actions
  - **handoff → adopt が最自然フロー**: 別マシン / 新セッションは会話コンテキストが空なので、handoff で固めた Next Actions を結晶化するのが本筋
  - start との違いは designing の steer だけ（`entry:"adopt"` を state に記録 → `fw_designing_steer` が「掘るな・結晶化せよ」に分岐）。design.md → validate → spec-ready → implementing の配線は完全共有。**検証は通す**（完了条件セクションが無ければ差し戻し = done を定義しないまま実装に入らせない）。C-2 不変（state は CLI、design.md はモデル、門は validate の exit code）
  - designing の入り方が3通りに: **start=掘る / plan mode=作って承認 / adopt=結晶化**

### 0.6.0
- **調査・検証の sub-agent 委譲（FR-26）** — Claude Code 2.1.172 の nested subagents（sub-agent が子を spawn できる・最大5階層）を配線。「判断は強く、収集は薄く」の二層構造:
  - **council メンバーの調査委譲** — researcher / analyst / scout に Agent ツールを付与。大きいコードベースの sweep（類似機能トレース・境界把握・規約抽出）を code-explorer / architecture-mapper / convention-scout の子に委譲し、「探した過程は捨てて結論だけ持つ」。requirements.md の質が context 汚染に律速されなくなる
  - **critic の adversarial verify** — critical / high の指摘ごとに反証専門の子を spawn してから報告。反証が成立した指摘は落とさず confidence を下げて反証根拠を併記（Coverage-first 維持）。確証バイアス対策
  - **verification の観測委譲** — 挙動検証のログ / 出力ダンプは子に収集させ、判定（VERIFY）だけ自分でやる（Iron Law は委譲しても緩まない）
  - **モデル方針** — 判断層（analyst / scout / researcher / critic / designer）と解釈系の収集層（code-explorer / architecture-mapper）は `sonnet`/`opus` 固定をやめ `inherit` に（main loop が Fable / Opus ならその質で判断）。skill 側の固定（discovery-council=sonnet / design=opus）も撤去——固定するとメンバーの inherit がそれを継承して二層構造が崩れるため。列挙系の子だけ呼び出し側が `haiku` を明示。迷ったら継承・期待と食い違えば継承モデルで撃ち直し（staged escalation）。heuristics は capabilities.md に集約
  - 要 2.1.172+（旧版では子に Agent が渡らず従来の自前調査に degrade）。nested の活動は skill-logger に乗らない（計測拡張は将来候補）

### 0.5.2
- **進捗方向の検知 + revert 規律（FR-25）** — veto loop が方向を持つ。eval 出力から fail 数を best-effort 抽出（pytest/ruff/ty/go 等）し、前回比で steer を変える: 📉改善=続行 / ➡️横ばい=別仮説へ / 📈**悪化=直前の変更を戻してから別アプローチ**（失敗を積んだまま重ねない）。green で baseline=0 にするため polish 後の regression は即 revert steer。cap までの8回を「同じ穴を掘る8回」にしない。

### 0.5.1
実戦投入（FR-19 が本番初動作・designing→done 46分）のレビューで見つけた穴を3点:
- **C-2 enforcement** — モデルが `flywheel _advance done` を直接叩いて eval 判定を迂回した実例（自己申告 done）への対策。`_advance` は `FLYWHEEL_HOOK=1` 必須に、`.flywheel/`（state）への Edit/Write は design-gate が全 phase でブロック。steer は「停止すれば loop-driver が eval で判定する」と正しい道へ誘導
- **fix: evolve の計測データ読み先** — 本番の skill-usage.csv は `~/.claude/plugins/data/flywheel-*/`（CLAUDE_PLUGIN_DATA）に溜まるが、main loop で動く evolve は fallback を読んでいた。解決順（env → plugins/data → fallback）を導入
- テスト規約: hook を直接叩くテストは `CLAUDE_PLUGIN_DATA` を /tmp に明示設定

### 0.5.0
**plan-mode route** — 「auto mode のまま全てを解く」前提を撤回し、native plan mode に compose。「しっかり = plan mode（Shift+Tab）、ワンショット = auto」のモード選択を誤爆ゼロの意図シグナルとして使う:
- **plan-steer（FR-24）** — engage 中の plan mode で grill の操作系（決定点列挙 / self-answer first / 1問ずつ推奨付き / 非スコープ・完了条件必須）を毎プロンプト注入。**grill を skill 発動依存から外し既定動作に**
- **plan-gate（FR-21）** — ExitPlanMode の計画テキストを検証し、非スコープ / 完了条件の無い計画は差し戻し。「ユーザーに提示される計画は検証済みのみ」
- **plan-approved（FR-22）** — 承認の瞬間に hook が計画を plan/design.md へ artifact 化 + 完了条件を eval_cmd 昇格 + implementing へ。モデルは計画を提示するだけ
- engage は `FLYWHEEL_PLAN=1` opt-in（FR-23）。intent-router は legacy 凍結。designing の read-only 強制は native が担い H-1（Bash 素通り）解決

<details>
<summary>0.4.x 以前</summary>

### 0.4.8
- **fix: `!` 動的注入行の permission check 拒否** — skill/command の `!` 行に shell 変数展開があると「Contains simple_expansion」で弾かれ skill 自体が起動失敗する。grill の Step 0 と `/flywheel:start` の起動行を展開フリーに書き直し
- **grill の plan-mode 適応（v0.5 先行）** — 対象優先 0 に「plan mode 中に会話で構成している計画」を追加
- v0.5 spec（plan-mode route への転回・FR-21/22/23）と spike 実証結果を plan/ に確定

### 0.4.7
- **fix: slash command の PATH 依存（FR-16 改）** — `/flywheel:start` が裸の `flywheel` を呼んでいたため、CLI を PATH に通したマシンでしか動かなかった。`${CLAUDE_PLUGIN_ROOT}/bin/flywheel` 経由に変更し、**plugin を install すれば全ディレクトリ・全マシンで動く**ように
- **空引数の degrade** — `/flywheel:start` の引数なし実行を error から status 表示 + モデル誘導に変更

### 0.4.6
- **polish の diff 適応（FR-20）** — start 時に baseline revision（jj `@-` / git HEAD）を記録し、初回 eval 合格時の累積変更行数が閾値（既定 30）未満なら polish を省略して即 done。計測不能（VCS なし）は従来どおり polish（degrade）
- **`/code-review` の運用方針を明文化** — 意図的に配線しない。推奨: done 後 push 前に `/code-review`

### 0.4.5
- **spec-designed eval（FR-19）** — design.md の `## 完了条件（eval）` を validate-plan の必須セクションにし、fenced block のコマンドを validate 合格時に eval_cmd へ昇格（解決順: `--eval` 明示 > spec > 自動検出 > 空）。deep-interview に DONE 軸、grill に完了条件の枝を追加。eval が「プロジェクト全体の test が通る」から「**この goal の完了条件**」に変わった

### 0.4.4
- **skill-logger hook（FR-18）** — PreToolUse(Skill) で全 skill 使用を CSV 記録。steer 発行も同 CSV に載るため steer 従命率が測れる。evolve の入力を実配線
- **evolve の自己完結化** — 旧 plugin への死に参照を除去、改善案の置き場を `improvements.md` に変更

### 0.4.3
- **active 時の再アンカー（FR-17 拡張）** — goal 進行中のセッション開始・compaction 復帰時に session-greeter が phase/goal/次手を context へ再注入
- **native `/goal` 併用の実配線** — `flywheel start` の出力と `/flywheel:start` に併用案内を追加
- **done 時の verification 提案（非ブロック）**

### 0.4.2
- **polish を eval 後に移動（FR-11 改 = polish-on-green）** — 新: implementing→eval→初回 green で1回だけ polish→再 eval→done。修正ループは eval 最短で回り、磨く対象は修正込みの最終形（make it work, then make it right）
- **spec-ready 停止の空振り done 防止** — 門が開いた直後に source 未編集のまま停止しても eval を回さず実装開始を steer
- fix: intent-router の前回 plan 退避漏れ / NotebookEdit の gate 素通り
- 頑健性: eval の自前 timeout（既定 540s）/ mise shims を PATH 前置 / goal 切り出しの UTF-8 安全化 / リポ外書き込みを gate 対象外に

### 0.4.1
- **SessionStart 入口案内（FR-17）** — dormant なセッション冒頭で入口を1行案内（`session-greeter`）。gate は閉じない

### 0.4.0
- **eval 自動検出（FR-14）** — `--eval` 省略でプロジェクト（pyproject/package.json/Cargo/go.mod）から test/lint/型チェックを自動検出
- **intent-router: invisible auto-engage（FR-15, opt-in）** — `FLYWHEEL_AUTO=1` で build 意図の prompt を検知し自動 start
- **slash command（FR-16）** — `/flywheel:start <作りたいもの>`

### 0.3.0
- **judgment library を同梱して自己完結化** — `validate-plan`(CLI) + designing フェーズの skill/agent を移設。実行時の外部依存ゼロ
- **designing パイプライン統合** — design-gate が plan/ の artifact を見て次の設計ステップを steer: 要件無し→`deep-interview`/`discovery-council`、要件のみ→`design`、設計あり→`grill`

### 0.2.0
- **polish フェーズ(FR-11)** / **完了スペックの archive(FR-12)** / **backlog ルート(FR-13)**: `flywheel add/list/next`
- fix: state 読取の空フィールド畳まれ問題を Unit Separator(0x1F) で解消

### 0.1.0
- walking skeleton: design-gate / design-validator / loop-driver / state machine / bin/flywheel

</details>
