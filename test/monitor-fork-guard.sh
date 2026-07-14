#!/usr/bin/env bash
# monitor-fork-guard.sh の PreToolUse deny ブロックを検証する。
# C1/C2: phase=eval/polish + skill=flywheel:monitor → deny
# C3: phase=implementing（対象外）→ deny なし
# C4: skill=flywheel:next（対象外）→ deny なし
# C5: FLYWHEEL_OFF=1 → deny なし
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/chain-lib.sh"
HOOK="$REPO/hooks/monitor-fork-guard.sh"

skill_input() { jq -cn --arg s "$1" '{tool_name:"Skill", tool_input:{skill:$s}}'; }

decision() {   # $1=phase $2=skill → permissionDecision（無ければ空）
  jq_patch "$(state)" --arg p "$1" '.phase=$p'
  skill_input "$2" | bash "$HOOK" 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecision // empty'
}

setup_impl "true"

[ "$(decision eval flywheel:monitor)" = "deny" ] || fail "C1: phase=eval で deny が出るべき"
ok "C1: phase=eval + flywheel:monitor → deny"

[ "$(decision polish flywheel:monitor)" = "deny" ] || fail "C2: phase=polish で deny が出るべき"
ok "C2: phase=polish + flywheel:monitor → deny"

[ -z "$(decision implementing flywheel:monitor)" ] || fail "C3: phase=implementing では deny が出てはならない"
ok "C3: phase=implementing（対象外）→ deny なし"

[ -z "$(decision eval flywheel:next)" ] || fail "C4: skill=flywheel:next では deny が出てはならない"
ok "C4: 対象外 skill（flywheel:next）→ deny なし"

jq_patch "$(state)" '.phase="eval"'
out="$(skill_input flywheel:monitor | FLYWHEEL_OFF=1 bash "$HOOK" 2>/dev/null)"
[ -z "$out" ] || fail "C5: FLYWHEEL_OFF=1 では deny が出てはならない"
ok "C5: FLYWHEEL_OFF=1 → deny なし"

echo "🎉 monitor-fork-guard 全ケース PASS"
