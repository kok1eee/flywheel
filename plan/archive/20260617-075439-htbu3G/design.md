# /flywheel:add に軽量 grill-me を組み込む（雑な add を防ぐ）

## Context

adopt chain（v0.8.10）で phase を backlog に積めるようになったが、`flywheel add` は goal 文字列を
積むだけで壁打ちが無い。`adopt` は「掘らない（結晶化）」前提なので、**雑な add がそのまま
next→adopt→design→実装に直行する**（grill が効かない）。ユーザーのフロー
「`/add⇨grill-me⇨正式な phase として追加`」を実現し、add 時に**軽量 grill（3点）**で phase を
練ってから積む。grill 成果は backlog に残し、別セッション跨ぎでも揮発させない。

## 方針

- `/flywheel:add`（`commands/add.md`）を「goal → **軽量 grill**（Done / Boundary / 依存・曖昧点の3点を
  AskUserQuestion で1問ずつ）→ 練れた phase を backlog に積む」オーケストレーションにする。
- grill 成果を backlog entry に保存: `notes` フィールド追加（Boundary/曖昧点）+ Done を既存 `eval_cmd` へ。
- `next` 起動時に `state.notes` へ引き継ぎ、起動後の design.md の種にする（`goal`/`eval_cmd` と同じ流れ）。
- フル grill は全体設計（start / plan mode）側に任せる。add は軽量3点に留める（手数を抑える）。

## Tasks（Boundary / Depends / Done）

- **T1 backlog notes 配線** | Boundary: `bin/flywheel`（`_parse_goal_args`/`add)`/`next)`/`list)`/`status)`）, `hooks/lib/common.sh`（`fw_init` に notes 引数 → `state.notes`） | Depends: - | Done: `flywheel add --notes "x" "g"` → backlog entry に `notes` → `next` → `flywheel get '.notes'` == `x`。`.notes // ""` で後方互換。
- **T2 /add の grill オーケストレーション** | Boundary: `commands/add.md` | Depends: T1（`--notes` を使う） | Done: add.md に「軽量 grill（Done/Boundary/曖昧点）で詰めてから `flywheel add --eval "<Done>" --notes "<Boundary/曖昧点>" --adopt` で積む」手順が記述されている。

既存 `commands/start.md`・`adopt.md`、今日追加の `next.md`・`add.md` と同型。`flywheel:grill` skill の軽量版を add.md 内で行う（フル skill 起動はしない）。

## 非スコープ

- **/adopt の「backlog 全部一気」（auto-chain）** — 次 phase に切り出し。`loop-driver.sh` の done→自動 next 変更で、無限ループ防止が要る独立 task（Boundary が別）。本計画では触らない。
- フル grill の add 組み込み（軽量3点のみ）。
- 既存 `/flywheel:adopt`（単発結晶化）・`/flywheel:next` の挙動変更（触らない）。

## 完了条件（eval）

```
bash -n bin/flywheel
grep -qE '\-\-notes' bin/flywheel
grep -qiE 'grill|Done|Boundary|曖昧' commands/add.md
bash test/add-notes.sh
```

`test/add-notes.sh` は T1 実装時に作成（mktemp で live state を壊さず検証）: `add --notes "x" "g"` →
`next` → `state.notes == x` / `list` が notes 有無を表示 / 旧 backlog（notes 無し）でも `.notes // ""` で壊れない。

## 検証

1. `bash test/add-notes.sh` が緑（backlog notes の配線）
2. `/flywheel:add "<goal>"` 実行 → 軽量 grill（3問）→ backlog に練れた phase が積まれる（`flywheel list` で確認）
3. `/flywheel:next` → 起動後 `flywheel status` の `notes` が design の種として残っている
