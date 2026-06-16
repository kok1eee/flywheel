# Journal

> セッション間の引き継ぎ。最新が上。Recap を時系列アーカイブとして保持し、
> 次のアクションを明示する。詳細なセッション内要約は built-in `/recap` も併用。

## 2026-06-16 16:50 [ip-10-0-67-244]

### Recap
`flywheel set-eval "<cmd>"`（v0.8.5）を実装・commit・install・push まで完走した（gap B 解消＝eval_cmd が spec-ready 以降 immutable で飛行中に直せなかった問題）。本機能自体を `flywheel:adopt` で dogfood し、`adopt→designing→spec-ready→implementing→eval→monitor clean→done` を 0.8.4 hooks 実戦で完走。実装は `bin/flywheel` の `set-eval)` ケース（`monitor-set`/`verify-set` と同型: `fw_state_exists` ガード・**phase 不問**・`FLYWHEEL_HOOK` ガードなし＝CLI の state 書き込みは C-2 対象外、`eval_cmd` と `eval_src=explicit` を書く）+ usage 追従の +14 行。完了条件の eval は **jj/git 外の mktemp -d 内**で `start→set-eval→get` を実機検証して live state を壊さない設計にした（`loop-driver.sh:111` が `cd "$FW_ROOT" && bash -c "$eval_cmd"` で回す前提を確認済み）。diff 14 行で polish は閾値(30)未満のため省略。version を 0.8.4→0.8.5（plugin.json / marketplace.json 2箇所 / README ヘッダ + changelog）。commit `97a8c11a`。**push 済み: `main@origin` が v0.8.5 に前進**（feature + journal handoff の2 commit）。`claude plugin update` で 0.8.4→0.8.5 install 済み（**反映は再起動が必要**）。repo は `kok1eee/flywheel` で **PUBLIC**（journal も公開される運用と確認）。

### Next
- **再起動して 0.8.5 hooks/CLI を live にする**（今のセッションは 0.8.4。set-eval は次セッションから実効）。再起動後 `flywheel set-eval "<cmd>"` が飛行中に効くか実 goal で確認。
- ROADMAP の次候補に着手: **★★ H-1（非コード goal が spec-ready で詰まる）** / ★★ マルチレポ対応 / ★ veto 原因示唆 / ★ polish 比例制御。`flywheel-noncode-goal-stuck` メモ参照。
- set-eval の将来 polish（非ブロッキング、monitor F001 conf72）: eval に `! fw_eval_is_thin` 確認を足すと、`eval_src=explicit` が FR-32 ゲートを外す副作用まで証明できる（今回は採用閾値未満で見送り）。
- 関連メモ: `flywheel-gap-b-eval-cmd-locked`（解消済み→更新候補）/ `flywheel-roadmap-doc` / `flywheel-noncode-goal-stuck`。

## 2026-06-16 14:13 [ip-10-0-67-244]

### Recap
flywheel を dogfooding して構造的弱点を3つ発見・うち2つを実装し、v0.8.4 を push + install した（要再起動で反映）。発端は skill-usage.csv の分析で `steer:verification` が 8 回発行され実行 0 件だった点 → 調査の結果バグでなく設計どおり（verification は done 後の optional nudge で強制力ゼロ、simplify/monitor は exit 2 の blocking）。grill で「eval が薄い(eval_src=auto)プロジェクト限定で blocking 化」と方針確定し **FR-32**（`verify-set` サブコマンド + `fw_eval_is_thin` + loop-driver ゲート）を実装。途中で **A**（`fw_detect_eval` が pytest/npm を直叩き → uv/bun/pnpm/yarn を lockfile 判定して `uv run` 等を前置）も修正。実装中に **gap B**（eval_cmd が spec-ready 以降 immutable・直すには reset しかない）と **H-1**（非コード goal が spec-ready で詰まる）を実地で踏み、ROADMAP.md と auto-memory に記録。注意: ツールが長時間ハングした事故あり（Edit/Skill/`!cmd` は別パスで通った）。eval_src の実値は `explicit|auto|spec`（`.eval_src` フィールド。`eval_source`/`fallback` は存在しない — ハング中の壊れ出力に騙された）。

### Next
- **最優先: 再起動して 0.8.4 hooks を live にする**（今のセッションは 0.8.2 hooks。FR-32 ゲート/uv 検出は再起動後に効く）。
- **ROADMAP ★★★#2 `flywheel set-eval "<cmd>"` を `flywheel:adopt` で実装**（gap B 解消）。設計: `bin/flywheel` に `monitor-set`/`verify-set` と同型のサブコマンドを追加し `state.eval_cmd=<cmd>` / `eval_src="explicit"` を書く（`fw_set_str`/`fw_set_json`）。`fw_state_exists` ガード・phase 不問（飛行中に直すのが目的）・usage と status 表示も追従。CLI は state を書ける（C-2 はモデル直編集のみ禁止）ので `FLYWHEEL_HOOK` ガード不要。
- set-eval の完了条件(eval): `bash -n bin/flywheel && grep -q 'set-eval' bin/flywheel` + mktemp で `flywheel start`→`set-eval "X"`→`get '.eval_cmd'`==X / `get '.eval_src'`==explicit を確認。**design.md の完了条件は `validate-plan design`（`all` 不可: adopt goal は requirements.md 無し。今回の reset 地獄の主因）**。
- 関連メモ: `flywheel-gap-b-eval-cmd-locked` / `flywheel-roadmap-doc` / `flywheel-noncode-goal-stuck` / `tool-hang-vary-tactics`。ROADMAP.md に残り改善候補（★★ verify 経路=H-1, ★★ マルチレポ, ★ veto 原因示唆, ★ polish 比例制御）。

## 2026-06-15 16:54 [ip-10-0-67-244]

### Recap
Zenn「Loop Engineering」記事を起点に、flywheel の次の改善方向を設計議論（実装はまだ・spec 化前）。記事の Loop Engineering を flywheel は概ね実装済みと確認。仕分け結論: **Worktrees 不要**（sub-agent 隔離では `isolation: worktree` を既に利用、並行実装はしない/jj運用・1リポ1wip）、**ハートビート不要**（自動起動は思想に反する＋sdtab/schedule/loop で外から叩けば足りる）、**jj new は flywheel 側でやらない**（`hooks/lib/common.sh:76` のとおり人間/jjルール側で start 前に new、flywheel は `@-` を変更前断面として baseline 計測に使う）、経験還元は `evolve` で実装済み。記事との差分は3軸に集約: ①検証=唯一のホールは「runnable の挙動判定を実装者本人がやる＝確証バイアス」（eval は CLI exit code で既に客観的）、②止め時=悪化トレンドが「助言」止まり→ロールバックを停止理由に昇格余地、③HITL=機構(AskUserQuestion)はあるが方針が薄い。**止め時の原則: 量(コスト/トークン)でなく方向(誤りのサイン)で止める**。監視は同期ゲート(Stop hook/loop-driver)が本体で、`/loop` の時間監視は粒度が合わず代替不可・長時間自律走行の補完に留まる。watchdog 設計の合意: 別エージェント(`Agent(run_in_background)` か cron、`/loop` は自己採点になるので不可)・**コンテキストはファイル経由**(plan/requirements.md・design.md・FW_STATE・diff を Read、会話は共有しない)・**hook は検知のみ**(シェルからは Agent を spawn 不可なので FW_STATE にフラグを立てるだけ)・**ブロックの執行は loop-driver に集約**・人間が手綱(watch_focus/on-off/hand-back応答/SendMessage)。**巻き戻し幅に天井**: 自動で戻れるのは implementing 内まで、design/PRD への遡上は必ず HITL を挟む(ぐるぐるが PRD まで発散するのを防ぐ)。discovery-council の実装を確認: TeamCreate + 3エージェント(researcher/analyst/scout)の peer-to-peer SendMessage、analyst が統合役、俯瞰専任は無し(orchestrator=skill実行セッション)。

### Next
- **監視 council の設計を詰める**（今ここ）。論点: (a) 複数セッション SendMessage の peer-to-peer か / (b) 俯瞰役(overseer)を別に置く fan-out→集約か。discovery-council は (a) だが、それは「main セッションの唯一の仕事が discovery」だから成立。監視では main=実装者が忙しいので俯瞰役を兼任できない → **俯瞰役を別に置く案が有力**。SendMessage は team 内通信で独立セッション間ではない点に注意。peer-to-peer の相互検証は「節目で1ラウンド」なら転用可、「常時ぐるぐる」はコスト発散。
- 未確定の分岐: ①発火=節目イベント(hook カウント/done ゲート) vs 時間(cron) vs 両方、②構成=single watchdog から始める vs 最初から council、③戻り幅=自動implementing/design・PRDはHITL で確定可か。
- 詰まったら FR spec に起こす（`/flywheel:start` か `adopt`）。confidence-scoring / council-output-schema policy は監視 council に再利用できそう。

## 2026-06-13 08:58 [ip-10-0-67-244]

### Recap
v0.5 系を3リリース実装・push・install 済み（plugin は 0.5.2、要再起動）。v0.5.0 = plan-mode route（plan-steer/plan-gate/plan-approved の3 hook。ExitPlanMode の計画テキストを検証し、承認の瞬間に hook が plan/design.md へ artifact 化 + 完了条件を eval_cmd 昇格 + implementing へ。engage は FLYWHEEL_PLAN=1 opt-in）。v0.5.1 = kakuduke 実戦レビューで発覚した C-2 違反（モデルが `flywheel _advance done` で eval 判定を迂回）への enforcement（`_advance` は FLYWHEEL_HOOK=1 必須・`.flywheel/` への Edit/Write を design-gate が全 phase ブロック）+ evolve の計測データ読み先修正（本番 CSV は `~/.claude/plugins/data/flywheel-kok1eee-flywheel/`）。v0.5.2 = veto loop に進捗方向（fail 数の前回比で 📉続行/➡️別仮説/📈revert 規律を steer）。autoresearch plugin は計測データ（使用0回）を根拠に棚卸し→学び2点だけ improvements.md に吸収→削除済み。kakuduke 実戦では FR-19（spec-designed eval）が本番初動作（eval_src=spec、designing→done 46分）。

### Next
- README.md を v0.5.2 の全体像で再構成する: plan-mode route（Shift+Tab → 承認 → 自動 loop）を主経路として冒頭に据え、CLI route（flywheel start）を従に。hook 8個の表・環境変数 5個（FLYWHEEL_OFF/PLAN/VETO_CAP/EVAL_TIMEOUT/POLISH_MIN_DIFF）・FR-25 までの機能を反映。肥大化した Changelog の整理（古い版は折りたたみ or 要約）も検討
- ユーザーの shell rc に `export FLYWHEEL_PLAN=1` を追加（plan route の常用化。未実施）
- 次の実戦 goal で確認: done の history が `loop-driver: eval pass` で刻まれるか（v0.5.1 の C-2 ガード効果）/ eval 失敗時に 📉📈 の方向表示が出るか（v0.5.2）
- 将来候補（spec 記載済み）: FR-3 headless 分岐（grill↔critic）、eval の挙動検証（verification 統合）、FLYWHEEL_PLAN の default 化判断（dogfood 後）
