#!/usr/bin/env bash
# 検証: fw_repo_diff_lines の git fallback が rename を -M で collapse する（diff.renames config 非依存）。
#   C1) diff.renames=false の git リポで 40 行ファイルを rename → diff lines < min(30)（≈0）。
#       -M 未適用なら delete+add で ~80 行になる＝この差で修正を検出。
#   C2) rename でない 40 行の内容追加 → diff lines >= 30（real change を誤抑制しない回帰ガード）。
# 足場（TMP/REPO_T/fail/ok・git-only リポ）は chain-lib を再利用。git-only なので fw_repo_diff_lines
# 内の jj diff が失敗し git fallback（修正対象）を踏む。common.sh は set -e 隔離のため subshell で source。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/chain-lib.sh"

git config diff.renames false   # rename 検出を config で OFF → 「-M が効いているか」を確実に試す

diff_lines() {  # $1 = base rev → fw_repo_diff_lines の出力（最終行）
  ( cd "$REPO_T" && source "$REPO/hooks/lib/common.sh" 2>/dev/null; fw_repo_diff_lines "$REPO_T" "$1" ) | tail -1
}

# ---- C1: 純粋 rename → collapse（< 30 = polish skip）----
seq 1 40 > bigfile.txt
git add -A && git commit -qm "add bigfile" || fail "C1: commit 失敗"
BASE1="$(git rev-parse HEAD)"
git mv bigfile.txt bigfile2.txt || fail "C1: git mv 失敗"
n1="$(diff_lines "$BASE1")"
[ "${n1:-99}" -lt 30 ] || fail "C1: 純粋 rename は collapse して <30 のはず。実際=$n1（-M 未適用なら ~80）"
ok "C1) 純粋 rename: diff lines=$n1 (<30 → polish skip)"

# ---- C2: 内容追加（rename でない）→ 数える（>= 30 = polish 継続）----
git add -A && git commit -qm "rename" || fail "C2: commit 失敗"
BASE2="$(git rev-parse HEAD)"
seq 1 40 >> bigfile2.txt   # 40 行追記（純粋な内容増）
n2="$(diff_lines "$BASE2")"
[ "${n2:-0}" -ge 30 ] || fail "C2: 内容追加は数えて >=30 のはず。実際=$n2"
ok "C2) 内容追加: diff lines=$n2 (>=30 → polish 継続)"

echo "🎉 polish-rename-skip 全ケース PASS"
