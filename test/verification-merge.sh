#!/usr/bin/env bash
# FR-34 検証: self-graded な verification ゲート（旧 FR-32）が撤去され、薄い eval（eval_src=auto）でも
# monitor clean なら done 前の verification steer なしで done に到達するか。
# 挙動検証は独立な monitor council（observer-behavior + overseer smoke）に統合済み。
# live state を壊さないよう mktemp -d の使い捨て git リポで検証する。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
FW="$REPO/bin/flywheel"
HOOK="$REPO/hooks/loop-driver.sh"

fail() { echo "❌ FAIL: $1"; exit 1; }
ok()   { echo "✅ $1"; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export CLAUDE_PLUGIN_DATA="$TMP/data"; mkdir -p "$CLAUDE_PLUGIN_DATA"
export PATH="$REPO/bin:$PATH"
unset FLYWHEEL_NO_CHAIN FLYWHEEL_OFF 2>/dev/null || true

REPO_T="$TMP/repo"; mkdir -p "$REPO_T"
( cd "$REPO_T" && git init -q && git config user.email t@example.com && git config user.name tester \
  && echo seed > seed.txt && git add -A && git commit -qm init ) || fail "git 初期化失敗"
cd "$REPO_T" || fail "cd 失敗"

state() { echo "$REPO_T/.flywheel/state.json"; }
getf()  { jq -r "$1" "$(state)"; }

# 薄い eval（eval_src=auto）+ 全ゲート緑（monitor clean）+ implementing にして done 直前にする
setup_thin_done_ready() {
  rm -rf "$REPO_T/.flywheel" "$REPO_T/plan"
  "$FW" start "thin goal" >/dev/null 2>&1 || fail "flywheel start 失敗"
  local s; s="$(state)"
  # eval_src=auto = 薄い（旧 FR-32 なら verification steer が出ていた条件）
  jq '.phase="implementing" | .eval_cmd="true" | .eval_src="auto" | .polish=false | .polished=true | .monitor={status:"clean"}' \
    "$s" > "$s.tmp" && mv "$s.tmp" "$s" || fail "state 整形失敗"
}

# ---- ケース1: 薄 eval + monitor clean → verification steer なしで done ----
setup_thin_done_ready
err="$(FLYWHEEL_HOOK=1 bash "$HOOK" </dev/null 2>&1 >/dev/null)"; rc=$?
[ "$rc" = "0" ]                        || fail "1: exit code は 0 のはず（done・steer なし）。実際=$rc / err=$err"
[ "$(getf .phase)" = "done" ]          || fail "1: phase は done のはず。実際=$(getf .phase)"
echo "$err" | grep -qi 'verify-set\|Skill: flywheel:verification\|steer:verification' \
  && fail "1: verification steer が出てはいけない。err=$err"
ok "1) 薄 eval + monitor clean → verification steer なしで done"

# ---- ケース2: verification state を一切触らない（撤去確認）----
setup_thin_done_ready
FLYWHEEL_HOOK=1 bash "$HOOK" </dev/null >/dev/null 2>&1
[ "$(getf '.verification // "ABSENT"')" = "ABSENT" ] || fail "2: verification フィールドが作られている: $(getf '.verification')"
ok "2) verification state を作らない（FR-32 撤去）"

# ---- ケース3: usage CSV に steer:verification が記録されない ----
grep -q 'steer:verification' "$CLAUDE_PLUGIN_DATA/skill-usage.csv" 2>/dev/null \
  && fail "3: steer:verification が記録されている（撤去漏れ）"
ok "3) steer:verification を記録しない"

echo "🎉 全ケース PASS"
