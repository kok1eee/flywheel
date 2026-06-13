# flywheel

> **Claude Code を「設計してから作る」マシンにする plugin。** 設計が無ければ実装ツールを hook が物理的にブロックし、設計が validate を通って初めて実装ゲートが開き、goal の完了条件（eval）を満たすまで自動で回り続ける。設計フェーズの judgment library（grill / critic / scout / discovery-council 等の skill・agent）と `validate-plan` を同梱した自己完結プラグイン。

v0.5.2 / MIT License

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
| `loop-driver` | Stop | implementing → eval（CLI 判定）→ 初回合格で polish（simplify を goal につき1回 steer）→ 再 eval → done。未達なら veto。fail 数の前回比で 📉改善=続行 / ➡️横ばい=別仮説 / 📈悪化=revert を steer |
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
| `FLYWHEEL_EVAL_TIMEOUT` | 540 | eval コマンドの打ち切り秒数 |
| `FLYWHEEL_POLISH_MIN_DIFF` | 30 | 累積変更行数がこれ未満なら polish を省略 |
| `FLYWHEEL_VALIDATE_PLAN` | — | validate-plan 実体の明示パス（通常は同梱版が自動解決） |
| `FLYWHEEL_AUTO` | off | legacy: build 意図の prompt で自動 engage（plan route が上位互換） |

## 同梱物

designing フェーズの judgment library を同梱し、**実行時の外部 plugin 依存ゼロ**で完結する:

- **skills**: `grill`（plan を対話で詰問）/ `design` / `discovery-council` / `deep-interview` / `verification` / `evolve` / `handoff`
- **agents**: critic / scout / designer / researcher / analyst / debugger / security-reviewer / コード理解系（code-explorer, architecture-mapper, convention-scout）/ prior-art 系（market-researcher, oss-scout, pattern-observer）
- **bin**: `flywheel`（CLI）/ `validate-plan`（設計の形式検証）

（作者の旧 plugin「o-m-cc」の後継。flywheel = loop を強制し steer する harness、o-m-cc = 判断知ライブラリという分業だったが、designing に必要な分は移設済み）

## 詳細

設計判断の全記録は [plan/design.md](plan/design.md) / [plan/requirements.md](plan/requirements.md) 参照。今後候補: FR-3 headless 分岐（grill↔critic）、eval の挙動検証（verification 統合）、`FLYWHEEL_PLAN` の default 化判断、backlog auto-chain。

## Changelog

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
