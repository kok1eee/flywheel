# flywheel — design

> requirements.md の FR-1〜FR-10 を、hook・state machine・gate ロジックに落とす設計。v1 は walking skeleton（FR scope は各 FR の「v1」欄を参照）。

## 設計原則（o-m-cc から継承し、1点だけ反転）

| 継承する原則 | flywheel での扱い |
|---|---|
| Lightweight（Markdown + Shell、ビルド不要） | 継承。hook は Bash + `set -euo pipefail` + 共通 lib |
| Plugin ネイティブ（settings.json で自動設定） | 継承。`.claude-plugin/plugin.json` + `hooks/hooks.json` |
| peer-to-peer（中央オーケストレーター不在） | 継承。loop は **hook + state machine** が駆動（agent ではない）|
| Guides × Sensors の2軸 | **Sensors に全振り**。Guides（prose 誘導）は補助に降格し、門・継続は Sensor が強制 |
| Progressive Disclosure | 継承。state file は最小、判断知は o-m-cc 側に置く |

**反転点**: o-m-cc は「設計しよう」と Guides で誘導 → auto mode が飛ばす。flywheel は「設計が無いなら実装を通さない」を Sensor で物理強制（FR-1）。これが唯一にして最大の差別化。

## アーキテクチャ全体図

```
                    ┌─────────────── state file (.flywheel/state.json) ───────────────┐
                    │  { phase, goal, design_path, eval_criteria, history[] }          │
                    └──────────────────────────────┬──────────────────────────────────┘
                          read ▲          read ▲   │   read ▲           read ▲
                               │                │   │        │                │
  ① 適当prompt          [design-gate]      [loop-driver]  [phase-tracker]   [eval-gate]
       │              PreToolUse(FR-1)    Stop(FR-5)     Post*(FR-7)      Stop/eval(FR-6)
       ▼                    │ block             │ 継続          │ 遷移            │ 判定
  UserPromptSubmit ───▶ phase 判定 ──┐         │              │                │
   (intent 検知)                     │         ▼              ▼                ▼
                                     └──▶ o-m-cc skill を steer（FR-8 / compose の2系統）
                                          design / discovery-council / grill /
                                          critic / scout / sisyphus / verification
```

flywheel が**所有する**のは: state machine・4 つの hook・gate ロジック・bin/flywheel CLI。
flywheel が**呼ぶ**のは: o-m-cc の skill / agent / bin（FR-8、再実装しない）。

## state machine（FR-7）

state file: `.flywheel/state.json`（リポ root 直下。o-m-cc の plan/ と並ぶ）

```
no-spec ──①prompt(intent検知)──▶ designing ──┐
   ▲                                          │ grill/critic で叩く（FR-3）
   │                                          ▼
   │                              validate-plan design 合格?（FR-4）
   │                                  │ no ──┐
   │                                  │      └─▶ designing に留まる（設計 loop）
   │                                  │ yes
   │                                  ▼
   │                              spec-ready ══門開く（FR-1 解錠）══▶ implementing
   │                                                                      │
   │                              eval（eval-gate 判定 ty/ruff/test）◀─────┘
   │                                  │ 未達(FR-5) ──▶ implementing に戻る（修正 loop。polish は挟まない）
   │                                  │ 初回合格
   │                                  ▼
   │                              polish（simplify steer, FR-11・goal につき1回）
   │                                  │
   │  goal 達成(FR-6) ◀───────── 再 eval（simplify が壊していないか）
   │       │ 合格                     │ 未達 ─▶ implementing（犯人は simplify と確定）
   │       ▼
   └──── done
```

| phase | design-gate(FR-1) | loop-driver(FR-5) | 意味 |
|---|---|---|---|
| `no-spec` | **block** 実装ツール | — | まだ設計が無い |
| `designing` | **block** 実装ツール | 設計 loop 継続 | 設計を立てて叩いている最中 |
| `spec-ready` | **open** | 実装開始を steer（veto。空振り eval 防止） | validate 合格。実装に入れる |
| `implementing` | open | **継続**（止めない） | 実装中 |
| `polish` | open | simplify を steer → 再 eval へ | 初回 eval 合格後の整理1ターン（FR-11・1回だけ）|
| `eval` | open | 未達なら implementing へ veto | 完了判定中（ty/ruff/test）|
| `done` | open | 停止許可 | goal 達成。loop 終了 |

state は各 hook が読み、**hook（Sensor）が書く**。会話履歴に非依存（FR-7）。

### state を誰が進めるか（自己矛盾の回避・最重要）

**原則: state 遷移は全て hook がモデルの自然なツール使用を観測して進める。モデルは一度も state を進めない。** モデルに `bin/flywheel state set` を撃たせる設計は禁止——それは「auto mode でモデルがアクションを撃たない」という flywheel が殺そうとしている問題の再発であり、自己矛盾になる。モデルは「設計を書く / コードを書く」という**作業だけ**を行い、harness がそれを観測して門を開閉する。

> **v0.5.1 enforcement**: この原則は kakuduke 実戦（2026-06-12）で実際に破られた——モデルが `flywheel _advance done "eval pass + ..."` を Bash で直接実行し、loop-driver の eval 判定・polish・archive を迂回した（結果は偶然正しかったが自己申告 done）。対策: ① `_advance` は `FLYWHEEL_HOOK=1` 必須の env ガード（hook とテストだけが立てる）、② `.flywheel/` への Edit/Write を design-gate が**全 phase で**ブロック。Bash による state 直書きまでは塞がない（H-1 と同じ割り切り）が、どちらの steer も「停止すれば loop-driver が eval で判定する」と正しい道を教える。

| 遷移 | 駆動する hook（イベント） | hook が観測するもの |
|---|---|---|
| `no-spec → designing` | **intent-router**（UserPromptSubmit） | prompt が新規作業意図 → state を designing にし設計を steer |
| `designing → spec-ready` | **design-validator**（PostToolUse, Write→plan/design.md） | design.md 書き込みを検知 → `validate-plan design` を自動実行 → 合格で遷移 |
| `spec-ready → implementing` | **design-gate**（PreToolUse, 最初の source 編集を許可した瞬間） | 門が開いて最初の実装編集が通った → implementing へ |
| `implementing → eval` | **loop-driver**（Stop） | モデルが turn を終えようとした → eval phase へ送り eval-gate 起動 |
| `eval → polish` | **loop-driver**（Stop, 初回 eval 合格時） | green を観測 → simplify を steer（`polished` フラグで goal につき1回だけ） |
| `eval → done / implementing` | **loop-driver + eval-gate**（Stop） | eval 基準を CLI で判定 → polish 済みで合格なら done、未達で implementing に戻す |

CLI（validate-plan / test / build）は hook が**直接実行**できる。skill（design/grill/critic/sisyphus/verification）は hook が**直接呼べない**ので exit 2 + steer メッセージでモデルに撃たせる（下記「compose の2系統」）。どちらも state 遷移自体は hook が書くので、モデルの撃ち損ねは state を壊さない。

## v0.5: plan-mode route（モード = 意図シグナル・2ルート構成）

「auto mode のまま全てを解く」前提を撤回し、native plan mode に compose する（継続を /goal に委ねた C-1 と同じ移動を、門に対して行う）:

| | **plan-mode route**（対話・主） | **CLI route**(headless・従) |
|---|---|---|
| 入口 | ユーザーが Shift+Tab で plan mode（+ `FLYWHEEL_PLAN=1`・FR-23） | `flywheel start` / `next` / intent-router(legacy) |
| designing | native plan mode（read-only は harness 強制 = **H-1 解決**。grill/deep-interview は read-only で動くのでそのまま使える） | designing phase + design-gate（従来どおり） |
| 門 | **plan-gate**: PreToolUse(ExitPlanMode) が計画テキストを検証・差し戻し（FR-21） | design-gate + design-validator（FR-1/FR-4） |
| 開錠 | **ユーザー承認** → plan-approved が spec を artifact 化 + eval 昇格 + implementing（FR-22） | validate-plan 合格で spec-ready |
| 以後 | loop-driver（共通: eval veto / polish-on-green / cap） | 同左 |

### spike 結果（2026-06-12・実機確認済み）
- **PreToolUse(ExitPlanMode)**: 発火する / `tool_input.plan` に計画全文 / `permission_mode` 取得可 / **exit 2 で差し戻し → haiku でも steer に1回で従い「## 完了条件」を自分で設計**した
- **PostToolUse(ExitPlanMode)**: **ユーザー承認の瞬間に発火** / `tool_response.plan` に承認済み計画全文 / `permission_mode` は承認後モード（auto 等）に切替済み
- 計画は native でも `~/.claude/plans/*.md` に保存される（参考情報）
- 公式 docs: plan mode は Bash 書き込みも含め read-only を強制 / 承認後モードはユーザー選択 / 対話では PermissionRequest event も使えるが headless で発火しないため PreToolUse を主軸にする

### 新 hook（v0.5.0 実装済み）
- **plan-steer（UserPromptSubmit）— FR-24**: engage 中かつ `permission_mode == plan` のとき、grill 操作系の圧縮版（決定点列挙 / self-answer first / AskUserQuestion 1問ずつ推奨付き / 非スコープ・完了条件を計画に必須）を additionalContext で毎プロンプト注入。**grill を skill 発動依存から外し既定動作にする**（明示 `/flywheel:grill` はオンデマンド深掘り・CLI route 用に存置）
- **plan-gate（PreToolUse, matcher: ExitPlanMode）— FR-21**: `FLYWHEEL_PLAN=1` のとき `tool_input.plan` を検証（必須: 非スコープ / 「## 完了条件（eval）」+ fenced command。hook 内 grep の軽量判定——ファイル前提の validate-plan はここでは使わない）。不合格 → exit 2 + 不足列挙
- **plan-approved（PostToolUse, matcher: ExitPlanMode）— FR-22**: `fw_archive_plan` で前回退避 → `tool_response.plan` を `plan/design.md` へ書き出し → `fw_extract_spec_eval` で eval_cmd 昇格 → state 生成（goal = 計画の見出し、phase=implementing、baseline・承認後 permission_mode 記録）→ 以後 loop-driver

> UserPromptSubmit の input JSON に `permission_mode` が含まれることも実機確認済み（2026-06-12 ミニ spike: `{"event":"UserPromptSubmit","permission_mode":"plan"}`）。

実装順: plan-gate / plan-approved + テスト（spike の headless 手法を流用）→ dogfood → `FLYWHEEL_PLAN` の default 化判断。

**designing スキル群の plan-mode 適応**: deep-interview / grill は read-only ツールのみなので plan mode 中そのまま動く。grill の対象優先 0 は「会話で構成中の計画」（v0.4.8 で追加——詰めた結果は ExitPlanMode の計画テキストに反映し、ファイル化は承認時の hook が担う）。designer agent（design.md を Write する）は CLI route 専用——plan-mode route では計画文書は会話で構成する。

> **実装上の制約（v0.4.8 で実地に踏んだ）**: skill / command の `!` 動的注入行は permission checker が静的検査し、**shell 変数展開（`$f` 等）や command substitution を含むと「Contains simple_expansion」で弾かれて skill 自体が起動失敗する**。`!` 行は展開フリーで書く（`$ARGUMENTS` / `${CLAUDE_PLUGIN_ROOT}` はローダーがテキスト置換するので可）。

## hook 設計

### design-gate（PreToolUse, matcher: Edit|Write|Bash）— FR-1, FR-2
1. state.json を読む。phase が `spec-ready`/`implementing`/`eval`/`done` なら **即 pass**（門は開いている）。
2. phase が `no-spec`/`designing` のとき、ツール使用が**実装意図**か判定:
   - **v1: Edit/Write の対象が plan/ ・ .flywheel/ ・ docs/ ・ README 以外（= source）→ 実装意図 として block**
   - **v1: Bash は常に pass**（H-1: `pytest` と `python analyze.py` を正規表現で安定区別できない。過検知で bypass 常態化 or 未検知で素通り、どちらも価値命題を壊す。Bash の実装意図判定は精度を上げてから v2 で導入）
   - **リポ外（FW_ROOT 外: /tmp 等）への書き込みは実装意図とみなさない**（設計フェーズの調査スクラッチを塞がない・v0.4.2）
   - それ以外（調査 grep、plan/ への書き込み等）→ pass
3. 実装意図 ×（`no-spec`/`designing`）→ **exit 2 + steer**: 「設計フェーズ未完了。先に `plan/design.md` を書き `validate-plan` を通せ。bypass は FLYWHEEL_OFF=1」
4. `FLYWHEEL_OFF=1` なら全 pass（FR-10）。

> **FR-2 の重さ自動スケール**は「別経路で素通り」させない＝門は常に判定する。些末さは設計フェーズ側（grill のトリアージ）が「設計=自明、即 validate 合格」で吸収し、state を素早く `spec-ready` に送ることで実現する。design-gate 自身に閾値ロジックは持たせない（責務分離）。

### loop-driver（Stop hook）— FR-5, FR-9, FR-6
**継続そのものは native `/goal` に compose する（C-1 対策）。** Stop hook で turn 継続を自作すると、Claude Code の Stop hook 連続 block の **セッション cap（〜8回）** に当たり「goal 達成まで止まらない」が 8 ターンで打ち切られうる。しかも o-m-cc に Stop hook 実績がゼロで未検証。よって:
- **継続エンジン = native `/goal`**（ターン跨ぎ継続は元々これの仕事。①の入口で goal を確立し、native が turn を運ぶ）
- **flywheel の Stop hook = polish 挿入 + eval veto に徹する**:
  - phase が `spec-ready`/`implementing` → `polish` に進め、`Skill: simplify` を steer して exit 2（モデルに整理の1ターンを与える、FR-11）。polish 無効時（`--no-polish`）はこの段を飛ばして直接 eval。
  - phase が `polish` → `eval` に進め、eval-gate（`eval_cmd` = ty/ruff/test）を CLI 実行。
  - phase が `eval` で未達なら exit 2 で「done を拒否」して `implementing` に戻す。「毎ターン回す」のではなく「整理1回 + 完了判定で veto」だけなので cap に当たりにくい。
- 停止許可: phase が `done`、または `designing` で grill が人間入力待ち（FR-9 の停止点 b）。
- 暴走防止: veto 連続回数の上限を持ち、超過で human に返す（FR-10）。

> **spike 結果（claude-code-guide で一次情報確認済み・2026-06-09）**:
> - Stop hook exit 2 → stderr がモデルに error feedback として渡り作業継続（Q1 ✅）
> - block cap = **8回「連続・進捗なし」で override**（stuck 検出）。`CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` で変更可。`stop_hook_active:true` を hook が読めば block 活動中か判定可。**進捗があればリセットされるので長時間 loop でも問題なし**——cap はむしろ暴走保護（FR-10）として歓迎（Q2 ✅）
> - `/goal` = session-scoped prompt-based Stop hook + Haiku evaluator。**継続は /goal に compose**、flywheel 自前 Stop hook は eval veto に徹する方針をガイドが追認（Q3 ✅）
> - PostToolUse は `tool_input.file_path`（Write/Edit）と `tool_output.exit_code`（Bash）を input JSON で読める → **design-validator の「design.md Write 検知 → validate-plan 実行 → state 遷移」が実装可能と確定**（Q4 ✅）
> - hook から skill 直接起動は不可、`additionalContext`/stderr で steer のみ（Q5 → C-3 の2系統設計が正しい）

### phase-advancer（state を進める hook 群）— FR-7
**state 遷移は全て hook がモデルの自然な作業を観測して進める（C-2 対策、モデルは state を進めない）。** 専用の単一 tracker ではなく、各イベント hook が自分の遷移を担当する:
- **intent-router（UserPromptSubmit）**: 新規作業 prompt → `no-spec`→`designing`、設計を steer
- **design-validator（PostToolUse, Write→plan/design.md）**: design.md 書き込みを検知 → `validate-plan design` を**直接実行**（CLI 委譲）→ exit 0 なら `designing`→`spec-ready`（FR-4）。合格時、design.md の `## 完了条件（eval）` の fenced block を `eval_cmd` へ昇格（FR-19・`--eval` 明示時は上書きしない。詳細は「spec-designed eval の配線」）
- **design-gate（PreToolUse）**: 門が開いて最初の source 編集が通った瞬間 → `spec-ready`→`implementing`
- **loop-driver（Stop）**: turn 終了時に `implementing`→`polish`（simplify steer, FR-11）→`eval`、eval-gate 判定で `eval`→`done`/`implementing`

CLI（validate-plan / test / build）の exit code は hook が直接読めるので、これらの遷移は決定論的でモデル非依存。

### 進捗方向と revert 規律（FR-25・v0.5.2）
loop-driver の eval 失敗分岐で `fw_count_fails`（出力から fail 数を best-effort 抽出）を `last_fail_count` と比較し、veto steer に方向を載せる: 📉改善=続行 / ➡️横ばい=別仮説 / 📈悪化=**revert してから**別アプローチ（git revert / jj op restore）。green で baseline を 0 にするため、polish 後の regression は「0→N 悪化」として即 revert steer になる（prev_phase=polish の犯人 hint と相乗）。抽出不能な eval_cmd では方向表示なしの従来動作（degrade）。

### eval-gate（FR-6）
loop-driver（Stop）が `eval` phase で起動。`eval_cmd` を CLI 実行し exit code で判定:
- **静的チェックを連鎖**（決定論・モデル非依存、M-1 対策）。**exit 0 → `done`、非ゼロ → `implementing` に戻す**。
- 推奨 `eval_cmd`（品質スタックの CLI 段、FR-11）: 型チェック + lint + test を `&&` 連鎖。
  - Python: `ty check && ruff check && pytest`
  - TS/JS: `npm run typecheck && npm run lint && npm test`
- **v2 以降: 挙動検証**（runnable な変更は native run/verify/webapp-testing で起動・観測。o-m-cc verification 挙動ゲート v0.63.0）。LLM 判定を含むので決定論段とは分けて段階導入。
- **実行環境の頑健化（v0.4.2）**: eval は `timeout`（既定 540s、`FLYWHEEL_EVAL_TIMEOUT`）で自前打ち切り → hook timeout（600s）に殺されて「判定なしで stop が通る」silent degrade を、明示メッセージ付きの veto に変換する。mise shims ディレクトリがあれば PATH に前置し、非対話 hook 環境で npm/node 等が解決できず eval が常に fail する事故を防ぐ。

### polish-gate（FR-11・v0.2.0、v0.4.2 で eval 後に移動 = polish-on-green）
**初回 eval 合格後・done 確定の前**に1回だけ。loop-driver が eval pass を観測したとき `polished` が未セットなら `polish` へ遷移 + `Skill: simplify` を steer（exit 2 でモデルに整理の1ターンを与える）。次の Stop で再 eval し、通れば done。旧配置（implementing→polish→eval）は修正ループ毎に polish が再発火して turn が倍掛かり・red なコードを磨いていたため、v0.4.2 で「make it work, then make it right」の順に改めた（詳細は FR-11）。役割分担:
- **polish**: simplify = reuse/simplification/efficiency/altitude を潰す（LLM / steer / 非決定論）
- **eval**: ty/ruff/test = 型・lint・テストの機械判定（CLI / 決定論）

`flywheel start --no-polish` で polish 段を飛ばせる（state の `polish:false`）。eval_cmd 未設定の degrade 時も polish は1回挿入してから stop を許可する。

**diff 適応（FR-20・v0.4.6）**: `should_polish` が goal の累積 diff（`fw_goal_diff_lines`: state の `baseline_rev` からの insertions+deletions）を見て、`FLYWHEEL_POLISH_MIN_DIFF`（既定 30）未満なら polish を skip して即 done。baseline は start 時に `fw_baseline_rev` が記録（jj `@-` / git HEAD）。累積なので途中 commit に影響されない。pure git では未 track 新規ファイルが diff --stat に乗らないため `git ls-files --others` の行数を加算する（新機能はたいてい新規ファイル——落とすと polish が常に skip になる）。jj は snapshot されるので diff --from だけで正確。計測不能時は常に polish（degrade）。

### skill-logger（PreToolUse, matcher: Skill）— FR-18
全 Skill 使用を `${CLAUDE_PLUGIN_DATA:-~/.claude/flywheel-data}/skill-usage.csv` に記録する（観測のみ・常に exit 0・dormant でも動く）。**実環境では Claude Code が hook に `CLAUDE_PLUGIN_DATA`（`~/.claude/plugins/data/flywheel-<marketplace>/`）を渡すことを確認済み**（2026-06-13）——本番データはそこに溜まる。main loop（skill 実行文脈）には無いため、読む側（evolve）は plugins/data を探す解決順を持つ。**テストから hook を直接叩くときは `CLAUDE_PLUGIN_DATA` を /tmp に明示設定**すること（fallback 領域がテストの steer 行で汚れる事故が実際に起きた）。design-gate（設計 steer）と loop-driver（polish / verification steer）は同じ CSV に `steer:<種別>` 行を記録するので、**steer 従命率 = steer 行の直後に対応 skill 行が現れた率**を dogfood で集計できる。evolve はこの CSV を「最近使われたスキル」の入力として読む（steer:* 行は除外）。

**spec-ready 停止の扱い（v0.4.2）**: 門が開いた直後にモデルが source を1度も編集せず停止した場合、eval を回すと「未実装でも既存テストは green」で**空振り done** になり得る。よって spec-ready での停止は eval を回さず「実装を開始せよ」と steer して veto する（cap で暴走防止）。既知の縁: Bash だけで完結する goal は design-gate が実装開始を観測できず（H-1 と同根）spec-ready に留まり cap まで veto される — その場合は FLYWHEEL_OFF=1 で逃がす。

## spec-designed eval の配線（FR-19・v0.4.5）

「spec が done を定義する」を実装で閉じる。design.md の `## 完了条件（eval）` セクション（validate-plan が存在を強制）の最初の fenced code block を、**design-validator が validate 合格時に抽出して `eval_cmd` に昇格**させる（`fw_extract_spec_eval`: 空行・コメント除去、`&&` 連結）。出所は state の `eval_src` で管理:

| eval_src | 意味 | spec による上書き |
|---|---|---|
| `explicit` | `--eval` 明示 | しない（人間の指定が最優先） |
| `auto` | fw_detect_eval の自動検出 | する（spec は goal 固有でより正確） |
| `spec` | 設計の完了条件から昇格 | （再 validate で更新される） |
| 空 | なし | する |

モデルは design.md を書くだけで state に触れない（C-2 維持）。完了条件の品質は deep-interview の DONE 軸（AI が案を設計→人間が承認）と grill の完了条件枝（実行可能性・goal 固有性・緩すぎ/厳しすぎ）で担保する。入口は増やさない——雑な goal の受け止めは既存 designing パイプラインの仕事で、本機構は「done の定義」だけを足す。

## 完了条件（eval）

flywheel 自身を flywheel で改修する場合の done 判定（FR-19 のドッグフード）:

```bash
for f in hooks/*.sh hooks/lib/common.sh bin/flywheel bin/validate-plan; do bash -n "$f" || exit 1; done
jq -e . hooks/hooks.json > /dev/null
jq -e . .claude-plugin/plugin.json > /dev/null
bin/validate-plan all
```

## compose の2系統（hook は skill を呼べない・C-3 対策）

**hook はシェルスクリプトであり、Skill tool を直接呼び出せない。** よって委譲は2系統に厳密に分ける:

| 系統 | 対象 | 実現 | 確実性 |
|---|---|---|---|
| **CLI 委譲** | `validate-plan` / `bin/flywheel` / test / build | hook が**直接 exec** | 100%（exit code で判定）|
| **Skill steering** | design / discovery-council / grill / critic / sisyphus / verification | hook が exit 2 + steer メッセージ → **モデルが Skill tool で呼ぶ** | 100% ではない（モデル判断）|

**重要**: Skill steering は prose 誘導と同じ構造で、Opus 4.7+ が確実に撃つ保証はない。flywheel が o-m-cc より強いのは、**物理ブロック（design-gate）と組み合わせて選択肢を絞る**点: 「他の実装ツールは全て block されている。今できるのは設計を書くことだけ」という状況を作れば、steer の従命率は prose 単独より大幅に上がる。ただし state 遷移自体は CLI 委譲（hook が validate-plan の exit code を読む）で決まるので、**Skill steering が外れても state は壊れない**（C-2 と C-3 の合わせ技で安全性を担保）。

> v1 dogfood で **steer 従命率を計測・記録**する（steer を出した回数 / モデルが実際に該当 skill を撃った回数）。これが低ければ steer メッセージの一意性を上げる or 物理ブロックの範囲を調整する。**v0.4.4 で計測基盤を実装済み**（FR-18 skill-logger: steer 発行と Skill 使用が同じ CSV に並ぶ）。

## sub-agent 委譲の二層構造（FR-26・v0.6.0）

nested subagents（Claude Code 2.1.172+）を「**判断は強く、収集は薄く**」の二層に使う:

| 層 | 担当 | モデル |
|---|---|---|
| 判断層 | analyst / scout / researcher（要件・ギャップ・調査統合）、critic（反証判定）、designer（設計） | frontmatter `inherit`（main loop を継承。普段 = Fable / Opus） |
| 収集層（解釈系） | code-explorer / architecture-mapper（トレース・境界把握は「気づけるか」が勝負） | frontmatter `inherit` |
| 収集層（列挙系） | convention-scout、汎用の機械的 sweep の子 | 呼び出し側が `model: haiku` を明示（convention-scout の frontmatter は sonnet のまま = 単独利用時の既定） |

設計判断:
- **判断層を `model: sonnet`/`opus` 固定から `inherit` に変更**: 「全部強いモデルで見る」はゼロ設定の既定（指定省略 = 継承）であり、判断が要るのは降格方向だけ。main loop で選んだモデルの質をそのまま council / designer に流す。降格 heuristics は capabilities.md に集約し、agent prompt から参照する
- **skill 側のモデル固定も撤去**: discovery-council（sonnet）/ design（opus）の frontmatter `model:` を削除。skill がターンのモデルを固定すると、メンバーの `inherit` がその固定値を継承してしまい二層構造の意図が崩れるため（セッションモデル追従が正）
- **子の done を定義**: 子の prompt に出力契約（何を・どの形式で返したら完了か）を必須で書く。報告が契約と食い違う / 期待と矛盾 → 継承モデルで撃ち直し（staged escalation）。安い子の失敗モードは「重要なディテールを要約で潰す」であり、要件発見で見落とした制約は design に伝播して一番高くつく——迷ったら継承
- **critic の反証は「落とさない」**: 反証が成立した指摘も削除せず confidence を下げて反証根拠を併記（Coverage-first 原則と矛盾させない。フィルタは集約側の仕事）
- **depth 予算**: main → council メンバー（depth 1）→ sweep の子（depth 2）で収まる設計。上限5階層・depth 5 の background 子は Agent を持てない制約には十分な余裕
- **計測の盲点**: skill-logger は PreToolUse(Skill) のみで、nested の Agent 呼び出しは観測できない。dogfood で委譲が定着したら計測拡張を検討（FR 候補）
- **未検証**: `permissionMode: plan` の agent からの子 spawn は実戦で確認する。失敗しても従来動作（自前で Read/Grep）に degrade するだけで壊れない

## council の Workflow 化（FR-27・v0.8.0 候補）

**peer-to-peer の調整は model-driven**（SendMessage を撃つかはモデル次第）で、steer 従命率と同じ不確実性を council 内部に抱えていた。Workflow script は編成の決定論版——「相互検証が必ず走る」を script の制御フローが保証する。compose の2系統（CLI 委譲 100% / Skill steering <100%）に **第3系統: Workflow 委譲（編成 100% / 中身はモデル）** が加わる。

### script 骨格（SKILL.md に inline で持つ）

```js
export const meta = {
  name: 'discovery-council',
  description: 'Discovery Council: 並列要件分析（決定論的編成）',
  phases: [{ title: '調査' }, { title: '交換検証' }, { title: '統合' }],
}
const COUNCIL_SCHEMA = { /* council-output-schema v1 の JSON Schema 化 */ }
phase('調査')
const [research, gaps] = await parallel([
  () => agent(RESEARCHER_PROMPT(args.feature), {agentType: 'flywheel:researcher', schema: COUNCIL_SCHEMA}),
  () => agent(SCOUT_PROMPT(args.feature),      {agentType: 'flywheel:scout',      schema: COUNCIL_SCHEMA}),
])  // barrier 正当: 交換検証は両方の結果のクロスが必要
phase('交換検証')
const [researchV, gapsV] = await parallel([
  () => agent(CROSS_VERIFY('researcher', gaps),     {agentType: 'flywheel:researcher', schema: COUNCIL_SCHEMA}),
  () => agent(CROSS_VERIFY('scout',      research), {agentType: 'flywheel:scout',      schema: COUNCIL_SCHEMA}),
])
phase('統合')
return await agent(ANALYST_PROMPT(args.feature, research, gaps, researchV, gapsV),
  {agentType: 'flywheel:analyst', schema: RESULT_SCHEMA})
// RESULT_SCHEMA: { requirements_path, ambiguities: [{topic, why, options?}], assumptions: [], summary }
```

計 5 agent 呼び出し（調査2 + 交換検証2 + 統合1）。FR-26 の nested 委譲は agentType 経由で各 agent 定義が効くため、調査段の sweep 子はそのまま動く。

### main loop 側（SKILL.md の手順）

1. `$ARGUMENTS` を `args.feature` に渡して Workflow 起動（background。完了は task-notification で戻る）
2. 返却の `ambiguities` 非空 → **AskUserQuestion**（Step 3 スキップ禁止の移植。質問は1回にまとめる）→ 回答を plan/requirements.md に反映
3. `assumptions` は requirements.md の `## 仮定` セクションへ（未回答時の degrade も従来どおり）

### 設計判断

- **analyst が plan/requirements.md を Write する**（今と同じ責務配置）。design-gate は plan/ を全 phase 許可済み・design-validator は design_path（plan/design.md）にのみ反応するため、門との干渉なし
- **AskUserQuestion を agent 定義から外さない**: scout / analyst の AskUserQuestion は単独呼び出し用に存置。workflow 経由の prompt では「仮定を記録して進む」（既存の自律完了原則）を明示
- **schema の出所は facets を維持**: council-output-schema.md が source of truth。script 内の JSON Schema はその実体化（破壊変更時は schema_version と両方更新）
- **skill-logger 拡張**: hooks.json の PreToolUse matcher を `Skill` → `Skill|Workflow` に。skill-logger.sh は tool_name で分岐し `workflow:<meta.name or name>` 行を記録
- **リスク**: Workflow tool は新しめの機能（要バージョン下限の実測）/ background 実行中に main loop が停止しても designing phase の loop-driver は eval を回さない（既存挙動）が、dogfood で要確認 / agentType の plugin agent 解決（`flywheel:researcher`）は docs 上サポートだが初回 spike で実証してから本実装に進む

## 会話合意からの adopt 入口（FR-29・v0.7.0）

`flywheel start` の designing は「要件をゼロから掘る」前提（`fw_designing_steer` が deep-interview / discovery-council へ誘導）。だが**会話で既に合意ができている**場合、掘り直しは摩擦。adopt は designing の**入り方だけ**を変える薄い variant——designing → spec-ready → implementing の配線は start と完全共有し、steer だけ「掘れ」から「結晶化せよ」に差し替える。

### start と adopt の差分

| | start | adopt |
|---|---|---|
| 想定 | goal は漠然・要件未確定 | 会話で実装方針が合意済み |
| designing steer | 要件無し→deep-interview / 要件のみ→design / 設計あり→grill | 「会話の合意を design.md に結晶化せよ（掘り直すな・完了条件も設計）」 |
| design.md の出所 | 設計フェーズで掘って書く | 会話コンテキストから結晶化 |
| 共通 | design.md → validate-plan → spec-ready → 実装編集で implementing → eval veto loop / polish-on-green | 同左（完全流用） |

### 実装

1. **bin/flywheel に `adopt` case**: `_start_goal` を流用しつつ state に `entry:"adopt"` を記録、出力メッセージを「会話の合意を design.md に結晶化してください（完了条件含む）。掘り直し不要」に
2. **fw_init に entry パラメータ**: 既定 `"start"`。state に保存（既存 start 経路は無変更で `"start"` が入る）
3. **design-gate の fw_designing_steer 分岐**: `entry=="adopt"` かつ design.md 未作成なら結晶化 steer。design.md 作成後は start と同じ（validate→spec-ready 以降は共通）
4. **slash command `/flywheel:adopt`**（commands/adopt.md）: 会話コンテキストを持つモデル向けの主入口。`${CLAUDE_PLUGIN_ROOT}/bin/flywheel adopt` を呼び、続けて design.md を書く

### handoff からの adopt（最自然フロー・source 2系統）

adopt の source は会話だけでなく `.claude/journal.md`（handoff 経由）も。**新セッション / 別マシンは会話コンテキストが空**なので、handoff で固めた Next Actions を読むのが本筋。

```
セッションA（設計議論）─ handoff ─▶ .claude/journal.md（Recap + Next、VCS 共有）
                                          │
        別マシン / 新セッションB ─────────┘
            └─ /flywheel:adopt ─▶ journal の最新 Next を結晶化 ─▶ design.md ─▶ validate ─▶ loop
```

- **source 解決順**: 会話 / 引数の合意 > journal.md の最新 Next（会話に合意があればそれを優先、無ければ journal を読む）。journal はファイルなので CLI / hook からも読めるが、結晶化（design.md 化）はモデルの仕事である点は会話 source と同じ
- **`/flywheel:adopt` の指示**（commands/adopt.md）: 「会話に合意した実装方針があればそれを、無ければ `.claude/journal.md` 先頭エントリの Next Actions を source に、design.md を結晶化せよ（完了条件 = eval も設計）」
- handoff skill 側は無変更（journal を書く役は handoff、読んで結晶化する役は adopt と分離）。[[handoff]] の Next Actions 規約（ファイル/関数/コマンドレベルで具体的）が結晶化品質を担保

### 設計判断

- **会話コンテキスト依存ゆえ CLI 単体では完結しない**: `flywheel adopt` を素の shell から打っても design.md を書くのは会話 / journal を持つモデル。だから主入口は slash command（モデル起動）。CLI adopt は「モデルが続けて書く」前提のヘルパー
- **plan route との棲み分け**: plan mode（FR-21/22）= 計画を新たに作って承認する場 / adopt = 会話 or handoff で既に固まった合意をそのまま載せる場。3 入口（start=掘る / plan=作って承認 / adopt=結晶化）が designing への 3 通りの入り方として並ぶ
- **門・C-2 は不変**: state を作るのは CLI、design.md を書くのはモデル、spec-ready に進めるのは design-validator（validate の exit code）。adopt でも「モデルは state を進めない」は崩れない

## フェーズ別 o-m-cc 委譲表（FR-8 / compose）

| flywheel phase | 委譲先 | 系統 | 人間在席（FR-3） |
|---|---|---|---|
| designing（要件） | `discovery-council` / `deep-interview` | steer | grill（在席）/ scout 仮定記録（不在） |
| designing（設計叩き） | `design` → `grill`（在席）/ `critic`（不在） | steer | ← FR-3 で分岐 |
| designing（合格判定） | `bin/validate-plan design`（FR-4） | **CLI** | — |
| implementing | `sisyphus` Step 4-5（実装→検証→修正ループ） | steer | 不在で可 |
| eval | test/build（v1）→ `verification` 挙動（v2, FR-6） | **CLI**（v1）| 不在で可 |
| done | `quality-gate`（任意）+ 完了通知 | steer | — |

合格判定（designing→spec-ready）と eval（v1）は **CLI 委譲＝決定論的**。それ以外は steer。state を進めるのは常に CLI 系なので、steer の外れは loop を壊さない。

## bin/flywheel CLI

| サブコマンド | 役割 |
|---|---|
| `flywheel start "<適当prompt>" [--eval ..][--no-polish]` | ① 既存 plan を archive(FR-12) → state を `designing` にし設計フェーズ起動 |
| `flywheel status` | 現在 phase・goal・eval・polish・遷移履歴を表示（FR-10 可観測性）|
| `flywheel get <jq-filter>` | state.json を読む（hook が内部使用）|
| `flywheel reset` | state を破棄して dormant に戻す（中断・やり直し）|
| `flywheel add "<goal>" [--eval ..][--no-polish]` | backlog に goal を1件追加（FR-13）|
| `flywheel list` | backlog 一覧（FR-13）|
| `flywheel next` | dormant/done のとき backlog 先頭を pop して start（FR-13）。作業中は拒否 |

## archive と backlog（FR-12 / FR-13）

**archive（FR-12）**: `fw_archive_plan` が `plan/{requirements,design}.md` + `state.json` スナップショットを `plan/archive/<ts>/` に move する。呼ばれるのは2箇所:
- loop-driver が `done` に遷移した直後（完了スペックを記録、plan/ をクリーンに）
- `flywheel start`/`next` の冒頭（前回の未完了 plan が残っていれば防御的に退避）。
done で plan/ が空になるので、通常フローでは start 側の archive は no-op（二重退避しない）。放棄された goal だけ start 側が拾う。

**backlog（FR-13）**: `.flywheel/backlog.jsonl`（1行1 goal: `{goal, eval_cmd, polish}`）。`add` が append、`list` が表示、`next` が「dormant か done」を確認して先頭を pop → start。**cron は持たない**: 外側の定期実行は native `/loop`/`/schedule` に委譲。`done` 時 loop-driver が残数を stderr で通知し `flywheel next` を促す（auto-chain は /goal 完了セマンティクスが絡むため将来）。

## 低摩擦入口（FR-14 / FR-15 / FR-16 / FR-17）

`flywheel start "..." --eval "..."` を毎回打つ摩擦を下げ、そもそも start の存在を思い出させる。共通の土台は **FR-14 eval 自動検出**（`fw_detect_eval` がプロジェクトファイルから test/lint を推定、`_start_goal` が `--eval` 省略時に使う）。入口は「軽い→重い」の4段:

| 入口 | 機構 | 摩擦 |
|---|---|---|
| **FR-17 greeter** | `hooks/session-greeter.sh`（SessionStart）が dormant 時は start の存在を案内、**active 時は phase/goal/次手を再アンカー**（compaction・resume で消えた context の復元、v0.4.3） | 0コマンド・gate を閉じない |
| **FR-16 slash** | `commands/start.md` → `/flywheel:start <goal>` が `${CLAUDE_PLUGIN_ROOT}/bin/flywheel start` を実行（**PATH 非依存**・v0.4.7。空引数は status + goal 確認の degrade）| CLI を打たず1コマンド（明示・安全）|
| **FR-15 intent-router** | `hooks/intent-router.sh`（UserPromptSubmit）が build 意図を検知して auto-engage | 何も打たない（invisible）。ただし **opt-in `FLYWHEEL_AUTO=1`** |

> **なぜ「常時 gate ON（最初から start モード）」にしないか**: goal の無いセッションで gate を閉じると validate を通す spec が書けず門が永久に閉じ、質問・調査・他リポ作業・flywheel 自己改修まで全部 block される（FR-15 を opt-in にした誤爆問題の常時 ON 版）。greeter は gate を**閉じず**思い出させるだけ。「いちいち start を打つのが面倒」は FR-15 auto-engage（`FLYWHEEL_AUTO=1`）で解く。

**intent-router の安全弁**（誤爆＝質問/些末で gate が閉じる事故の回避）:
- opt-in 既定 off。除外パターン（質問・調査・説明）で engage しない。active 中は触らない。`flywheel reset`/`FLYWHEEL_OFF=1` で即解除。state 遷移は他 hook と同じく CLI 経由なので、誤 engage しても loop は壊れず reset で戻せる。
- **完全 invisible の快適化には weight-scaling（些末タスクは設計ゲート即通過）が必要**（将来）。それまでは opt-in + 粗い engage 分類で運用し、誤爆率を実測して default 化を判断する。

## validate-plan パス規約（H-2 対策）

o-m-cc の `bin/validate-plan` は `PLAN_DIR="plan"`（cwd 相対）固定。よって flywheel は **`plan/requirements.md` + `plan/design.md` 規約**に従う:
- `flywheel start` がリポ root に `plan/` を用意し、設計フェーズはそこに書く
- `state.json.design_path` は v1 では `plan/design.md` 固定
- design-validator hook は cwd をリポ root にして o-m-cc の `bin/validate-plan design` をそのまま呼ぶ（再実装しない＝FR-8）

> 実証済み: flywheel 自身の `plan/requirements.md` + `plan/design.md` に対し o-m-cc の `validate-plan all` が「✅ 形式チェック通過」を返すことを確認済み。規約は機能する。

## v1 walking skeleton スコープ

v1 で**作る**（最小で thesis 実証）:
- **spike（最初のタスク）**: Stop hook 継続挙動 + 8回 cap スコープ + PostToolUse での Bash exit code 取得を実機検証（C-1）。結果で loop-driver/phase-advancer を確定
- `.flywheel/state.json` の state machine（FR-7）
- **phase-advancer 群**（C-2 対策、state はモデルでなく hook が進める）: design-validator(PostToolUse) / design-gate(PreToolUse) の遷移責務。v1 の入口は明示 `flywheel start`（intent-router=UserPromptSubmit 自動検知は noisy classifier なので v2 へ）
- design-gate hook（FR-1）— **v1 は Edit/Write→source のみ block、Bash 素通り**（H-1）+ bypass（FR-10）
- loop-driver hook（FR-5/FR-6）— **継続は native `/goal` に compose、Stop hook は eval veto に徹する**（C-1）。eval は **test/build exit code のみ**で決定論判定（M-1）
- `bin/flywheel`（start/status/state/reset）。※`state set` は hook 内部用で、**モデルには撃たせない**（C-2）
- o-m-cc 委譲は **design → validate-plan(CLI) → sisyphus(steer) → test/build(CLI) の1本道**（FR-8 最小経路）

v1 で**作らない**（v2 以降、requirements 非スコープ）:
- intent-router（UserPromptSubmit 自動検知）。v1 入口は明示 `flywheel start`。auto 検知は noisy なので精度を上げてから v2
- FR-3 の headless 分岐（v1 は対話セッション = grill 前提。critic フォールバックは v2）
- Bash の実装意図 block（H-1: 精度不足。v1 は Edit/Write のみ）
- eval の挙動検証（FR-6 の v2 部分。v1 は静的 exit code のみ）
- 複数 goal の並行 loop / 探索ループ

**v1 の合格条件（dogfood）**: 「適当な1プロンプト → flywheel が設計フェーズを強制（source 編集が block される）→ design.md 書き込み → design-validator が validate-plan を自動実行し合格で門が開く → sisyphus 実装 → test/build exit 0 で done」が auto mode で **state 遷移をモデルに撃たせず**（grill 応答のみ人手）に1周回ること。

## リスクと対策

| リスク | 対策 |
|---|---|
| C-1: Stop hook 8回 cap で「止まらない」が打ち切られる | 継続は native `/goal` に compose、Stop hook は eval veto のみ。v1 spike で cap スコープを実機確認 |
| C-2: state 遷移がモデル依存に逆戻り（自己矛盾） | state は hook（CLI exit code 観測）が進める。モデルに `state set` を撃たせない |
| C-3: steer が外れて skill が発火しない | state 遷移は CLI 委譲で決まるので steer 外れでも loop は壊れない。物理ブロックで steer 従命率を上げ、v1 で従命率を計測 |
| H-1: design-gate が調査 Bash を誤 block | v1 は Bash を block しない（Edit/Write→source のみ）。plan/・.flywheel/・docs/・調査は pass |
| loop-driver veto の無限ループでトークン焚き火 | veto 連続 cap（FR-10）+ done/人間待ちで停止（FR-9）|
| o-m-cc 未インストールで動かない | SessionStart で依存検出、無ければ degrade（門だけ効かせ skill は手動案内）|
| state file 破損で門が永久に閉じる | `flywheel reset` + `FLYWHEEL_OFF=1` の二重脱出口（FR-10）|
| o-m-cc 側の skill 名・bin パス変更で委譲が壊れる | 委譲先を委譲表1箇所に集約。check-consistency 的な疎結合検証を将来追加 |

## o-m-cc との境界（再掲・FR-8）

flywheel = **loop を強制し steer する harness**（hook・state・gate）。
o-m-cc = **撃つべき仕事の中身**（skill・agent・判断知）。
flywheel は o-m-cc を**呼ぶ**。置き換えない。両者は `kok1eee` marketplace に並ぶ別プラグインで、flywheel は o-m-cc を soft dependency とする。
