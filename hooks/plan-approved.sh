#!/usr/bin/env bash
# plan-approved (PostToolUse, matcher: ExitPlanMode) — FR-22
# ユーザーが計画を承認した瞬間（spike 実証: 承認時のみ発火、tool_response.plan に承認済み全文、
# permission_mode は承認後モード）に:
#   1. 承認済み計画を plan/design.md へ書き出す（spec の artifact 化まで hook がやる。
#      モデルは計画を提示するだけ = C-2 の強化。plan mode 中はファイルが書けないため唯一解）
#   2. 完了条件を eval_cmd へ昇格（FR-19 流用）
#   3. state を生成して implementing へ（designing/spec-ready は plan mode と承認が肩代わり）
# 以後は既存 loop-driver（eval veto / polish-on-green / cap）が done まで回す。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

[[ "${FLYWHEEL_OFF:-}"  == "1" ]] && exit 0
[[ "${FLYWHEEL_PLAN:-}" == "1" ]] || exit 0   # FR-23: opt-in

INPUT="$(cat)"
# 承認の証拠は tool_response.plan のみ（spike 実証: 承認時にだけ入る）。tool_input.plan への
# フォールバックはしない——拒否/中断でも tool_input は残っており、誤って loop を arm してしまう。
# `?` は tool_response が文字列（エラー等）のときの index エラーを握る。
# 計画は複数行のため行ベース read は使えない（コマンド置換で改行ごと取る）。
plan="$(printf '%s' "$INPUT" | jq -r '.tool_response.plan? // empty' 2>/dev/null || true)"
mode="$(printf '%s' "$INPUT" | jq -r '.permission_mode // empty' 2>/dev/null || true)"
[[ -z "$plan" ]] && exit 0

# 1) spec の artifact 化（前回 plan は FR-12 で退避）
fw_archive_plan >/dev/null
mkdir -p "$FW_ROOT/plan"
printf '%s\n' "$plan" > "$FW_ROOT/plan/design.md"

# 2) goal = 計画の最初の見出し（無ければ先頭行）
goal="$(printf '%s' "$plan" | grep -m1 -E '^#' | sed 's/^#\+[[:space:]]*//')"
[[ -z "$goal" ]] && goal="$(printf '%s' "$plan" | head -1)"

# 3) state 生成 → implementing。eval は spec の完了条件（plan-gate が存在を保証済み）
eval_cmd="$(fw_extract_spec_eval)"
fw_init "$goal" "$eval_cmd" "true" "spec"
[[ -n "$mode" ]] && fw_set_str approved_mode "$mode"
fw_advance implementing "plan-approved: user approved plan"

jq -cn --arg c "✅ flywheel: 計画の承認を観測しました。
  spec を plan/design.md に保存（goal: $goal）
  eval_cmd: ${eval_cmd:-（完了条件から抽出できず — degrade）}
  phase: implementing — 実装を開始してください。停止すると eval で done を判定し、未達なら loop が続きます。" \
  '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $c}}'
exit 0
