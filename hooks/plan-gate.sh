#!/usr/bin/env bash
# plan-gate (PreToolUse, matcher: ExitPlanMode) — FR-21
# ユーザーに提示される計画は検証済みのみ。tool_input.plan（計画本文）を検証し、
# 必須要素（非スコープ / 完了条件 + fenced command）が無ければ exit 2 で差し戻す。
# designing の read-only 強制は native plan mode が担う（H-1 解決）ので、
# この hook は「計画の品質」だけを見る。
# spike 実証済み: PreToolUse は ExitPlanMode に発火し、exit 2 の stderr にモデルは1回で従う。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

[[ "${FLYWHEEL_OFF:-}"  == "1" ]] && exit 0
[[ "${FLYWHEEL_PLAN:-}" == "1" ]] || exit 0   # FR-23: opt-in

INPUT="$(cat)"
plan="$(printf '%s' "$INPUT" | jq -r '.tool_input.plan // empty' 2>/dev/null || true)"
[[ -z "$plan" ]] && exit 0   # 計画本文が取れない形式は素通し（degrade）

missing=()
printf '%s' "$plan" | grep -qE '非スコープ|スコープ外|out.?of.?scope' \
  || missing+=("「## 非スコープ」（今回やらないことの明示）")
if ! printf '%s' "$plan" | grep -qE '^#{2,3} .*(完了条件|受け入れ基準)'; then
  missing+=("「## 完了条件（eval）」セクション")
elif [[ -z "$(printf '%s' "$plan" | fw_extract_spec_eval_text)" ]]; then
  missing+=("完了条件セクション内の fenced bash block（done を機械判定するコマンド。1行 = 1コマンド）")
fi

[[ ${#missing[@]} -eq 0 ]] && exit 0   # 検証済み計画 → 承認ダイアログへ

fw_log_usage "steer:plan-gate"   # FR-18: steer 従命率の分母
{
  echo "🚫 flywheel plan-gate: 計画に不足があります（ユーザーに提示する前に直してください）:"
  for m in "${missing[@]}"; do echo "  - $m"; done
  echo ""
  echo "補って ExitPlanMode を再実行してください。要件自体が曖昧なら AskUserQuestion で1問ずつ（推奨付き）詰めるか、/flywheel:deep-interview を使ってください。"
} >&2
exit 2
