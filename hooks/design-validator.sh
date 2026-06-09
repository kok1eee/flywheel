#!/usr/bin/env bash
# design-validator (PostToolUse, matcher: Write|Edit) — FR-4, phase-advancer
# plan/design.md への書き込みを検知 → o-m-cc の validate-plan を直接実行（CLI 委譲）
# → 合格なら designing → spec-ready に遷移し実装ゲートを開ける。
#
# state を進めるのは hook（CLI exit code 観測）であってモデルではない（C-2 対策）。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

fw_hook_guard || exit 0

INPUT="$(cat)"
fw_parse_tool_input "$INPUT"   # → FW_TOOL / FW_FP

# state の design_path への Write/Edit のみ反応（パスは state が持つ = 単一の出所）
[[ "$FW_TOOL" == "Write" || "$FW_TOOL" == "Edit" ]] || exit 0
design_path="$(fw_get '.design_path')"
[[ -n "$design_path" && "$FW_FP" == *"$design_path" ]] || exit 0

# 設計フェーズ中だけ検証（spec-ready 以降は再検証不要）。phase 述語は common.sh に集約。
fw_gate_closed "$(fw_phase)" || exit 0

emit_ctx() {  # PostToolUse の additionalContext でモデルに伝える
  jq -cn --arg c "$1" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $c}}'
}

vp="$(fw_find_validate_plan || true)"
if [[ -z "$vp" ]]; then
  emit_ctx "⚠️ flywheel: o-m-cc の validate-plan が見つからず設計を検証できません。FLYWHEEL_VALIDATE_PLAN を設定するか o-m-cc を install してください。実装ゲートは閉じたままです。"
  exit 0
fi

# CLI 委譲: リポ root で validate-plan design を実行し exit code で判定
out="$(cd "$FW_ROOT" && "$vp" design 2>&1)" && rc=0 || rc=$?

if [[ "$rc" -eq 0 ]]; then
  fw_advance spec-ready "design-validator: validate-plan design pass"
  emit_ctx "✅ flywheel: 設計が validate-plan を通過。実装ゲートを開きました（phase=spec-ready）。実装に進めます。goal: $(fw_get '.goal')"
else
  emit_ctx "❌ flywheel: 設計が validate-plan を通っていません（実装ゲートは閉じたまま）。修正してください:
$out"
fi
exit 0
