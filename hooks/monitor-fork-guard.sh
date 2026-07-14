#!/usr/bin/env bash
# monitor-fork-guard (PreToolUse, matcher: Skill) — v0.8.47
# Skill: flywheel:monitor は Skill tool 経由で呼ぶと forked execution になり、
# loop-driver の lite/標的 council hint（monitor_hint()、state.json に保存されず
# その場で計算して消える）が無視され、常に 3レンズ full fan-out にフォールバックする
# 既知バグ（skills/monitor/SKILL.md の Gotcha [2026-06-15] 参照）。
#
# hint 判定ロジックはここに複製しない（loop-driver.sh と2箇所に分散させない）。
# inline 実行が正しい対策であることに例外は無い（fork してよいケースは無い）ため、
# eval/polish phase での呼出し全件を deny で機械的に止める（ask だと、最頻出 multi-agent
# 操作である monitor に毎回人間確認を挟むことになり、HOTL の「人間は on-loop」原則に
# 逆行する。過検知（今 lite hint が出ていないときも deny）は許容——対策は常に同じ
# inline 実行なので、判定を誤っても redirect 先が変わらない）。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

fw_hook_guard || exit 0   # bypass / dormant なら門は開いている

# skill 名の判定は stdin のみ（disk I/O 無し）なので、state.json を読む phase 判定より
# 先に行う。Skill 呼出しの大半は flywheel:monitor 以外なので、ここで大半が state.json
# アクセス無しに抜けられる。
skill="$(jq -r '.tool_input.skill // empty' 2>/dev/null || true)"
[[ "$skill" == "flywheel:monitor" ]] || exit 0

phase="$(fw_phase)"
[[ "$phase" == "eval" || "$phase" == "polish" ]] || exit 0

jq -cn '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:"Skill tool 経由の flywheel:monitor 呼出しは forked execution になり、loop-driver の lite/標的 council hint が無視されて常に full 3レンズ fan-out にフォールバックする既知バグがある（skills/monitor/SKILL.md の Gotcha 参照）。overseer の手順（context 収集 → drift-observer を fan-out → 集約 → flywheel monitor-set）を呼び出し側で inline 実行してください。"}}'
exit 0
