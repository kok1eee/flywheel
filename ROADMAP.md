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
| ★★ | adopt chain auto — done で backlog を自動消化（adopt は連鎖続行・start は HITL 停止・`FLYWHEEL_NO_CHAIN=1` で無効化） | 手動 `/next` を消して backlog 全部一気 | ✅ 実装済（v0.8.14・FR-33）。`test/adopt-chain.sh` で4ケース検証。無限ループ不可（pop で単調減少）・専用 cap 不要 |
| ★★ | grill が判断を必ず聞く — 事実/判断の峻別を grill/plan-steer/add に明文化（判断は self-answer せず聞く） | 「質問してこない grill」の矯正 | ✅ 実装済（v0.8.12） |
| ★★ | ROADMAP をメイン機能に — 源→`/add`→backlog→`/next` の中核ワークフロー（ROADMAP.md ヘッダ + guide 導線） | 改善の源を実装に繋ぐ | ✅ 実装済（v0.8.12・このファイル自身の回し方） |

### epic: マルチレポ対応

> FW_ROOT 単一リポ前提を崩し、sibling repo を跨ぐ goal でも diff/polish/gate が両方を見る。

| 優先 | 改善 | 効果 | 状態 |
|---|---|---|---|
| ★★ | マルチレポ対応 — eval_cmd に sibling を含める（`uv run pytest && uv run --directory ../shared-python-lib pytest`）/ polish が両 diff を見る | 「半分しか検証されない」問題の解消 | ✅ 実装済（v0.8.9・最小スコープ）。`flywheel repos <path>...` で宣言 → diff/polish が合算。#5（cross-repo gate/昇格）は go に委譲・未実装。jj diff path / error 経路テストは follow-up |

### epic: loop 制御（polish / drift / veto）

> implementing→eval→polish→done のループ駆動を無駄なく回す。

| 優先 | 改善 | 効果 | 状態 |
|---|---|---|---|
| ★ | drift steer の文言明確化 — 修正後の空振り steer に「この verdict はクリア済み・次停止で再 monitor が走る」を明示（`loop-driver.sh:177-178`） | monitor 判定と loop-driver 執行のタイミングずれでの混乱を消す | ✅ 実装済（v0.8.13・ROADMAP→/add→next の初 dogfood） |
| ★ | polish の比例制御 — 純粋 move/rename（追加≒削除で対称）は simplify skip。`reset` の再 baseline で min-diff 閾値が無効化される件も | 無意味な simplify ターン削減 | ✅ 実装済（v0.8.17・FR-37・最小スコープ）。調査で「純粋 rename は jj/git 既定で 0 行 collapse＝既に skip 済み」と判明 → `fw_repo_diff_lines` の git fallback に明示 `-M` を足し `diff.renames=false` でも config 非依存に collapse。copy(`-C`) は重複＝simplify 対象なので skip させない。`test/polish-rename-skip.sh`(2)。**ファイル間コード移動(add≈del) と reset 再 baseline は defer**（下記） |
| ★ | polish+monitor steer の融合 — done 前ゲートの polish(simplify) と monitor を1本の steer に束ね、同一ターンで simplify→monitor を実行（3往復→2往復）。eval は毎停止で独立に回るので polish が壊しても次停止で拾い done をすり抜けない（安全）。トレードオフ: polish が eval を壊した稀ケースで council 1回分を無駄打ち | loop の往復削減で done が速くなる | 未着手（出所: 2026-06-18 ユーザー観察「monitor を一緒に動かせば早い」） |
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
