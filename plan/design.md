# H-1: 非コード goal を eval に乗せる `flywheel go`

## 背景 / 問題

非コード goal（Bash 運用 / docs のみ）は source 編集が発生しないため、`hooks/design-gate.sh:58`「spec-ready で最初の source 編集が通った瞬間 implementing へ昇格」が永久に発火せず、**spec-ready で詰まる**。結果 loop-driver の eval フローに乗らず done にできない。現状の逃げは `FLYWHEEL_OFF=1`（flywheel を切る＝本末転倒）のみ。

Bash で昇格させない設計は維持する（`design-gate.sh:6`: pytest と調査スクリプトを正規表現で安定区別できないため、Bash は block も昇格もしない）。

## 方針（方針 A: CLI 入口）

偽の source 編集を捏造させず、CLI 入口 **`flywheel go`** で spec-ready→implementing を手動昇格する正規ルートを与える。`design-gate.sh:58`「最初の source 編集」の**非コード版**。

## 設計判断（grill 確定）

1. **セマンティクス**: `go` は phase を spec-ready→implementing へ昇格するだけ。eval / veto / polish / monitor / done は既存 loop-driver に委譲（再利用）。polish は diff≒0 で自動 skip されるので非コード goal でも無害。
2. **コマンド名**: `flywheel go`（`verify-set` / FR-32 verification と語感が衝突しないため verify は回避）。
3. **eval 前提**: thick eval 必須。`eval_cmd` 非空 かつ `! fw_eval_is_thin`（= `eval_src` ∈ {explicit, spec}）。未満なら go を**拒否**し、`set-eval` または design.md の完了条件で goal 固有の eval を設定するよう促す。薄い eval（eval_src=auto = プロジェクト全体の test/lint）での空振り done を入口で防ぐ。
4. **phase ガード**: spec-ready 限定。
   - `designing`（ゲート閉）→ **拒否**（go が設計スキップの裏口になるのを防ぐ。flywheel の設計優先思想の根幹）。
   - `implementing` 以降 → no-op（情報表示のみ）。
   - misuse の backstop は thick-eval 必須: コード goal で誤って go しても、eval（= テスト等）が実装無しでは落ちるので done にならない。go 単体では完了を偽装できない。
5. **既存パターン準拠**: `fw_state_exists` ガード・`FLYWHEEL_HOOK` ガードなし（CLI の state 書き込みは C-2 対象外、禁止はモデルの state.json 直編集のみ）。`set-eval` / `monitor-set` / `verify-set` と同型。

### 不採用

- **B 案（非コード専用 phase 新設）**: `fw_work_active` / `session-greeter` / `loop-driver` dispatch / `design-gate` を横断する大改修。implementing 再利用で足りるため不採用。
- **C 案（Bash で昇格）**: 調査スクリプトと区別不能（`design-gate.sh:6`）。不採用。

## 変更点

- `bin/flywheel`: `go)` ケース追加。`fw_state_exists` ガード → phase 検査（spec-ready 以外は拒否/no-op）→ thick eval 検査（未満は拒否）→ `fw_advance implementing "flywheel go: non-code goal, no source edit"`。
- `bin/flywheel`: usage / help 行に `go` を追加。`fw_log_usage "go"`（set-eval 準拠）。`status` 表示に必要なら追従。
- `README.md`: changelog + version bump（次版）。
- メモ `flywheel-noncode-goal-stuck` を「`flywheel go` で解消」に更新（実装後）。

## 完了条件（eval）

mktemp -d 内で live state（jj/git 配下の `.flywheel/`）を壊さず実機検証する。実行可能な静的チェックは即時、機能アサーションは `go` 実装後に green になる（実装前は red ＝ eval として正しい）。

```
set -e
bash -n bin/flywheel
grep -qE '^[[:space:]]*go\)' bin/flywheel
# --- 以下は実装後に green（mktemp の使い捨てリポで） ---
# happy:    flywheel start "x" → plan/design.md(## 完了条件(eval) 付き) を書く
#           → FLYWHEEL_HOOK=1 で hooks/design-validator.sh を直接実行（validate-plan design 合格→spec-ready, eval_src=spec）
#           → flywheel go → flywheel get '.phase' が "implementing"
# negative1: designing のまま flywheel go → 非ゼロ終了（拒否）かつ phase は "designing" のまま
# negative2: spec-ready かつ thin eval（eval_src=auto）で flywheel go → 非ゼロ終了（拒否）かつ phase は "spec-ready" のまま
```

合格 = happy で implementing へ昇格し、negative1/2 の両方で昇格が拒否される。

## 進め方メモ

- 実装 + dogfood は **live 0.8.6 が要る → 再起動後**（このセッションの hooks は stale）。
- H-1 自身はコード goal なので通常フローで回せる（adopt → validate-plan design → spec-ready → bin/flywheel 編集で implementing 自動昇格 → eval → done）。`go` は H-1 では不要（皮肉だが、go は非コード goal 向けの機能）。
- adopt 経由なら requirements.md 不要・`validate-plan design`（`all` 不可）で通す。
