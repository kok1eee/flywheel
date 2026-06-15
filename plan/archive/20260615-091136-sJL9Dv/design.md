# FR-30 — 監視 council（done-gate 検証 council）

## Context

Zenn「Loop Engineering」記事をきっかけに flywheel の弱点を点検した結果、**唯一のホールは「runnable な変更の挙動判定を実装者本人がやっている＝確証バイアス」**だと特定した（eval は CLI exit code で既に客観的、loop-driver は eval 失敗の fail 数トレンドを既にカバー）。記事の罠1「検証の死角」と「Verifier を別に」がちょうどここに刺さる。

そこで **done を宣言する直前に、実装文脈を持たない別エージェント群（観測者）に多観点で drift を検証させる** 仕組みを入れる。これは記事の「別 verifier」を flywheel に取り込みつつ、設計ゲート同様「人間が手綱を握れる」形にする。

スコープは段階導入の第1段（v1 = done-gate）。走行中ずっと監視する continuous watchdog（v2）は **同じ drift→loop-driver 執行経路に無改修で載る**ように設計するが、本 FR では作らない。

### 設計判断（確定）
- **v1 = done-gate council**。overseer は done 境界で同期実行する skill（discovery-council が設計時に main を占有するのと同型。実装は止まっているので占有してよい）。background Agent / cron は不要。continuous（Shape B）は v2。
- **観測者 3 レンズ**（要件逸脱 / 挙動 / 進捗）を **データ化したリスト**で持ち、後から増やせる。
- **集約は overseer 単独**（confidence-scoring + 降格マトリクス）。観測者間 peer cross-check は入れない。
- **巻き戻し天井**: 自動で戻れるのは implementing まで。design/requirements レベルの drift は phase を designing に戻して**人間に hand-back**（HITL）。

## アーキテクチャ

```
[実装メイン] --全力で実装--> eval 緑
     │
loop-driver (Stop hook) green 経路:
   should_polish → polish（従来どおり）→ 再 eval 緑
   → monitor ゲート:
       monitor 未実施 → main を steer「Skill: flywheel:monitor で検証せよ」+ exit 2
     │
[Skill: flywheel:monitor]（overseer・done 境界で同期実行）
   plan/requirements.md・plan/design.md・diff・watch_focus を Read
   → 観測者 3体を Agent で fan-out（独立コンテキスト・Read-only）
       ①要件逸脱 ②挙動 ③進捗  各々 council-output-schema JSON で報告
   → overseer が confidence-scoring + 降格マトリクスで集約 → drift 判定
   → `flywheel monitor-set <status> [level] [reason]`（Bash・CLI 経由で state 書込）
     │
次の Stop → loop-driver が monitor を読む:
   clean              → done（従来どおり archive）
   drift implementing → monitor クリア・phase=implementing・exit 2・「直して」steer
   drift design/req   → monitor クリア・phase=designing・exit 0・人間に hand-back
```

**重要な制約**: hook（シェル）から Agent は spawn 不可。かつ design-gate が `.flywheel/*` への model の Edit/Write を全 phase でブロックする（C-2）。よって drift フラグは **CLI 経由**（`flywheel monitor-set`、Bash 実行）で書く。overseer skill が観測者を spawn し、結果を CLI で state に書く。

## 変更ファイル

### 新規
- **`skills/monitor/SKILL.md`** — overseer skill。frontmatter: `allowed-tools: [Read, Glob, Grep, Agent, Bash]`, `effort: high`, `context: fork`。Step: 入力 Read → 観測者リスト（データ）を 3体 fan-out → 集約 → `flywheel monitor-set`。観測者 prompt は `facets/policies/plan-handoff.md` の4原則（path 渡し・長文上指示下・coverage-first・quote-first）に従う。
- **`agents/drift-observer.md`** — 汎用の観測者 1 種（Read-only: `tools: Read, Glob, Grep`、`model: inherit`）。レンズ charter は skill の prompt slot で注入（要件逸脱/挙動/進捗）。出力は `facets/policies/council-output-schema.md` の JSON（confidence+severity+quotes 必須、`facets/policies/confidence-scoring.md` 準拠、coverage-first で全件報告）。

### 修正
- **`hooks/lib/common.sh`** — `fw_init` の初期化 JSON（:131-134 付近）に `watch_focus:""` / `monitor:null` / `monitor_attempts:0` を追加。`fw_set_json`/`fw_get` は汎用なので新規ヘルパー不要。
- **`hooks/loop-driver.sh`** — green 経路（:96-110）の `should_polish && enter_polish` の**後**、`fw_advance done` の**前**に monitor ゲートを挿入。monitor が null→pending 化して検証 steer / clean→done / drift implementing→implementing 差し戻し(exit 2) / drift design|requirements→designing 差し戻し(exit 0, hand-back)。implementing へ戻す全経路（eval fail 含む）で `monitor` を null クリア（fresh green で再検証させる）。
  - **監視ループの hand-back cap は `monitor_bump`（`monitor_attempts` カウンタ・eval veto と別系統）で保証する**。eval veto は green ごとに `veto_count=0` リセットされるため、green 領域を回る監視ループ（pending churn / drift-impl 反復）には効かない（B002）。`monitor_attempts` は green 領域でも単調累積し、`FLYWHEEL_MONITOR_CAP`（既定 = veto cap = 8）到達で人間 hand-back する: pending/不正 verdict churn → implementing 復帰 + 人間通知 / drift-impl が cap 回未解決 → 設計レベル疑いとして designing へ escalate。clean / design・requirements hand-back / eval 失敗で `monitor_attempts` を 0 リセット。
- **`bin/flywheel`** — サブコマンド追加: `monitor-set <status> [level] [reason]`（state へ monitor 書込）, `watch-focus <text>`（人間が監視の重点を指定）。`status` 表示に watch_focus と最新 monitor verdict を追加。
- **`README.md` / `CHANGELOG`** — FR-30 を追記。`plugin.json` と `marketplace.json` の version を `0.7.0`→`0.8.0`。

### 再利用（編集不要・参照のみ）
- `facets/policies/confidence-scoring.md`（drift の確信度付け＋降格マトリクス）
- `facets/policies/council-output-schema.md`（観測者→overseer の報告 JSON）
- `facets/policies/plan-handoff.md`（overseer→観測者の指示 4 原則）
- discovery-council の fan-out パターン（`skills/discovery-council/` を雛形に）

## HITL（人間が手綱）
- `flywheel watch-focus "<text>"` で監視の重点を指定 → overseer が Read して観測者に渡す。
- design/requirements レベルの drift は必ず人間に hand-back（phase=designing で停止、自動修正しない）。
- **監視ループは必ず人間に返る**: `monitor_attempts` が `FLYWHEEL_MONITOR_CAP`（既定 8）到達で hand-back する。skill 不調で verdict が出ない・drift が解消しない場合でも無限ループせず人間の手綱に戻る（B002 対策。緑領域専用カウンタなので eval veto の green リセットに defeat されない）。
- monitor は LLM 判断であり決定論ゲートではない（eval が決定論ゲートのまま）。verdict は state に残り `flywheel status` で確認可。

## 非スコープ
- **continuous mid-run watchdog（Shape B / v2）**: PostToolUse カウンタ→watch_due→background Agent or cron での定期監視。drift→loop-driver の執行経路は共通なので無改修で後付けできるが、本 FR では作らない。
- **観測者間 peer cross-check**: 観測者の相互 SendMessage 検証は入れない（overseer 単独集約）。
- **3 レンズ超のレンズ**（security-drift / perf-drift 等）: レンズはデータ化するので後から追加可。本 FR は 3 つ。
- **implementing 超の自動巻き戻し**: design/PRD drift は常に人間 hand-back（意図的な天井）。
- **monitor verdict の偽装対策**: monitor は LLM 判断のため CLI で gaming 可能。決定論的防御は eval ゲートが担うという前提を維持（本 FR では強化しない）。

## 完了条件（eval）

```bash
bash -n bin/flywheel && bash -n hooks/loop-driver.sh && bash -n hooks/lib/common.sh
./bin/validate-plan all
grep -q 'monitor-set' bin/flywheel && grep -q 'watch-focus' bin/flywheel && grep -q 'watch_focus' hooks/lib/common.sh && grep -q 'monitor' hooks/loop-driver.sh
FW="$PWD/bin/flywheel"; T="$(mktemp -d)"; ( cd "$T" && "$FW" start "eval-probe" --eval "true" >/dev/null 2>&1 && "$FW" watch-focus "pf" >/dev/null && "$FW" monitor-set clean >/dev/null && "$FW" get '.watch_focus' | grep -qx pf && "$FW" monitor-set drift design "r" >/dev/null && "$FW" get '.monitor.level' | grep -qx design )
test -f skills/monitor/SKILL.md && test -f agents/drift-observer.md
```

## 検証（手動・挙動）
1. 実 goal で flywheel を回し、eval 緑到達時に `Skill: flywheel:monitor` への steer が出ること（loop-driver の stderr）。
2. monitor が観測者 3 体を spawn し、要件逸脱を仕込んだケースで drift を検知 → done がブロックされ implementing に戻ること。
3. design レベル drift を仕込んだケースで phase=designing に戻り、人間に hand-back メッセージが出ること（自動ループしない）。
4. `flywheel watch-focus "X"` 設定後、観測者の prompt に X が反映されること。
5. drift 無しケースで monitor=clean → 通常どおり done・archive されること。
