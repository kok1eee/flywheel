# flywheel — requirements

> Sensors-first / harness-driven loop engine。auto mode を前提に「設計が無ければ実装を通さない」門を物理的に強制し、設計合格後は goal 達成まで自動で回り続ける Claude Code プラグイン。

## 背景

o-m-cc は「品質が維持される限り止まらない」Sisyphus Loop を **Guides（prose で skill 発動を誘導）** で実現している。しかし Opus 4.7+ / 4.8 + auto mode では、prose による skill 発動誘導が抑制される（モデルが「prefer action over planning」を過剰解釈し、内部に planning phase を持つ o-m-cc skill を「planning っぽい」と判断して撃たない）。結果、**auto mode で o-m-cc が構造的に発動しない**。CLAUDE.md をどれだけ盛っても直らないのは、問題が prose の届かない mode レベルにあるため。

これは o-m-cc に機能を「足して」直せる類ではない。**o-m-cc の Guides-first という形そのものが原因**。よって新しいアーキテクチャ＝ **Sensors-first（hook と state machine が loop と steering を強制し、モデルが skill を思い出すかに依存しない）** が要る。

設計思想の源流は cc-sdd（spec-driven development）の「設計をしっかり固めてから実装」。flywheel はその規律を **auto-mode ネイティブな門**に変換する: 設計が無ければ実装ツールを物理ブロックし、設計が validate を通って初めて実装フェーズに入り、以降は goal 達成まで自動 loop する。

### コアフロー（ユーザーの言葉）

```
① 適当プロンプト（人間。雑でいい）
        ↓
② 設計フェーズ【絶対・非スキップ】← 門
   Claude が設計を立てる → grill / critic で叩いて穴を埋める
   → validate 合格まで実装に入れない
        ↓（合格して初めて実装ツールの門が開く）
③ 自動 loop（人間不在）
   実装 → eval（②の設計に照合）→ 未達なら回り続ける → done
```

人間が触れるのは①と②だけ。③は完全自動。

### v0.5 の転回: モードが意図シグナル（plan-mode route）

v0.4.x までは「auto mode のまま全てを解く」前提で入口の意図判定に苦労してきた（FR-15 の正規表現 classifier は誤爆ゆえ opt-in 止まり、FR-20 の diff 適応は事後の代理指標）。v0.5 で前提を反転する: **「しっかりやりたい」は native plan mode の選択（Shift+Tab）がユーザー自身の宣言**であり、誤爆率ゼロの意図シグナル。ワンショットは auto のまま素通しする。

- **designing フェーズ ≒ native plan mode**: read-only は harness 本体が強制（Bash 書き込みも塞がる = 積み残しの H-1 が解決）。flywheel は門の再実装をやめ、**計画の品質保証**（FR-21）と**承認後の自動 loop**（FR-22）に再配置する
- flywheel の役割 = 「plan mode の強化」+「切り替わった瞬間からの強化」
- CLI ルート（`flywheel start` + design-gate）は headless / backlog 用に存置（2ルート構成）

## 機能要件

### FR-1: 設計ゲート（入口・hard block）
実装意図のツール使用（source への Edit/Write、実装系 Bash）を、state が `no-spec` / `designing` の間は **PreToolUse hook が exit 2 で物理ブロック**する。ブロック時は steer メッセージで設計フェーズへ誘導する。prose による「お願い」ではなく、ツール実行を実際に止める。

### FR-2: 設計フェーズは非スキップ（絶対）— v0.5 で強制範囲を再定義
**flywheel が engage している作業**（plan-mode route = FR-23 で engage した plan mode 作業 / CLI route = `flywheel start` した goal）では、設計フェーズは省略不可。変更の重さに応じて**設計の重さは自動スケール**する（些末な変更は設計フェーズ内のトリアージで即合格して抜ける）。

**v0.5 改**: auto mode のワンショットは**ユーザーのモード選択を尊重して門を閉じない**。「全ての実質的変更に常時強制」（v0.4.x の前提）は、意図判定の誤爆と引き換えだったため撤回。設計が要る作業かはユーザーがモードで宣言する。

### FR-3: 設計の硬化手段を人間の在席で切り替える
設計を叩く手段を、人間が応答可能かで適応させる:
- 対話セッション（人間在席）→ **grill**（1問ずつ AskUserQuestion で雑な入力を精密化）
- headless / background / cloud（人間不在）→ **critic + scout**（非対話で敵対批判、曖昧点は仮定として記録して進む）

設計フェーズが起きること自体は不変（FR-2）、叩き方だけ適応する。

### FR-4: 設計合格判定（門の開錠条件）
設計フェーズの完了は **validate（o-m-cc の `bin/validate-plan design` 相当: requirements.md/design.md の必須セクション + FR 言及率）合格**で判定する。合格して初めて state を `spec-ready` に遷移させ、実装ゲート（FR-1）を開ける。判定は LLM の自己申告ではなく形式チェック（Layer 1）に接地する。

### FR-5: loop ドライバ（出口・自動継続）
state が `implementing` / `eval` で goal 未達の間、**Stop hook が turn 終了を抑止**し、次フェーズへ自動継続させる。「止まらない」をモデルの意志ではなく hook が強制する。

### FR-6: eval ゲート（出口・完了判定）= 設計を2回目に使う
完了判定は、②で固めた設計の**受け入れ基準に照合**して行う。設計は入口（FR-1 の通行許可）と出口（完了判定の源）の**2回**使われる。runnable な変更は静的チェック（test/build）に加え**挙動検証**（o-m-cc の verification 挙動ゲート: native run/verify/webapp-testing で起動・観測）まで満たして初めて done。eval 未達なら loop（FR-5）に戻す。

### FR-7: state machine をファイルに持つ（context 非依存）
loop の状態（`no-spec → designing → spec-ready → implementing → eval → done`）を**ファイル state machine** に保持する。会話履歴に依存せず、ターン跨ぎ・セッション跨ぎ・マシン跨ぎ（EC2/Mac）で再開できる。各 hook はこの state を読んで門の開閉・継続可否を決める。

### FR-8: o-m-cc を workflow 部品として compose（再実装しない）
各フェーズの実作業は o-m-cc の既存 skill / agent を**発火して委譲**する（design / discovery-council / grill / critic / scout / sisyphus / validate-plan / verification）。flywheel はそれらを**駆動する harness** であり、o-m-cc の 16 skill / 14 agent を再実装しない。flywheel が持つのは hook・state machine・gate ロジックだけ。

### FR-9: 正当な停止点は2つだけ
auto loop が人間に止まってよいのは (a)「完了（done）」と (b)「要件の人間判断待ち（設計フェーズで grill が AskUserQuestion を出す瞬間）」のみ。それ以外でモデルが勝手に止まることを FR-5 が抑止する。

### FR-10: 緊急脱出と可観測性
- 門を一時無効化する bypass 環境変数（例 `FLYWHEEL_OFF=1`）を持つ（publicity-gate / simplify-diff-gate と同様の運用脱出口）。
- 現在の state とフェーズ遷移ログを人間が確認できる（state ファイル + ログ）。暴走・無限ループ時に何が起きているか追える。

### FR-11: polish フェーズ（初回 eval 合格後の自動品質整理・v0.2.0、v0.4.2 で eval 後に移動）
**初回の eval 合格後・done 確定の前**に、flywheel は **polish フェーズ**を1ターンだけ挿入し、モデルに simplify（コード整理: reuse / simplification / efficiency / altitude）を実行するよう steer する。polish 後に**再 eval が通って初めて done**（simplify が壊していないことを機械判定で確認）。これは LLM による非決定論的整理なので **Skill steering**（hook は撃たせるだけ）。一方、型チェック・lint・テストといった**決定論的品質チェックは eval_cmd（FR-6）に載せる**（例: `ty check && ruff check && pytest`）。

品質スタックは2段に分かれる:
- **polish**（LLM / steer）: `Skill: simplify` でコードを整理（冗長・重複・過剰複雑を潰す）
- **eval**（CLI / 決定論）: 型チェック(`ty`)・lint(`ruff`)・test の exit code

これは flywheel の CLI委譲 / Skill steering の2系統（FR-8 / C-3）にそのまま対応する。polish は `--no-polish` で無効化できる（FR-10 系の運用脱出口と同じ思想）。state machine は `implementing → eval →（初回合格で）polish → 再 eval → done`。

**v0.2.0 の旧配置（implementing → polish → eval）を v0.4.2 で改めた理由**: 旧配置は eval 失敗で implementing に戻るたび polish が再発火し、修正ループの turn とトークンが倍掛かりだった（veto cap 8 で最大8回 simplify）。さらに red なコードを磨くため、磨いた箇所が修正で消える無駄と「元から壊れていたのか simplify が壊したのか」の曖昧さがあった。green 後に1回だけ磨く（make it work, then make it right）ことで、修正ループは eval 最短で回り、磨く対象は修正込みの最終形になり、polish 後の再 eval 失敗は simplify が犯人と確定できる。1回だけの保証は state の `polished` フラグ。

### FR-12: 完了スペックの archive（v0.2.0）
goal が `done` に達したとき、その `plan/requirements.md` + `plan/design.md` を `plan/archive/<timestamp>/` に退避し、`state.json` のスナップショットも一緒に残す。spec を記録として保存しつつ、次の goal が `plan/` を上書きする前にクリーンにする。`flywheel start` も、前回の未完了 plan が残っていれば防御的に同じ archive を行う（done せず放棄された設計を失わない）。o-m-cc の archive-plans と同じ思想。

### FR-13: backlog ルート（goal キュー・v0.2.0）
複数の goal を順に処理する**薄いキュー**。独自の cron/scheduler は持たない——外側の定期/連続ループは native `/loop` / `/schedule` に委ね、再実装しない。flywheel が提供するのは**キュー操作だけ**:
- `flywheel add "<goal>" [--eval ...] [--no-polish]`: backlog に1件追加（`.flywheel/backlog.jsonl`）
- `flywheel list`: backlog 一覧
- `flywheel next`: flywheel が dormant か `done` のとき backlog 先頭を pop して `start`。作業中（active で done でない）なら拒否して clobber を防ぐ

`done` 到達時、loop-driver は backlog 残数を通知して `flywheel next` を促す。**auto-chain（hook が次を自動起動）は native `/goal` の完了セマンティクスが絡むため将来**。これで「goal の山を順に消化」が cron なしで回る（内側ループ=goal→done は既存、外側=backlog 消化はこの薄い層）。

### FR-14: eval 自動検出（低摩擦・v0.4.0）
`flywheel start "<goal>"` で `--eval` を省略したとき、プロジェクトファイルから test/lint/型チェックコマンドを**自動検出**する: `pyproject.toml`/`pytest.ini`→`ruff check && pytest`、`package.json`→`npm run typecheck && lint && test`、`Cargo.toml`→`cargo test`、`go.mod`→`go test ./...`。検出できなければ空（degrade）。解決順は `--eval` 明示 > **spec の完了条件（FR-19、validate 合格時に昇格）** > 自動検出 > 空。これで日常は `flywheel start "<goal>"` だけで済む。

### FR-15: intent-router（invisible auto-engage・opt-in・v0.4.0 → v0.5 で legacy 凍結）
「使っていることを感じさせない」理想形。**UserPromptSubmit hook** が build 意図の強い prompt（実装して/作って/機能追加 等）を検知し、flywheel が dormant なら自動で `flywheel start`（eval 自動検出付き）する。誤爆（質問・調査・些末修正で gate が閉じる）を避けるため:
- **opt-in `FLYWHEEL_AUTO=1` のときだけ**動く（既定 off。default 化は誤爆率を実測してから）
- 質問・調査・説明依頼は engage しない（除外パターン）
- 既に active なら触らない / 不要なら `flywheel reset`・`FLYWHEEL_OFF=1` で即解除

完全 invisible が快適になるには「些末タスクは設計ゲートを即通過」する weight-scaling が要る（将来）。現状は engage 分類で粗く weight を見る。

**v0.5 注記**: モード選択（FR-23）という誤爆率ゼロの上位互換シグナルの登場により legacy 凍結。コードは残すが default 化はしない。

### FR-16: slash command 定型化（v0.4.0、v0.4.7 で PATH 非依存化）
`/flywheel:start <作りたいもの>` で `flywheel start`（eval 自動検出）を起動し、設計フェーズへ誘導する。CLI を打たず1コマンドで開始できる明示的入口（auto-engage を opt-in にしない派の受け皿）。

**PATH 非依存（v0.4.7）**: command は `${CLAUDE_PLUGIN_ROOT}/bin/flywheel` を呼ぶ（裸の `flywheel` だと CLI を PATH に通したマシンでしか動かず「plugin を install すれば全ディレクトリで使える」が壊れる）。hook のメッセージも `FW_CLI`（PATH にあれば `flywheel`、無ければ plugin 同梱の実体パス）で案内する。引数なし起動（サジェストから Enter 直押し）は error にせず、status + 「goal を聞いてから start せよ」の degrade で受ける。

### FR-17: dormant 時の入口案内（SessionStart・低摩擦・v0.4.1）
flywheel が dormant（state なし＝門が開いている）なセッション冒頭で、**SessionStart hook** が「設計駆動で作るなら `flywheel start`（or `/flywheel:start`）」を1行案内し、入口の discoverability を上げる。FR-15 と違い **gate を閉じない**（state を作らず、ただ思い出させるだけ）ので誤爆リスクが無い、最も軽い入口層。ノイズを避けるため:
- **dormant のときだけ**出す（goal 進行中は loop 系が喋るので沈黙）
- `FLYWHEEL_OFF=1` で沈黙
- 現在の `FLYWHEEL_AUTO` 状態を併記し、常用するなら auto-engage（FR-15）を勧める

「最初は start を使え」を強制（gate を閉じる）でなく示唆（案内）で伝える。常時 gate ON は質問・調査・他作業まで巻き込み誤爆地獄になるため**採らない**——摩擦低減の欲求は FR-15 auto-engage で満たす。

### FR-19: spec-designed eval — 完了条件を AI が設計し harness が拾う（v0.4.5）
FR-6 の「完了判定は設計の受け入れ基準に照合する」を文字どおり実装する。従来 eval_cmd は `--eval` 手動 or 自動検出（プロジェクト全体の test/lint）のみで、**goal 固有の完了条件は誰も設計していなかった**。メタプロンプト手法（「目的に最適な指示文と完了条件を AI 自身に設計させ、人間は質問に答えて承認する」）を designing フェーズに融合する:

- **design.md に「## 完了条件（eval）」セクションを必須化**（validate-plan が存在チェック。無ければ不合格）。fenced code block に実行コマンドを書く（1行 = 1コマンド、`&&` 連結）
- **design-validator が validate 合格時にその block を `eval_cmd` へ昇格**。state の `eval_src`（explicit/auto/spec）で出所を管理し、`--eval` 明示時は上書きしない。state を書くのは hook（モデルは design.md を書くだけ＝C-2 原則維持）
- deep-interview の曖昧性評価に **DONE 軸**を追加（完了条件の案を AI が設計し、ユーザーは承認/修正だけ）。grill の決定木に**完了条件の枝**を追加（実行可能か・goal 固有か・合格=達成と言い切れるか）
- 入口は増やさない（`/vibe` 等の別コマンドは作らない）。雑な goal の受け止めは既存の designing パイプラインが担い、本 FR は「done の定義」だけを足す

これで「AI が完了条件を設計する（メタプロンプトの本質）+ 判定は CLI の exit code（自己評価バイアスの排除）」が両立する。

### FR-20: polish の diff 適応スケーリング（v0.4.6）
polish（FR-11）を goal の規模に適応させる。`flywheel start` 時に **baseline revision**（jj は `@` の親 / git は HEAD）を state に記録し、初回 eval 合格時に **baseline からの累積変更行数**を計測。閾値（既定 30 行・`FLYWHEEL_POLISH_MIN_DIFF`）未満なら polish を省略して即 done へ（typo 修正級の goal に simplify 1ターンは過剰）。

- **累積 diff** なので goal 中に細かく commit / push しても測れる（working copy の diff だけだと commit ごとにゼロリセットされ常に skip になる）
- baseline が取れない（VCS なし）・diff 計測失敗 → 従来どおり polish（degrade）
- skip も「実施判断済み」として `polished` に記録（再判定しない）
- これは FR-15 で「将来」とした weight-scaling の polish 版（些末な goal は門を軽く通す思想の最初の実装）

### FR-21: plan-mode gate — 提示される計画は検証済みのみ（v0.5）
**PreToolUse(ExitPlanMode)** が `tool_input.plan`（計画本文）を検証し、必須要素——非スコープ、**完了条件（eval）= done を機械判定する fenced command**——が無ければ **exit 2 で差し戻す**（steer: 不足の列挙 + 設計スキルの案内）。合格した計画だけがユーザーの承認ダイアログに到達する。設計の対話的硬化（grill / deep-interview）は plan mode 中にそのまま動く（read-only ツールのみで成立するため）。spike（2026-06-12）で haiku ですら差し戻し steer に1回で従い、完了条件を自分で設計することを実証済み。

### FR-22: 承認 = spec 確定 + loop 起動（v0.5）
**PostToolUse(ExitPlanMode)**（= ユーザーが計画を承認した瞬間に発火することを spike で実証済み）に hook が:
1. `tool_response.plan`（承認済み計画全文）を `plan/design.md` に書き出す——**spec の artifact 化まで hook がやる**（モデルは計画を提示するだけ。C-2 の強化であり、plan mode 中はファイルが書けないため唯一解でもある）。前回 plan は FR-12 の archive で退避
2. 完了条件の fenced block を `eval_cmd` へ昇格（FR-19 の機構を流用）
3. state を生成して `implementing` へ（designing / spec-ready は plan mode と承認が肩代わり）。baseline（FR-20）と承認後の permission_mode も記録
以後は既存 loop-driver（eval veto / polish-on-green / veto cap）が done まで回す。

### FR-23: plan-route の engage 条件（v0.5）
plan mode は flywheel 以外の用途（雑な調査計画等）にも使われるため、FR-21/22 の発動は **opt-in `FLYWHEEL_PLAN=1`** から始める（FR-15 と同じ「実測してから default 化」の手順）。`FLYWHEEL_OFF=1` は常に優先。常用するユーザーは shell rc に export して「plan mode に入る = flywheel が乗る」を既定にできる。

### FR-24: grill の基本動作化 — plan mode の既定の振る舞い（v0.5）
plan-mode route では、grill の方法論（決定点の列挙 → コードで答えが出るものは self-answer → 残る決定は AskUserQuestion で1問ずつ・推奨付き → 詰め切ってから計画提示）を **skill 発動に頼らず hook が注入する既定動作**にする。flywheel の thesis（モデルが skill を思い出すかに依存しない）を designing フェーズ自身に適用する——従来の「`/flywheel:grill` を使え」という steer は prose 誘導であり、flywheel が殺そうとした形そのものだった。

- **plan-steer hook（UserPromptSubmit）**: engage 中（FR-23）かつ `permission_mode == plan` のとき、grill 操作系の圧縮版を additionalContext で毎プロンプト注入（compaction 後も効く = FR-17 再アンカーと同じ思想）
- **plan-gate（FR-21）が下支え**: 操作系注入（soft）+ 形式ゲート（hard）の2段で「grilled な計画しかユーザーに提示されない」
- **明示的 `/flywheel:grill` は存置**: CLI route（plan/*.md を叩く）、plan mode 中のオンデマンド深掘り、flywheel 外での利用。基本動作（暗黙）とオンデマンド（明示）の2層構造

### FR-25: 進捗方向の検知と revert 規律（v0.5.2）
veto loop を「pass/fail の二値」から「**方向のあるループ**」にする（autoresearch plugin の core-loop / fix から借用し、prose でなく hook 注入で実装）:
- eval 失敗時、出力から fail 数を best-effort 抽出（pytest/jest「N failed」、ruff/ty「Found N errors/diagnostics」、go「--- FAIL:」。抽出不能なら方向表示なしに degrade）し、state の `last_fail_count` と比較して steer を変える: **改善**（続行）/ **横ばい**（別の仮説へ）/ **悪化**（**直前の変更を戻してから**別アプローチ——失敗した変更を積んだまま重ねない = revert 規律）
- eval 合格時は baseline を 0 にリセット。以後の悪化（例: polish の simplify が壊した）は「0→N」として即 revert steer になる
- 狙い: veto cap までの 8 回を「同じ穴を掘り続ける8回」でなく「方向修正のある8回」にする

### FR-26: 調査・検証の sub-agent 委譲（v0.6.0）
Claude Code 2.1.172 の nested subagents（sub-agent が自分の sub-agent を spawn できる・最大5階層）を designing / 検証フェーズに配線する。狙いは「**探した過程は捨てて結論だけ持つ**」——判断を担う agent の context を生のファイルダンプで埋めない。

- **council メンバーの調査委譲**: researcher / analyst / scout の tools に `Agent` を付与。大きいコードベースの sweep（類似機能トレース・境界把握・規約抽出）は code-explorer / architecture-mapper / convention-scout を子として切り、結論だけ受け取って要件整理・ギャップ分析に集中する
- **critic の adversarial verify**: critic が報告前に critical / high の指摘ごとに反証専門の子（「この指摘を反証しろ」）を spawn。反証が成立した指摘は confidence を下げて反証根拠を併記する（落とさない = Coverage-first 維持）。批判レポートの確証バイアス（もっともらしいが間違っている指摘）を削る
- **verification の観測委譲**: 挙動検証（起動・観測）のログ / 出力ダンプは子に収集させ、main context にはエビデンス要約だけ戻す。判定（VERIFY）は委譲しない
- **モデル方針（社内配布前提・明示指定で可）**: 判断層（council メンバー / critic / designer）と解釈系の収集層（code-explorer / architecture-mapper）は `model: sonnet`/`opus` 固定をやめ **`inherit`** に変更——main loop で選んだモデル（普段 Fable / Opus）がそのまま判断の質になる。skill 側の固定（discovery-council=sonnet / design=opus）も撤去（固定するとメンバーの inherit がそれを継承して意図が崩れる）。列挙系の sweep の子だけ呼び出し側が `model: haiku` を明示して降格。迷ったら継承。子の報告が期待と食い違ったら継承モデルで撃ち直す（staged escalation）。heuristics は capabilities.md に集約
- **制約の自覚**: 子の prompt には**出力契約**（何を返したら終わりか）を必ず明記（「spec が done を定義する」思想の子への適用）。skill-logger は main loop しか観測しないため nested の活動は計測の盲点になる（将来の計測拡張候補）。要 2.1.172+（旧版では子に Agent ツールが渡らず、従来どおり自前調査に degrade）

### FR-27: discovery-council の Workflow 化 — 決定論的 council（v0.7.0）
peer-to-peer（TeamCreate + SendMessage）の調整は model-driven であり、Gotchas に記録済みの失敗（SendMessage の recipient 名ミスで silent loss / researcher 待ちぼうけ / 相互検証の省略）は構造的に再発しうる。**Workflow tool（決定論的編成）に置き換え**、main loop から見て council を「**Workflow 1 call + AskUserQuestion**」に封じ込める。loop の継続を /goal に、designing の read-only を plan mode に委ねたのと同じ「native に compose」の移動を、council の編成に対して行う。

- **skill 名は維持**（`/flywheel:discovery-council`）。design-gate の steer（`fw_designing_steer`）・deep-interview のハンドオフ・design skill の誘導は無変更——**中身だけ差し替え**（hook 変更は skill-logger の matcher のみ）
- **ステージ構成は script が強制する**: ① `parallel(researcher, scout)` 独立調査 → ②（barrier 正当: 相互の結果が要る）**交換検証** — 互いの findings を引数に再 spawn（researcher は scout の gaps を技術検証、scout は researcher の知見を踏まえてギャップ再点検）→ ③ analyst が全 findings を入力に統合し `plan/requirements.md` を Write + 未解決曖昧点を構造化して返す。相互検証は「モデルが思い出したら」から「**必ず実行される**」へ
- **schema 強制**: council-output-schema v1（facets/policies/council-output-schema.md）を JSON Schema 化し `agent(…, {agentType: 'flywheel:<member>', schema})` で強制。不一致はツール層が自動リトライ。prose の「従え」から機械強制へ（集約の機械適用が初めて保証される）
- **人間接点は main loop に残す**: workflow は `{requirements_path, ambiguities[], assumptions[], summary}` を返し、ambiguities 非空なら main loop が AskUserQuestion（Step 3 スキップ禁止は維持）→ 回答を requirements.md に反映して確定。子・workflow 内から人間に聞けない制約を「自律作業 = 封じ込め / 人間接点 = main loop」の線引きとして固定する
- **Team 版は削除**（完全置き換え。旧実装は jj 履歴に残る）。FR-26 の nested 委譲は workflow agent でも agent 定義経由でそのまま有効
- **計測**: skill-logger の matcher を `Skill` → `Skill|Workflow` に拡張し、Workflow 起動を `workflow:<name>` 行で skill-usage.csv に記録（FR-18 の延長。nested の盲点は残るが「council が workflow で走った」は観測可能に）
- **完了条件**: dogfood 1回で (a) main loop の編成が Workflow 1 call に収まる (b) 曖昧 goal で ambiguities が AskUserQuestion に到達 (c) requirements.md が生成され schema 準拠の findings が CSV/ログで確認できる。機械判定が難しい対話部分は verification（挙動エビデンス）で代替
- 効果検証後、同じ型を design → critic 反証 → 修正の loop-until-pass に展開（**FR-28 候補**）

### FR-29: 会話合意からの adopt 入口 — designing の「掘る」をスキップ（v0.8.0 候補）
会話の中で「何をやるか」が既に合意できているのに、`flywheel start` は designing フェーズで要件をゼロから掘り直す（deep-interview / discovery-council へ誘導）。合意は既に会話コンテキストにある——必要なのは「掘る」ではなく「**結晶化**」（会話の合意を design.md + 完了条件に書き起こす）だけ。これを専用入口 `adopt` として提供する。

- **正体**: 会話 → design.md 生成 → validate → spec-ready → implementing。plan-approved（FR-22）と同型だが **plan mode を経由しない**（通常会話の流れのまま載せる）。「計画を新たに作る場」が plan route なら、adopt は「会話で固まった合意をそのまま載せる場」——作り直さないのが価値
- **source は2つ（会話 / handoff journal）**: adopt の入力は (a) 現セッションの会話で合意した方針、または (b) `.claude/journal.md` の最新 Next Actions（[[handoff]] 経由）。(a) はモデルだけが持つ会話コンテキスト。(b) は **新セッション / 別マシンで会話コンテキストが空でも成立する**——むしろ **handoff → adopt が最も自然な実戦フロー**（セッションA で議論 → handoff で合意を Next Actions に固める → 別マシンで adopt して loop に載せる）。handoff 規約で Next Actions は「ファイル名・関数名・コマンド名レベルで具体的」に書かれるため、結晶化の入力として質が高い。会話 source と handoff source は「自律作業 = 封じ込め / 人間接点 = main loop」の線引きとも整合（journal はその引き継ぎ媒体）
- **入口は slash command が主**: `/flywheel:adopt`（会話コンテキストを持つモデルが起動）。source 解決は **会話/引数の合意 > journal.md の最新 Next**（会話に合意があればそれを、無ければ journal を読むフォールバック）。CLI `flywheel adopt "<一言サマリ>"` は state を作り steer を切り替えるヘルパーだが、design.md を書くのは続けて動くモデル（素の shell からは完結しない）
- **start との違いは designing の入り方だけ**: 共通配線（design.md → design-validator → spec-ready → 実装編集で implementing → eval veto loop / polish-on-green）は完全に流用。adopt は state に `entry:"adopt"` を記録し、design-gate の `fw_designing_steer` が「要件を掘り直すな、会話で合意した方針を design.md に結晶化せよ（完了条件 = eval も設計）」に分岐する
- **検証は通す**（ユーザー確認済み）: 結晶化した design.md も design-validator の validate-plan を通す。完了条件（eval）セクションが無ければ差し戻し。「検証済みの設計だけが門を開ける」原則を adopt でも維持（信用スキップはしない＝ done を定義しないまま implementing に入らせない）
- **archive は通常どおり**（FR-12）: 前回 plan は退避。adopt は「既存 design.md を再利用」ではなく「会話から新規生成」なので前回 plan を残す理由はない
- **C-2 維持**: state を作るのは CLI、design.md を書くのはモデル、spec-ready に進めるのは design-validator（validate の exit code）。adopt でも「モデルは state を進めない」は不変
- **完了条件**: 会話で実装方針が合意済みの状態から `/flywheel:adopt` 一発で (a) design.md が会話内容で生成され (b) validate を通って spec-ready になり (c) deep-interview / discovery-council の掘り直し steer が出ない

### FR-18: スキル使用と steer の計測（v0.4.4）
PreToolUse(Skill) hook（skill-logger）が**全 Skill 使用**を `skill-usage.csv`（`${CLAUDE_PLUGIN_DATA:-~/.claude/flywheel-data}`）に記録し、design-gate / loop-driver は **steer 発行**を `steer:*` 行で同じ CSV に記録する。観測のみで block しない（FR-10 の可観測性の延長）。これで:
- (a) **evolve の入力が実配線される** — 従来 skill-usage.csv の書き手が無く、evolve は常に空データで動いていた
- (b) **steer 従命率が測れる** — 「steer 行の後に対応する skill 行が現れた率」。design.md の dogfood 宿題（compose の2系統）の実装
- (c) 人気 / 過少トリガー skill を把握できる（Anthropic skills blog の practice「スキルの計測」）

**active 時の再アンカー（v0.4.3）**: goal 進行中のセッション開始（resume・compaction 復帰・新セッション）では、入口案内の代わりに**現在の phase / goal / 次にすべきこと**を context に注入する。state.json は context 非依存（FR-7）だが、モデル側の context は compaction で消えるため、SessionStart で再注入して数時間〜数日の長時間自律運転を支える（Fable 5 の長時間 context 保持を harness 側から補強）。designing なら設計ステップの steer（FR-2 のパイプライン案内）、implementing/polish/eval なら eval_cmd 込みの続行案内、done なら next/reset 案内を出す。

## 非スコープ

- **o-m-cc の置き換え / 作り直し**: flywheel は driver であり、o-m-cc の skill・agent・state 層（atoms 等）・jj ルール・leak gate を再実装しない（FR-8）。両者は compose 関係。
- **新しい workflow skill 群の作成**: 要件分析・設計・実装・レビューの中身は o-m-cc に既にある。flywheel はそれらを呼ぶだけ。
- **中央オーケストレーター agent の導入**: loop は hook + state machine（決定論的 harness）が駆動する。「全 agent を統括するマスター agent」は置かない（o-m-cc の peer-to-peer 原則と整合）。
- **open-ended 探索ループ**: 予算上限付きの探索的 loop（o-m-cc の experiment 的なもの）は v1 では扱わない。flywheel v1 は closed loop（設計で done が定義され、eval で終わる）に限る。
- **TypeScript / Python ランタイムへの移行**: o-m-cc 同様 Markdown + Shell（hook）で構成し、ビルド不要・依存最小を維持する。
- **v1 のフル機能**: v1 は walking skeleton（最小の設計ゲート + loop ドライバ + state file + design-as-eval が o-m-cc workflow を auto mode で end-to-end 駆動する所まで）に限定。全フェーズの Sensor を最初から揃えるのは v2 以降。
