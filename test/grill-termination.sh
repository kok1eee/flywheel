#!/usr/bin/env bash
# 検証: grill / deep-interview / plan-steer の終了判定が self-graded から外れている（lever 1・FR-39）。
# prose 変更なので skill/hook ファイルを直接 grep する（state も hook 実行も不要）。
# 検証ケース:
#   C1) deep-interview から「7問」ハードキャップが消えている（under-ask の前提撤去）
#   C2) 3経路すべてに「止めるのは人間」（human owns stop）の sentinel がある
#   C3) 3経路すべてに「未決の判断」（止める前に残り枝を提示）の sentinel がある
#   C4) grill の `事実=self-answer` filter が温存（lever 1 が「無限に聞く」に退行していない回帰ガード）
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
DI="$ROOT/skills/deep-interview/SKILL.md"
GR="$ROOT/skills/grill/SKILL.md"
PS="$ROOT/hooks/plan-steer.sh"

fail() { echo "❌ $1"; exit 1; }
ok()   { echo "✅ $1"; }

for f in "$DI" "$GR" "$PS"; do
  [ -f "$f" ] || fail "対象ファイルが無い: $f"
done

# ---- C1: deep-interview の 7問ハードキャップ撤去 ----
grep -q "7問" "$DI" && fail "C1: deep-interview にまだ「7問」ハードキャップが残っている（under-ask 前提を撤去すること）"
ok "C1) deep-interview: 7問ハードキャップ撤去"

# ---- C2: human owns stop ----
for f in "$DI" "$GR" "$PS"; do
  grep -q "止めるのは人間" "$f" || fail "C2: $(basename "$(dirname "$f")")/$(basename "$f") に「止めるのは人間」が無い"
done
ok "C2) 3経路すべてに「止めるのは人間」"

# ---- C3: surface remaining branches before stop ----
for f in "$DI" "$GR" "$PS"; do
  grep -q "未決の判断" "$f" || fail "C3: $(basename "$(dirname "$f")")/$(basename "$f") に「未決の判断」が無い"
done
ok "C3) 3経路すべてに「未決の判断」"

# ---- C4: grill の事実/self-answer filter 温存（無限質問への退行ガード）----
grep -q "self-answer" "$GR" || fail "C4: grill から self-answer filter が消えた（lever 1 ≠ 無限に聞く）"
grep -q "事実" "$GR"        || fail "C4: grill から「事実」filter が消えた（lever 1 ≠ 無限に聞く）"
ok "C4) grill の事実/self-answer filter 温存"

echo "🎉 grill-termination 全ケース PASS"
