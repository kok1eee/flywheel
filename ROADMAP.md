# flywheel ROADMAP — 改善 backlog（flywheel の中核ワークフローの源）

実運用（dogfooding）で見つかった構造的弱点と改善候補。レバレッジ順。
（`flywheel add` の backlog は `.flywheel/backlog.jsonl` = gitignore でローカル限定のため、
共有したい改善 backlog はこのファイルを正とする。）

## このファイルの回し方（源 → 実装）

ROADMAP はメイン機能の**源**。項目を実装へ流す中核ワークフロー（新コマンドは無く、既存の `/add`→`/next` で繋ぐ）:

1. このテーブルから着手する項目を選ぶ
2. **`/flywheel:add "<項目>"`** — 軽量 grill（Done / Boundary / 曖昧点を1問ずつ）で phase 化して backlog に積む（複数項目を一気に積める）
3. **`/flywheel:next`** — backlog 先頭を起動（adopt 経路＝掘らず結晶化）→ design → eval → done
4. done したら状態列を `✅ 実装済（vX）` に更新

状態列の値: `未着手` / `backlog 中`（`/add` で取り込み済み・実装待ち）/ `✅ 実装済（vX）`。

### epic で関連 phase をまとめる（任意・state なし）

関連する複数項目は `### epic: <名前>` 見出しでグルーピングしてよい（phase の1つ上の整理層）。
epic は **ただの Markdown 見出し**で、独自の進捗 state / CLI / jsonl / 層間 sync は **持たせない**
（持たせた瞬間に「タスク全部完了 = done」の自己申告シグナルが eval ゲートと並走する二重管理＝
ナンセンス。完了判定は phase の eval ゲート一本のまま）。実装の流れ（源 →`/add`→`/next`）は不変で、
epic 配下の各行を individually `/add` して phase 化する。階層は **epic（源・MD）→ phase（goal・唯一
state を持つ層）→ design.md `## Tasks`（分解・MD）**。詳細は auto-memory `flywheel-eval-is-sole-done-gate`。

## 根っこ

flywheel は「**コード実装タスク**」前提で設計されている。実運用では、運用（Bash のみ）/docs/
設定変更/マルチレポ系の goal や、eval を後から直したいケースで摩擦が出る。本質は
**「eval を直す」「実装済みを認める」の2つに、`reset`（plan を archive して history を消す核兵器）
しか手段が無い**こと。軽量な横道が1本ずつあれば迂回ゼロで done まで行ける。

## 改善候補（epic 別・各 epic 内はレバレッジ順）

### epic: eval / 完了判定の柔軟化

> 根っこの「eval を直す」「実装済みを認める」摩擦への横道群。完了は eval ゲート一本のまま柔らかくする。

| 優先 | 改善 | 効果 | 状態 |
|---|---|---|---|
| ★★★ | eval 検出のランナー解決（uv.lock→`uv run`, bun/pnpm/yarn, poetry） | 今回の摩擦の9割が消える | ✅ 実装済（`fix: eval 自動検出を uv/bun/pnpm/yarn 対応`）。poetry は未 |
| ★★★ | `flywheel set-eval "<cmd>"` — CLI で eval_cmd を書き換え（model 禁止は維持） | `reset` の儀式が不要に。**gap B** 解消 | ✅ 実装済（v0.8.5 `flywheel set-eval`） |
| ★★ | 「実装済み」経路 — spec-ready から `flywheel go`（即 implementing→eval へ）。偽の編集を捏造しない | **H-1** / spec-ready 詰まり解消 | ✅ 実装済（v0.8.7 `flywheel go`。thick eval 必須・spec-ready 限定） |
| ★ | 最初の eval veto で原因示唆 — `command not found` 系なら「eval_cmd 自体が怪しい。`set-eval` で直せ」 | 長い迂回を初手で短絡 | ✅ 実装済（v0.8.17・FR-36）。eval-fail steer に shell プレフィクス付き解決失敗だけ検出する `$cmd_hint` を追加（裸の `No such file` 等は通常失敗にも出るので弾く）。`test/eval-veto-hint.sh`(3・誤検知ガード込み) |

### epic: 計画・分解の質

> 雑な計画／聞かない grill／手数の多い phase 逐次を矯正し、源→実装の質を上げる。

| 優先 | 改善 | 効果 | 状態 |
|---|---|---|---|
| ★★ | task 分解の型 + adopt chain（cc-sdd 由来）— design 成果物に Tasks(Boundary/Depends/Done)、`add --adopt` で backlog に積み `next` が掘らず結晶化起動 | phase 逐次の手数削減・task を構造的に割る | ✅ 実装済（v0.8.10）。follow-up: 完了条件 eval を mktemp 実行時テストに厚く |
| ★★ | adopt chain auto — done で backlog を自動消化（adopt は連鎖続行・start は HITL 停止・`FLYWHEEL_NO_CHAIN=1` で無効化） | 手動 `/next` を消して backlog 全部一気 | ✅ 実装済（v0.8.14・FR-33）。`test/adopt-chain.sh` で4ケース検証。無限ループ不可（pop で単調減少）・専用 cap 不要。**follow-up（v0.8.24 観測）**: 対話セッション中に done→次 goal を auto-start すると、人間が別話題に移っていた場合に goal が宙に落ちる（ROADMAP に残れば復旧可だがローカル backlog から消える＝本セッションで intent-router が実際に蒸発した）。start 経路は FR-35 で go/no-go 済みだが adopt 経路は無条件継続。adopt 経路も **着手前に軽い「次を始める?」checkpoint**（or 対話時は既定 `FLYWHEEL_NO_CHAIN`）を入れる候補。backlog #1「chain auto-checkpoint」の commit 粒度問題と隣接 |
| ★★ | grill が判断を必ず聞く — 事実/判断の峻別を grill/plan-steer/add に明文化（判断は self-answer せず聞く） | 「質問してこない grill」の矯正 | ✅ 実装済（v0.8.12） |
| ★★ | ROADMAP をメイン機能に — 源→`/add`→backlog→`/next` の中核ワークフロー（ROADMAP.md ヘッダ + guide 導線） | 改善の源を実装に繋ぐ | ✅ 実装済（v0.8.12・このファイル自身の回し方） |
| ★ | adopt の args sanitize — `/flywheel:adopt` の `!` 動的注入行が長い/特殊文字（バッククォート・引用符・ASCII 括弧）の args で shell parse error を起こし skill 起動に失敗。adopt は会話を source に読むので短い args で回避可だが、入口で落ちると驚く（v0.4.8「`!` 行展開」と同類） | adopt 起動の頑健性 | ✅ 実装済（v0.8.20・FR-40）。`"$ARGUMENTS"` → `'$ARGUMENTS'` の single-quote 包み（adopt/start/add）。`test/adopt-args-sanitize.sh`(C1/C2)。residual: literal `'`（稀・bulletproof 非スコープ）。出所: v0.8.19 FR-39 dogfood 実踏 |
| ★ | grep-test の boilerplate 共有化（rule-of-three・simplify 指摘）— `fail`/`ok`+`ROOT` を副作用なしの `test/grep-lib.sh` に抽出し3 grep-test が source（`chain-lib.sh` は mktemp/cd 副作用足場で grep-only test に不適） | test の重複削減・boilerplate 一箇所化 | ✅ 実装済（v0.8.22・FR-42）。grill-termination/adopt-args-sanitize/checkpoint-button が source、chain-lib 系 state テストは不変。adopt chain で backlog #1 として自動起動の dogfood |
| ★ | chain の goal 間 auto-checkpoint — adopt chain（FR-33）が done→次 goal で commit せず、連続 done が1つの未コミット change に混在（v0.8.22+23 dogfood で FR-42+43 が混ざり手で commit 整理＋change 切りした）。大物が小物と bundle されると履歴粒度が潰れる | chain 連鎖時のコミット粒度を保つ | ✅ 実装済（v0.8.26・FR-46）。done→chain 境界（`fw_chain_checkpoint`・`next` 直前）で完了 goal を **jj describe+new** で独立 change に確定（git は degrade・skip）。message は goal から自動生成・タイミングは done 時（backlog>0 のみ）。`FLYWHEEL_NO_CHECKPOINT=1` で無効化。C-2 整合: hook が VCS 操作（モデル≠state 不変）。`test/chain-checkpoint.sh`(C1 jj 分離 / C2 git degrade / C3 NO_CHECKPOINT)。**実装中に手動 jj new 分離を踏み dogfood**。adopt 経路の着手前 checkpoint は別件（ROADMAP:54 follow-up） |
| ★ | stacked slash-skill（2.1.199・最大5同時ロード）の干渉 watch — `/flywheel:add ... /flywheel:next` の1プロンプト運用が可能になった一方、複数 SKILL.md のプロンプト合成でスキル間干渉（指示の衝突・steer の混線）が起き得る | flywheel skill 群の合成挙動を把握してから運用推奨を決める | 未着手（観測のみ。実運用で干渉を踏んだら実例ベースで対処） |
| ★ | intent-router（legacy auto-engage）の削除 — `FLYWHEEL_AUTO=1` の auto-engage hook。plan route が上位互換で README 自身が「凍結」。`session-greeter.sh` が deprecated 経路を推奨する矛盾も残る | 毎プロンプト発火 hook を1つ減らす・docs/greeter 整理 | ✅ 実装済（v0.8.25・FR-45）。出所: v0.8.23 ユーザー判断 delete。`hooks/intent-router.sh` 削除 / `hooks.json` 配線+description / `session-greeter.sh` の FLYWHEEL_AUTO 分岐 / `lib/common.sh` コメント / README 表・env を撤去（changelog 履歴は残す）。恒久ガード `test/intent-router-removed.sh`（hooks/ に参照ゼロを assert）を CI に追加。低リスク（opt-in superseded） |

### epic: マルチレポ対応

> FW_ROOT 単一リポ前提を崩し、sibling repo を跨ぐ goal でも diff/polish/gate が両方を見る。

| 優先 | 改善 | 効果 | 状態 |
|---|---|---|---|
| ★★ | マルチレポ対応 — eval_cmd に sibling を含める（`uv run pytest && uv run --directory ../shared-python-lib pytest`）/ polish が両 diff を見る | 「半分しか検証されない」問題の解消 | ✅ 実装済（v0.8.9・最小スコープ）。`flywheel repos <path>...` で宣言 → diff/polish/**指紋**（v0.8.31）が合算。#5（cross-repo gate/昇格）は go に委譲・未実装。jj diff path / error 経路テストは follow-up。**follow-up（v0.8.31 council 由来・low）**: 本番 jj は untracked を snapshot するため、sibling 側 `.gitignore` が `.flywheel` を除外していないと state churn で指紋が揺れ無限 re-council し得る。`flywheel repos` 登録時に sibling の `.flywheel` gitignore を警告/要求する設計判断が未了（C5 は FW_ROOT 側のみ assert） |

### epic: loop 制御（polish / drift / veto）

> implementing→eval→polish→done のループ駆動を無駄なく回す。

| 優先 | 改善 | 効果 | 状態 |
|---|---|---|---|
| ★ | drift steer の文言明確化 — 修正後の空振り steer に「この verdict はクリア済み・次停止で再 monitor が走る」を明示（`loop-driver.sh:177-178`） | monitor 判定と loop-driver 執行のタイミングずれでの混乱を消す | ✅ 実装済（v0.8.13・ROADMAP→/add→next の初 dogfood） |
| ★ | polish の比例制御 — 純粋 move/rename（追加≒削除で対称）は simplify skip。`reset` の再 baseline で min-diff 閾値が無効化される件も | 無意味な simplify ターン削減 | ✅ 実装済（v0.8.17・FR-37・最小スコープ）。調査で「純粋 rename は jj/git 既定で 0 行 collapse＝既に skip 済み」と判明 → `fw_repo_diff_lines` の git fallback に明示 `-M` を足し `diff.renames=false` でも config 非依存に collapse。copy(`-C`) は重複＝simplify 対象なので skip させない。`test/polish-rename-skip.sh`(2)。**ファイル間コード移動(add≈del) と reset 再 baseline は defer**（下記） |
| ★ | polish+monitor steer の融合 — done 前ゲートの polish(simplify) と monitor を1本の steer に束ね、同一ターンで simplify→monitor を実行（3往復→2往復）。eval は毎停止で独立に回るので polish が壊しても次停止で拾い done をすり抜けない（安全）。トレードオフ: polish が eval を壊した稀ケースで council 1回分を無駄打ち | loop の往復削減で done が速くなる | ✅ 実装済（v0.8.18・FR-38）。`enter_polish` に `$2="monitor"` モードを足し統合（新関数増やさず）。融合時 monitor を pending に prime（model が飛ばしても次停止 pending 分岐が拾い degrade）。デフォルト ON・`FLYWHEEL_NO_FUSE=1` でエスケープ。`test/polish-monitor-fuse.sh`(4・degrade 安全 C4 込み)。自己 dogfood 完走（融合 steer 自身が発火） |
| ★★ | monitor verdict 再利用（無変更時）— `monitor=clean` を作業ツリー指紋に紐付け、clean ゲートが指紋一致時のみ done（無変更=再 council せず）。あわせて clean 記録後の変更を done すり抜けさせない穴塞ぎ | done 前の最重量オペ（529源）の無駄な再実行を gate を弱めず削減＋stale clean 穴塞ぎ | ✅ 実装済（v0.8.30・FR-50）。`fw_impl_fingerprint`(sha256 of baseline 累積 jj/git diff)+monitor-set が clean に指紋付与+loop-driver clean ゲート。指紋未記録は後方互換 done。**multi-repo sibling は v0.8.31 で解消**（指紋に `state.repos` を fw_goal_diff_lines と同一規約で連結・空判定は連結後・FW_ROOT/sibling とも凍結 baseline。council が live baseline ゼロリセットの潜在バグも捕捉し修正）。`test/monitor-fingerprint.sh`(C1-C9)。grill で b(単一observer)/c(diff可変)は gate 薄化で不採用。出所: 本セッションの skill-usage 分析（改善C）+ FR-50 follow-up |
| ★ | polish 比例制御の follow-up — ①ファイル間コード移動（追加≒削除で対称）の skip（--numstat ヒューリスティック・誤 skip リスクありで今回 decline）②`reset` の再 baseline で min-diff 閾値が無効化される件（baseline 捕捉タイミング） | FR-37 で defer した残件 | 未着手（FR-37 follow-up） |

### epic: 文脈の保持

> compact / 中断で揮発する now-context を安く残す中間層。

| 優先 | 改善 | 効果 | 状態 |
|---|---|---|---|
| ★ | 進行中文脈の軽量スナップショット（`status` と `journal` の中間）— mid-session に「今手に持っている文脈」（作業仮説 / in-flight ファイル / なぜ今これを）を安く checkpoint する薄い層。`flywheel note`（append-only scratch、次回 context に自動同梱）のような1コマンド | compact / セッション中断での now-context 揮発を防ぐ。journal を書くほどでもない区切りを拾える | 未着手（出所: pachitown-kb OKF 作業 2026-06-16） |

### epic: HOTL 移行（human in → on the loop）

> 北極星: 人間を loop の必須ステップ(in)から監督者(on)へ（auto-memory `flywheel-hitl-to-hotl`）。
> 合意した形は **調べる = loop（自動）/ 決める = grill-me（人間）/ 判定 = 独立**。
> 順序原則: verification 独立化が先（弱い検証のまま自律度を上げると drift 垂れ流し）→ それを土台に start 経路を緩める。

| 優先 | 改善 | 効果 | 状態 |
|---|---|---|---|
| ★★★ | verification を monitor council に統合 — self-graded な `verify-set` ゲートを廃し、挙動レンズを drift-observer fan-out に足して独立検証へ一本化 | 「実行0の空通過」の穴を塞ぐ＝HOTL の前提条件 | ✅ 実装済（v0.8.15・FR-34）。FR-32 ブロック+`verify-set` 撤去・monitor の observer-behavior に runtime レンズ+overseer smoke。`test/verification-merge.sh` で検証 |
| ★★ | start 経路 auto-chain を「調査自動 + grill-me で判断だけ聞いて続行」へ — 現状の hard-stop を廃し、discovery を loop が回し決め所だけ人間に pop | start 経路も human-on で連鎖（in に縛らない） | ✅ 実装済（v0.8.16・FR-35）。start 分岐を exit 2 + steer（連鎖前に go/no-go grill → discovery 自動 → 判断だけ grill）へ。`FLYWHEEL_NO_CHAIN=1` で従来 hard-stop。`test/start-chain.sh`(3) + adopt-chain.sh ケース2 更新 |
| ★★ | grill 終了判定の self-graded 撤去（lever 1）— grill/deep-interview/plan-steer の「もう十分」モデル自己判定を廃し**止めるのは人間**に（informed stop: 止める直前に未決判断の枝を提示）。deep-interview の7問cap撤去 | 「握れた感」false-positive＝under-ask を矯正（「決める=人間」の ask-quality を上げる） | ✅ 実装済（v0.8.19・FR-39）。done の self-graded 撤去(FR-34)の grill 層への適用。prose のみ・新機構ゼロ・7問マジックナンバー減。`test/grill-termination.sh`(4)。completeness-critic と plan-gate 強制は defer（人間 live で足りるか dogfood）。**follow-up**（monitor の非ブロック指摘）: test の grep ガードを厚く — C4 を rule-phrase grep に・filter 温存ガードを3経路に拡張 |
| ★★ | grill closing-checkpoint を AskUserQuestion 化（FR-39 phase 2）— informed stop（残り枝の提示＋stop/continue）を prose でなく**ボタン**で出す。残った判断の枝を選択肢に・「進めて」を1クリックに | prose だとモデルが省略・埋没＝self-graded に逆戻りの隙。ボタンなら「止めるのは人間」が構造的に必ず出る＋摩擦最小 | ✅ 実装済（v0.8.21・FR-41）。3経路の checkpoint を AskUserQuestion 化（残り枝を上位3＋「握れた・進めて」・single-select・4個超は「他にN個」）。`test/checkpoint-button.sh`(C1/C2)。出所: v0.8.20 dogfood 中ユーザー提案＝lever 1 が checkpoint を出した→改善が surface した効果実証。**follow-up 整合**: L41 原則 bullet も Step3 ボタン化と揃えた（v0.8.23・FR-43） |

### epic: dev infra（test runner / CI）

> テスト実行の客観化。flywheel の eval ゲート思想（self-grade せず客観 exit code）を自分のテストに適用する。

| 優先 | 改善 | 効果 | 状態 |
|---|---|---|---|
| ★ | test を push+PR で走らせる GitHub Actions CI — `test/run-all.sh`（`test/*.sh` を lib 除外でループ・非ゼロ集約）を共有 runner にし `ubuntu-latest` で `bash test/run-all.sh`。依存 git/bash/jq はプリインストール | リグレッションを push 時に客観検知（dogfood） | ✅ 実装済（v0.8.24・FR-44）。`.github/workflows/ci.yml`（push/pull_request）+ `test/run-all.sh`。matrix なし（bash version 依存なし）。実 CI green は push 後 `/ci-watch`（done 外）。adopt で結晶化 → 設計ゲート→eval→monitor→done を自己 dogfood |
| ★ | backlog の remove / reorder CLI — `flywheel add` は末尾追加・`next` は先頭 pop のみで、特定 backlog 項目の削除も並び替えもできない（`.flywheel/` は C-2 で model 編集禁止＝手編集も不可） | 誤積み / 優先変更 / adopt 直起動で残る重複の解消 | ✅ 実装済（v0.8.29・FR-49）。`flywheel backlog rm <n>`（n 番目削除）/ `mv <n> <pos>`（並べ替え）。番号は `list` の 1-indexed・範囲外/非整数/空は exit 1。CLI 編集は C-2 対象外（モデル直編集のみ禁止・進行中 state.json 不触＝phase ガード不要）。mv は awk で配列読み→抜き挿し（JSON 原文保持）。`test/backlog-cli.sh`(C1-C6)。出所: 本セッションの skill-usage 分析（改善 B） |
| ★★ | evolve を実走させる nudge — skill-usage.csv 419 events に対し `flywheel:evolve` 実行 1 回（最終 6-15）＝自己改善ループに起動トリガーが無く停止。greeter（SessionStart）に「evolve 未実行 N 日／未消化 N goal」を表示し人が `/flywheel:evolve` を回すよう促す | 溜まった実行データが skill の Gotchas に還元される（他改善も複利で効く） | ✅ 実装済（v0.8.28・FR-48）。`fw_evolve_staleness`（common.sh）が CSV 最終 evolve から経過日数+未消化 goal 数を算出し閾値超（既定 7日 / 5 goal・env 上書き可）で dormant/done greeting に1行。**nudge のみ・無人 auto-run は不採用**（grill 確定＝Gotchas 編集は人レビュー・HOTL 保持）。`test/evolve-nudge.sh`(C1-C4)。出所: 本セッションの skill-usage 分析（改善 A） |
| ★ | evolve actor-routing の機械検査 — 観測者向け Gotcha が skill 側 AUTO-GOTCHAS に誤配送されても誰も検知できない（.md 変更は eval/smoke の死角。実例: 観測者レンズ2件が monitor SKILL.md で数日死蔵・外部 /code-review が検出） | 学習 loop の「actor に届いたか」を CI で客観検証（evolve Step 2.7 の機械化） | ✅ 実装済（v0.8.32・FR-51）。`test/gotcha-actor-routing.sh`: skills/*/SKILL.md の AUTO-GOTCHAS 配下で actor 主語 title（「観測者は」「reviewer は」・増えたら足す）を fail。実例 class 限定＝false positive ゼロ（本文言及・マーカー上は不問）。positive control / fp ガードの実走 assert 込み |
| ★ | lens 効果計測 — council のどのレンズが採用 drift を出したか無記録で、AUTO-GOTCHAS cap 追い出し・「レンズ別の着眼点」昇格が勘（skill-usage.csv があるのに council 効果だけ無計測の非対称） | レンズ運用（追い出し / 昇格）をデータ駆動に | ✅ 実装済（v0.8.33・FR-52）。`monitor-set --lens <a,b>` → `monitor-verdicts.csv`（timestamp,verdict,level,lenses。clean も分母記録・pending 非記録・lenses はパイプ連結で4列固定）。observation-only（計測失敗でも verdict 成功・C-2 整合で書き手は CLI）。--lens 忘れ / 余計は stderr 警告（exit 0）。`test/monitor-lens-csv.sh`(C1-C6)。Gotcha 単位 attribution・集計 CLI は非スコープ（データが溜まってから） |
| ★ | 2.1.198/199 対応 — subagent 背景デフォルト化で fork 経由 council が構造的に空振り（spawn→ターン終了→通知が親に漂着し集約・monitor-set 不実行。FR-52 で実踏）+ 2.1.191 カンマ matcher silent 失敗が示した「気づけない配線破れ」class（design-gate は fail-open） | council の同期性を明文化・hook 配線を CI で機械観測 | ✅ 実装済（v0.8.34・FR-53）。monitor Step 2 に観測者 `run_in_background: false` 明記 + Gotcha 113 root cause 追記 + 遅延漂着レポート規律（clean 後ツリー不触・improvements.md 退避）を Gotchas 化。`test/hooks-wiring.sh`（valid JSON / 全 script 実在 / カンマ matcher 禁止 / monitor sync 指示の消失検知・positive control 実走込み）。**residual**: 静的ガードは repo 側の破れのみ・host 側 hook 意味論変更による fail-open は未観測（候補: design-gate 発火時に fw_data_dir へ heartbeat を touch し greeter が痕跡ゼロを warn する live positive control） |

### epic: onboarding / 自己記述

> Claude / 人間が flywheel の使い方に辿り着く導線。plugin 側で自己記述的に持つ（user config と結合しない）。

| 優先 | 改善 | 効果 | 状態 |
|---|---|---|---|
| ★ | greeter に `/flywheel:guide` 導線 — `session-greeter` の dormant 案内に「迷ったら `/flywheel:guide`」を1行。SessionStart で Claude の context に injection される導線 | 「使い方が分からず素手で大物を作り始める」を入口で減らす | ✅ 実装済（v0.8.27・FR-47）。dormant emit に1行 + `test/greeter-guide.sh`（導線消失の grep ガード）。active greeter・guide 本体は不変 |
| ★ | global CLAUDE.md への pointer（B 案）— flywheel を「本格的に作る時の harness」として常時 context に置く | 長セッションで greeter が薄れても忘れない | 未着手（A=greeter で不足が実証されたら。出所: v0.8.27 FR-47 で「A だけ・B は投機しない」と判断）。**注意**: 「build なら自動で flywheel」は FR-45 で削除した intent-router の prose 復活なので「plan route で提案・人間承認」に留める |

## 機構メモ（コードで裏取り済み）

- **gap B（eval immutable）**: `hooks/design-validator.sh:23` が `fw_gate_closed`（no-spec|designing）の
  ときだけ検証 → spec-ready 以降は design.md を編集しても early-exit で**再昇格しない**。
  state.json はモデル編集禁止（C-2）。よって eval_cmd は spec-ready 以降 immutable。
- **H-1（非コード goal 詰まり）**: spec-ready→implementing は「最初の source 編集」がトリガー。
  Bash 運用/docs のみの goal は src を変えないので進めない。逃げは `FLYWHEEL_OFF=1`（`loop-driver.sh:81`）。
  → **v0.8.7 で解消**: `flywheel go`（`bin/flywheel` の `go)`）が spec-ready→implementing を手動昇格する
  正規ルート（`design-gate` の「最初の source 編集」の非コード版）。thick eval 必須・spec-ready 限定。
  → **v0.8.8 で live dogfood 確認済み**: 非コード goal（ROADMAP 追記）を start→design.md(完了条件)→spec-ready
  →`.md` 編集で昇格しないこと→`flywheel go`→implementing→loop-driver eval 緑→done まで実機で一気通貫。
- **multi-repo**: eval は `cd "$FW_ROOT" && bash -c "$eval_cmd"`（`loop-driver.sh:111`）、diff/polish も
  `cd "$FW_ROOT" && jj diff`（`common.sh` fw_goal_diff_lines）。FW_ROOT のリポしか見ず sibling は素通り。
  → **v0.8.9 で最小スコープ解消**: `flywheel repos <path>...` で sibling を宣言（baseline 捕捉）→ `fw_goal_diff_lines`
  が FW_ROOT + 宣言リポを合算（`fw_repo_diff_lines` の per-repo 化）。eval は eval_cmd で跨ぐ運用（不変）。
  cross-repo 編集の gate/昇格（#5）は未実装で `flywheel go` に委譲。jj diff path / error 経路のテストは follow-up。
- **status/journal gap**: `flywheel status`（state.json 由来＝機械状態、phase/goal で terse、常時上書き）と
  handoff journal（`.claude/journal.md`、session 境界で LLM 要約を追記＝重い）の二極しかなく、
  mid-session の作業文脈（今の作業仮説 / in-flight ファイル / 着手理由）を安く残す中間層が無い。
  compact / 中断で now-context が揮発する。`flywheel note` のような append-only scratch が候補。

## 残すべき（効いていた点・退行させない）

- **設計ゲート**（requirements/design を先に書かせる）— 実装がブレない。col_letter の 1-based/0-based
  非対称・後方互換・OUT スコープの線引きが事前に固まった。
- **validate-plan** は速くて邪魔にならない。
- **eval veto が赤を止めた**のは正しい挙動（コマンドが本当に落ちていた。悪いのはゲートでなくコマンド）。

---
出所: 2026-06-16 実運用 retrospective（southernstar / shared-python-lib の goal）。
gap 詳細は auto-memory `flywheel-gap-b-eval-cmd-locked` / `flywheel-noncode-goal-stuck` も参照。
