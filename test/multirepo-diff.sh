#!/usr/bin/env bash
# FR-B 検証: fw_goal_diff_lines が宣言した sibling repo の diff を合算するか。
# live state を壊さないよう mktemp -d の使い捨て2リポ（main + sibling）で検証する。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
FW="$REPO/bin/flywheel"
COMMON="$REPO/hooks/lib/common.sh"

fail() { echo "❌ FAIL: $1"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
MAIN="$TMP/main"; SIB="$TMP/sib"
mkdir -p "$MAIN" "$SIB"
export CLAUDE_PLUGIN_DATA="$TMP/data"; mkdir -p "$CLAUDE_PLUGIN_DATA"  # 本番 CSV 汚染防止

# 2リポを git init + 初期 commit（baseline を作る）。sibling は .flywheel を gitignore
# （FR-57 の警告を CI ログに出さない・警告自体の検証は test/repos-gitignore-warn.sh の担当）
for d in "$MAIN" "$SIB"; do
  ( cd "$d" && git init -q && git config user.email t@example.com && git config user.name tester \
    && echo seed > seed.txt && echo ".flywheel/" > .gitignore && git add -A && git commit -qm init ) \
    || fail "git 初期化失敗: $d"
done

# main で start（cwd=MAIN → FW_ROOT=MAIN, baseline=MAIN HEAD）
( cd "$MAIN" && "$FW" start "multirepo diff test" >/dev/null ) || fail "flywheel start 失敗"

# main に実装変更（impl = .py を20行）
( cd "$MAIN" && { echo "def f():"; for i in $(seq 1 20); do echo "    x$i = $i"; done; } > app.py )

# repos 未登録時の diff（FW_ROOT のみ）
only_main="$(cd "$MAIN" && bash -c "source '$COMMON'; fw_goal_diff_lines")"
only_main="${only_main:-0}"

# sibling を登録（baseline=SIB HEAD）
( cd "$MAIN" && "$FW" repos "$SIB" >/dev/null ) || fail "flywheel repos 登録失敗"

# sibling に実装変更（.py を30行）
( cd "$SIB" && { echo "def g():"; for i in $(seq 1 30); do echo "    y$i = $i"; done; } > lib.py )

# 登録後の diff（FW_ROOT + sibling 合算）
with_sib="$(cd "$MAIN" && bash -c "source '$COMMON'; fw_goal_diff_lines")"
with_sib="${with_sib:-0}"

echo "only_main=$only_main  with_sib=$with_sib"
[[ "$only_main" =~ ^[0-9]+$ && "$only_main" -ge 1 ]] || fail "main 単独 diff が測れない（baseline/impl 判定が壊れている）: '$only_main'"
[[ "$with_sib" =~ ^[0-9]+$ ]] || fail "with_sib が数値でない: '$with_sib'"
[[ "$with_sib" -gt "$only_main" ]] || fail "sibling 登録後も diff が増えない（合算されていない）: only=$only_main with=$with_sib"
[[ $((with_sib - only_main)) -ge 20 ]] || fail "sibling の diff 増分が小さすぎる（増分=$((with_sib - only_main))・期待 ~30）"

echo "🟢 multirepo diff PASS: only_main=$only_main → with_sib=$with_sib（sibling repo の diff を合算）"
