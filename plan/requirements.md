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

## 機能要件

### FR-1: 設計ゲート（入口・hard block）
実装意図のツール使用（source への Edit/Write、実装系 Bash）を、state が `no-spec` / `designing` の間は **PreToolUse hook が exit 2 で物理ブロック**する。ブロック時は steer メッセージで設計フェーズへ誘導する。prose による「お願い」ではなく、ツール実行を実際に止める。

### FR-2: 設計フェーズは非スキップ（絶対）
どんなに雑なプロンプトからでも、実質的な変更には**必ず設計フェーズを通す**。設計フェーズは省略不可。ただし変更の重さに応じて**設計の重さは自動スケール**する（些末な変更は設計フェーズ内のトリアージで即合格して抜ける。別途「diff 閾値で素通り」する別経路は設けない＝門は常に ON）。

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

### FR-15: intent-router（invisible auto-engage・opt-in・v0.4.0）
「使っていることを感じさせない」理想形。**UserPromptSubmit hook** が build 意図の強い prompt（実装して/作って/機能追加 等）を検知し、flywheel が dormant なら自動で `flywheel start`（eval 自動検出付き）する。誤爆（質問・調査・些末修正で gate が閉じる）を避けるため:
- **opt-in `FLYWHEEL_AUTO=1` のときだけ**動く（既定 off。default 化は誤爆率を実測してから）
- 質問・調査・説明依頼は engage しない（除外パターン）
- 既に active なら触らない / 不要なら `flywheel reset`・`FLYWHEEL_OFF=1` で即解除

完全 invisible が快適になるには「些末タスクは設計ゲートを即通過」する weight-scaling が要る（将来）。現状は engage 分類で粗く weight を見る。

### FR-16: slash command 定型化（v0.4.0）
`/flywheel:start <作りたいもの>` で `flywheel start`（eval 自動検出）を起動し、設計フェーズへ誘導する。CLI を打たず1コマンドで開始できる明示的入口（auto-engage を opt-in にしない派の受け皿）。

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
