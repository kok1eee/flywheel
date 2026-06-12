#!/usr/bin/env bash
# plan-steer (UserPromptSubmit) — FR-24
# engage 中（FLYWHEEL_PLAN=1）の plan mode で、grill の操作系（圧縮版）を毎プロンプト注入し
# **既定動作**にする。「/flywheel:grill を使え」という prose 誘導（= flywheel が殺そうとした形）を
# やめ、skill 発動に依存しない。毎プロンプト注入なので compaction 後も効く（FR-17 と同じ思想）。
# 明示的 /flywheel:grill はオンデマンド深掘り・CLI route 用に残る。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

[[ "${FLYWHEEL_OFF:-}"  == "1" ]] && exit 0
[[ "${FLYWHEEL_PLAN:-}" == "1" ]] || exit 0   # FR-23: opt-in

INPUT="$(cat)"
mode="$(printf '%s' "$INPUT" | jq -r '.permission_mode // empty' 2>/dev/null || true)"
[[ "$mode" == "plan" ]] || exit 0

jq -cn '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext:
"🛞 flywheel plan-mode（grill 既定動作・FR-24）— この計画作りでは以下を守ること:
- 計画の決定点を列挙し、コード/リポを見れば答えが出るものは Glob/Grep/Read で self-answer して埋める（人間に聞かない）
- 残った決定は AskUserQuestion で1問ずつ、あなたの推奨案と理由を添えて詰める
- 計画には「## 非スコープ」と「## 完了条件（eval）」を必ず含める。完了条件は done を機械判定する fenced bash block（1行 = 1コマンド、&& 連結で実行される）
- 詰め切るまで ExitPlanMode しない（形式不足の計画は plan-gate が差し戻す）
承認されると flywheel が計画を plan/design.md に保存し、完了条件を eval として done まで自動 loop します。"}}'
exit 0
