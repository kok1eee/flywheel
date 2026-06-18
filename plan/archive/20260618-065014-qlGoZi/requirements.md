# requirements — polish 比例制御: 純粋な move/rename は simplify を skip

## 背景

`should_polish`（FR-20）は goal の累積 diff 行数が `FLYWHEEL_POLISH_MIN_DIFF`(既定30) 未満なら
simplify を skip する。だが「純粋な rename / move」は中身が変わらないのに行数を稼ぎ、無意味な
simplify ターンを生む懸念があった（ROADMAP の本項目）。

## 調査結果（実機検証・2026-06-18）

- **git も jj も、純粋なファイル rename を `{a => b} | 0`（0 行）に collapse する**（rename 検出は
  既定 ON）。→ `fw_repo_diff_lines` は pure rename を 0 行と数え、**既存の min-diff 閾値で polish は
  既に skip 済み**。核心ケースは実は解決済みだった。
- **残る穴（defensive）**: `fw_repo_diff_lines` の **git fallback は `git diff --stat`（`-M` 無し）**。
  rename 検出は `diff.renames` config 依存（既定 true だが false にしている環境では rename が
  delete+add = 2×N 行に膨らみ、polish が誤発火する）。
- jj path は rename を既定で検出（変更不要）。

## 決定（grill 済み・2026-06-18）

- **検出は VCS rename 検知のみ**（保守）。新しい行数ヒューリスティックは入れない。
- **git fallback に明示 `-M`（--find-renames）** を足し、`diff.renames` config 非依存で rename を
  collapse させる。
- **copy（`-C`）は足さない**: コピー＝コード重複＝まさに simplify が拾うべき対象。skip は逆効果。
- **「reset 後の再 baseline で min-diff 無効化」は defer**（別機構＝baseline 捕捉タイミング。別 phase）。
- ファイル間コード移動（add≈del 対称）は今回スコープ外（riskier として decline 済み）。

## スコープ

- IN: `hooks/lib/common.sh` の `fw_repo_diff_lines` git fallback（`git diff --stat` → `-M` 付き）+ test/。
- OUT: jj path / 行数ヒューリスティック / copy 検知 / reset 再 baseline / should_polish のロジック自体。

## 完了条件

- `diff.renames=false` の git リポで sizable file を rename → `fw_repo_diff_lines` が ≈0（min 未満）
  を返す（`-M` 修正の効果）。
- 純粋な内容追加（rename でない）は従来どおり行数を数える（real change を誤って抑制しない）。
