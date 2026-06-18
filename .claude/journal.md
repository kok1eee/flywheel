# Journal

> セッション間の引き継ぎ。最新が上。Recap を時系列アーカイブとして保持し、
> 次のアクションを明示する。詳細なセッション内要約は built-in `/recap` も併用。

## 2026-06-18 16:00 [ip-10-0-67-244]

### Recap
15:02 の v0.8.16(FR-35) 出荷に続けて、**チェーン dogfood + FR-36/37 + docs 一式（v0.8.17）を出荷**。
**チェーン dogfood（本セッションの山場）**: `/flywheel:add` で adopt(eval-veto-hint) + start(polish比例制御) を積み→`/flywheel:next` で起動。**①FR-36（adopt）done → ②done→start 連鎖で FR-35 の go/no-go grill が実発火**（ユーザー go 判断）→ **③FR-37（start）done** まで一気通貫。FR-33 連鎖・FR-35 go/no-go・**監視 council の本物 drift-catch を 2 度ライブで検証**（FR-36 で grep 誤検知を council が検出→差し戻し→修正→clean）。
**FR-36（v0.8.17）初回 eval veto の原因示唆**: eval-fail steer に `$cmd_hint`。シェル解決失敗（`bash -c` 経由）だけを **shell プレフィクス付き grep**（`(^|/)(bash|zsh|sh|dash|ash): .*(command not found|No such file or directory|: not found)`）で検出し set-eval を促す。裸の `No such file` 等は通常失敗にも出るので弾く（C3 誤検知ガード）。`test/eval-veto-hint.sh`(3)。
**FR-37（v0.8.17）polish 比例制御**: 調査で「**pure rename は jj/git 既定で 0 行 collapse＝既に skip 済み**」と判明 → スコープを `fw_repo_diff_lines` git fallback の明示 `-M`（`diff.renames=false` でも config 非依存に collapse）に絞った。copy(`-C`)は重複＝simplify 対象なので skip させない。`test/polish-rename-skip.sh`(2)。**ファイル間コード移動(add≈del)・reset 再 baseline は defer**。
**docs 同期**: README(v0.8.17・NO_CHAIN 説明・loop-driver 行・0.8.16/0.8.17 changelog) / ROADMAP(FR-36/37 ✅ + 融合項目 + FR-37 follow-up) / `skills/guide`(done 自動連鎖) / **CLAUDE.md 新規**（C-2 不変条件・state machine・dogfood 規約・test/version/jj 規約に絞った working ガイド）。`verification` skill は FR-34 で既に最新＝変更なし。共有テストハーネスを `test/chain-lib.sh` に抽出（`setup_impl`/`setup_done_ready`）。全 7 テストスイート緑。
`main@origin` 予定 = **v0.8.17**。

### Next
- **polish+monitor steer の融合**（ユーザー観察「monitor を一緒に動かせば早い」→ ROADMAP loop 制御 epic に追加済）: done 前ゲートの polish(simplify) と monitor を1本の steer に束ね 3往復→2往復に。eval は毎停止で独立に回るので安全（polish が壊しても次停止で拾い done をすり抜けない）。トレードオフ=polish が eval を壊した稀ケースで council 1回無駄打ち。**次の実装候補**。
- **FR-37 follow-up**（ROADMAP）: ①ファイル間コード移動（add≈del 対称）の skip（--numstat ヒューリスティック・誤 skip リスクで今回 decline）②reset 再 baseline で min-diff 無効化（baseline 捕捉タイミング）。
- **残り backlog**: evolve 定期稼働 / マルチレポ follow-up テスト（multirepo-diff.sh の jj path・error 経路）/ ★ `flywheel note`（文脈スナップショット）/ monitor 529（server-side・対処不可）。
- **HOTL epic**: phase1(FR-34)・phase2(FR-35) 完了。チェーン dogfood で実運用挙動を確認済み。次の自律度引き上げは融合(往復削減)が筋。

## 2026-06-18 15:02 [ip-10-0-67-244]

### Recap
再起動後セッション（13:41 handoff の Next を実行）。**v0.8.16 / FR-35（HOTL phase2: start 経路 auto-chain）を出荷**。
まず live 確認: flywheel プラグインは `directory` ソース（repo 直読み）なので**本セッションは v0.8.15 hooks が live**＝再起動債務は解消済みと判明。Next の最優先（FR-33/34 dogfood）と「HOTL phase2 設計」のうち、ユーザー選択で **phase2 を設計・実装**。
**設計判断（grill 2問）**: ①start 経路 auto-chain は**デフォルト ON だが連鎖前に go/no-go を grill**（vague な start goal の drift を人間が一段目で止める）②discovery が requirements を draft する過程で**判断だけ grill**したら自動続行（requirements 後に必ず1回止める案は不採用＝human-in 寄り）。
**実装**: flywheel harness で dogfood（`/flywheel:start`→requirements/design→validate 通過→implementing→eval→polish(simplify)→**monitor council=clean**→done）。`hooks/loop-driver.sh` の start 分岐を `exit 0`(hard-stop) → **`exit 2` + 新 steer**（go/no-go gate・discovery 指示・「判断は self-answer せず grill」明記）+ `fw_log_usage "steer:start-chain"`。`FLYWHEEL_NO_CHAIN=1` の後方互換維持。`test/start-chain.sh`(3ケース) 新規 + `test/adopt-chain.sh` ケース2 を新挙動(start→exit2)に更新。**polish で test ハーネス重複を `test/chain-lib.sh` に抽出**（adopt/start 両 chain test が source）。monitor の memo 2件（version slip / no-go テスト未カバー）を**その場で対応**（plugin.json+marketplace.json×2 を 0.8.16 に / C2 に no-go marker + discovery grep 厳格化）。eval 7ケース全緑。
**機構の学び**: loop-driver は **Stop hook（非対話）**で AskUserQuestion を呼べない → 「人間に pop」は `exit 2` + steer（次ターンのモデルに grill を打たせる）で実現＝adopt chain と同型。phase2 は hook のみ変更なので**再起動不要で即 live**（skill/command は未変更）。
出荷物: 7ファイル +109 -48（hooks/loop-driver.sh, test/{chain-lib,start-chain,adopt-chain}.sh, ROADMAP.md, .claude-plugin/{plugin,marketplace}.json）+ plan/archive。`main@origin` 予定 = v0.8.16。

### Next
- **FR-33 chain の live dogfood**（今回未踏）: 複数 phase を `/flywheel:add` で積み→`/flywheel:next`→done で **adopt 連鎖**が実際に回るか、**start 連鎖**で go/no-go grill→discovery 自動が steer どおり動くか実機確認（FR-35 の挙動を本番で踏む）。
- **メモ更新**: `flywheel-goal-start-metrics` の「verification 空通過＝要調査」は FR-34 で解消済 → 更新（このセッションで対応予定）。HOTL epic は phase2 まで実装完了。
- **残り backlog（ROADMAP）**: evolve 定期稼働（ほぼ未稼働）/ マルチレポ follow-up テスト（`test/multirepo-diff.sh` の jj path・error 経路）/ ★ polish 比例制御（move/rename は simplify skip）/ ★ `flywheel note`（文脈スナップショット）/ ★ 初回 eval veto の原因示唆 / monitor 529（server-side・対処不可）。
- **HOTL epic**: phase1(verification 独立化=FR-34)・phase2(start 経路=FR-35) 完了。次の自律度引き上げ候補があれば ROADMAP に新 phase として積む。

## 2026-06-18 13:41 [ip-10-0-67-244]

### Recap
再起動債務の確認から始め、**2 機能を出荷 + HITL→HOTL の方向を確立**した（全 push + install 済み・**反映は要再起動**・現セッション hooks は依然 0.8.13）。①**docs**: `agents/capabilities.md` の planner/TaskCreate drift 修正（実在しない `planner` エージェント / `/task-decomposition` 参照を除去 → タスク分解は designer が `design.md` の `## Tasks` で書く実態に統一）+ **ROADMAP に epic 層（stateless 見出しグルーピング）を導入**（5 epic に再編。メモ `flywheel-eval-is-sole-done-gate`: 完了は eval ゲート一本・状態を持つ層を増やさない）。commit `5f86c45f`。②**v0.8.14 FR-33（adopt chain auto）**: loop-driver の done 後に backlog があれば自動で次 goal を起動。**adopt 経路は exit 2 で連鎖続行（全部一気）・start 経路は exit 0 で人間 hand-back（要件掘りは HITL）**。無限ループ不可（next が pop で単調減少）。`FLYWHEEL_NO_CHAIN=1` で無効化。`test/adopt-chain.sh` 4ケース緑。commit `bec52205`。③**HITL→HOTL の北極星を確立**（ユーザー合意・メモ `flywheel-hitl-to-hotl`）: **調べる=loop（自動）/ 決める=grill-me（人間）/ 判定=独立**。④**v0.8.15 FR-34（verification→monitor 統合）**: 調査で `steer:verification` 9回に対し `flywheel:verification` skill 起動 **0回**（skill-logger が全 skill 記録するのに CSV 皆無＝空通過は本物・根因は self-graded な `verify-set clean` 素通り）。self-graded ゲート（FR-32 ブロック + `verify-set` CLI）を撤去し、**done を閉めるのは eval(客観)+monitor(独立)の2つだけ**に。挙動検証は monitor に統合（`observer-behavior` に runtime レンズ + overseer が smoke 実行→Read-only 観測者が判定）。`fw_eval_is_thin` は `go` 用に温存。verification skill は gate から外し汎用規律として存続。`test/verification-merge.sh` 3ケース緑。commit `96fcd54d`。`main@origin` = **`96fcd54d`**（v0.8.15）。

### Next
- **再起動が最優先**: 0.8.15 を live に → FR-33/FR-34 を dogfood。adopt chain: `/flywheel:add` で複数 phase 積む→`/flywheel:next`→done で**自動連鎖**するか・start 経路で止まるか確認。verification: 薄 eval（`eval_src=auto`）の runnable goal で **monitor の overseer smoke**（Step 1.5）が実際に回り observer-behavior が runtime を見るか実機確認。
- **HOTL epic phase2（次の設計）**: start 経路 auto-chain を hard-stop から「**調査自動 + grill-me で判断だけ聞いて続行**」へ（FR-33 follow-up）。ROADMAP の HOTL epic に登録済み。`loop-driver.sh` の done→次が start のとき exit 0 hand-back している箇所を、discovery を loop が回し決め所だけ pop する形に。
- **残り**: ③ evolve 定期稼働（ほぼ未稼働）/ ⑤ マルチレポ follow-up テスト（`test/multirepo-diff.sh` の jj diff path / error 経路）/ ④ monitor 529（server-side・対処不可）。
- **メモ更新候補**: `flywheel-goal-start-metrics` の「verification 空通過＝要調査」は FR-34 で解消 → 更新。新規 `flywheel-hitl-to-hotl` / `flywheel-eval-is-sole-done-gate` を参照。

## 2026-06-18 11:51 [ip-10-0-67-244]

### Recap
直前の 11:44 handoff 後の追補（出荷物は無し・調査のみ）。ユーザーの「flywheel は TaskCreate も使うようになってる?」の問いを契機にコード確認: **flywheel のコア loop（phase state machine + backlog.jsonl）は TaskCreate を使わない**（独自管理）。`skills/discovery-council/SKILL.md` のみ allowed-tools に `TaskCreate/TaskUpdate` を持つ（要件分析チームの作業管理）。今日作った「task 分解の型」は `design.md` の Markdown `## Tasks`(Boundary/Depends/Done) で、ネイティブ TaskCreate とは別レイヤー（二重管理しない設計）。**発見した drift**: `agents/capabilities.md:76,79,153` が「**planner** が TaskCreate でタスク分解」と記述するが、`planner` エージェントは現在の available agents list に**存在しない**（古い記述＝実態 drift）。

### Next
- **再起動が最優先**（11:44 エントリ参照: 2.1.181 更新 + flywheel 0.8.13 を live に）。
- **capabilities.md の drift 修正**: `agents/capabilities.md` の planner/TaskCreate 記述を実態に合わせる（planner 不在・task 分解は design.md の `## Tasks` 型に統一）。ROADMAP に ★ で積んで再起動後に `/flywheel:add`→`/next` で回す dogfood 候補。
- 残りの Next は 11:44 エントリを参照（別セッション knowledge-links の実 DB 反映待ち / /adopt auto-chain / monitor 529 / verification・evolve・マルチレポ follow-up）。

## 2026-06-18 11:44 [ip-10-0-67-244]

### Recap
前回 handoff(6-17 16:56) 以降、さらに **v0.8.12・v0.8.13 を出荷**（全 push + install 済み・**反映は要再起動**、現セッションは 0.8.8 hooks のまま）。**v0.8.12**: ①grill が「コードで答えが出るなら聞くな（肝）」を *判断* にまで広げて self-answer し質問しなくなる問題（ユーザー指摘「grill-me が質問してこない」、この会話でも私が該当）を、`skills/grill/SKILL.md`（原則+Gotcha）・`hooks/plan-steer.sh`(FR-24)・`commands/add.md` の3箇所に「self-answer は *事実* のみ・*判断*(スコープ/トレードオフ/優先順位/命名/案の選択)は必ず聞く・迷ったら聞く側」と明文化。②**ROADMAP をメイン機能に**: `ROADMAP.md`(手動.md のまま)を中核ワークフローの源にし「源→`/flywheel:add`(軽量 grill で phase 化)→backlog→`/flywheel:next`→実装」を確立、ヘッダに回し方+状態列「backlog 中」、`skills/guide/SKILL.md` にルート枝。新コマンド・テーブル parse は作らず既存の /add→/next で繋ぐ。**v0.8.13**: drift steer 文言明確化（`loop-driver.sh:177-178`）。発端はユーザーの別セッションで「loop-driver が古い drift verdict を読んでバグ?」→ 実コード診断で**バグでないと判明**（drift は `loop-driver.sh:150` で読んだ瞬間 monitor=null にクリア・1回しか執行されない。monitor 記録後にモデルが先回り修正すると次停止で初回執行が空振りに見えるタイミングずれ）。steer に「この verdict はクリア済み・次停止で再 monitor が走る」を明示（挙動不変）。**この v0.8.13 自体が v0.8.12 の ROADMAP メイン機能化の初 dogfood**（ROADMAP 項目→`add --adopt --eval --notes`→backlog→`next`(entry=adopt・notes 引き継ぎ)→design→実装→done を実機完走）。最後に Claude Code **2.1.181** リリースノート確認: monitor council の **API 529 は server-side で未修正**（retry 改善は connection-drop 向けで capacity 529 とは別）。`main@origin` = b0e7e112（v0.8.13）。

### Next
- **再起動する**（このセッションの第一目的）: Claude Code 2.1.181 へ更新 + 再起動 → **flywheel 0.8.13 が live に・全セッションの再起動債務を一掃**。再起動後 `/flywheel:add` の軽量 grill / grill の判断必須 / drift steer 新文言 / notes 引き継ぎ等が実効化。
- **別セッション（knowledge-links web アプリ）**: eval（`bun run typecheck && lint && test`）は 95 pass で緑だが、**実 RDS への migration 適用・tags backfill・初回リンク構築・push は未実施**（design.md にデプロイ手順記載、ユーザー指示待ち）。monitor が 529 なら `flywheel monitor-set clean "" "<理由>"` で手動記録して done。再起動後 `bun run test` が 95 pass 維持か1回確認（bundled Bun 1.4 はプロジェクト bun と別なので影響薄の想定）。
- **flywheel 次 phase**: `/adopt` の「backlog 全部一気」(auto-chain・`loop-driver.sh` の done→自動 next 化、無限ループ防止が要る独立 task。既存 /adopt 単発との命名衝突も解決)。ROADMAP に未記載なら追加して `/add`→`/next` で回す。
- **monitor council の 529 頻発**（このセッションで手動 clean を多数）: server-side だが、形骸化を避けるため「薄い eval を作らない／drift 修正後の再 monitor を軽量化」等を ROADMAP 候補に。verification 空通過調査 / evolve 稼働 / マルチレポ jj path テストも未着手のまま。

## 2026-06-17 16:56 [ip-10-0-67-244]

### Recap
「最近の flywheel 振り返り」から始まり、**計測分析 → 設計議論 → v0.8.10/v0.8.11 出荷**まで一気通貫。①**振り返り**: `skill-usage.csv`（175 events）を集計し経路別傾向を初実測（`goal:start` 21 / `adopt` 6 / `plan` 4）。**推奨経路の plan route が最少**＝ユーザーが「phase を立てて一個ずつ start」するワークフローの自然な帰結と判明（乖離ではない）。verification は steer 9/実行 0（空通過）、evolve はほぼ未稼働も発見。②**設計議論**: ユーザーが cc-sdd（gotalab/cc-sdd）を「task を綺麗に作れる参考」として提示。WebFetch で確認し「task 境界は design の File Structure Plan から導く + Boundary/Depends 注釈」がエッセンスと抽出。③**v0.8.10 出荷**: task 分解の型（`skills/design/SKILL.md` に `## Tasks`(Boundary/Depends/Done)）+ adopt chain（`flywheel add --adopt`→`next` が entry 尊重で掘らず起動）。flywheel 自身で dogfood、監視 council が FR-D（status の baseline 表示欠落）を drift 検出→修正→done。④**v0.8.11 出荷**: adopt chain の**スラッシュ入口**（`/flywheel:next`・`/flywheel:add`）+ **`/add` に軽量 grill-me**（Done/Boundary/曖昧点の3点で練ってから積む。雑な add が adopt で掘られず実装直行するのを防ぐ）。grill 成果は backlog entry の `notes` + `eval_cmd` に保存し `next` で `state.notes` へ引き継ぐ。これは **plan mode + grill で計画 → 承認 → 実装 → 監視 council が test gap を drift 検出→補強→done** という full flow の dogfood になった（go/adopt/task 型/grill 全部使用）。`main@origin` = 54a93511（v0.8.11）。全 install 済み（**反映は要再起動**・現セッションは 0.8.8 hooks）。

### Next
- **再起動して live 0.8.11 hooks にする**（現セッションは 0.8.8 hooks。`/flywheel:add` の軽量 grill・`/next`・notes 引き継ぎは再起動後から実効）。
- **`/flywheel:add` を実運用 dogfood**: 複数 phase を `/flywheel:add "<phase>"`（→軽量 grill 3点→`flywheel add --eval --notes --adopt`）で積み、`/flywheel:next` で逐次起動 → `state.notes` が design の種になるか確認。
- **次 phase: `/adopt` の「backlog 全部一気」（auto-chain）** — v0.8.11 で切り出した。`loop-driver.sh` の done→自動 next 化（無限ループ防止が要る）。既存 `/flywheel:adopt`（単発結晶化）との命名衝突も解決する。Boundary: `commands/`(新規) + `loop-driver.sh`。
- 振り返りで出た observation（別 phase 候補）: ①verification が steer 9/実行 0 の空通過＝FR-32 実効性調査（薄い eval を作らない運用 or ゲート強化）②evolve がほぼ未稼働＝定期的に回す ③v0.8.9 follow-up（マルチレポ diff の jj path / error 経路テスト）④monitor council の API 529 が頻発（手動 clean で迂回した回あり）。
- 計測メモ更新済み: `flywheel-goal-start-metrics`（経路別傾向 + plan route の理由 + adopt chain 対応）。

## 2026-06-17 15:22 [ip-10-0-67-244]

### Recap
flywheel の自己改善を**3バージョン連続で出荷**（すべて push + `claude plugin update` 済み、反映は要再起動）。①**v0.8.8**: 前セッションの v0.8.7 `flywheel go` が `fw_log_usage "go"` を記録していた片肺を是正＝記録を削除（`set-eval`/`monitor-set`/`verify-set` も非記録で揃え、evolve が `skill-usage.csv` を「スキル名」として読む＝裸の `go` 行はノイズ、という裏取り付き。`bin/flywheel` の go) から削除、mktemp eval 緑）。②**go の live dogfood**: 再起動後の 0.8.7 hooks で非コード goal（ROADMAP 追記）を start→design.md(完了条件)→spec-ready→`.md` 編集で昇格しない（=従来の詰まり）→`flywheel go`→implementing→loop-driver eval緑→monitor→done まで実機完走（記録を ROADMAP に残し docs commit）。③**v0.8.9 マルチレポ対応（最小スコープ）**: FW_ROOT 単一リポ前提で sibling の diff が polish 判定に乗らない「半分しか検証されない」問題を解消。`flywheel repos <path>...` で sibling を宣言（登録時に baseline=jj `@-`/git `HEAD` 捕捉）→ `fw_goal_diff_lines` が FW_ROOT + `state.repos` を合算。`common.sh` に `fw_repo_baseline`/`fw_repo_dir`/`fw_repo_diff_lines` を追加し per-repo 化（VCS は cwd ベース自動検出で jj/git 混在可）、`bin/flywheel` に `repos)` + status 表示 + usage、`test/multirepo-diff.sh` で git 2リポ合算を検証。**flywheel 自身の実 goal で完走**: grill でスコープを最小確定（#5=cross-repo gate/昇格は `go` に委譲）→ design → 実装 → eval緑 → polish(simplify で `fw_repo_dir` 抽出) → **監視 council が FR-D の実 drift（status が baseline 表示を欠く）を検出して implementing 差し戻し** → 1行修正 → monitor clean → done。客観 verifier が自己採点では見逃す bug を捕まえた好例。`main@origin` = 24b3325c（v0.8.9）。途中、auto mode の Bash 分類器が一時 unavailable で `flywheel start` が数分弾かれた（read-only は通る・待って復帰）。

### Next
- **再起動して live 0.8.9 hooks にする**（このセッションは 0.8.8 hooks）。
- **v0.8.9 の follow-up テスト（監視 council 指摘・spec 上は out-of-scope だった）**: `test/multirepo-diff.sh` は git + 未track 経路しか踏んでいない。**jj diff path / per-file `--stat` parse loop / error 経路（sibling 不在・baseline 空・diff 失敗）** が green-but-unverified。cross-repo diff を本番で使うなら jj リポでの合算テストを追加。
- **マルチレポを実運用で dogfood**: 実際に app + sibling repo に跨る goal で `flywheel repos ../sibling` → 両リポに変更 → polish 判定が合算を見るか、`flywheel status` の repos 行（path + baseline短縮）を確認。
- ROADMAP 残候補（レバレッジ順）: ★ 初回 eval veto の原因示唆（`command not found`→set-eval 誘導）/ ★ polish 比例制御（move/rename は skip）/ ★ 進行中文脈の軽量スナップショット（`flywheel note`）。
- 小粒 UX: `monitor-set` は `clean` でも reason だけ付けたいとき level に `""` を挟む必要（`monitor-set clean "" "<reason>"`）。clean/pending は第2引数を reason 扱いにする改善余地（council skill 経由なら実害なし）。

## 2026-06-17 13:38 [ip-10-0-67-244]

### Recap
**H-1 を実装し v0.8.7 を出荷**（非コード goal が spec-ready で詰まる問題の解消）。`plan/design.md` を spec として `bin/flywheel` に `go)` ケースを直接追加（経路X＝adopt を使わず clobber 回避）。仕様どおり: `fw_state_exists` ガード → phase 検査（`spec-ready` のみ昇格 / `no-spec`・`designing` は拒否＝設計スキップ裏口防止 / `implementing` 以降 no-op）→ thick eval 検査（`eval_cmd` 非空 ∧ `! fw_eval_is_thin`＝`eval_src ∈ {explicit, spec}`、薄い auto / eval 無しは拒否し set-eval か design.md 完了条件を促す）→ `fw_advance implementing`。`set-eval`/`monitor-set`/`verify-set` と同型（`FLYWHEEL_HOOK` ガードなし＝CLI の state 書き込みは C-2 対象外）。`fw_log_usage "go"` も追加（昇格成功時）+ usage 行追記。**完了条件 eval を mktemp -d 内で live state を壊さず全緑確認**（`/tmp/go_eval_test.sh`: 静的 `bash -n`+`go)` grep / happy: start→design.md→design-validator直叩き→spec-ready(eval_src=spec)→go→implementing / negative1: designing で go 拒否・phase維持 / negative2: spec-ready+thin auto eval で go 拒否・phase維持。`CLAUDE_PLUGIN_DATA` を temp に逃がし本番 CSV 不汚染）。version bump 0.8.6→0.8.7（plugin.json / marketplace.json×2 / README ヘッダ + changelog）。**2 commit を push 済み**（`feat: v0.8.7 flywheel go` + `docs: ROADMAP H-1/gap B 状態更新`、`main@origin` = `db58ab03`）。`claude plugin update` で **0.8.5→0.8.7 install 済み（反映は再起動が必要）**。auto-memory `flywheel-noncode-goal-stuck` と MEMORY.md を「解消済み」に更新。注意: このセッションの hooks は依然 stale（0.8.5）。

### Next
- **再起動して live 0.8.7 にする**（このセッションは 0.8.5 hooks）。`flywheel go` は再起動後から実効。
- **実 goal で `flywheel go` を dogfood**: 非コード goal（Bash 運用 / docs のみ）を `flywheel start` → design.md に **goal 固有の完了条件 eval** を書く → validate 合格で spec-ready → `flywheel go` → implementing 昇格 → 停止して loop-driver が eval exit code で done 判定、を一気通貫で確認。thin eval（`auto`）だと go が拒否することも実地確認（`set-eval` で thick 化 → go）。
- ROADMAP 残候補（レバレッジ順）: ★★ マルチレポ対応（eval_cmd に sibling・polish 両 diff）/ ★ 初回 eval veto の原因示唆（`command not found` → set-eval 誘導）/ ★ polish 比例制御（move/rename は skip）/ ★ 進行中文脈の軽量スナップショット（`flywheel note`）。
- gotcha: PostToolUse:Write の security hook が文字列 "eval" に誤反応する（`eval_cmd`/完了条件の語。シェル `eval` 未使用なら無視可）。

## 2026-06-17 13:14 [ip-10-0-67-244]

### Recap
flywheel **v0.8.6 を出荷**（handoff に「CLAUDE.md ↔ README drift チェック」を非ブロック nudge として追加＝`skills/handoff/SKILL.md` の新 Step 4。両方ある時だけ・drift シグナル時だけ `/claude-md-management:revise-claude-md` を名指しで促す。自動書き換えなし）。README changelog + plugin.json + marketplace.json×2 を 0.8.6 に揃え、`docs(ROADMAP)` + `chore(journal handoff)` の未 push 分も一緒に origin/main へ push（`main@origin` = v0.8.6、同期済み）。発端はユーザーの「他リポで README と CLAUDE.md が食い違う」事故。続けて **H-1（非コード goal が spec-ready で詰まる）の設計を grill で確定し `plan/design.md` に結晶化**（実装は未着手）。詰まりの唯一のチョークポイントは `design-gate.sh:58`「最初の source 編集で implementing 昇格」で、非コード goal は source 編集が無く永遠に spec-ready。方針 A（CLI 入口 `flywheel go` で spec-ready→implementing を手動昇格＝偽編集を捏造しない）に決定。grill 5決定: ①implementing 再利用（loop-driver の eval/veto/monitor/done 委譲・polish は diff≒0 で自動skip）②名前は `go`（verify-set と衝突回避）③thick eval 必須（eval_cmd 非空 ∧ `! fw_eval_is_thin`、未満は拒否し set-eval/完了条件を促す）④spec-ready 限定（designing は拒否＝設計スキップ防止、implementing以降 no-op、misuse backstop は thick-eval）⑤完了条件は mktemp フル機能テスト（syntax+grep / happy / negative×2）。注意: このセッションの hooks は **stale**（0.8.6 を今出荷・反映に再起動が必要）。FR-12（`fw_archive_plan`）が done/新goal/放棄で plan/*.md を `plan/archive/<ts>/` へ自動退避することも確認済み。

### Next
- **再起動して live 0.8.6 にする**（このセッションは stale hooks）。
- **H-1 実装（経路X = 直接実装。adopt は使わない＝clobber 回避）**: `plan/design.md` を spec として Read → `bin/flywheel` に `go)` ケース追加（`fw_state_exists` ガード → phase が spec-ready 以外なら拒否/no-op → thick eval 検査 → `fw_advance implementing "flywheel go: non-code goal, no source edit"`）+ usage/help 行に `go` + `fw_log_usage "go"`（set-eval/monitor-set/verify-set と同型）。
- **eval を mktemp で手動実行**（design.md の完了条件: happy=start→design.md(完了条件付)→`FLYWHEEL_HOOK=1 hooks/design-validator.sh` 直接実行→spec-ready→`go`→phase==implementing / negative1=designing で go 拒否 / negative2=thin eval で go 拒否）。live state を壊さない。
- 緑なら README changelog + version bump（0.8.7・plugin.json/marketplace.json×2/README ヘッダ）→ commit/push。
- **注意**: adopt を H-1 で使うと `_start_goal`→`fw_archive_plan` が `plan/design.md` を真っ先に archive する（bin/flywheel:68）。経路X は adopt を使わないので design.md は spec として残る。done 後は次 goal 開始時に FR-12 が archive。
- 実装後メモ更新: `flywheel-noncode-goal-stuck` を「`flywheel go` で解消」に。関連: `flywheel-roadmap-doc` / `tool-hang-vary-tactics`。
- ROADMAP 他候補: ★★ マルチレポ対応 / ★ veto 原因示唆 / ★ polish 比例制御。

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
