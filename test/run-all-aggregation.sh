#!/usr/bin/env bash
# run-all.sh の失敗集約契約を runtime 検証する（FR-44・監視 council 指摘）。
# 全緑 eval では runner の fail 経路（fail=1 / exit 1 / 失敗名出力）が一度も実走されず
# 静的読みでしか裏取りされない＝happy-path のみ検証。捨てテスト群を temp に置き、
# run-all.sh に対象ディレクトリを渡して「失敗あり→非ゼロ + 失敗名出力」「全緑→exit 0」を客観検証する。
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$ROOT/test/run-all.sh"
fail() { echo "❌ FAIL: $1"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILDIR="$TMP/withfail"; PASSDIR="$TMP/allpass"
mkdir -p "$FAILDIR" "$PASSDIR"

# --- ケース1: 失敗を含む → exit 非0 + 失敗ファイル名を出力 ---
printf '#!/usr/bin/env bash\nexit 0\n' > "$FAILDIR/pass.sh"
printf '#!/usr/bin/env bash\nexit 1\n' > "$FAILDIR/boom.sh"
out="$(bash "$RUNNER" "$FAILDIR" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || fail "失敗テストありなのに exit 0（非ゼロ集約されていない）"
printf '%s' "$out" | grep -q "boom.sh" || fail "失敗ファイル名 boom.sh が出力に無い"
echo "✅ C1) 失敗あり: exit 非0（rc=$rc）+ 失敗名 boom.sh を集約"

# --- ケース2: 全緑 → exit 0 ---
printf '#!/usr/bin/env bash\nexit 0\n' > "$PASSDIR/a.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$PASSDIR/b.sh"
bash "$RUNNER" "$PASSDIR" >/dev/null 2>&1 || fail "全緑なのに非ゼロ exit"
echo "✅ C2) 全緑: exit 0"

echo "🎉 run-all-aggregation 全ケース PASS（runner の失敗集約契約を runtime 検証）"
