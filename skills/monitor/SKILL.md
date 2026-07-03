---
name: monitor
description: "done の直前に監視 council を走らせ、実装が要件/挙動/進捗から drift していないか、実装文脈を持たない観測者で多観点検証する。flywheel の loop-driver が eval 緑→done の前に steer する。「drift 検証」「監視して」「done 前チェック」「乖離を確認」で発動。※ 計画レビューは critic、完了前の自己検証(自分で)は verification、ゼロから要件を掘るのは deep-interview。"
argument-hint: "<watch-focus（任意・人間の重点）>"
allowed-tools: [Read, Glob, Grep, Agent, Bash]
effort: high
context: fork
---

# Monitor — done-gate 検証 council（overseer）

**done を宣言する直前に、実装していない第三者の目（観測者）を多観点で当て、eval（静的）が捉えられない drift を潰す。** 記事 Loop Engineering の「Verifier を別に」「検証の死角」への解毒剤（FR-30）。

あなたは overseer（俯瞰役）。自分で深掘りせず、観測者を fan-out し、結果を集約して verdict を1つ出し、CLI で記録する。**判定（集約）は委譲しない**——観測者の「drift なし」を鵜呑みにせず、返ってきたエビデンスを自分で要件と照合する（Iron Law）。

## Step 1: コンテキスト収集（Bash / Read）

```
flywheel get '.goal'           # goal
flywheel get '.baseline_rev'   # 変更の起点
flywheel get '.watch_focus'    # 人間が指定した重点（あれば最優先）
```

- 変更 diff を取得し、main context を汚さないようスクラッチに退避する（観測者へは path で渡す）:
  - jj: `jj diff --from "$(flywheel get '.baseline_rev')" > /tmp/fw-monitor-diff.txt`
  - git: `git diff "$(flywheel get '.baseline_rev')" > /tmp/fw-monitor-diff.txt`
- 変更されたソースのパス一覧も控える（観測者が現ソースを Read できるように）。
- `plan/requirements.md` / `plan/design.md` は path のまま観測者に渡す（Read させる）。

## Step 1.5: 挙動 smoke を実行（条件付き・FR-34）

旧 verification ゲートを統合した独立検証。**動かすのは Bash を持つ overseer（あなた）・判定は Read-only 観測者**＝自己申告でない（観測者に Bash は持たせない＝過去の state 汚染事故を回避）。

次の **両方**を満たすときだけ smoke を実行する:
- 変更が **runnable surface**（web アプリ / サーバ / CLI / UI）に触れている、かつ
- eval が **薄い**（`flywheel get '.eval_src'` == `auto`＝プロジェクト全体の test/lint を自動検出しただけで、この goal の挙動を起動していない）。

該当時の手順:
1. `Skill: verification` の「挙動検証」手順で smoke を実行（`Skill: run` / `Skill: verify` / webwright 等に委譲して起動 → 要件のユーザーパスを実行）。
2. エビデンス（出力 / レスポンス / スクショの要点）を `/tmp/fw-monitor-behavior.txt` に退避し、`observer-behavior` に **path で渡す**（生ダンプで context を膨らませない）。

skip 条件（smoke 不要）: docs / 純ロジックで実行面が無い、または eval が **厚い**（explicit/spec＝eval が既に挙動を走らせている）。skip した旨を `observer-behavior` の入力に明記する。

## Step 2: 観測者を 3 レンズで fan-out（並列）

観測者リスト（**データ**。後でレンズを増やすときはここに追加するだけ）:

| reviewer | レンズ | 見るもの |
|---|---|---|
| observer-requirement | 要件逸脱 | 実装 vs requirements.md / design.md の各要件・完了条件。実装漏れ・解釈ズレ・スコープ逸脱 |
| observer-behavior | 挙動 | 緑のテストが要件のユーザーパスを実際に検証しているか（モック過多 / ハッピーパスのみ / 握り潰し＝anti-slop）。**runnable な変更なら runtime エビデンス**（Step 1.5 の smoke 出力 path があれば Read して要件と照合）。静的テストしか無い runnable 変更で runtime 未検証なら **drift(impl)** とし memo に「eval に runtime smoke を足せ（`flywheel set-eval` / design 完了条件）」 |
| observer-progress | 進捗 | 変更が goal に収束しているか。堂々巡り・残骸・goal 無関係な混入 |

各レンズを `Agent`（`subagent_type: "flywheel:drift-observer"`・**`run_in_background: false`（同期）**）で**同時 spawn**する。2.1.198+ は subagent が背景デフォルトのため、背景 spawn だと「fan-out→集約→記録を同一ターンで」の前提が構造的に空振りする（同一メッセージ内の並列呼び出しで 3 体の並行性は保たれる＝sync にして失うものは無い）。prompt は `facets/policies/plan-handoff.md` の4原則に従い、**長文はパス渡し・指示は末尾・coverage-first・quote-first**。prompt の骨子（末尾に指示を置く）:

```
agents/drift-observer.md の指示に従ってください。

## 入力（path で渡す。必要箇所を Read/Grep で取りに行くこと）
- 要件: plan/requirements.md
- 設計: plan/design.md
- 変更 diff: /tmp/fw-monitor-diff.txt
- 変更されたソース: <paths>
- goal: <goal>
- watch-focus（人間の重点・あれば最優先）: <watch_focus>

## あなたのレンズ
<このレンズの charter（上表の1行）>

## 出力
facets/policies/council-output-schema.md に従う JSON を1つ。reviewer="observer-<レンズ>"。
検出した drift は confidence/severity 付きで全件報告（閾値カットしない）。根拠は quotes に引用。
drift が無ければ findings:[] と summary に「drift なし」。
各 finding の memo に「実装で直せる(impl)/設計・要件レベル(design|requirements)」の心証を添える。
```

> **注意**: 「Confidence 80+ のみ」等の閾値指示は prompt に書かない（4.7+ のリテラル解釈トラップ。`facets/policies/confidence-scoring.md`）。フィルタは集約（Step 3）でやる。

## Step 3: 集約して verdict を決める（overseer 単独・peer cross-check なし）

1. 3観測者の JSON findings を集める。
2. `facets/policies/confidence-scoring.md` の降格マトリクスを機械的に適用:
   - 🔴 Critical（conf 90+ & critical/high） / 🟡 Warning（conf 80-89 & high/medium）を **drift として採用**。
   - ℹ️ Note / 📦 Archive は採用しない（verdict には載せず memo 程度）。
3. 採用 drift が **無ければ** → `clean`。
4. 採用 drift が **あれば** level を判定（**巻き戻し天井**）:
   - 採用 drift がすべて **コード修正で解消できる**（実装漏れ・挙動バグ・未収束。observer の memo が impl 寄り） → `implementing`。
   - 採用 drift に **設計が要件を満たせない / 要件自体が矛盾・実現不能** なものが1つでも含まれる（memo が design/requirements 寄り） → `design`（要件破綻なら `requirements`）。**自動では戻らず人間に hand-back される**ので、reason を具体的に。
5. reason は採用 drift の要約（どのファイル・どの要件・なぜ）を1〜3文で。

## Step 4: verdict を記録（CLI）

```
flywheel monitor-set clean
# または（--lens は採用 drift を出した reviewer のカンマ列。レンズ効果計測 FR-52）
flywheel monitor-set drift implementing "<reason>" --lens observer-behavior,observer-requirement
flywheel monitor-set drift design "<reason>" --lens observer-requirement
```

drift のときは **採用 drift を出した reviewer** を `--lens` で添える（どのレンズが効いたかの計測。
clean は採用 drift ゼロなので不要）。記録は `monitor-verdicts.csv`（fw_data_dir）に溜まり、
AUTO-GOTCHAS の追い出し・「レンズ別の着眼点」昇格の判断材料になる。

記録すると、次の停止で loop-driver が読み、clean→done / drift implementing→差し戻し / drift design|requirements→人間 hand-back を執行する。**verdict を記録するまで done は通らない。**

## Gotchas

- **観測者の「drift なし」を鵜呑みにする**: 返ってきた findings と quotes を自分で要件と照合してから clean を出す（Iron Law は委譲で緩まない）。
- **monitor-set を忘れる**: 記録しないと loop-driver が pending のまま再 steer する（veto cap で人間に返る）。必ず Step 4 で記録する。
- **drift を全部 implementing にしてしまう**: 設計/要件自体が破綻している drift を implementing に丸めるとコード修正で堂々巡りになる。memo が design/requirements 寄りなら level を上げて人間に返す。
- **diff を inline で観測者に渡す**: main / 観測者の context が膨らむ。スクラッチに退避して path で渡す。
- **watch-focus を無視**: 人間が重点を指定していたら最優先で観測者に渡す。
- **観測者に Bash を持たせる（実 state 汚染事故）**: 観測者は必ず Read-only の `flywheel:drift-observer`（Read/Glob/Grep のみ）で spawn する。Bash を持つ agent（general-purpose 等）を観測者にすると、動的検証のつもりで `flywheel` / loop-driver を**実リポの `.flywheel` に対して**走らせ、verdict を自己執行して phase を勝手に done まで進める事故が起きる（2026-06-15、drift-observer 未登録時に general-purpose で代替して実発生。history に `[sim]` 由来の遷移が残った）。シミュレーションは必ず隔離 temp dir で。verdict を記録するのは overseer だけ（`flywheel monitor-set`）、観測者は state を一切書かない。

<!-- AUTO-GOTCHAS -->
<!-- 以下は実行経験から自動追記。不要なら削除してよい -->
- **[2026-06-15] forked 実行（context:fork）が verdict を出さず空振りする**: `Skill: flywheel:monitor` が `(forked execution)` で「タスク待ち / ready」等の汎用応答だけ返し、観測者 fan-out も monitor-set も実行しないことがある（FR-30 実装時に複数回再現）。fork が走ったと信じ込まず、overseer の手順（context 収集 → drift-observer を fan-out → 集約 → `flywheel monitor-set`）を**呼び出し側で inline 実行**する。monitor-set が記録されない限り loop-driver は pending のまま再 steer するので、空振りは放置すると veto/monitor cap まで steer が続く。**[2026-07-03 追記]** 2.1.198 の subagent 背景化以降は構造的に起きる: fork が観測者を（デフォルトの）背景で spawn →「完了を待つ」とターン終了 → fork は非永続で待つ主体が消え、完了通知は親セッションに漂着して集約・monitor-set が実行されない（FR-52 council で実踏）。inline 実行 + 観測者の `run_in_background: false` が正。
- **[2026-06-15] 修正後に stale な drift verdict で1回だけ余分に差し戻される**: council が drift を記録 → それを直しても、次の停止で loop-driver は**記録済みの drift を消費して** implementing に1回差し戻す（「修正して続けて」）。既に直していれば再修正せずそのまま通す。drift 枝が monitor を null クリアするので、その次の停止で pending → 再検証（修正後の実装に対して）に進む。stale verdict の bounce を「まだ直っていない」と誤読しない。
- **[2026-06-29] FR-50 後: `monitor-set clean` は「最後のツリー変更」として記録する**: clean verdict は記録時の作業ツリー指紋（baseline 累積 diff の sha256）に紐付く（FR-50）。`monitor-set clean` の**後に**追跡ファイルを1つでも編集して停止すると、clean ゲートで指紋不一致→done せず**再 council**（stale-clean 穴塞ぎの意図どおりだが、知らないと「clean を記録したのに done しない」と驚く）。docs / version bump 等の仕上げは monitor-set clean の**前**に終わらせ、monitor-set clean を最後の編集にする。`.flywheel/` は gitignore で指紋に出ないので state 書き込み自体は無害。
- **[2026-07-03] 遅延漂着した council レポートで clean 後のツリーを触らない**: 背景 spawn された観測者の結果が後続 phase（clean 記録後・push 作業中など）に teammate message として漂着することがある（2.1.198+ の背景デフォルトで増加）。`monitor-set clean` の後にツリーを触ると FR-50 指紋が無効化され意図しない再 council になる。漂着した低 severity の指摘は improvements.md（fw_data_dir・リポ外＝指紋非影響）へ退避し、採用級なら次 goal に同乗させる（FR-52 で実踏）。

## 出力

`.flywheel/state.json` の `monitor`（`flywheel monitor-set` 経由）。verdict は `flywheel status` で確認可。
