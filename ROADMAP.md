# flywheel ROADMAP — 改善 backlog

実運用（dogfooding）で見つかった構造的弱点と改善候補。レバレッジ順。
（`flywheel add` の backlog は `.flywheel/backlog.jsonl` = gitignore でローカル限定のため、
共有したい改善 backlog はこのファイルを正とする。）

## 根っこ

flywheel は「**コード実装タスク**」前提で設計されている。実運用では、運用（Bash のみ）/docs/
設定変更/マルチレポ系の goal や、eval を後から直したいケースで摩擦が出る。本質は
**「eval を直す」「実装済みを認める」の2つに、`reset`（plan を archive して history を消す核兵器）
しか手段が無い**こと。軽量な横道が1本ずつあれば迂回ゼロで done まで行ける。

## 改善候補（レバレッジ順）

| 優先 | 改善 | 効果 | 状態 |
|---|---|---|---|
| ★★★ | eval 検出のランナー解決（uv.lock→`uv run`, bun/pnpm/yarn, poetry） | 今回の摩擦の9割が消える | ✅ 実装済（`fix: eval 自動検出を uv/bun/pnpm/yarn 対応`）。poetry は未 |
| ★★★ | `flywheel set-eval "<cmd>"` — CLI で eval_cmd を書き換え（model 禁止は維持） | `reset` の儀式が不要に。**gap B** 解消 | 未着手 |
| ★★ | 「実装済み」経路 — spec-ready から `flywheel verify`（即 eval へ）。偽の編集を捏造しない | **H-1** / spec-ready 詰まり解消 | 未着手 |
| ★★ | マルチレポ対応 — eval_cmd に sibling を含める（`uv run pytest && uv run --directory ../shared-python-lib pytest`）/ polish が両 diff を見る | 「半分しか検証されない」問題の解消 | 未着手 |
| ★ | 最初の eval veto で原因示唆 — `command not found` 系なら「eval_cmd 自体が怪しい。`set-eval` で直せ」 | 長い迂回を初手で短絡 | 未着手 |
| ★ | polish の比例制御 — 純粋 move/rename（追加≒削除で対称）は simplify skip。`reset` の再 baseline で min-diff 閾値が無効化される件も | 無意味な simplify ターン削減 | 未着手 |

## 機構メモ（コードで裏取り済み）

- **gap B（eval immutable）**: `hooks/design-validator.sh:23` が `fw_gate_closed`（no-spec|designing）の
  ときだけ検証 → spec-ready 以降は design.md を編集しても early-exit で**再昇格しない**。
  state.json はモデル編集禁止（C-2）。よって eval_cmd は spec-ready 以降 immutable。
- **H-1（非コード goal 詰まり）**: spec-ready→implementing は「最初の source 編集」がトリガー。
  Bash 運用/docs のみの goal は src を変えないので進めない。逃げは `FLYWHEEL_OFF=1`（`loop-driver.sh:81`）。
- **multi-repo**: eval は `cd "$FW_ROOT" && bash -c "$eval_cmd"`（`loop-driver.sh:111`）、diff/polish も
  `cd "$FW_ROOT" && jj diff`（`common.sh` fw_goal_diff_lines）。FW_ROOT のリポしか見ず sibling は素通り。

## 残すべき（効いていた点・退行させない）

- **設計ゲート**（requirements/design を先に書かせる）— 実装がブレない。col_letter の 1-based/0-based
  非対称・後方互換・OUT スコープの線引きが事前に固まった。
- **validate-plan** は速くて邪魔にならない。
- **eval veto が赤を止めた**のは正しい挙動（コマンドが本当に落ちていた。悪いのはゲートでなくコマンド）。

---
出所: 2026-06-16 実運用 retrospective（southernstar / shared-python-lib の goal）。
gap 詳細は auto-memory `flywheel-gap-b-eval-cmd-locked` / `flywheel-noncode-goal-stuck` も参照。
