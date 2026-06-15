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

## Step 2: 観測者を 3 レンズで fan-out（並列）

観測者リスト（**データ**。後でレンズを増やすときはここに追加するだけ）:

| reviewer | レンズ | 見るもの |
|---|---|---|
| observer-requirement | 要件逸脱 | 実装 vs requirements.md / design.md の各要件・完了条件。実装漏れ・解釈ズレ・スコープ逸脱 |
| observer-behavior | 挙動 | 緑のテストが要件のユーザーパスを実際に検証しているか。モック過多 / ハッピーパスのみ / 握り潰し（anti-slop） |
| observer-progress | 進捗 | 変更が goal に収束しているか。堂々巡り・残骸・goal 無関係な混入 |

各レンズを `Agent`（`subagent_type: "flywheel:drift-observer"`）で**同時 spawn**する。prompt は `facets/policies/plan-handoff.md` の4原則に従い、**長文はパス渡し・指示は末尾・coverage-first・quote-first**。prompt の骨子（末尾に指示を置く）:

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
# または
flywheel monitor-set drift implementing "<reason>"
flywheel monitor-set drift design "<reason>"
```

記録すると、次の停止で loop-driver が読み、clean→done / drift implementing→差し戻し / drift design|requirements→人間 hand-back を執行する。**verdict を記録するまで done は通らない。**

## Gotchas

- **観測者の「drift なし」を鵜呑みにする**: 返ってきた findings と quotes を自分で要件と照合してから clean を出す（Iron Law は委譲で緩まない）。
- **monitor-set を忘れる**: 記録しないと loop-driver が pending のまま再 steer する（veto cap で人間に返る）。必ず Step 4 で記録する。
- **drift を全部 implementing にしてしまう**: 設計/要件自体が破綻している drift を implementing に丸めるとコード修正で堂々巡りになる。memo が design/requirements 寄りなら level を上げて人間に返す。
- **diff を inline で観測者に渡す**: main / 観測者の context が膨らむ。スクラッチに退避して path で渡す。
- **watch-focus を無視**: 人間が重点を指定していたら最優先で観測者に渡す。
- **観測者に Bash を持たせる（実 state 汚染事故）**: 観測者は必ず Read-only の `flywheel:drift-observer`（Read/Glob/Grep のみ）で spawn する。Bash を持つ agent（general-purpose 等）を観測者にすると、動的検証のつもりで `flywheel` / loop-driver を**実リポの `.flywheel` に対して**走らせ、verdict を自己執行して phase を勝手に done まで進める事故が起きる（2026-06-15、drift-observer 未登録時に general-purpose で代替して実発生。history に `[sim]` 由来の遷移が残った）。シミュレーションは必ず隔離 temp dir で。verdict を記録するのは overseer だけ（`flywheel monitor-set`）、観測者は state を一切書かない。

<!-- AUTO-GOTCHAS -->

## 出力

`.flywheel/state.json` の `monitor`（`flywheel monitor-set` 経由）。verdict は `flywheel status` で確認可。
